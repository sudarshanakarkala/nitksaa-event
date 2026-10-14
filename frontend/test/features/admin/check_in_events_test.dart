// Admin → Check-in offers only the events worth checking people in to.

import 'package:event_app/features/admin/presentation/admin_check_in_tab.dart';
import 'package:event_app/features/events/domain/event.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 31, 9);

AppEvent _event(int id, DateTime start, {int registered = 10, String status = 'published'}) =>
    AppEvent(
      eventId: id,
      slug: 'e$id',
      title: 'Event $id',
      status: status,
      startDatetime: start,
      endDatetime: start.add(const Duration(hours: 3)),
      timezone: 'Asia/Kolkata',
      isVirtual: false,
      registrationStatus: 'open',
      registeredCount: registered,
    );

void main() {
  test('on now and coming up first, then the last 7 days; nothing else', () {
    final events = [
      _event(1, DateTime(2026, 11, 15, 8)), // coming up
      _event(2, DateTime(2026, 10, 31, 8)), // on now
      _event(3, DateTime(2026, 10, 27, 8)), // 4 days ago
      _event(4, DateTime(2026, 9, 1, 8)), // long past
      _event(5, DateTime(2026, 11, 20, 8), registered: 0), // nobody registered
      _event(6, DateTime(2026, 11, 2, 8), status: 'cancelled'),
      _event(7, DateTime(2026, 11, 3, 8), status: 'draft'),
      _event(8, DateTime(2026, 11, 4, 8), status: 'completed'), // closed early, still at the door
    ];

    expect(checkInEvents(events, _now).map((e) => e.eventId), [2, 8, 1, 3]);
  });

  test('smart landing: an event on now or within 3 hours, else none', () {
    final later = _event(1, DateTime(2026, 10, 31, 11, 30)); // in 2.5 h
    final onNow = _event(2, DateTime(2026, 10, 31, 8)); // 8–11
    final tonight = _event(3, DateTime(2026, 10, 31, 19)); // in 10 h
    final ended = _event(4, DateTime(2026, 10, 31, 5)); // 5–8
    final empty = _event(5, DateTime(2026, 10, 31, 9), registered: 0);
    final draft = _event(6, DateTime(2026, 10, 31, 9), status: 'draft');

    expect(eventOnNow([later, onNow, tonight, ended, empty, draft], _now)?.eventId, 2);
    expect(eventOnNow([later, tonight], _now)?.eventId, 1);
    expect(eventOnNow([tonight, ended, empty, draft], _now), isNull);
  });
}
