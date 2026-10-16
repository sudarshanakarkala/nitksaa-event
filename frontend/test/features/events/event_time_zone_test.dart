// Event times in the event's own timezone (EventTimeZone).
//
// - Summer time: a wall time is read with the offset in force on that date,
//   including the hour when clocks go back (first one) and the hour that
//   doesn't exist when they go forward (moved on, as browsers do).
// - Zones without summer time work off the web too (tests in the VM).
// - Unknown zones are refused, not read as IST.
import 'package:event_app/features/events/domain/event_time_zone.dart';
import 'package:flutter_test/flutter_test.dart';

/// A New York-like rule for 2026: -4h from 8 Mar 07:00Z to 1 Nov 06:00Z,
/// else -5h.
int? _newYorkLike(DateTime utc) {
  final start = DateTime.utc(2026, 3, 8, 7);
  final end = DateTime.utc(2026, 11, 1, 6);
  return !utc.isBefore(start) && utc.isBefore(end) ? -240 : -300;
}

void main() {
  group('instantFromWall (summer time)', () {
    DateTime? at(int m, int d, int h, [int min = 0]) =>
        EventTimeZone.instantFromWall(DateTime(2026, m, d, h, min), _newYorkLike);

    test('winter and summer use their own offsets', () {
      expect(at(1, 15, 9), DateTime.utc(2026, 1, 15, 14));
      expect(at(7, 10, 9), DateTime.utc(2026, 7, 10, 13));
    });

    test('the days clocks change, either side of the change', () {
      expect(at(3, 8, 1, 30), DateTime.utc(2026, 3, 8, 6, 30));
      expect(at(3, 8, 9), DateTime.utc(2026, 3, 8, 13));
      expect(at(11, 1, 0, 30), DateTime.utc(2026, 11, 1, 4, 30));
      expect(at(11, 1, 9), DateTime.utc(2026, 11, 1, 14));
    });

    test('a time that happens twice is the first one', () {
      expect(at(11, 1, 1, 30), DateTime.utc(2026, 11, 1, 5, 30));
    });

    test("a time that doesn't exist moves on by the gap", () {
      // 2:30 am on 8 Mar is 3:30 am summer time.
      expect(at(3, 8, 2, 30), DateTime.utc(2026, 3, 8, 7, 30));
    });

    test('an unknown zone gives null', () {
      expect(
        EventTimeZone.instantFromWall(DateTime(2026, 1, 1), (_) => null),
        isNull,
      );
    });
  });

  group('zones without summer time (also off the web)', () {
    test('IST: 8:00 am is 02:30 UTC, saved with +05:30', () {
      expect(
        EventTimeZone.iso(DateTime(2026, 11, 15, 8), 'Asia/Kolkata'),
        '2026-11-15T08:00:00+05:30',
      );
      expect(
        EventTimeZone.instantOf(DateTime(2026, 11, 15, 8), 'Asia/Kolkata'),
        DateTime.utc(2026, 11, 15, 2, 30),
      );
    });

    test('a saved moment reads back as the same wall time', () {
      final wall = EventTimeZone.wallTime(
        DateTime.utc(2026, 11, 15, 2, 30),
        'Asia/Kolkata',
      )!;
      expect(
        [wall.year, wall.month, wall.day, wall.hour, wall.minute],
        [2026, 11, 15, 8, 0],
      );
    });

    test('UTC and Tokyo', () {
      expect(
        EventTimeZone.iso(DateTime(2026, 2, 1, 18, 45), 'UTC'),
        '2026-02-01T18:45:00+00:00',
      );
      expect(
        EventTimeZone.iso(DateTime(2026, 2, 1, 18, 45), 'Asia/Tokyo'),
        '2026-02-01T18:45:00+09:00',
      );
    });

    test('an unknown zone is refused, not read as IST', () {
      expect(EventTimeZone.isKnown('Mars/Olympus_Mons'), isFalse);
      expect(EventTimeZone.iso(DateTime(2026, 1, 1), 'Mars/Olympus_Mons'), isNull);
      expect(EventTimeZone.isKnown('Asia/Kolkata'), isTrue);
    });
  });
}
