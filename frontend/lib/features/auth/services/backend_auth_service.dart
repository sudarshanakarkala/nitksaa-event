import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/auth_session.dart';

class BackendAuthService {
  BackendAuthService({Dio? dio}) : _dio = dio ?? _createDio();

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
        connectTimeout: const Duration(seconds: 30),
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

  Future<AuthSession> loginWithFirebaseToken(String firebaseIdToken) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/firebase',
      data: {'token': firebaseIdToken},
    );
    final session = AuthSession.fromBackendLogin(
      response.data ?? <String, dynamic>{},
    );
    if (!session.isValid) {
      throw StateError('Backend login did not return a valid session.');
    }
    return session;
  }

  Future<AuthSession> validateAccessToken(String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/auth/me',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    final session = AuthSession.fromMeResponse(
      accessToken: accessToken,
      json: response.data ?? <String, dynamic>{},
    );
    if (!session.isValid) {
      throw StateError('/auth/me did not return a valid user.');
    }
    return session;
  }
}
