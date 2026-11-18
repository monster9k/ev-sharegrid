import 'dart:convert';

import 'package:http/http.dart' as http;

const apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://localhost:8000',
);

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'HTTP $statusCode: $message';
}

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = (baseUrl ?? apiBase).replaceFirst(RegExp(r'/+$'), '');

  final http.Client _client;
  final String _baseUrl;
  String? _accessToken;
  Map<String, dynamic>? currentUser;

  String? get accessToken => _accessToken;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (_accessToken case final token?) 'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final result = await postJson(
      '/api/v1/auth/login',
      body: {'email': email, 'password': password},
      includeAuthorization: false,
    );
    final token = result['access_token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('API không trả access_token hợp lệ.');
    }
    _accessToken = token;
    try {
      currentUser = await getJson('/api/v1/auth/me');
      return currentUser!;
    } catch (_) {
      clearSession();
      rethrow;
    }
  }

  void clearSession() {
    _accessToken = null;
    currentUser = null;
  }

  Future<Map<String, dynamic>> submitBooking({
    required int userId,
    required int vehicleId,
    required int stationId,
    required String arrivalTime,
    required String departureTime,
    required double socNow,
    required double socTarget,
    required String idempotencyKey,
  }) => postJson(
    '/api/v1/requests',
    body: {
      'user_id': userId,
      'vehicle_id': vehicleId,
      'station_id': stationId,
      'arrival_time': arrivalTime,
      'departure_time': departureTime,
      'soc_now': socNow,
      'soc_target': socTarget,
      'idempotency_key': idempotencyKey,
    },
  );

  Future<Map<String, dynamic>> getRequestSchedule(int requestId) =>
      getJson('/api/v1/requests/$requestId/schedule');

  Future<Map<String, dynamic>> confirmRequest(int requestId) =>
      postJson('/api/v1/requests/$requestId/confirm', body: const {});

  Future<Map<String, dynamic>> cancelRequest(int requestId) =>
      postJson('/api/v1/requests/$requestId/cancel', body: const {});

  Future<Map<String, dynamic>> getBenchmark() =>
      getJson('/api/v1/admin/benchmark');

  Future<List<Map<String, dynamic>>> getActiveStations() async {
    final response = await getJson('/api/v1/stations');
    final data = response['data'];
    if (data is! List) {
      throw const FormatException(
        'API trạm sạc không trả danh sách data hợp lệ.',
      );
    }
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => row['status'] == 'ACTIVE')
        .toList();
  }

  Future<Map<String, dynamic>> getStation(int stationId) async {
    final response = await getJson('/api/v1/stations/$stationId');
    final data = response['data'];
    if (data is! Map) {
      throw const FormatException(
        'API chi tiết trạm không trả object data hợp lệ.',
      );
    }
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final response = await _client.get(_uri(path), headers: _headers);
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, dynamic> body,
    bool includeAuthorization = true,
  }) async {
    final headers = <String, String>{
      ..._headers,
      'Content-Type': 'application/json; charset=utf-8',
    };
    if (!includeAuthorization) headers.remove('Authorization');
    final response = await _client.post(
      _uri(path),
      headers: headers,
      body: jsonEncode(body),
    );
    return _decodeObject(response);
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, dynamic> _decodeObject(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 400) {
      var detail = text.trim();
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map && decoded['detail'] != null) {
          detail = decoded['detail'].toString();
        }
      } on FormatException {
        // Keep a non-JSON error body so the screen can show the server message.
      }
      throw ApiException(
        response.statusCode,
        detail.isEmpty ? 'Yêu cầu API thất bại.' : detail,
      );
    }
    if (text.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'API trả dữ liệu không đúng định dạng JSON object.',
      );
    }
    return decoded;
  }
}

final apiClient = ApiClient();

Future<Map<String, dynamic>> submitBooking({
  required int userId,
  required int vehicleId,
  required int stationId,
  required String arrivalTime,
  required String departureTime,
  required double socNow,
  required double socTarget,
  required String idempotencyKey,
}) => apiClient.submitBooking(
  userId: userId,
  vehicleId: vehicleId,
  stationId: stationId,
  arrivalTime: arrivalTime,
  departureTime: departureTime,
  socNow: socNow,
  socTarget: socTarget,
  idempotencyKey: idempotencyKey,
);
