import 'dart:convert';

import 'package:ev_sharegrid/data/api.dart';
import 'package:ev_sharegrid/main.dart';
import 'package:ev_sharegrid/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ApiClient _client(String role, Object? Function(http.Request) reply) =>
    ApiClient(
      client: MockClient((request) async {
        final body = switch (request.url.path) {
          '/api/v1/auth/login' => {'access_token': 'fixture-token'},
          '/api/v1/auth/me' => {'user_id': 7, 'role': role},
          _ => reply(request),
        };
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      }),
    );

Future<void> _signIn(ApiClient client) =>
    client.login(email: 'test@example.test', password: 'fixture');

void main() {
  setUpAll(() => AppFonts.enabled = false);

  testWidgets('Host mở đúng cổng và hiển thị trạng thái tối ưu từ API', (
    tester,
  ) async {
    var status = 'ACTIVE';
    final client = _client('HOST', (request) {
      if (request.url.path == '/api/v1/host/ports/44/status') {
        expect(request.method, 'PATCH');
        expect(jsonDecode(request.body), {'status': 'OFFLINE'});
        status = 'OFFLINE';
        return {
          'port_id': 44,
          'status': status,
          'optimization_status': 'OPTIMAL',
        };
      }
      expect(request.url.path, '/api/v1/host/stations');
      return {
        'data': [
          {
            'station_id': 8,
            'name': 'Trạm thử',
            'status': 'ACTIVE',
            'ports': [
              {
                'port_id': 44,
                'port_code': 'P44',
                'status': status,
                'connector_type': 'CCS2',
              },
            ],
          },
        ],
      };
    });
    await _signIn(client);
    await tester.pumpWidget(
      EvShareGridApp(initialLocation: '/host/stations', api: client),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem cổng'));
    await tester.pumpAndSettle();
    expect(find.text('#8 · Trạm thử'), findsOneWidget);
    await tester.tap(find.text('Ngừng cổng'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tái tối ưu · OPTIMAL'), findsOneWidget);
    expect(find.text('P44 · CCS2 · OFFLINE'), findsOneWidget);
    expect(find.text('Ngừng cổng'), findsNothing);
  });

  testWidgets('Admin gửi công suất mới và hiển thị trạng thái tái tối ưu', (
    tester,
  ) async {
    var limit = 250.0;
    final client = _client('ADMIN', (request) {
      if (request.method == 'PATCH') {
        expect(request.url.path, '/api/v1/admin/clusters/8');
        limit = (jsonDecode(request.body)['grid_limit_kw'] as num).toDouble();
        return {
          'cluster_id': 8,
          'grid_limit_kw': limit,
          'optimization_status': 'FEASIBLE',
        };
      }
      expect(request.url.path, '/api/v1/admin/clusters');
      return {
        'data': [
          {
            'cluster_id': 8,
            'name': 'Cụm thử',
            'status': 'ACTIVE',
            'grid_limit_kw': limit,
          },
        ],
      };
    });
    await _signIn(client);
    await tester.pumpWidget(
      EvShareGridApp(initialLocation: '/admin/clusters', api: client),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chỉnh công suất'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '230');
    await tester.tap(find.text('Gửi'));
    await tester.pumpAndSettle();
    expect(limit, 230);
    expect(find.textContaining('Tái tối ưu · FEASIBLE'), findsOneWidget);
  });

  testWidgets('Admin thấy mô hình thực tế và cảnh báo fallback', (
    tester,
  ) async {
    final client = _client('ADMIN', (request) {
      if (request.method == 'POST') {
        expect(request.url.path, '/api/v1/admin/forecast');
        expect(jsonDecode(request.body)['cluster_id'], 8);
        return {
          'cluster_id': '8',
          'model': 'HOURLY_MEAN',
          'warnings': ['Dưới 14 ngày quan sát.'],
          'predictions': [
            {'hour_start': '2026-11-21T08:00:00+07:00', 'pred_arrivals': 2},
          ],
        };
      }
      expect(request.url.path, '/api/v1/admin/clusters');
      return {
        'data': [
          {'cluster_id': 8, 'name': 'Cụm thử'},
        ],
      };
    });
    await _signIn(client);
    await tester.pumpWidget(
      EvShareGridApp(initialLocation: '/admin/forecast', api: client),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chạy dự báo AI'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mô hình thực tế HOURLY_MEAN'), findsOneWidget);
    expect(find.text('Dưới 14 ngày quan sát.'), findsOneWidget);
    expect(find.text('2 lượt'), findsOneWidget);
  });
}
