import 'package:dio/dio.dart';

import '../../../core/network/backend_api_config.dart';
import '../domain/public_event_detail.dart';

abstract interface class PublicEventDetailService {
  Future<PublicEventDetail> getEvent(int eventId);
}

class DioPublicEventDetailService implements PublicEventDetailService {
  DioPublicEventDetailService({Dio? dio}) : _dio = dio ?? _createDio();

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

  @override
  Future<PublicEventDetail> getEvent(int eventId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/events/public/$eventId',
    );
    final event = response.data?['event'];
    if (event is! Map) {
      throw const FormatException('Public event detail response is invalid.');
    }
    return PublicEventDetail.fromJson(Map<String, dynamic>.from(event));
  }
}
