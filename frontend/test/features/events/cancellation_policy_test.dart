// Regression tests for ISSUE-012: Unregister was hidden as soon as the
// event's registration window closed, often well before the event. The
// backend has no such cut-off: `refund_service.cancel_registration` cancels
// any `registered` registration, with a full refund. The app now offers
// Unregister on an active registration until the event starts.
//
// The rule at a fixed time, so nothing here depends on the clock. The
// screens are in cancellation_policy_screens_test.dart.

import 'package:event_app/features/events/domain/event.dart';
import 'package:event_app/features/events/domain/my_event_registration.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 10, 15, 6, 30);

/// The public event, as `GET /events/public/{id}` returns it.
AppEvent _publicEvent({
  required DateTime start,
  DateTime? end,
  String registrationStatus = 'open',
}) {
  return AppEvent.fromJson({
    'event_id': 7,
    'slug': 'event-7',
    'title': 'Annual Alumni Meet',
    'status': 'published',
    'start_datetime': start.toIso8601String(),
    'end_datetime': (end ?? start.add(const Duration(hours: 3)))
        .toIso8601String(),
    'timezone': 'Asia/Kolkata',
    'registration_status': registrationStatus,
    'registration_closes_at': registrationStatus == 'closed'
        ? _now.subtract(const Duration(days: 1)).toIso8601String()
        : null,
  });
}

/// A registration whose event starts at [start] (ends at [end], 3 hours
/// later by default), with the public event's window [registrationStatus].
MyEventRegistration _registration({
  String status = 'registered',
  required DateTime start,
  DateTime? end,
  String registrationStatus = 'open',
}) {
  return MyEventRegistration(
    registrationId: 501,
    eventId: 7,
    status: status,
    registeredAt: _now.subtract(const Duration(days: 10)),
    event: RegisteredEventSummary(
      eventId: 7,
      title: 'Annual Alumni Meet',
      startDatetime: start,
      endDatetime: end ?? start.add(const Duration(hours: 3)),
      timezone: 'Asia/Kolkata',
      isVirtual: false,
    ),
    publicEvent: _publicEvent(
      start: start,
      end: end,
      registrationStatus: registrationStatus,
    ),
  );
}

void main() {
  final tomorrow = _now.add(const Duration(days: 1));

  group('ISSUE-012: canCancelAt', () {
    test('Test A: registered, registration open, event ahead: offered', () {
      expect(_registration(start: tomorrow).canCancelAt(_now), isTrue);
    });

    test('Test B: registered, registration closed, event ahead: offered', () {
      final registration = _registration(
        start: tomorrow,
        registrationStatus: 'closed',
      );
      expect(registration.publicEvent!.registrationStatus, 'closed');
      expect(registration.canCancelAt(_now), isTrue);
    });

    for (final window in const ['open', 'closed']) {
      test('Test C: the event has started (registration $window): not '
          'offered', () {
        final registration = _registration(
          start: _now.subtract(const Duration(hours: 1)),
          end: _now.add(const Duration(hours: 2)),
          registrationStatus: window,
        );
        expect(registration.canCancelAt(_now), isFalse);
      });

      test('Test D: the event has ended (registration $window): not '
          'offered', () {
        final registration = _registration(
          start: _now.subtract(const Duration(days: 3)),
          registrationStatus: window,
        );
        expect(registration.canCancelAt(_now), isFalse);
      });
    }

    test('offered until the start time, not at it', () {
      final registration = _registration(start: _now);
      expect(
        registration.canCancelAt(_now.subtract(const Duration(minutes: 1))),
        isTrue,
      );
      expect(registration.canCancelAt(_now), isFalse);
    });

    test('the start is compared as a moment in time, whatever the time zone',
        () {
      // 12:30 in India is 07:00 UTC: half an hour after _now.
      final registration = _registration(
        start: DateTime.parse('2026-10-15T12:30:00+05:30').toLocal(),
      );
      expect(registration.canCancelAt(_now), isTrue);
      expect(
        registration.canCancelAt(DateTime.utc(2026, 10, 15, 7)),
        isFalse,
      );
    });

    for (final status in const [
      'cancelled',
      'seat_held',
      'payment_pending',
      'payment_verification',
      'payment_failed',
    ]) {
      test('Test E: a $status registration: not offered', () {
        final registration = _registration(status: status, start: tomorrow);
        expect(registration.canCancelAt(_now), isFalse);
      });
    }

    test('the start comes from the registration row; the public event is '
        'the fallback', () {
      final summaryOnly = MyEventRegistration(
        registrationId: 501,
        eventId: 7,
        status: 'registered',
        registeredAt: _now,
        event: RegisteredEventSummary(
          eventId: 7,
          title: 'Annual Alumni Meet',
          startDatetime: _now.subtract(const Duration(hours: 1)),
          timezone: 'Asia/Kolkata',
          isVirtual: false,
        ),
      );
      expect(summaryOnly.canCancelAt(_now), isFalse);

      final publicOnly = MyEventRegistration(
        registrationId: 501,
        eventId: 7,
        status: 'registered',
        registeredAt: _now,
        publicEvent: _publicEvent(start: _now.subtract(const Duration(hours: 1))),
      );
      expect(publicOnly.canCancelAt(_now), isFalse);
    });

    test('with no start known, the backend decides: offered', () {
      final registration = MyEventRegistration(
        registrationId: 501,
        eventId: 7,
        status: 'registered',
        registeredAt: _now,
      );
      expect(registration.canCancelAt(_now), isTrue);
    });
  });

  group('ISSUE-012: canCancel', () {
    test('is canCancelAt now', () {
      expect(_registration(start: DateTime.utc(2099)).canCancel, isTrue);
      expect(_registration(start: DateTime.utc(2000)).canCancel, isFalse);
    });

    test('does not look at the registration window', () {
      final registration = _registration(
        start: DateTime.utc(2099),
        registrationStatus: 'closed',
      );
      expect(registration.canCancel, isTrue);
    });
  });
}
