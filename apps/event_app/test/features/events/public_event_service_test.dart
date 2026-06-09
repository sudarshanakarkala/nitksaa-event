import 'package:dio/dio.dart';
import 'package:event_app/features/events/services/public_event_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'requests the public endpoint without an authorization header',
    () async {
      late RequestOptions capturedRequest;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequest = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'events': [
                    {
                      'event_id': 1,
                      'slug': 'public-event',
                      'title': 'Public Event',
                      'status': 'published',
                      'start_datetime': '2026-06-12T09:00:00Z',
                      'end_datetime': '2026-06-12T10:00:00Z',
                      'timezone': 'UTC',
                      'is_virtual': true,
                      'capacity': null,
                      'registered_count': 0,
                      'registration_status': 'open',
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

      final events = await DioPublicEventService(
        dio: dio,
      ).listEvents(EventPeriod.upcoming);

      expect(capturedRequest.path, '/api/v1/events/public');
      expect(capturedRequest.queryParameters, {'period': 'upcoming'});
      expect(capturedRequest.headers.containsKey('Authorization'), isFalse);
      expect(events.single.title, 'Public Event');
    },
  );
}
