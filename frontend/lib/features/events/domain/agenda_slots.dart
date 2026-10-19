/// The agenda of a big event (NITKonnect), grouped for the event page (B1).
///
/// - Sessions that start at the same minute share a **time slot**; parallel
///   sessions are the ones in a slot with others.
/// - Within a slot: sessions with a hall first, by hall name; then the rest,
///   in the order the server sent them.
/// - Slots are grouped by day; the page only shows day headings when there
///   is more than one day.
/// - A **break** (tea, lunch…) is a slot of one session of type Break (B4).
///   A session with no type still counts as a break when it has no speaker
///   and its title starts with Tea, Lunch, Break or Dinner (data from
///   before B4).
///
/// Small events (no two sessions at the same time) keep today's simple list;
/// see [Agenda.hasParallel].
library;

import 'event.dart';

class AgendaSlot {
  AgendaSlot({required this.start, required this.sessions});

  /// The slot's start, to the minute.
  final DateTime start;
  final List<EventSession> sessions;

  bool get isParallel => sessions.length > 1;

  /// The end every session in the slot shares, or null when they differ
  /// (or none has one).
  DateTime? get sharedEnd {
    final first = sessions.first.endDatetime;
    if (first == null) return null;
    for (final s in sessions.skip(1)) {
      if (s.endDatetime == null || !s.endDatetime!.isAtSameMomentAs(first)) return null;
    }
    return first;
  }

  /// A break band (tea, lunch…): one session, no speaker, a break-like title.
  bool get isBreak => sessions.length == 1 && Agenda.looksLikeBreak(sessions.first);
}

class AgendaDay {
  AgendaDay({required this.date, required this.slots});

  /// The day (date only).
  final DateTime date;
  final List<AgendaSlot> slots;
}

abstract final class Agenda {
  static final _breakTitle = RegExp(r'^(tea|lunch|break|dinner)\b', caseSensitive: false);

  /// Whether any two sessions start at the same minute. Only then does the
  /// page use the big-event layout.
  static bool hasParallel(List<EventSession> sessions) {
    final seen = <int>{};
    for (final s in sessions) {
      if (!seen.add(_minuteKey(s.startDatetime))) return true;
    }
    return false;
  }

  static bool looksLikeBreak(EventSession session) {
    if (session.sessionType != null) return session.isBreakType;
    final speaker = session.speakerName?.trim() ?? '';
    return speaker.isEmpty && _breakTitle.hasMatch(session.title.trim());
  }

  /// The sessions' pillars, in the order they first appear (B4).
  static List<String> pillars(List<EventSession> sessions) {
    final seen = <String>[];
    for (final s in sessions) {
      final pillar = s.pillar;
      if (pillar != null && !seen.contains(pillar)) seen.add(pillar);
    }
    return seen;
  }

  /// "A", "A & B", "A, B & C".
  static String joinNames(List<String> names) {
    if (names.length <= 1) return names.join();
    return '${names.sublist(0, names.length - 1).join(', ')} & ${names.last}';
  }

  /// [sessions] grouped by day, then by start minute, in time order.
  static List<AgendaDay> build(List<EventSession> sessions) {
    final indexed = [for (var i = 0; i < sessions.length; i++) (i, sessions[i])];
    final bySlot = <int, List<(int, EventSession)>>{};
    for (final entry in indexed) {
      bySlot.putIfAbsent(_minuteKey(entry.$2.startDatetime), () => []).add(entry);
    }
    final keys = bySlot.keys.toList()..sort();

    final days = <AgendaDay>[];
    for (final key in keys) {
      final entries = bySlot[key]!..sort(_bySlotOrder);
      final start = _truncateToMinute(entries.first.$2.startDatetime);
      final slot = AgendaSlot(start: start, sessions: [for (final e in entries) e.$2]);
      final date = DateTime(start.year, start.month, start.day);
      if (days.isEmpty || days.last.date != date) {
        days.add(AgendaDay(date: date, slots: []));
      }
      days.last.slots.add(slot);
    }
    return days;
  }

  /// Hall first (by name, ignoring case), sessions without a hall after;
  /// otherwise the server's order.
  static int _bySlotOrder((int, EventSession) a, (int, EventSession) b) {
    final ha = a.$2.track?.trim() ?? '';
    final hb = b.$2.track?.trim() ?? '';
    if (ha.isNotEmpty && hb.isEmpty) return -1;
    if (ha.isEmpty && hb.isNotEmpty) return 1;
    if (ha.isNotEmpty && hb.isNotEmpty) {
      final byHall = ha.toLowerCase().compareTo(hb.toLowerCase());
      if (byHall != 0) return byHall;
    }
    return a.$1.compareTo(b.$1);
  }

  static int _minuteKey(DateTime d) => d.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;

  static DateTime _truncateToMinute(DateTime d) =>
      DateTime.fromMillisecondsSinceEpoch(_minuteKey(d) * Duration.millisecondsPerMinute,
          isUtc: d.isUtc);
}
