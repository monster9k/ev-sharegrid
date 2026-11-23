import 'dart:convert';

import 'package:ev_sharegrid/data/api.dart';
import 'package:ev_sharegrid/main.dart';
import 'package:ev_sharegrid/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUpAll(() => AppFonts.enabled = false);
  testWidgets('guests can open onboarding deep links', (tester) async {
    await tester.pumpWidget(EvShareGridApp(initialLocation: '/onboarding/2'));
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    String path() => router.routerDelegate.currentConfiguration.uri.path;
    expect(path(), '/onboarding/2');
    for (final target in ['/', '/onboarding/3', '/login', '/home']) {
      router.go(target);
      await tester.pumpAndSettle();
      expect(path(), target == '/home' ? '/login' : target);
    }
  });

  for (final (role, wrong, home) in [
    ('USER', '/admin', '/home'),
    ('HOST', '/admin/review', '/host/stations'),
    ('ADMIN', '/host/ports', '/admin/clusters'),
  ]) {
    testWidgets('$role về đúng trang và đăng xuất khi hết phiên', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.reset);
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path == '/expired') return http.Response('{}', 401);
          final response = switch (request.url.path) {
            '/api/v1/auth/login' => {'access_token': 'test-token'},
            '/api/v1/auth/me' => {'user_id': 4, 'role': role, 'vehicles': []},
            _ => {'data': []},
          };
          return http.Response(jsonEncode(response), 200);
        }),
      );
      await tester.pumpWidget(EvShareGridApp(initialLocation: wrong, api: api));
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      String path() => router.routerDelegate.currentConfiguration.uri.path;
      expect(path(), '/login');
      await api.login(email: 'example@example.test', password: 'test-only');
      await tester.pumpAndSettle();
      expect(path(), home);
      for (final target in [wrong, '/login']) {
        router.go(target);
        await tester.pumpAndSettle();
        expect(path(), home);
      }
      await expectLater(api.getJson('/expired'), throwsA(isA<ApiException>()));
      await tester.pumpAndSettle();
      expect(path(), '/login');
      expect(api.currentUser, isNull);
      expect(api.accessToken, isNull);
      expect(find.text('Phiên đăng nhập đã hết hạn'), findsOneWidget);
      if (role != 'USER') {
        await api.login(email: 'example@example.test', password: 'test-only');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Đăng xuất'));
        await tester.pumpAndSettle();
        expect(path(), '/login');
        expect(api.accessToken, isNull);
        expect(find.text('Phiên đăng nhập đã hết hạn'), findsNothing);
      }
    });
  }
}
