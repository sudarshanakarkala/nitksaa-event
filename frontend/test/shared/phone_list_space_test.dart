// Phones: list pages give the screen to the list.
//
// - The toolbar stays put while the list scrolls (no jerk at the top).
// - Scrolling down a long list folds the footer away (it tells the app
//   shell); scrolling up, or reaching the top or end, brings it back.
// - Short lists, computers and Check-in (opted out) keep the footer.
// - Phones: no count where the pills count; small actions in the search row.
// - Phones: the date line is one row of chips; "Pick dates" opens the slider.
import 'package:event_app/shared/widgets/filter_controls.dart';
import 'package:event_app/shared/widgets/list_page.dart';
import 'package:event_app/shared/widgets/phone_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ScrollMetrics _m({required double pixels, double max = 2000}) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: max,
      pixels: pixels,
      viewportDimension: 600,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

/// A list page with [rows] rows, on a screen [width] wide. Records what the
/// page tells the page around it.
Future<List<PhoneChromeNotification>> _showList(
  WidgetTester tester, {
  required double width,
  double height = 800,
  String? title,
  int rows = 60,
  bool collapse = true,
  bool countOnPhone = true,
  List<Widget>? phoneActions,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final heard = <PhoneChromeNotification>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NotificationListener<PhoneChromeNotification>(
          onNotification: (n) {
            heard.add(n);
            return false;
          },
          child: ListPage(
            title: title,
            subtitle: title == null ? null : 'Reunions and meetups',
            search: const TextField(decoration: InputDecoration(hintText: 'Search events…')),
            count: const Text('44 events'),
            actions: [FilledButton(onPressed: () {}, child: const Text('Create event'))],
            collapseOnPhone: collapse,
            countOnPhone: countOnPhone,
            phoneActions: phoneActions,
            body: ListView(
              children: [
                for (var i = 0; i < rows; i++) SizedBox(height: 60, child: Text('Row $i')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return heard;
}

void main() {
  group('PhoneChromeTracker', () {
    test('hides the footer after scrolling down a long list, shows it on the way back', () {
      final t = PhoneChromeTracker();
      expect(t.onScroll(_m(pixels: 10), 10), isFalse);
      expect(t.onScroll(_m(pixels: 40), 30), isTrue);
      expect(t.footerHidden, isTrue);
      expect(t.onScroll(_m(pixels: 30), -10), isFalse);
      expect(t.onScroll(_m(pixels: 10), -25), isTrue);
      expect(t.footerHidden, isFalse);
    });

    test('the top and the end show the footer', () {
      final t = PhoneChromeTracker()..onScroll(_m(pixels: 100), 100);
      expect(t.footerHidden, isTrue);
      expect(t.onScroll(_m(pixels: 2000), 50), isTrue);
      expect(t.footerHidden, isFalse);
      t.onScroll(_m(pixels: 500), 100);
      t.onScroll(_m(pixels: 0), -500);
      expect(t.footerHidden, isFalse);
    });

    test('a short list keeps the footer', () {
      final t = PhoneChromeTracker();
      expect(t.onScroll(_m(pixels: 100, max: 300), 100), isFalse);
      expect(t.footerHidden, isFalse);
    });

    test('a list that can no longer scroll shows the footer again', () {
      final t = PhoneChromeTracker()..onScroll(_m(pixels: 100), 100);
      expect(t.onMetrics(_m(pixels: 0, max: 0)), isTrue);
      expect(t.footerHidden, isFalse);
    });
  });

  group('ListPage on a phone', () {
    testWidgets('the toolbar stays put; the footer folds away and comes back', (tester) async {
      final heard = await _showList(tester, width: 390);
      final searchTop = tester.getTopLeft(find.byType(TextField)).dy;

      await tester.drag(find.text('Row 3'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(TextField)).dy, searchTop);
      expect(heard.last.footerHidden, isTrue);

      await tester.drag(find.byType(ListView), const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(TextField)).dy, searchTop);
      expect(heard.last.footerHidden, isFalse);
    });

    testWidgets('a short list keeps the footer', (tester) async {
      final heard = await _showList(tester, width: 390, rows: 12);
      await tester.drag(find.text('Row 3'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(heard, isEmpty);
    });

    testWidgets('opted out (Check-in): the footer stays, nothing is sent', (tester) async {
      final heard = await _showList(tester, width: 390, collapse: false);
      await tester.drag(find.text('Row 3'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(heard, isEmpty);
    });

    testWidgets('no count where the pills count; actions in the search row', (tester) async {
      await _showList(
        tester,
        width: 390,
        countOnPhone: false,
        phoneActions: [
          ListIconAction(icon: Icons.add, tooltip: 'Create event', onPressed: () {}, filled: true),
        ],
      );
      expect(find.text('44 events'), findsNothing);
      expect(find.byTooltip('Create event'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Create event'), findsNothing);
      // Same row as the search box.
      final searchY = tester.getCenter(find.byType(TextField)).dy;
      expect(tester.getCenter(find.byTooltip('Create event')).dy, moreOrLessEquals(searchY, epsilon: 4));
    });
  });

  testWidgets('computers: unchanged (footer stays, count and Create event)', (tester) async {
    final heard = await _showList(
      tester,
      width: 1200,
      countOnPhone: false,
      phoneActions: [ListIconAction(icon: Icons.add, tooltip: 'Create event', onPressed: () {})],
    );
    expect(find.text('44 events'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create event'), findsOneWidget);
    await tester.drag(find.text('Row 3'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(heard, isEmpty);
  });

  testWidgets('a short laptop window: compact top, the footer folds away', (tester) async {
    final heard = await _showList(tester, width: 1200, height: 500, title: 'Events');
    expect(find.text('Events'), findsOneWidget);
    expect(find.text('NITKSAA ALUMNI NETWORK'), findsNothing);
    expect(find.text('Reunions and meetups'), findsNothing);
    // Still the computer's count line and actions.
    expect(find.text('44 events'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create event'), findsOneWidget);
    await tester.drag(find.text('Row 3'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(heard.last.footerHidden, isTrue);
  });

  testWidgets('a tall computer window keeps the eyebrow and subtitle', (tester) async {
    await _showList(tester, width: 1200, height: 900, title: 'Events');
    expect(find.text('NITKSAA ALUMNI NETWORK'), findsOneWidget);
    expect(find.text('Reunions and meetups'), findsOneWidget);
  });

  group('Date line on a phone', () {
    Future<void> showDates(WidgetTester tester, ValueNotifier<DateTimeRange?> value) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final today = DateUtils.dateOnly(DateTime.now());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<DateTimeRange?>(
              valueListenable: value,
              builder: (context, v, _) => FilterDateRange(
                inline: true,
                label: 'Starts',
                first: today,
                last: today.add(const Duration(days: 120)),
                value: v,
                presets: [
                  ('This week', DateTimeRange(start: today, end: today.add(const Duration(days: 6)))),
                ],
                onChanged: (r) => value.value = r,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('chips only; Pick dates opens the slider and From – To', (tester) async {
      final value = ValueNotifier<DateTimeRange?>(null);
      await showDates(tester, value);
      expect(find.text('This week'), findsOneWidget);
      expect(find.byType(RangeSlider), findsNothing);
      expect(find.text('From'), findsNothing);

      await tester.tap(find.text('Pick dates'));
      await tester.pumpAndSettle();
      expect(find.byType(RangeSlider), findsOneWidget);
      expect(find.text('From'), findsOneWidget);

      await tester.tap(find.text('Pick dates'));
      await tester.pumpAndSettle();
      expect(find.byType(RangeSlider), findsNothing);
    });

    testWidgets('a picked range keeps it open; closing clears it', (tester) async {
      final today = DateUtils.dateOnly(DateTime.now());
      final value = ValueNotifier<DateTimeRange?>(
        DateTimeRange(start: today.add(const Duration(days: 20)), end: today.add(const Duration(days: 40))),
      );
      await showDates(tester, value);
      expect(find.byType(RangeSlider), findsOneWidget);

      await tester.tap(find.text('Pick dates'));
      await tester.pumpAndSettle();
      expect(value.value, isNull);
      expect(find.byType(RangeSlider), findsNothing);
    });
  });
}
