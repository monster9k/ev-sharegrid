import 'package:ev_sharegrid/theme.dart';
import 'package:ev_sharegrid/widgets/api_content.dart';
import 'package:ev_sharegrid/widgets/common.dart';
import 'package:ev_sharegrid/widgets/glass.dart';
import 'package:ev_sharegrid/widgets/mobile_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => AppFonts.enabled = false);

  testWidgets('the last row clears the nav at the end of the list', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    tester.view.padding = tester.view.viewPadding = const FakeViewPadding(
      bottom: 34,
    );
    addTearDown(tester.view.reset);

    const lastKey = ValueKey('last-row');
    await tester.pumpWidget(
      MaterialApp(
        home: UserScaffold(
          tab: UserTab.map,
          showSimulationTag: false,
          children: [
            for (var index = 1; index <= 23; index++)
              SizedBox(height: 64, child: Text('Trạm $index')),
            const SizedBox(key: lastKey, height: 64, child: Text('Trạm cuối')),
          ],
        ),
      ),
    );

    final lastRow = find.byKey(lastKey);
    final scrollable = find.byType(Scrollable);
    await tester.scrollUntilVisible(lastRow, 350, scrollable: scrollable);
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();

    final row = tester.getRect(lastRow);
    final nav = tester.getRect(find.byType(GlassNavBar));
    final viewport = tester.getRect(find.byType(ListView));
    expect(row.top, greaterThanOrEqualTo(viewport.top));
    expect(row.bottom, lessThanOrEqualTo(nav.top));
    expect(viewport.bottom, lessThanOrEqualTo(nav.top));
    expect(nav.bottom, lessThanOrEqualTo(640 - 34));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the short error state and retry sit above the nav', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 600);
    addTearDown(tester.view.reset);

    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MobileFrame(
          child: UserScaffold(
            tab: UserTab.bookings,
            showSimulationTag: false,
            children: [
              ApiErrorCard(
                error: StateError('Unavailable'),
                onRetry: () => retries++,
              ),
            ],
          ),
        ),
      ),
    );

    final navTop = tester.getTopLeft(find.byType(GlassNavBar)).dy;
    final list = find.byType(ListView);
    expect(tester.getBottomLeft(list).dy, lessThanOrEqualTo(navTop));
    expect(
      tester.getBottomLeft(find.byType(ApiErrorCard)).dy,
      lessThanOrEqualTo(navTop),
    );
    final retry = find.widgetWithText(TextButton, 'Thử lại');
    await tester.tap(retry);
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the form action and scroll area clear the keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    var sends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: UserScaffold(
          showSimulationTag: false,
          actionBar: GlassActionBar(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Gửi yêu cầu',
                  onPressed: () => sends++,
                ),
              ),
            ],
          ),
          children: const [SizedBox(height: 440), TextField()],
        ),
      ),
    );

    final field = find.byType(TextField);
    await tester.showKeyboard(field);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();

    final action = tester.getRect(find.byType(GlassActionBar));
    final viewport = tester.getRect(find.byType(ListView));
    final input = tester.getRect(field);
    expect(action.bottom, lessThanOrEqualTo(844 - 320));
    expect(viewport.bottom, lessThanOrEqualTo(action.top));
    expect(input.top, greaterThanOrEqualTo(viewport.top));
    expect(input.bottom, lessThanOrEqualTo(action.top));
    expect(find.byType(GlassNavBar), findsNothing);
    await tester.tap(find.text('Gửi yêu cầu'));
    expect(sends, 1);
    expect(tester.takeException(), isNull);
  });
}
