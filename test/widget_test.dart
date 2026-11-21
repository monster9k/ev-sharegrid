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

  testWidgets('lịch không có response không hiển thị lịch mẫu', (tester) async {
    await tester.pumpWidget(EvShareGridApp(initialLocation: '/schedule'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Chưa có lịch sạc. Hãy gửi yêu cầu ở màn Đặt lịch.'),
      findsOneWidget,
    );
    expect(
      find.text('Request #R-5012 · Job #J-2291 · Run #1042'),
      findsNothing,
    );
    expect(find.text('Dữ liệu mô phỏng'), findsNothing);
  });

  testWidgets('chọn ngày và giờ 24h ở form đặt lịch', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(EvShareGridApp(initialLocation: '/booking'));
    await tester.pumpAndSettle();
    expect(find.text('Dữ liệu mô phỏng'), findsNothing);

    final timeTile = find
        .textContaining(RegExp(r'\d{2}/\d{2}/\d{4} · \d{2}:\d{2}'))
        .first;
    await Scrollable.ensureVisible(tester.element(timeTile), alignment: .5);
    await tester.pumpAndSettle();
    expect(timeTile.hitTestable(), findsOneWidget);
    await tester.tap(timeTile);
    await tester.pumpAndSettle();
    expect(find.text('Chọn ngày đến'), findsOneWidget);
    expect(find.textContaining('Ngày mai'), findsOneWidget);

    await tester.tap(find.textContaining('Hôm nay'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn giờ đến'), findsOneWidget);
    expect(find.text('AM'), findsNothing);
    expect(find.text('PM'), findsNothing);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
  });

  testWidgets('lịch đặt hiện lời nhắc đăng nhập khi chưa có phiên', (
    tester,
  ) async {
    await tester.pumpWidget(EvShareGridApp(initialLocation: '/sessions'));
    await tester.pumpAndSettle();
    expect(find.text('Đăng nhập để xem lịch sạc.'), findsOneWidget);
    expect(find.text('Dữ liệu mô phỏng'), findsNothing);
  });

  testWidgets('onboarding đọc được hết mô tả trên màn nhỏ và web', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);

    for (final size in const [Size(360, 640), Size(1440, 900)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(EvShareGridApp(initialLocation: '/'));
      await tester.pumpAndSettle();

      for (final (phrase, button) in const [
        ('Trạm công cộng và điểm sạc', 'Tiếp tục'),
        ('Cho biết pin hiện tại', 'Tiếp tục'),
        ('Có trụ sạc ở nhà', 'Bắt đầu'),
      ]) {
        final description = find.textContaining(phrase);
        final viewport = find.ancestor(
          of: description,
          matching: find.byType(Scrollable),
        );
        await tester.ensureVisible(description);
        await tester.pumpAndSettle();

        final textRect = tester.getRect(description);
        final scrollRect = tester.getRect(viewport.first);
        expect(textRect.top, greaterThanOrEqualTo(scrollRect.top - 0.01));
        expect(textRect.bottom, lessThanOrEqualTo(scrollRect.bottom + 0.01));
        expect(tester.takeException(), isNull);
        final action = find.text(button);
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        await tester.tap(action);
        await tester.pumpAndSettle();
      }
    }
  });

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
