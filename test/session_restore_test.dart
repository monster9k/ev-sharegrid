import 'dart:convert';

import 'package:ev_sharegrid/data/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  String jwt(int exp) {
    final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': exp})));
    return 'header.$payload.signature';
  }

  test(
    'a fresh client restores the JWT and fetches the current role',
    () async {
      final token = jwt(DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600);
      var meStatus = 200;
      final httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return http.Response(jsonEncode({'access_token': token}), 200);
        }
        expect(request.headers['Authorization'], 'Bearer $token');
        return http.Response('{"role":"ADMIN","user_id":3}', meStatus);
      });
      final original = ApiClient(client: httpClient);
      await original.login(email: 'demo@example.test', password: 'fixture');
      final restored = ApiClient(client: httpClient);
      await restored.restoreSession();
      expect(restored.accessToken, token);
      expect(restored.role, 'ADMIN');

      meStatus = 401;
      await expectLater(restored.getMe(), throwsA(isA<ApiException>()));
      expect(restored.accessToken, isNull);
      expect(
        (await SharedPreferences.getInstance()).getString('access_token'),
        isNull,
      );
    },
  );

  test('expired and malformed stored JWTs are discarded before /me', () async {
    final prefs = await SharedPreferences.getInstance();
    var requests = 0;
    final api = ApiClient(
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    for (final token in [jwt(1), 'invalid']) {
      await prefs.setString('access_token', token);
      await api.restoreSession();
      expect(api.accessToken, isNull);
      expect(prefs.containsKey('access_token'), isFalse);
    }
    expect(requests, 0);
  });
}
