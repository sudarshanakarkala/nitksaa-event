// EventTimeZone with the browser's real timezone data (Chrome tests):
// summer time, and the zones the old fixed table got wrong.
@TestOn('browser')
library;

import 'package:event_app/features/events/domain/event_time_zone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? iso(int y, int m, int d, int h, String zone) =>
      EventTimeZone.iso(DateTime(y, m, d, h), zone);

  test('New York: winter -05:00, summer -04:00', () {
    expect(iso(2027, 1, 15, 9, 'America/New_York'), '2027-01-15T09:00:00-05:00');
    expect(iso(2027, 7, 10, 9, 'America/New_York'), '2027-07-10T09:00:00-04:00');
  });

  test('Chicago, Denver, Los Angeles (not read as IST)', () {
    expect(iso(2027, 1, 15, 9, 'America/Chicago'), '2027-01-15T09:00:00-06:00');
    expect(iso(2027, 1, 15, 9, 'America/Denver'), '2027-01-15T09:00:00-07:00');
    expect(iso(2027, 7, 10, 9, 'America/Los_Angeles'), '2027-07-10T09:00:00-07:00');
  });

  test('London and Sydney summer time', () {
    expect(iso(2027, 7, 10, 9, 'Europe/London'), '2027-07-10T09:00:00+01:00');
    expect(iso(2027, 1, 10, 9, 'Europe/London'), '2027-01-10T09:00:00+00:00');
    expect(iso(2027, 1, 10, 9, 'Australia/Sydney'), '2027-01-10T09:00:00+11:00');
  });

  test('IST and the other zones in the list', () {
    expect(iso(2026, 11, 15, 8, 'Asia/Kolkata'), '2026-11-15T08:00:00+05:30');
    for (final zone in [
      'Europe/Paris', 'Europe/Berlin', 'Asia/Shanghai', 'Pacific/Auckland',
    ]) {
      expect(EventTimeZone.isKnown(zone), isTrue, reason: zone);
    }
  });

  test('a New York event reads back the same, whatever the browser zone', () {
    final saved = EventTimeZone.instantOf(
      DateTime(2027, 7, 10, 9),
      'America/New_York',
    )!;
    expect(saved, DateTime.utc(2027, 7, 10, 13));
    final wall = EventTimeZone.wallTime(saved, 'America/New_York')!;
    expect([wall.month, wall.day, wall.hour, wall.minute], [7, 10, 9, 0]);
    // Saving what was read gives the same moment again.
    expect(EventTimeZone.instantOf(wall, 'America/New_York'), saved);
  });

  test('an unknown zone is refused', () {
    expect(EventTimeZone.isKnown('Mars/Olympus_Mons'), isFalse);
  });
}
