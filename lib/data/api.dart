import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://localhost:8000',
);

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  String get userMessage => switch (statusCode) {
    401 => 'Vui lòng đăng nhập lại. (HTTP 401)',
    403 => 'Tài khoản không có quyền thực hiện thao tác này. (HTTP 403)',
    _ => '$message (HTTP $statusCode)',
  };

  @override
  String toString() => 'HTTP $statusCode: $message';
}

class ApiClient extends ChangeNotifier {
  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = (baseUrl ?? apiBase).replaceFirst(RegExp(r'/+$'), '');

  final http.Client _client;
  final String _baseUrl;
  String? _accessToken;
  Map<String, dynamic>? currentUser;
  Map<String, dynamic>? _lastBooking;

  String? get accessToken => _accessToken;
  String? get role => currentUser?['role']?.toString().toUpperCase();
  int? get lastRequestId => (_lastBooking?['request_id'] as num?)?.toInt();
  Map<String, dynamic>? get lastBooking => _lastBooking;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (_accessToken case final token?) 'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    clearSession();
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
      currentUser = await getMe();
      notifyListeners();
      return currentUser!;
    } catch (_) {
      clearSession();
      rethrow;
    }
  }

  void clearSession() {
    _accessToken = null;
    currentUser = null;
    _lastBooking = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>> getMe() => getJson('/api/v1/auth/me');

  Future<Map<String, dynamic>> submitBooking({
    required int userId,
    required int vehicleId,
    required int stationId,
    required String arrivalTime,
    required String departureTime,
    required double socNow,
    required double socTarget,
    required String idempotencyKey,
  }) async {
    final token = _accessToken;
    final result = await postJson(
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
    if (token != null && token == _accessToken) {
      _lastBooking = Map.unmodifiable(result);
    }
    return result;
  }

  Future<Map<String, dynamic>> getRequestSchedule(int requestId) =>
      getJson('/api/v1/requests/$requestId/schedule');

  Future<Map<String, dynamic>> confirmRequest(int requestId) =>
      postJson('/api/v1/requests/$requestId/confirm', body: const {});

  Future<Map<String, dynamic>> cancelRequest(int requestId) =>
      postJson('/api/v1/requests/$requestId/cancel', body: const {});

  Future<Map<String, dynamic>> checkinRequest(int requestId) =>
      postJson('/api/v1/requests/$requestId/checkin', body: const {});

  Future<Map<String, dynamic>> getBenchmark() =>
      getJson('/api/v1/admin/benchmark').timeout(const Duration(seconds: 10));

  Future<List<Map<String, dynamic>>> getMyRequests({int limit = 50}) =>
      _getRows('/api/v1/requests/me?limit=$limit');

  Future<List<Map<String, dynamic>>> getHostStations() =>
      _getRows('/api/v1/host/stations');

  Future<Map<String, dynamic>> createHostStation(Map<String, dynamic> fields) =>
      postJson('/api/v1/host/stations', body: fields);

  Future<Map<String, dynamic>> addHostPort(
    int stationId,
    Map<String, dynamic> fields,
  ) => postJson('/api/v1/host/stations/$stationId/ports', body: fields);

  Future<Map<String, dynamic>> changeHostPortStatus(
    int portId,
    String status,
  ) => _writeJson('PATCH', '/api/v1/host/ports/$portId/status', {
    'status': status,
  });

  Future<List<Map<String, dynamic>>> getHostSchedule(int stationId) =>
      _getRows('/api/v1/host/stations/$stationId/schedule', key: 'slots');

  Future<List<Map<String, dynamic>>> getAdminClusters() =>
      _getRows('/api/v1/admin/clusters');

  Future<List<Map<String, dynamic>>> getAdminStations(String status) =>
      _getRows('/api/v1/admin/stations?status=$status');

  Future<Map<String, dynamic>> updateClusterLimit(int id, double kw) =>
      _writeJson('PATCH', '/api/v1/admin/clusters/$id', {'grid_limit_kw': kw});

  Future<Map<String, dynamic>> verifyStation(int id, bool verified) =>
      _writeJson('PATCH', '/api/v1/admin/stations/$id/verify', {
        'verified': verified,
      });

  Future<Map<String, dynamic>> runBenchmark(Map<String, dynamic> snapshot) =>
      postJson(
        '/api/v1/admin/benchmark/run',
        body: {
          'scenario_id': 'page20',
          'algorithms': ['MILP_MPC', 'LLF'],
          'snapshot': snapshot,
        },
      ).timeout(const Duration(seconds: 125));

  Future<Map<String, dynamic>> runForecast(int clusterId, String model) =>
      postJson(
        '/api/v1/admin/forecast',
        body: {'cluster_id': clusterId, 'horizon_hours': 24, 'model': model},
      ).timeout(const Duration(seconds: 20));

  Future<List<Map<String, dynamic>>> getStations({
    double? lat,
    double? lng,
    double radiusKm = 25,
  }) {
    final path = lat == null || lng == null
        ? '/api/v1/stations'
        : '/api/v1/stations?lat=$lat&lng=$lng&radius_km=$radiusKm';
    return _getRows(path);
  }

  Future<List<Map<String, dynamic>>> getActiveStations() async =>
      (await getStations()).where((row) => row['status'] == 'ACTIVE').toList();

  Future<List<Map<String, dynamic>>> getVehicleModels() =>
      _getRows('/api/v1/vehicle-models');

  Future<List<Map<String, dynamic>>> getNotifications() =>
      _getRows('/api/v1/notifications', key: 'notifications');

  Future<Map<String, dynamic>> markNotificationRead(int notificationId) async {
    final token = _accessToken;
    final response = await _client.patch(
      _uri('/api/v1/notifications/$notificationId/read'),
      headers: _headers,
    );
    return _decodeObject(response, token: token);
  }

  Future<List<Map<String, dynamic>>> _getRows(
    String path, {
    String key = 'data',
  }) async {
    final data = (await getJson(path))[key];
    if (data is! List) {
      throw FormatException('Máy chủ không trả danh sách $key hợp lệ.');
    }
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
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
    final token = _accessToken;
    final response = await _client.get(_uri(path), headers: _headers);
    return _decodeObject(response, token: token);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, dynamic> body,
    bool includeAuthorization = true,
  }) => _writeJson(
    'POST',
    path,
    body,
    includeAuthorization: includeAuthorization,
  );

  Future<Map<String, dynamic>> _writeJson(
    String method,
    String path,
    Map<String, dynamic> body, {
    bool includeAuthorization = true,
  }) async {
    final token = includeAuthorization ? _accessToken : null;
    final headers = <String, String>{
      ..._headers,
      'Content-Type': 'application/json; charset=utf-8',
    };
    if (!includeAuthorization) headers.remove('Authorization');
    final request = http.Request(method, _uri(path));
    request.headers.addAll(headers);
    request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    return _decodeObject(response, token: token);
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, dynamic> _decodeObject(http.Response response, {String? token}) {
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode == 401 && token != null && token == _accessToken) {
      clearSession();
    }
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
