import 'package:dio/dio.dart';
import 'package:event_app/features/events/services/public_event_detail_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requests public detail without an authorization header', () async {
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
                'event': {
                  'event_id': 6,
                  'slug': 'public-event',
                  'title': 'Public Event',
                  'status': 'published',
                  'start_datetime': '2026-06-19T11:00:00Z',
                  'end_datetime': '2026-06-19T12:00:00Z',
                  'timezone': 'UTC',
                  'is_virtual': true,
                  'capacity': 100,
                  'registered_count': 0,
                  'registration_status': 'open',
                  'speakers': [],
                  'sessions': [],
                },
              },
            ),
          );
        },
      ),
    );

    final event = await DioPublicEventDetailService(dio: dio).getEvent(6);

    expect(capturedRequest.path, '/api/v1/events/public/6');
    expect(capturedRequest.headers.containsKey('Authorization'), isFalse);
    expect(event.title, 'Public Event');
  });
}
