import 'package:dio/dio.dart';

/// Sends feedback to the events API.
///
/// `POST /api/v1/feedback` on the events API (`backend/app/api/feedback.py`),
/// the same contract as the website's: it emails nitksaa.infra@gmail.com,
/// with the sender as Reply-To. If it fails, the form shows the website's
/// "please email us" fallback.
class FeedbackApi {
  FeedbackApi({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;

  static Dio _createDio() {
    const configured = String.fromEnvironment('BACKEND_BASE_URL');
    const devConfigured = String.fromEnvironment('DEV_BACKEND_BASE_URL');
    final baseUrl = configured.isNotEmpty
        ? configured
        : devConfigured.isNotEmpty
            ? devConfigured
            : 'http://127.0.0.1:8000';
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        headers: const {'Content-Type': 'application/json'},
      ),
    );
  }

  /// Throws on any failure.
  Future<void> submit({
    required String accessToken,
    required String area,
    required String category,
    required String message,
  }) async {
    await _dio.post<void>(
      '/api/v1/feedback',
      data: {
        'area': area,
        'category': category,
        'message': message,
        'source': 'events_app',
      },
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
  }
}
