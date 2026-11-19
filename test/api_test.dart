import 'dart:convert';

import 'package:ev_sharegrid/data/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('login keeps JWT in memory and sends it on later requests', () async {
    final requests = <http.Request>[];
    final client = ApiClient(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'access_token': 'signed-token',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': {'user_id': 3, 'role': 'USER'},
              }),
            ),
            200,
          );
        }
        if (request.url.path == '/api/v1/auth/me') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({'user_id': 3, 'role': 'USER', 'vehicles': []}),
            ),
            200,
          );
        }
        if (request.url.path == '/api/v1/requests') {
          return http.Response.bytes(
            utf8.encode(jsonEncode({'request_id': 31, 'allocated_kwh': 8})),
            200,
          );
        }
        throw StateError('Unexpected URL ${request.url}');
      }),
    );

    await client.login(email: 'user@example.test', password: 'secret');
    final result = await client.submitBooking(
      userId: 3,
      vehicleId: 101,
      stationId: 11,
      arrivalTime: '2026-11-20T08:00:00+07:00',
      departureTime: '2026-11-20T17:30:00+07:00',
      socNow: 30,
      socTarget: 80,
      idempotencyKey: 'booking-1',
    );

    expect(client.accessToken, 'signed-token');
    expect(client.currentUser?['user_id'], 3);
    expect(requests[0].headers['authorization'], isNull);
    expect(requests[1].headers['authorization'], 'Bearer signed-token');
    expect(requests[2].headers['authorization'], 'Bearer signed-token');
    expect(requests[2].method, 'POST');
    expect(requests[2].url.path, '/api/v1/requests');
    expect(jsonDecode(requests[2].body)['vehicle_id'], 101);
    expect(result['request_id'], 31);
  });

  test('HTTP errors include UTF-8 server detail', () async {
    final client = ApiClient(
      baseUrl: 'http://localhost:8000',
      client: MockClient((_) async {
        return http.Response.bytes(
          utf8.encode(jsonEncode({'detail': 'Xe đã có lịch trùng thời gian.'})),
          409,
        );
      }),
    );

    await expectLater(
      client.submitBooking(
        userId: 3,
        vehicleId: 101,
        stationId: 11,
        arrivalTime: '2026-11-20T08:00:00+07:00',
        departureTime: '2026-11-20T17:30:00+07:00',
        socNow: 30,
        socTarget: 80,
        idempotencyKey: 'booking-2',
      ),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having(
              (error) => error.message,
              'message',
              contains('Xe đã có lịch trùng'),
            ),
      ),
    );
  });
}
