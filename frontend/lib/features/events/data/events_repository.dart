import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/event.dart';
import '../domain/my_event_registration.dart';

class EventsRepository {
  EventsRepository({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;

  static Dio _createDio() {
    const configured = String.fromEnvironment('BACKEND_BASE_URL');
    const devConfigured = String.fromEnvironment('DEV_BACKEND_BASE_URL');
    final baseUrl = configured.isNotEmpty
        ? configured
        : devConfigured.isNotEmpty
        ? devConfigured
        : _defaultBackendBaseUrl;

    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 90),
        sendTimeout: const Duration(seconds: 90),
        headers: const {'Content-Type': 'application/json'},
      ),
    );
  }

  static String get _defaultBackendBaseUrl {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  Future<Map<String, dynamic>> getPublicEvents({
    required int page,
    required int perPage,
    required String period,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/events/public',
      queryParameters: {
        'page': page,
        'per_page': perPage,
        'period': period,
      },
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<AppEvent> createAdminEvent(
    Map<String, dynamic> data,
    String accessToken,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/events',
      data: data,
      options: Options(headers: {
        'Authorization': 'Bearer $accessToken',
        'X-Dev-User': 'admin',
      }),
    );
    final eventJson = response.data?['event'] as Map<String, dynamic>;
    return AppEvent.fromJson(eventJson);
  }

  Future<AppEvent> updateAdminEvent(
    int eventId,
    Map<String, dynamic> data,
    String accessToken,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/v1/events/$eventId',
      data: data,
      options: Options(headers: {
        'Authorization': 'Bearer $accessToken',
        'X-Dev-User': 'admin',
      }),
    );
    final eventJson = response.data?['event'] as Map<String, dynamic>;
    return AppEvent.fromJson(eventJson);
  }

  Future<AppEvent> getPublicEvent(int eventId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/events/public/$eventId',
    );
    final eventJson = response.data?['event'] as Map<String, dynamic>;
    return AppEvent.fromJson(eventJson);
  }

  Future<Map<String, dynamic>> getRegistrationEligibility(int eventId, String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/events/$eventId/registration-eligibility',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>?> getMyEventRegistration(int eventId, String accessToken) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/events/$eventId/my-registration',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return response.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<List<MyEventRegistration>> getMyRegistrations(String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/my/registrations',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    final rawRegistrations =
        response.data?['registrations'] as List<dynamic>? ?? [];
    final registrations = rawRegistrations
        .map((json) => MyEventRegistration.fromJson(json as Map<String, dynamic>))
        .toList();

    final hydrated = <MyEventRegistration>[];
    for (final registration in registrations) {
      try {
        final event = await getPublicEvent(registration.eventId);
        hydrated.add(registration.copyWith(publicEvent: event));
      } on DioException {
        hydrated.add(registration);
      }
    }
    return hydrated;
  }

  Future<MyEventRegistration> cancelMyRegistration(
    int eventId,
    String accessToken,
  ) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/api/v1/events/$eventId/my-registration',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return MyEventRegistration.fromJson(response.data ?? <String, dynamic>{});
  }

  Future<Map<String, dynamic>> registerForEvent(int eventId, String accessToken, String attendeeNote) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/events/$eventId/register',
      data: {'attendee_note': attendeeNote},
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getAlumniProfile(String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/alumni/me',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return response.data ?? <String, dynamic>{};
  }
}

final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  return EventsRepository();
});
