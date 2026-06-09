import 'package:event_app/features/events/domain/public_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PublicEvent', () {
    test('parses only the public event projection and formats labels', () {
      final event = PublicEvent.fromJson({
        'event_id': 7,
        'slug': 'alumni-meet',
        'title': 'Alumni Meet',
        'tagline': 'Reconnect',
        'description': 'An alumni gathering.',
        'status': 'published',
        'start_datetime': '2026-06-12T09:00:00+05:30',
        'end_datetime': '2026-06-12T11:00:00+05:30',
        'timezone': 'Asia/Kolkata',
        'location_text': 'Bengaluru',
        'location_maps_url': null,
        'is_virtual': false,
        'thumbnail_url': null,
        'banner_url': null,
        'capacity': 30,
        'registered_count': 4,
        'registration_status': 'not_open_yet',
        'published_at': '2026-06-08T10:30:00+05:30',
        'virtual_url': 'https://should-not-be-modeled.example',
        'created_by_firebase_uid': 'private-uid',
        'created_by_name': 'Private Name',
      });

      expect(event.eventId, 7);
      expect(event.eventTypeLabel, 'In-person');
      expect(event.capacityLabel, '4 / 30');
      expect(event.registrationStatusLabel, 'Not Open Yet');
    });

    test('formats virtual, unlimited, and backend status labels', () {
      final event = PublicEvent.fromJson({
        'event_id': 8,
        'slug': 'online-session',
        'title': 'Online Session',
        'status': 'published',
        'start_datetime': '2026-06-13T09:00:00Z',
        'end_datetime': '2026-06-13T10:00:00Z',
        'timezone': 'UTC',
        'is_virtual': true,
        'capacity': null,
        'registered_count': 0,
        'registration_status': 'not_applicable',
      });

      expect(event.eventTypeLabel, 'Virtual');
      expect(event.capacityLabel, 'Unlimited');
      expect(event.registrationStatusLabel, 'Not Applicable');
    });
  });
}
