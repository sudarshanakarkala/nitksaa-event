// The big-event agenda grouping (B1): time slots, hall order, days, breaks.
import 'package:event_app/features/events/domain/agenda_slots.dart';
import 'package:event_app/features/events/domain/event.dart';
import 'package:flutter_test/flutter_test.dart';

EventSession _s(
  int id,
  String title,
  DateTime start, {
  DateTime? end,
  String? hall,
  String? speaker,
}) =>
    EventSession(
      sessionId: id,
      title: title,
      startDatetime: start,
      endDatetime: end,
      track: hall,
      speakerName: speaker,
    );

DateTime _t(int hour, int minute, {int day = 14}) => DateTime(2027, 2, day, hour, minute);

void main() {
  group('hasParallel', () {
    test('false when every session starts at its own time (the breakfast)', () {
      expect(
        Agenda.hasParallel([_s(1, 'Welcome', _t(8, 0)), _s(2, 'Talk', _t(8, 30))]),
        isFalse,
      );
    });

    test('true when two sessions start at the same minute', () {
      expect(
        Agenda.hasParallel([
          _s(1, 'Panel A', _t(14, 0)),
          _s(2, 'Panel B', DateTime(2027, 2, 14, 14, 0, 30)),
        ]),
        isTrue,
      );
    });

    test('false with no sessions', () => expect(Agenda.hasParallel(const []), isFalse));
  });

  group('build', () {
    test('groups by start minute, in time order', () {
      final days = Agenda.build([
        _s(3, 'Lunch', _t(13, 0)),
        _s(1, 'Keynote', _t(9, 30)),
        _s(4, 'Panel A', _t(14, 0)),
        _s(5, 'Panel B', _t(14, 0)),
      ]);
      expect(days, hasLength(1));
      final slots = days.single.slots;
      expect(slots.map((s) => s.start), [_t(9, 30), _t(13, 0), _t(14, 0)]);
      expect(slots[2].isParallel, isTrue);
      expect(slots[2].sessions.map((s) => s.title), ['Panel A', 'Panel B']);
    });

    test('halls first, by name; then the server order', () {
      final slot = Agenda.build([
        _s(1, 'No hall 1', _t(14, 0)),
        _s(2, 'In C', _t(14, 0), hall: 'Hall C'),
        _s(3, 'No hall 2', _t(14, 0)),
        _s(4, 'In A', _t(14, 0), hall: 'hall a'),
      ]).single.slots.single;
      expect(slot.sessions.map((s) => s.title), ['In A', 'In C', 'No hall 1', 'No hall 2']);
    });

    test('a new day starts a new group', () {
      final days = Agenda.build([
        _s(1, 'Day 1', _t(9, 0)),
        _s(2, 'Day 2', _t(9, 0, day: 15)),
      ]);
      expect(days.map((d) => d.date), [DateTime(2027, 2, 14), DateTime(2027, 2, 15)]);
    });

    test('sharedEnd only when every session ends together', () {
      final same = Agenda.build([
        _s(1, 'A', _t(14, 0), end: _t(14, 40)),
        _s(2, 'B', _t(14, 0), end: _t(14, 40)),
      ]).single.slots.single;
      expect(same.sharedEnd, _t(14, 40));

      final differ = Agenda.build([
        _s(1, 'A', _t(14, 0), end: _t(14, 40)),
        _s(2, 'B', _t(14, 0), end: _t(15, 0)),
      ]).single.slots.single;
      expect(differ.sharedEnd, isNull);
    });
  });

  group('breaks', () {
    test('tea, lunch, break and dinner with no speaker', () {
      for (final title in ['Tea break', 'LUNCH', 'Break', 'Dinner and networking']) {
        expect(Agenda.looksLikeBreak(_s(1, title, _t(11, 40))), isTrue, reason: title);
      }
    });

    test('not with a speaker, not other titles, not breakfast', () {
      expect(Agenda.looksLikeBreak(_s(1, 'Lunch keynote', _t(13, 0), speaker: 'A. Rao')), isFalse);
      expect(Agenda.looksLikeBreak(_s(1, 'Breakfast meeting', _t(8, 0))), isFalse);
      expect(Agenda.looksLikeBreak(_s(1, 'Teaching AI', _t(8, 0))), isFalse);
    });

    test('a slot of parallel sessions is never a break', () {
      final slot = Agenda.build([
        _s(1, 'Lunch', _t(13, 0)),
        _s(2, 'Lunch', _t(13, 0)),
      ]).single.slots.single;
      expect(slot.isBreak, isFalse);
    });
  });

  group('B4', () {
    EventSession typed(String title, {String? type, String? pillar}) => EventSession(
          sessionId: title.hashCode,
          title: title,
          startDatetime: DateTime(2027, 2, 14, 10),
          sessionType: type,
          pillar: pillar,
        );

    test('the type decides a break when it is set', () {
      expect(Agenda.looksLikeBreak(typed('Networking lunch', type: 'BREAK')), isTrue);
      expect(Agenda.looksLikeBreak(typed('Lunch talk', type: 'TALK')), isFalse);
      expect(Agenda.looksLikeBreak(typed('Tea')), isTrue); // no type: the title guess
    });

    test('pillars in the order they first appear, once each', () {
      expect(
        Agenda.pillars([
          typed('a', pillar: 'Main Event'),
          typed('b'),
          typed('c', pillar: 'Career Konnect'),
          typed('d', pillar: 'Main Event'),
        ]),
        ['Main Event', 'Career Konnect'],
      );
    });

    test('names joined with commas and a final &', () {
      expect(Agenda.joinNames(['A']), 'A');
      expect(Agenda.joinNames(['A', 'B']), 'A & B');
      expect(Agenda.joinNames(['A', 'B', 'C']), 'A, B & C');
    });

    test('session and sponsor read the B4 fields', () {
      final session = EventSession.fromJson({
        'session_id': 1,
        'title': 'Panel',
        'start_datetime': '2027-02-14T10:00:00+05:30',
        'session_type': 'panel',
        'pillar': '  ',
        'presented_by': [3, 4],
      });
      expect(session.sessionType, 'PANEL');
      expect(session.typeLabel, 'Panel');
      expect(session.pillar, isNull);
      expect(session.presentedBy, [3, 4]);

      final old = EventSession.fromJson({
        'session_id': 2,
        'title': 'Talk',
        'start_datetime': '2027-02-14T10:00:00+05:30',
      });
      expect(old.sessionType, isNull);
      expect(old.presentedBy, isEmpty);

      final sponsor = EventSponsor.fromJson({
        'sponsor_id': 1, 'event_id': 1, 'sponsor_type': 'GOLD_SPONSOR', 'name': 'Acme',
        'label': 'Co-presenter',
      });
      expect(sponsor.shownLabel, 'Co-presenter');
      expect(
        EventSponsor.fromJson({'sponsor_id': 2, 'event_id': 1, 'sponsor_type': 'GOLD_SPONSOR', 'name': 'B'})
            .shownLabel,
        'Gold Sponsor',
      );
    });
  });
}
