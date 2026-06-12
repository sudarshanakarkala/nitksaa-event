import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  return EventsRepository();
});
