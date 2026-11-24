import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Web release uses same-origin /api/ via Nginx when the base is empty.
/// Firebase Hosting needs the absolute HTTPS API origin at build time.
const apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: kIsWeb && kReleaseMode ? '' : 'http://localhost:8000',
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

/// The credentials were accepted, but the account could not be loaded.
class ProfileLoadException implements Exception {
  const ProfileLoadException(this.cause);

  final Exception cause;
}

class ApiClient extends ChangeNotifier {
  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = (baseUrl ?? apiBase).replaceFirst(RegExp(r'/+$'), '');

  static const _tokenKey = 'access_token';
  final http.Client _client;
  final String _baseUrl;
  String? _accessToken;
  Map<String, dynamic>? currentUser;
  Map<String, dynamic>? _lastBooking;
  int _sessionVersion = 0;
  bool _expired = false;

  bool get sessionExpired => _expired;

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
  }) => _authenticate('/api/v1/auth/login', {
    'email': email,
    'password': password,
  });

  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String password,
  }) => _authenticate('/api/v1/auth/register', {
    'full_name': fullName,
    'email': email,
    'password': password,
  });

  Future<Map<String, dynamic>> _authenticate(
    String path,
    Map<String, dynamic> body,
  ) async {
    final cleared = logout();
    final version = _sessionVersion;
    await cleared;
    const timeout = Duration(seconds: 15);
    final result = await postJson(
      path,
      body: body,
      includeAuthorization: false,
    ).timeout(timeout);
    if (version != _sessionVersion) throw StateError('Phiên đã thay đổi.');
    final token = result['access_token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('API không trả access_token hợp lệ.');
    }
    _accessToken = token;
    try {
      final Map<String, dynamic> user;
      try {
        user = await getMe().timeout(timeout);
      } on Exception catch (error) {
        throw ProfileLoadException(error);
      }
      if (version != _sessionVersion) throw StateError('Phiên đã thay đổi.');
      final prefs = await SharedPreferences.getInstance();
      if (version != _sessionVersion) throw StateError('Phiên đã thay đổi.');
      if (!await prefs.setString(_tokenKey, token)) {
        throw StateError('Không thể lưu phiên đăng nhập.');
      }
      if (version != _sessionVersion) throw StateError('Phiên đã thay đổi.');
      currentUser = user;
      notifyListeners();
      return user;
    } catch (_) {
      if (version == _sessionVersion) await logout();
      rethrow;
    }
  }

  Future<void> restoreSession() async {
    final version = _sessionVersion;
    final prefs = await SharedPreferences.getInstance();
    if (version != _sessionVersion) return;
    final token = prefs.getString(_tokenKey);
    if (token == null) return;
    if (!_hasValidExpiry(token)) {
      await logout(expired: true);
      return;
    }

    _accessToken = token;
    try {
      final user = await getMe().timeout(const Duration(seconds: 10));
      if (version != _sessionVersion) return;
      currentUser = user;
      notifyListeners();
    } catch (_) {
      // A 401 already clears storage. Keep the saved JWT on a network failure
      // so a later startup can retry, but only grant access after /me succeeds.
      if (version == _sessionVersion) {
        _accessToken = null;
        currentUser = null;
        notifyListeners();
      }
    }
  }

  bool _hasValidExpiry(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final expiry = payload is Map ? payload['exp'] : null;
      return expiry is num &&
          expiry > DateTime.now().millisecondsSinceEpoch / 1000;
    } on FormatException {
      return false;
    }
  }

  Future<void> logout({bool expired = false}) async {
    final version = ++_sessionVersion;
    _expired = expired;
    _accessToken = null;
    currentUser = null;
    _lastBooking = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
    } finally {
      if (version == _sessionVersion) notifyListeners();
    }
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

  Future<List<Map<String, dynamic>>> getVehicles() =>
      _getRows('/api/v1/vehicles');

  Future<Map<String, dynamic>> createVehicle({
    required int modelId,
    required String licensePlate,
    String? nickname,
    double defaultSocTarget = 80.0,
    bool isDefault = false,
  }) async {
    final token = _accessToken;
    final response = await _client.post(
      _uri('/api/v1/vehicles'),
      headers: _headers,
      body: jsonEncode({
        'model_id': modelId,
        'license_plate': licensePlate,
        if (nickname != null && nickname.isNotEmpty) 'nickname': nickname,
        'default_soc_target': defaultSocTarget,
        'is_default': isDefault,
      }),
    );
    return _decodeObject(response, token: token);
  }

  Future<Map<String, dynamic>> updateVehicle(
    int vehicleId, {
    int? modelId,
    String? licensePlate,
    String? nickname,
    double? defaultSocTarget,
    bool? isDefault,
  }) async {
    final token = _accessToken;
    final body = <String, dynamic>{};
    if (modelId != null) body['model_id'] = modelId;
    if (licensePlate != null) body['license_plate'] = licensePlate;
    if (nickname != null) body['nickname'] = nickname;
    if (defaultSocTarget != null) body['default_soc_target'] = defaultSocTarget;
    if (isDefault != null) body['is_default'] = isDefault;
    final response = await _client.patch(
      _uri('/api/v1/vehicles/$vehicleId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _decodeObject(response, token: token);
  }

  Future<Map<String, dynamic>> deleteVehicle(int vehicleId) async {
    final token = _accessToken;
    final response = await _client.delete(
      _uri('/api/v1/vehicles/$vehicleId'),
      headers: _headers,
    );
    return _decodeObject(response, token: token);
  }

  Future<Map<String, dynamic>> updateProfile({
    String? fullName,
    String? phone,
  }) async {
    final token = _accessToken;
    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName;
    if (phone != null) body['phone'] = phone;
    final response = await _client.patch(
      _uri('/api/v1/auth/me'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final user = await _decodeObject(response, token: token);
    currentUser = user;
    notifyListeners();
    return user;
  }

  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final token = _accessToken;
    final response = await _client.post(
      _uri('/api/v1/auth/change-password'),
      headers: _headers,
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
    return _decodeObject(response, token: token);
  }

  Future<List<Map<String, dynamic>>> getTariffs() =>
      _getRows('/api/v1/tariffs');

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

  Uri _uri(String path) =>
      _baseUrl.isEmpty ? Uri.base.resolve(path) : Uri.parse('$_baseUrl$path');

  Future<Map<String, dynamic>> _decodeObject(
    http.Response response, {
    String? token,
  }) async {
    if (response.statusCode == 401 && token != null && token == _accessToken) {
      await logout(expired: true);
    }
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode >= 400) {
      var detail = text.trim();
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map && decoded['detail'] != null) {
          final value = decoded['detail'];
          detail = value is List && value.isNotEmpty && value.first is Map
              ? value.first['msg'].toString()
              : value.toString();
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
