import 'package:ev_sharegrid/main.dart';
import 'package:ev_sharegrid/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Các route cần dựng được mà không lỗi layout.
const routes = [
  '/',
  '/onboarding/2',
  '/onboarding/3',
  '/login',
  '/home',
  '/garage',
  '/map',
  '/station',
  '/booking',
  '/schedule',
  '/sessions',
  '/notifications',
  '/profile',
  '/host/stations',
  '/host/ports',
  '/host/schedule',
  '/admin/clusters',
  '/admin/review',
  '/admin/tariff',
  '/admin/solver',
  '/admin/benchmark',
  '/admin/forecast',
];

void main() {
  setUpAll(() => AppFonts.enabled = false);

  for (final size in const [Size(390, 844), Size(1440, 900)]) {
    for (final r in routes) {
      testWidgets('dựng $r ở ${size.width.toInt()}px', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(EvShareGridApp(initialLocation: r));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(Scaffold), findsWidgets);
      });
    }
  }
}
