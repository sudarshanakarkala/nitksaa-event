// Admin → Dashboard: reading the backend's summary.

import 'package:event_app/features/admin/data/dashboard_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads tiles, lists, weeks and decades', () {
    final data = DashboardData.fromJson({
      'period': '30d',
      'tiles': {
        'upcoming_events': 2,
        'registrations': 24,
        'cancellations': 4,
        'money_collected': 1180.0,
      },
      'upcoming': [
        {
          'event_id': 1,
          'title': 'Upcoming Meet',
          'start_datetime': '2030-10-22T06:39:58+00:00',
          'end_datetime': '2030-10-22T09:39:58+00:00',
          'status': 'published',
          'capacity': 100,
          'registered': 10,
          'new_7d': 5,
          'checked_in': 0,
          'registration_status': 'open',
        },
      ],
      'recent': [
        {
          'event_id': 2,
          'title': 'Past Dinner',
          'start_datetime': '2026-09-22T06:39:58+00:00',
          'registered': 10,
          'checked_in': 6,
          'no_shows': 4,
          'money_collected': 0,
        },
      ],
      'weekly': [
        {'week': '2026-09-28', 'registrations': 10, 'cancellations': 2},
        {'week': '2026-10-05', 'registrations': 14, 'cancellations': 2},
      ],
      'by_decade': [
        {'decade': 1990, 'count': 16},
        {'decade': 2000, 'count': 4},
      ],
    });

    expect(data.upcomingEvents, 2);
    expect(data.registrations, 24);
    expect(data.cancellations, 4);
    expect(data.money, 1180.0);

    final up = data.upcoming.single;
    expect(up.title, 'Upcoming Meet');
    expect(up.capacity, 100);
    expect(up.newThisWeek, 5);
    expect(up.registrationStatus, 'open');
    expect(up.isToday, isFalse);

    expect(data.weekly.map((w) => w.registrations), [10, 14]);
    expect(data.byDecade, {1990: 16, 2000: 4});
  });

  test('an empty answer gives an empty dashboard, not an error', () {
    final data = DashboardData.fromJson(const {});
    expect(data.upcomingEvents, 0);
    expect(data.upcoming, isEmpty);
    expect(data.weekly, isEmpty);
    expect(data.byDecade, isEmpty);
  });
}
