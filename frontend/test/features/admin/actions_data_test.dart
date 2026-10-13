// Admin → Actions: reading the backend's pending counts.

import 'package:event_app/features/admin/data/actions_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the counts, the badge total and the per-event lists', () {
    final c = PendingCounts.fromJson({
      'total': 10,
      'drafts': 3,
      'closing_soon': 1,
      'near_capacity': 2,
      'failed_emails': 3,
      'stuck_payments': 2,
      'failed_refunds': 2,
      'delayed_refunds': 1,
      'events': {
        'closing_soon': [
          {
            'event_id': 3,
            'title': 'Alumni Meet',
            'start_datetime': '2030-10-18T06:00:00+00:00',
            'registration_closes_at': '2030-10-15T12:30:00+00:00',
            'capacity': 100,
            'registered': 1,
          },
        ],
        'near_capacity': [
          {'event_id': 6, 'title': 'Full one', 'start_datetime': '2030-10-16T06:00:00+00:00', 'capacity': 10, 'registered': 10},
          {'event_id': 7, 'title': 'Nearly', 'start_datetime': '2030-10-22T06:00:00+00:00', 'capacity': 10, 'registered': 9},
        ],
        'failed_emails': [
          {'event_id': 3, 'title': 'Alumni Meet', 'start_datetime': '2030-10-18T06:00:00+00:00', 'failed': 1},
          {'event_id': 7, 'title': 'Nearly', 'start_datetime': '2030-10-22T06:00:00+00:00', 'failed': 2},
        ],
      },
    });

    expect(c.total, 10);
    expect(c.drafts, 3);
    expect(c.stuckPayments, 2);
    expect(c.failedRefunds, 2);
    expect(c.delayedRefunds, 1);
    expect(c.closingSoonEvents.single.eventId, 3);
    expect(c.closingSoonEvents.single.closesAt, isNotNull);
    expect(c.nearCapacityEvents.map((e) => e.registered), [10, 9]);
    expect(c.failedEmailEvents.fold<int>(0, (n, e) => n + e.failed), c.failedEmails);
  });

  test('tolerates a missing events block and missing numbers', () {
    final c = PendingCounts.fromJson({'total': 0});
    expect(c.drafts, 0);
    expect(c.closingSoonEvents, isEmpty);
    expect(c.failedEmailEvents, isEmpty);
  });
}
