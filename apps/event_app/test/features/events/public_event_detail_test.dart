import 'package:event_app/features/events/domain/public_event_detail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses public detail without modeling private fields', () {
    final event = PublicEventDetail.fromJson({
      'event_id': 6,
      'slug': 'innovation-summit',
      'title': 'Innovation Summit',
      'tagline': 'Build the future',
      'description': 'A physical event.',
      'status': 'published',
      'start_datetime': '2026-06-19T11:00:00Z',
      'end_datetime': '2026-06-19T13:00:00Z',
      'timezone': 'Asia/Kolkata',
      'location_text': 'Chennai',
      'location_maps_url': null,
      'is_virtual': false,
      'thumbnail_url': null,
      'banner_url': null,
      'capacity': 200,
      'registered_count': 12,
      'registration_status': 'open',
      'published_at': '2026-06-01T10:00:00Z',
      'speakers': [
        {'name': 'Ada Alumni', 'title': 'CTO'},
      ],
      'sessions': [
        {'title': 'Opening Session', 'description': 'Welcome'},
      ],
      'virtual_url': 'https://private.example.test',
      'created_by_firebase_uid': 'private-uid',
      'created_by_name': 'Private Admin',
    });

    expect(event.eventId, 6);
    expect(event.eventTypeLabel, 'In-person');
    expect(event.capacityLabel, '12 / 200');
    expect(event.speakers.single.name, 'Ada Alumni');
    expect(event.sessions.single.title, 'Opening Session');
  });

  test('treats null speaker and session collections as empty', () {
    final event = PublicEventDetail.fromJson({
      'event_id': 7,
      'slug': 'virtual-event',
      'title': 'Virtual Event',
      'status': 'published',
      'start_datetime': '2026-06-20T11:00:00Z',
      'end_datetime': '2026-06-20T12:00:00Z',
      'timezone': 'UTC',
      'is_virtual': true,
      'capacity': null,
      'registered_count': 0,
      'registration_status': 'not_open_yet',
      'speakers': null,
      'sessions': null,
    });

    expect(event.speakers, isEmpty);
    expect(event.sessions, isEmpty);
    expect(event.capacityLabel, 'Unlimited');
    expect(event.registrationStatusLabel, 'Not Open Yet');
  });
}
