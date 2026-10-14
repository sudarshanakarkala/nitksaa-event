import 'package:event_app/features/events/domain/my_event_registration.dart';
import 'package:event_app/features/events/domain/my_events_view.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 14, 12);

MyEventRegistration _reg(
  int id,
  int eventId, {
  String status = 'registered',
  int minutes = 0,
  String? order,
  DateTime? start,
}) {
  final at = DateTime(2026, 10, 1).add(Duration(minutes: minutes));
  return MyEventRegistration(
    registrationId: id,
    eventId: eventId,
    status: status,
    registeredAt: at,
    cancelledAt: status == 'cancelled' ? at.add(const Duration(minutes: 1)) : null,
    latestOrderId: order,
    event: RegisteredEventSummary(
      eventId: eventId,
      title: 'Event $eventId',
      startDatetime: start ?? DateTime(2026, 11, 1),
      timezone: 'Asia/Kolkata',
      isVirtual: false,
    ),
  );
}

void main() {
  test('ISSUE-011: one entry per event, the active registration shown', () {
    final entries = myEventEntries([
      _reg(2, 7, minutes: 10),
      _reg(1, 7, status: 'cancelled', order: 'ORD-1'),
    ], now: _now);

    expect(entries, hasLength(1));
    expect(entries.single.registration.registrationId, 2);
    // The earlier paid cancellation's refund can still be looked up.
    expect(entries.single.refundFrom?.registrationId, 1);
  });

  test('all cancelled: the newest is shown, with its own refund', () {
    final entries = myEventEntries([
      _reg(1, 7, status: 'cancelled', order: 'ORD-1'),
      _reg(3, 7, status: 'cancelled', order: 'ORD-3', minutes: 20),
      _reg(2, 7, status: 'cancelled', minutes: 10),
    ], now: _now);

    expect(entries.single.registration.registrationId, 3);
    expect(entries.single.refundFrom?.registrationId, 3);
  });

  test('a free cancellation has no refund link', () {
    final entries = myEventEntries([_reg(1, 7, status: 'cancelled')], now: _now);
    expect(entries.single.refundFrom, isNull);
  });

  test('upcoming events first (soonest first), then past (latest first)', () {
    final entries = myEventEntries([
      _reg(1, 1, start: DateTime(2026, 9, 1)),
      _reg(2, 2, start: DateTime(2026, 12, 1)),
      _reg(3, 3, start: DateTime(2026, 10, 20)),
      _reg(4, 4, start: DateTime(2026, 10, 1)),
    ], now: _now);

    expect(entries.map((e) => e.eventId), [3, 2, 4, 1]);
  });
}
