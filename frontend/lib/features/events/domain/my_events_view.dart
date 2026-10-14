import 'my_event_registration.dart';

/// One card on My Events: an event and your registration for it.
///
/// The backend lists every registration you've made, so an event you
/// unregistered from and registered for again has two rows. My Events shows
/// one card per event, for [registration]: the active one if there is one,
/// else the newest.
class MyEventEntry {
  const MyEventEntry({required this.registration, this.refundFrom});

  final MyEventRegistration registration;

  /// The registration whose refund the card links to: [registration] itself
  /// when it was cancelled after a payment, or an earlier cancelled one when
  /// you registered again (so its refund can still be looked up).
  final MyEventRegistration? refundFrom;

  int get eventId => registration.eventId;

  DateTime? get start =>
      registration.event?.startDatetime ?? registration.publicEvent?.startDatetime;

  DateTime? get end =>
      registration.event?.endDatetime ?? registration.publicEvent?.endDatetime ?? start;

  /// Not over yet (an event without dates counts as upcoming).
  bool isUpcoming(DateTime now) => end == null || end!.isAfter(now);

  String get title =>
      registration.event?.title ?? registration.publicEvent?.title ?? 'Registered event';
}

/// One entry per event, upcoming first (soonest first), then past (most
/// recent first).
List<MyEventEntry> myEventEntries(
  List<MyEventRegistration> registrations, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final byEvent = <int, List<MyEventRegistration>>{};
  for (final r in registrations) {
    byEvent.putIfAbsent(r.eventId, () => []).add(r);
  }

  int newestFirst(MyEventRegistration a, MyEventRegistration b) {
    final byTime = b.registeredAt.compareTo(a.registeredAt);
    return byTime != 0 ? byTime : b.registrationId.compareTo(a.registrationId);
  }

  final entries = <MyEventEntry>[];
  for (final rows in byEvent.values) {
    rows.sort(newestFirst);
    final active = rows.where((r) => r.isActive);
    final shown = active.isNotEmpty ? active.first : rows.first;
    final refund = rows.where((r) => r.mayHaveRefund);
    entries.add(MyEventEntry(
      registration: shown,
      refundFrom: refund.isEmpty ? null : refund.first,
    ));
  }

  entries.sort((a, b) {
    final aUp = a.isUpcoming(at), bUp = b.isUpcoming(at);
    if (aUp != bUp) return aUp ? -1 : 1;
    final aStart = a.start, bStart = b.start;
    if (aStart == null || bStart == null) {
      return aStart == null ? (bStart == null ? 0 : 1) : -1;
    }
    return aUp ? aStart.compareTo(bStart) : bStart.compareTo(aStart);
  });
  return entries;
}
