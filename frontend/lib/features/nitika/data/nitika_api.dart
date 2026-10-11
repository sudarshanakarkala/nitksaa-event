import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/nitika_models.dart';
import '../nitika_config.dart';

/// NITiKa chat, through the events backend.
abstract class NitikaApi {
  /// Throws [NitikaError] on every failure.
  Future<NitikaReply> chat({
    required String accessToken,
    required String message,
    required List<ChatTurn> history,
    required String locale,
    required NitikaPageContext context,
  });
}

/// `POST /api/v1/nitika/chat` on the events backend, which adds the user's
/// role and scope and calls NITiKa. The backend answers 404 when NITiKa
/// isn't configured.
class DioNitikaApi implements NitikaApi {
  DioNitikaApi({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;

  static Dio _createDio() => Dio(
    BaseOptions(
      baseUrl: nitikaBackendBaseUrl,
      // NITiKa's own deadline is 20 s; the backend adds its own on top.
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 35),
      sendTimeout: const Duration(seconds: 10),
      headers: const {'Content-Type': 'application/json'},
    ),
  );

  @override
  Future<NitikaReply> chat({
    required String accessToken,
    required String message,
    required List<ChatTurn> history,
    required String locale,
    required NitikaPageContext context,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/nitika/chat',
        data: {
          'message': message,
          'history': [for (final t in history) t.toJson()],
          'locale': locale,
          'context': context.toJson(),
        },
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final data = response.data;
      if (data == null) throw const NitikaError(NitikaErrorKind.failed);
      return NitikaReply.fromJson(data);
    } on DioException catch (e) {
      final response = e.response;
      if (response != null) {
        throw NitikaError.fromResponse(response.statusCode, response.data);
      }
      throw NitikaError(
        e.type == DioExceptionType.receiveTimeout
            ? NitikaErrorKind.timeout
            : NitikaErrorKind.failed,
        code: 'network',
      );
    } on FormatException {
      throw const NitikaError(NitikaErrorKind.failed);
    } on TypeError {
      // A body that isn't a JSON object.
      throw const NitikaError(NitikaErrorKind.failed);
    }
  }
}

final nitikaApiProvider = Provider<NitikaApi>((ref) => DioNitikaApi());
