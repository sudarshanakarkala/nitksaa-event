import 'package:dio/dio.dart';

import '../../../core/network/backend_api_config.dart';
import '../../auth/services/auth_session_store.dart';
import '../domain/alumni_profile.dart';
import '../domain/registration.dart';

class RegistrationService {
  RegistrationService({Dio? dio}) : _dio = dio ?? _makeDio();

  final Dio _dio;

  static Dio _makeDio() => Dio(
        BaseOptions(
          baseUrl: BackendApiConfig.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          headers: const {'Content-Type': 'application/json'},
        ),
      );

  Future<Options> _authOptions() async {
    final store = AuthSessionStore();
    final session = await store.load();
    final token = session?.accessToken ?? '';
    if (token.isEmpty) {
      throw StateError('Not signed in. Please sign in to continue.');
    }
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<AlumniProfile> getAlumniProfile() async {
    final opts = await _authOptions();
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/v1/alumni/me',
      options: opts,
    );
    final data = resp.data;
    if (data == null) throw const FormatException('Empty alumni profile response.');
    return AlumniProfile.fromJson(data);
  }

  Future<Registration> registerForEvent(
    int eventId, {
    String? attendeeNote,
  }) async {
    final opts = await _authOptions();
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/v1/events/$eventId/register',
      data: attendeeNote != null && attendeeNote.isNotEmpty
          ? {'attendee_note': attendeeNote}
          : {},
      options: opts,
    );
    final data = resp.data;
    if (data == null) throw const FormatException('Empty register response.');
    return Registration.fromJson(data);
  }

  Future<List<Registration>> getMyRegistrations() async {
    final opts = await _authOptions();
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/v1/my/registrations',
      options: opts,
    );
    final data = resp.data;
    if (data == null) throw const FormatException('Empty registrations response.');
    final list = data['registrations'] as List? ?? [];
    return list
        .whereType<Map>()
        .map((r) => Registration.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<Registration> getMyEventRegistration(int eventId) async {
    final opts = await _authOptions();
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/v1/events/$eventId/my-registration',
      options: opts,
    );
    final data = resp.data;
    if (data == null) throw const FormatException('Empty registration response.');
    return Registration.fromJson(data);
  }
}

String registrationErrorMessage(Object error) {
  if (error is DioException) {
    final detail = error.response?.data is Map
        ? (error.response!.data as Map)['detail']?.toString()
        : null;
    return switch (detail) {
      'alumni_only' => 'This event is for alumni only.',
      'alumni_not_active' => 'Your alumni profile is inactive. Contact the registrar.',
      'alumni_profile_not_found' => 'Alumni profile not found. Contact the registrar.',
      'event_full' => 'This event is full. Registration is no longer available.',
      'already_registered' => 'You are already registered for this event.',
      'registration_closed' => 'Registration for this event has closed.',
      'event_not_published' => 'This event is not currently accepting registrations.',
      _ => error.response?.statusCode == null
          ? 'Check your connection and try again.'
          : 'Registration failed (${error.response!.statusCode}). Please try again.',
    };
  }
  if (error is StateError) return error.message;
  return 'Something went wrong. Please try again.';
}
