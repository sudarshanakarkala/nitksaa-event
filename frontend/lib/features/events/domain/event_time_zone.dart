/// Times in an event's own timezone (its IANA name, e.g. `America/New_York`),
/// whoever is looking and wherever they are.
///
/// An event's times are stored as exact moments. The event form shows and
/// takes them as wall-clock times in the event's timezone, so a 9:00 am
/// New York event reads 9:00 am in the form in India too, and is saved as
/// 9:00 am New York time, with the offset that applies on that date (summer
/// time included).
///
/// On the web the browser's own timezone data is used (`Intl`), so every
/// zone works and the rules stay current. Off the web (tests in the Dart VM)
/// only zones without summer time are known.
library;

import 'event_time_zone_offset.dart';

abstract final class EventTimeZone {
  /// Whether [zone] is a timezone this browser knows.
  static bool isKnown(String zone) =>
      utcOffsetMinutes(DateTime.utc(2026, 1, 1), zone) != null;

  /// The wall clock in [zone] at [instant]. Only the date and time fields of
  /// the result mean anything: they are the wall time. Null for an unknown
  /// zone.
  static DateTime? wallTime(DateTime instant, String zone) {
    final utc = instant.toUtc();
    final offset = utcOffsetMinutes(utc, zone);
    if (offset == null) return null;
    final w = utc.add(Duration(minutes: offset));
    return DateTime(w.year, w.month, w.day, w.hour, w.minute, w.second);
  }

  /// The exact moment of [wall] (its date and time fields, read as a wall
  /// clock in [zone]). Null for an unknown zone.
  static DateTime? instantOf(DateTime wall, String zone) =>
      instantFromWall(wall, (utc) => utcOffsetMinutes(utc, zone));

  /// [wall] in [zone] as ISO 8601 with that moment's offset, e.g.
  /// `2026-11-15T08:00:00+05:30`. Null for an unknown zone.
  static String? iso(DateTime wall, String zone) {
    final instant = instantOf(wall, zone);
    if (instant == null) return null;
    final offset = utcOffsetMinutes(instant, zone)!;
    String two(int n) => n.toString().padLeft(2, '0');
    final sign = offset < 0 ? '-' : '+';
    final abs = offset.abs();
    return '${wall.year.toString().padLeft(4, '0')}-${two(wall.month)}-'
        '${two(wall.day)}T${two(wall.hour)}:${two(wall.minute)}:00'
        '$sign${two(abs ~/ 60)}:${two(abs % 60)}';
  }

  /// [instantOf], with the zone's offset rule given as [offsetAt] (minutes
  /// east of UTC at a UTC moment). Separate so the summer-time handling can
  /// be tested anywhere.
  ///
  /// A wall time that happens twice (clocks going back) is the first; one
  /// that never happens (clocks going forward) moves on by the gap, as
  /// browsers do.
  static DateTime? instantFromWall(
    DateTime wall,
    int? Function(DateTime utc) offsetAt,
  ) {
    final asUtc = DateTime.utc(
      wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second,
    );
    final before = offsetAt(asUtc.subtract(const Duration(days: 1)));
    final after = offsetAt(asUtc.add(const Duration(days: 1)));
    if (before == null || after == null) return null;
    // Try the offset in force before, then after, the change (if any).
    for (final offset in {before, after}) {
      final candidate = asUtc.subtract(Duration(minutes: offset));
      if (offsetAt(candidate) == offset) return candidate;
    }
    // A wall time in a gap: read it with the offset from before the gap.
    return asUtc.subtract(Duration(minutes: before));
  }
}
