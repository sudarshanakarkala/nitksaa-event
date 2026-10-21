// Events on computers (filtersInRail): the page is just the header, the
// search and the count; every filter lives in the rail on the left. The
// rail starts closed and opens in its own full-height strip, so nothing
// moves. Short
// windows drop the subtitle. Phones keep the pills on the page.
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
  testWidgets('computers: filters in the rail, not on the page', (tester) async {
    await _show(tester, size: const Size(1366, 900));
    expect(find.text('Upcoming pill'), findsNothing);
    expect(find.text('Date line'), findsNothing);
    expect(find.text('Create event'), findsOneWidget);
    expect(find.text('Reunions, talks and meetups.'), findsOneWidget);
  });

  testWidgets('the rail starts closed and opens in its own strip; nothing moves', (tester) async {
    await _show(tester, size: const Size(1366, 900));
    double railLeft() => tester.getTopLeft(find.text('Rail filters')).dx;
    expect(railLeft(), lessThan(0)); // off screen
    final search = tester.getTopLeft(find.byType(TextField));
    final card = tester.getTopLeft(find.text('Card 0'));

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    expect(railLeft(), greaterThanOrEqualTo(0));
    expect(railLeft(), lessThan(search.dx));
    // Full height, as NITiKA's rail: it starts above the search row.
    expect(tester.getTopLeft(find.text('Rail filters')).dy, lessThan(search.dy));
    expect(tester.getTopLeft(find.byType(TextField)), search);
    expect(tester.getTopLeft(find.text('Card 0')), card);

    await tester.tap(find.byTooltip('Hide filters'));
    await tester.pumpAndSettle();
    expect(railLeft(), lessThan(0));
    expect(tester.getTopLeft(find.text('Card 0')), card);
  });

  testWidgets('short windows drop the subtitle', (tester) async {
    await _show(tester, size: const Size(1366, 640));
    expect(find.text('Reunions, talks and meetups.'), findsNothing);
  });

  testWidgets('phones keep the pills and the date line on the page', (tester) async {
    await _show(tester, size: const Size(390, 800));
    expect(find.text('Upcoming pill'), findsOneWidget);
    expect(find.text('Date line'), findsOneWidget);
  });
}
