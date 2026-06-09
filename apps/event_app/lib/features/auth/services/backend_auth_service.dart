import 'package:dio/dio.dart';

import '../../../core/network/backend_api_config.dart';
import '../domain/auth_session.dart';

class BackendAuthService {
  BackendAuthService({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        baseUrl: BackendApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        headers: const {'Content-Type': 'application/json'},
      ),
    );
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
