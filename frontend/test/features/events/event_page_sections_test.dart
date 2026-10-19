// The event page's Agenda, Speakers and Sponsors (B1).
//
// - Small events (the breakfast) keep today's list, with no search and no
//   tier headings.
// - Big events: parallel sessions swipe on a phone ("1 of 6") and sit in a
//   grid on a computer; hall, subtitle and break bands show.
// - Speakers: the first 12, "Show all", search by name or company.
// - Speakers under each session (B2): the first 3, "+N more", a moderator
//   labelled; sessions without linked people keep their speaker line.
// - Sponsors across tiers get a heading per tier.
// - Session details (B4): a Break band by type, type and pillar on the card,
//   "Presented by", a pillar filter; a sponsor's label instead of its tier.
import 'package:event_app/features/events/domain/event.dart';
import 'package:event_app/features/events/presentation/widgets/agenda_section.dart';
import 'package:event_app/features/events/presentation/widgets/speakers_section.dart';
import 'package:event_app/features/events/presentation/widgets/sponsors_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _show(WidgetTester tester, Widget child, {required double width}) async {
  tester.view.physicalSize = Size(width, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DateTime _t(int hour, int minute) => DateTime(2027, 2, 14, hour, minute);

EventSession _s(int id, String title, DateTime start,
        {DateTime? end, String? hall, String? subtitle, String? speaker}) =>
    EventSession(
      sessionId: id,
      title: title,
      startDatetime: start,
      endDatetime: end,
      track: hall,
      description: subtitle,
      speakerName: speaker,
    );

/// A NITKonnect-like day: a keynote, tea, then six sessions at 2:00 PM.
List<EventSession> _bigAgenda() => [
      _s(1, 'Keynote', _t(9, 30), end: _t(10, 15), subtitle: 'Building for Bharat'),
      _s(2, 'Tea break', _t(11, 40), end: _t(12, 0)),
      for (var i = 1; i <= 6; i++)
        _s(10 + i, 'Parallel $i', _t(14, 0),
            end: _t(14, 40), hall: i <= 3 ? 'Hall ${String.fromCharCode(64 + i)}' : null),
    ];

EventPerson _p(int id, String name, {String? org}) =>
    EventPerson(personId: id, role: 'SPEAKER', fullname: name, title: 'CTO', organisation: org ?? 'Acme');

EventSponsor _sponsor(int id, String name, String type) =>
    EventSponsor(sponsorId: id, eventId: 1, sponsorType: type, name: name, displayOrder: id);

void main() {
  group('Agenda', () {
    testWidgets('a small agenda stays the simple list', (tester) async {
      await _show(
        tester,
        AgendaSection(sessions: [
          _s(1, 'Welcome', _t(8, 0), end: _t(8, 30), speaker: 'A. Rao'),
          _s(2, 'Breakfast', _t(8, 30), end: _t(9, 30)),
        ]),
        width: 390,
      );
      expect(find.text('Welcome - A. Rao'), findsOneWidget);
      expect(find.text('8:00 AM – 8:30 AM'), findsOneWidget);
      expect(find.textContaining('sessions at once'), findsNothing);
      // "Breakfast" isn't a break band.
      expect(find.byIcon(Icons.local_cafe_outlined), findsNothing);
    });

    testWidgets('phone: parallel sessions swipe, with "1 of 6"', (tester) async {
      await _show(tester, AgendaSection(sessions: _bigAgenda()), width: 390);

      expect(find.text('6 sessions at once'), findsOneWidget);
      expect(find.text('2:00 PM – 2:40 PM'), findsOneWidget);
      expect(find.text('1 of 6'), findsOneWidget);
      expect(find.text('Hall A'), findsOneWidget);
      expect(find.text('Building for Bharat'), findsOneWidget);
      expect(find.text('Tea break · 11:40 AM – 12:00 PM'), findsOneWidget);

      await tester.drag(find.text('Parallel 1'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 of 6'), findsOneWidget);
    });

    testWidgets('computer: parallel sessions in a grid, no counter', (tester) async {
      await _show(tester, AgendaSection(sessions: _bigAgenda()), width: 1400);

      expect(find.text('6 sessions at once'), findsOneWidget);
      expect(find.text('1 of 6'), findsNothing);
      for (var i = 1; i <= 6; i++) {
        expect(find.text('Parallel $i'), findsOneWidget);
      }
      // Three across: Parallel 1 to 3 on one row, 4 below.
      final y1 = tester.getTopLeft(find.text('Parallel 1')).dy;
      expect(tester.getTopLeft(find.text('Parallel 3')).dy, y1);
      expect(tester.getTopLeft(find.text('Parallel 4')).dy, greaterThan(y1));
    });

    testWidgets('different end times show on each card', (tester) async {
      await _show(
        tester,
        AgendaSection(sessions: [
          _s(1, 'Short', _t(14, 0), end: _t(14, 30)),
          _s(2, 'Long', _t(14, 0), end: _t(15, 0)),
        ]),
        width: 1400,
      );
      expect(find.text('2:00 PM'), findsOneWidget);
      expect(find.text('Until 2:30 PM'), findsOneWidget);
      expect(find.text('Until 3:00 PM'), findsOneWidget);
    });
  });

  group('Speakers under each session (B2)', () {
    // Two sessions at 2:00 PM, so the big layout is on.
    List<EventSession> agenda() => [
          EventSession(
            sessionId: 1,
            title: 'Big panel',
            startDatetime: _t(14, 0),
            endDatetime: _t(14, 40),
            people: [
              for (var i = 1; i <= 5; i++)
                SessionPersonRef(personId: i, role: i == 1 ? 'MODERATOR' : 'PANELIST'),
            ],
          ),
          _s(2, 'Workshop', _t(14, 0), end: _t(14, 40), speaker: 'A. Rao'),
        ];
    final people = [for (var i = 1; i <= 5; i++) _p(i, 'Person $i', org: 'Org $i')];

    testWidgets('the first 3, then +2 more; a moderator labelled', (tester) async {
      await _show(tester, AgendaSection(sessions: agenda(), people: people), width: 1400);
      expect(find.text('Person 2'), findsOneWidget);
      expect(find.text('Person 3'), findsOneWidget);
      expect(find.text('Person 4'), findsNothing);
      expect(find.text('Person 1 · Moderator'), findsOneWidget);
      expect(find.text('CTO · Org 2'), findsOneWidget);

      await tester.tap(find.text('+2 more'));
      await tester.pumpAndSettle();
      expect(find.text('Person 5'), findsOneWidget);
      expect(find.text('Show fewer'), findsOneWidget);
    });

    testWidgets('a session without linked people keeps its speaker line', (tester) async {
      await _show(tester, AgendaSection(sessions: agenda(), people: people), width: 1400);
      expect(find.text('A. Rao'), findsOneWidget);
    });

    testWidgets('people not found (hidden) are left out', (tester) async {
      await _show(tester, AgendaSection(sessions: agenda(), people: people.take(2).toList()), width: 1400);
      expect(find.text('Person 2'), findsOneWidget);
      expect(find.text('Person 3'), findsNothing);
      expect(find.textContaining('more'), findsNothing);
    });
  });

  group('Speakers', () {
    testWidgets('up to 12 speakers: today\'s list, no search', (tester) async {
      await _show(tester, SpeakersSection(speakers: [for (var i = 1; i <= 3; i++) _p(i, 'Speaker $i')]),
          width: 390);
      expect(find.text('Speakers'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Speaker 3'), findsOneWidget);
    });

    testWidgets('many speakers: first 12, Show all, search', (tester) async {
      final speakers = [
        for (var i = 1; i <= 19; i++) _p(i, 'Speaker $i'),
        _p(20, 'Meera Bhat', org: 'Zeta Labs'),
      ];
      await _show(tester, SpeakersSection(speakers: speakers), width: 1400);

      expect(find.text('Speakers · 20'), findsOneWidget);
      expect(find.text('Speaker 12'), findsOneWidget);
      expect(find.text('Speaker 13'), findsNothing);

      await tester.tap(find.text('Show all 20 speakers'));
      await tester.pumpAndSettle();
      expect(find.text('Speaker 13'), findsOneWidget);
      expect(find.text('Meera Bhat'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zeta');
      await tester.pumpAndSettle();
      expect(find.text('Meera Bhat'), findsOneWidget);
      expect(find.text('Speaker 1'), findsNothing);

      await tester.enterText(find.byType(TextField), 'nobody');
      await tester.pumpAndSettle();
      expect(find.text('No speakers match "nobody".'), findsOneWidget);
    });
  });

  group('Sponsors', () {
    testWidgets('one tier: today\'s SPONSORS heading', (tester) async {
      await _show(
        tester,
        SponsorsSection(
          sponsors: [_sponsor(1, 'Acme', 'GOLD_SPONSOR'), _sponsor(2, 'Zeta', 'GOLD_SPONSOR')],
          partners: const [],
          onOpenLink: (_) {},
        ),
        width: 1400,
      );
      expect(find.text('SPONSORS'), findsOneWidget);
      expect(find.text('GOLD SPONSOR'), findsNothing);
    });

    testWidgets('several tiers: a heading per tier, title sponsor first', (tester) async {
      await _show(
        tester,
        SponsorsSection(
          sponsors: [
            _sponsor(1, 'Gold Co', 'GOLD_SPONSOR'),
            _sponsor(2, 'Title Co', 'TITLE_SPONSOR'),
            _sponsor(3, 'Silver Co', 'SILVER_SPONSOR'),
          ],
          partners: const [],
          onOpenLink: (_) {},
        ),
        width: 1400,
      );
      expect(find.text('SPONSORS'), findsNothing);
      final title = tester.getTopLeft(find.text('TITLE SPONSOR')).dy;
      final gold = tester.getTopLeft(find.text('GOLD SPONSOR')).dy;
      final silver = tester.getTopLeft(find.text('SILVER SPONSOR')).dy;
      expect(title, lessThan(gold));
      expect(gold, lessThan(silver));
    });
  });

  group('Session details (B4)', () {
    EventSession typed(int id, String title, DateTime start,
            {String? type, String? pillar, List<int> presentedBy = const [], String? speaker}) =>
        EventSession(
          sessionId: id,
          title: title,
          startDatetime: start,
          endDatetime: start.add(const Duration(minutes: 40)),
          sessionType: type,
          pillar: pillar,
          presentedBy: presentedBy,
          speakerName: speaker,
        );

    List<EventSession> agenda() => [
          typed(1, 'Opening', _t(9, 0), type: 'KEYNOTE', pillar: 'Main Event'),
          typed(2, 'Networking lunch', _t(13, 0), type: 'BREAK'),
          typed(3, 'Future of Work', _t(14, 0), type: 'PANEL', pillar: 'Career Konnect', presentedBy: [7, 8]),
          typed(4, 'Pitches', _t(14, 0), type: 'SHOWCASE', pillar: 'Startup Showcase'),
        ];

    final sponsors = [_sponsor(7, 'Acme', 'GOLD_SPONSOR'), _sponsor(8, 'Beta Labs', 'SILVER_SPONSOR')];

    testWidgets('a Break by type is a band, whatever its title', (tester) async {
      await _show(tester, AgendaSection(sessions: agenda(), sponsors: sponsors), width: 1400);
      expect(find.text('Networking lunch · 1:00 PM – 1:40 PM'), findsOneWidget);
    });

    testWidgets('a typed session is not a band, even titled Lunch', (tester) async {
      await _show(
        tester,
        AgendaSection(sessions: [
          typed(1, 'Lunch with the founders', _t(13, 0), type: 'PANEL'),
          typed(2, 'Other', _t(13, 0)),
        ]),
        width: 1400,
      );
      expect(find.byIcon(Icons.local_cafe_outlined), findsNothing);
      expect(find.text('Lunch with the founders'), findsOneWidget);
    });

    testWidgets('type and pillar above the title; Presented by under it', (tester) async {
      await _show(tester, AgendaSection(sessions: agenda(), sponsors: sponsors), width: 1400);
      expect(find.text('Panel · Career Konnect'), findsOneWidget);
      expect(find.text('Keynote · Main Event'), findsOneWidget);
      expect(find.text('Presented by Acme & Beta Labs'), findsOneWidget);
    });

    testWidgets('pillar chips filter the agenda; breaks always show', (tester) async {
      await _show(tester, AgendaSection(sessions: agenda(), sponsors: sponsors), width: 1400);
      expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Career Konnect'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Career Konnect'));
      await tester.pumpAndSettle();
      expect(find.text('Future of Work'), findsOneWidget);
      expect(find.text('Pitches'), findsNothing);
      expect(find.text('Opening'), findsNothing);
      expect(find.text('Networking lunch · 1:00 PM – 1:40 PM'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      expect(find.text('Pitches'), findsOneWidget);
    });

    testWidgets('one pillar or none: no filter', (tester) async {
      await _show(
        tester,
        AgendaSection(sessions: [
          typed(1, 'A', _t(14, 0), pillar: 'Main Event'),
          typed(2, 'B', _t(14, 0)),
        ]),
        width: 1400,
      );
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('the small agenda is unchanged by the new fields', (tester) async {
      await _show(
        tester,
        AgendaSection(sessions: [
          typed(1, 'Welcome', _t(8, 0), type: 'TALK', pillar: 'Main Event', presentedBy: [7], speaker: 'A. Rao'),
          typed(2, 'Breakfast', _t(8, 40), type: 'BREAK'),
        ], sponsors: sponsors),
        width: 390,
      );
      expect(find.text('Welcome - A. Rao'), findsOneWidget);
      expect(find.textContaining('Presented by'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets("a sponsor's label shows instead of its tier", (tester) async {
      await _show(
        tester,
        SponsorsSection(
          sponsors: [
            EventSponsor(
              sponsorId: 1, eventId: 1, sponsorType: 'GOLD_SPONSOR', name: 'Acme',
              displayOrder: 1, label: 'Co-presenter',
            ),
            _sponsor(2, 'Beta Labs', 'GOLD_SPONSOR'),
          ],
          partners: const [],
          onOpenLink: (_) {},
        ),
        width: 1400,
      );
      expect(find.text('Co-presenter'), findsOneWidget);
      expect(find.text('Gold Sponsor'), findsOneWidget);
    });
  });
}
