import 'package:dio/dio.dart';

import '../../../core/network/backend_api_config.dart';
import '../domain/public_event.dart';

enum EventPeriod {
  upcoming,
  past;

  String get queryValue => name;
}

abstract interface class PublicEventService {
  Future<List<PublicEvent>> listEvents(EventPeriod period);
}

class DioPublicEventService implements PublicEventService {
  DioPublicEventService({Dio? dio}) : _dio = dio ?? _createDio();

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
  Future<List<PublicEvent>> listEvents(EventPeriod period) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/events/public',
      queryParameters: {'period': period.queryValue},
    );
    final payload = response.data;
    final events = payload?['events'];
    if (events is! List) {
      throw const FormatException('Public events response is invalid.');
    }

    return events
        .map(
          (event) =>
              PublicEvent.fromJson(Map<String, dynamic>.from(event as Map)),
        )
        .toList(growable: false);
  }
}
