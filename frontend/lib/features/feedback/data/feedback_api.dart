import 'dart:convert';

import 'package:dio/dio.dart';

import 'feedback_attachment.dart';

/// Sends feedback to the events API.
///
/// `POST /api/v1/feedback` on the events API (`backend/app/api/feedback.py`),
/// the same contract as the website's: it emails nitksaa.infra@gmail.com,
/// with the sender as Reply-To. If it fails, the form shows the website's
/// "please email us" fallback.
///
/// Attachments go in the same JSON body as base64 and arrive on the email
/// only; nothing is stored.
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

  /// How long a send with files may take in all. On the web, Dio's
  /// connect + receive timeouts cap the whole request (upload included),
  /// and 20 MB on mobile data can take minutes.
  static const attachmentTimeout = Duration(minutes: 4);

  /// Throws on any failure. [onSendProgress] reports the upload (bytes sent,
  /// bytes in all) when there are attachments.
  Future<void> submit({
    required String accessToken,
    required String area,
    required String category,
    required String message,
    List<FeedbackAttachment> attachments = const [],
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final withFiles = attachments.isNotEmpty;
    await _dio.post<void>(
      '/api/v1/feedback',
      data: {
        'area': area,
        'category': category,
        'message': message,
        'source': 'events_app',
        if (withFiles)
          'attachments': [
            for (final a in attachments)
              {
                'filename': a.name,
                'content_type': a.mimeType,
                'data_base64': base64Encode(a.bytes),
              },
          ],
      },
      options: Options(
        headers: {'Authorization': 'Bearer $accessToken'},
        receiveTimeout: withFiles ? attachmentTimeout : null,
      ),
      onSendProgress: withFiles ? onSendProgress : null,
    );
  }
}
