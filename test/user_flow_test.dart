import 'dart:convert';

import 'package:ev_sharegrid/data/api.dart';
import 'package:ev_sharegrid/main.dart';
import 'package:ev_sharegrid/screens/user/booking_screen.dart';
import 'package:ev_sharegrid/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _station(int id) => {
  'station_id': id,
  'name': 'Trạm $id',
  'status': 'ACTIVE',
  'is_24h': true,
  'ports': [
    {'connector_type': 'CCS2', 'status': 'ACTIVE', 'port_code': 'P$id'},
  ],
};

ApiClient _client(List<String> visited) => ApiClient(
  client: MockClient((request) async {
    final path = request.url.path;
    visited.add(path);
    final body = switch (path) {
      '/api/v1/auth/login' => {'access_token': 'test-token'},
      '/api/v1/auth/me' => {
        'user_id': 3,
        'role': 'USER',
        'full_name': 'User thử nghiệm',
        'email': 'account@example.test',
        'vehicles': [
          {
            'vehicle_id': 10,
            'is_default': true,
            'brand': 'VinFast',
            'model_name': 'VF 5',
            'connector_type': 'CCS2',
            'battery_kwh': 37,
            'max_kw': 50,
          },
        ],
      },
      '/api/v1/stations' => {
        'data': [_station(23), _station(24)],
      },
      '/api/v1/stations/24' => {'data': _station(24)},
      '/api/v1/requests' => {'request_id': 31},
      '/api/v1/requests/31/schedule' => {
        'request_id': 31,
        'status': 'SCHEDULED',
        'slots': [
          {'slot_start': '2026-11-23T01:00:00Z', 'power_kw': 5, 'port_id': 24},
        ],
      },
      _ => throw StateError('Unexpected request $path'),
    };
    return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
  }),
);

Future<void> _signIn(ApiClient client) =>
    client.login(email: 'account@example.test', password: 'test-input');

Future<void> _book(ApiClient client) => client.submitBooking(
  userId: 3,
  vehicleId: 10,
  stationId: 24,
  arrivalTime: '2026-11-23T01:00:00Z',
  departureTime: '2026-11-23T02:00:00Z',
  socNow: 30,
  socTarget: 80,
  idempotencyKey: 'test-booking',
);

void main() {
  setUpAll(() => AppFonts.enabled = false);

  testWidgets('đặt lịch từ chi tiết giữ đúng mã trạm', (tester) async {
    final paths = <String>[];
    final client = _client(paths);
    await _signIn(client);
    await tester.pumpWidget(
      EvShareGridApp(initialLocation: '/station/24', api: client),
    );
    await tester.pumpAndSettle();
    expect(find.text('Trạm 24'), findsOneWidget);
    await tester.tap(find.text('Đặt lịch sạc'));
    await tester.pumpAndSettle();

    final booking = tester.widget<BookingScreen>(find.byType(BookingScreen));
    expect(booking.stationId, 24);
    expect(find.text('Trạm 24'), findsOneWidget);
    expect(paths.where((path) => path == '/api/v1/stations/24'), hasLength(2));
    expect(paths, isNot(contains('/api/v1/stations/23')));
  });

  testWidgets('schedule tự lấy yêu cầu cuối khi route không có extra', (
    tester,
  ) async {
    final paths = <String>[];
    final client = _client(paths);
    await _signIn(client);
    await _book(client);
    await tester.pumpWidget(
      EvShareGridApp(initialLocation: '/schedule', api: client),
    );
    await tester.pumpAndSettle();

    expect(paths, contains('/api/v1/requests/31/schedule'));
    expect(find.text('Yêu cầu #31'), findsOneWidget);
    expect(find.textContaining('08:00–08:15'), findsOneWidget);
  });

  for (final route in ['/admin/benchmark', '/host/stations']) {
    testWidgets('chặn $route khi chưa đăng nhập', (tester) async {
      await tester.pumpWidget(
        EvShareGridApp(initialLocation: route, api: _client([])),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập'), findsOneWidget);
    });
  }

  testWidgets('chặn admin khi đã đăng nhập bằng vai trò User', (tester) async {
    final client = _client([]);
    await _signIn(client);
    await tester.pumpWidget(
      EvShareGridApp(initialLocation: '/admin/clusters', api: client),
    );
    await tester.pumpAndSettle();
    expect(find.text('Đăng nhập'), findsOneWidget);
  });

  testWidgets('đăng xuất xóa JWT, hồ sơ và mã yêu cầu cuối', (tester) async {
    final client = _client([]);
    await _signIn(client);
    await _book(client);
    await tester.pumpWidget(
      EvShareGridApp(initialLocation: '/profile', api: client),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();
    expect(find.text('Đăng nhập'), findsOneWidget);
    expect(client.accessToken, isNull);
    expect(client.currentUser, isNull);
    expect(client.lastRequestId, isNull);
  });

  testWidgets('chọn Host điền email demo khi chưa cấu hình mật khẩu', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 960);
    addTearDown(tester.view.reset);
    final paths = <String>[];
    await tester.pumpWidget(
      EvShareGridApp(initialLocation: '/login', api: _client(paths)),
    );
    await tester.pumpAndSettle();
    final host = find.text('Host');
    await tester.ensureVisible(host);
    await tester.tap(host);
    await tester.pumpAndSettle();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields.first.controller?.text, 'host1@sharegrid.vn');
    expect(fields.last.controller?.text, isEmpty);
    expect(paths, isEmpty);
  });
}
