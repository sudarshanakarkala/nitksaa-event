// Events on computers (filtersInRail): the page is just the header, the
// search and the count; every filter lives in the rail on the left, open
// from the start (website directory). Short windows drop the subtitle.
// Phones keep the pills on the page.
import 'package:event_app/shared/widgets/list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _show(WidgetTester tester, {required Size size}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListPage(
          filtersInRail: true,
          title: 'Events',
          subtitle: 'Reunions, talks and meetups.',
          search: const TextField(decoration: InputDecoration(hintText: 'Search events…')),
          count: const Text('22 events'),
          actions: [FilledButton(onPressed: () {}, child: const Text('Create event'))],
          quickFilters: const [Text('Upcoming pill')],
          belowPills: const Text('Date line'),
          filters: (_) => const Text('Rail filters'),
          onOpenFilters: () {},
          body: ListView(children: [for (var i = 0; i < 30; i++) Text('Card $i')]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('computers: filters in the open rail, not on the page', (tester) async {
    await _show(tester, size: const Size(1366, 900));
    expect(find.text('Rail filters'), findsOneWidget);
    expect(find.text('Upcoming pill'), findsNothing);
    expect(find.text('Date line'), findsNothing);
    expect(find.text('Create event'), findsOneWidget);
    // The rail is on screen, left of the search.
    final rail = tester.getTopLeft(find.text('Rail filters'));
    expect(rail.dx, greaterThanOrEqualTo(0));
    expect(rail.dx, lessThan(tester.getTopLeft(find.byType(TextField)).dx));
    expect(find.text('Reunions, talks and meetups.'), findsOneWidget);
  });

  testWidgets('short windows drop the subtitle', (tester) async {
    await _show(tester, size: const Size(1366, 640));
    expect(find.text('Reunions, talks and meetups.'), findsNothing);
  });

  testWidgets('closing the rail gives its strip to the list', (tester) async {
    await _show(tester, size: const Size(1366, 900));
    final before = tester.getTopLeft(find.byType(TextField)).dx;
    await tester.tap(find.byTooltip('Close filters'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(TextField)).dx, lessThan(before));
  });

  testWidgets('phones keep the pills and the date line on the page', (tester) async {
    await _show(tester, size: const Size(390, 800));
    expect(find.text('Upcoming pill'), findsOneWidget);
    expect(find.text('Date line'), findsOneWidget);
  });
}
