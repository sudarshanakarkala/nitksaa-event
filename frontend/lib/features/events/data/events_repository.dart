import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/event.dart';
import '../domain/my_event_registration.dart';
import '../domain/refund_status.dart';

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

  Future<Map<String, dynamic>> getAdminEvents({
    required int page,
    required int perPage,
    required String period,
    required String accessToken,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/events',
      queryParameters: {
        'page': page,
        'per_page': perPage,
        'period': period,
      },
      options: Options(headers: {
        'Authorization': 'Bearer $accessToken',
        'X-Dev-User': 'admin',
      }),
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

  Future<AppEvent> updateEventStatus(
    int eventId,
    String status,
    String accessToken,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/v1/events/$eventId/status',
      data: {'status': status},
      options: Options(headers: {
        'Authorization': 'Bearer $accessToken',
        'X-Dev-User': 'admin',
      }),
    );
    final eventJson = response.data?['event'] as Map<String, dynamic>;
    return AppEvent.fromJson(eventJson);
  }

  Future<void> deleteAdminEvent(
    int eventId,
    String accessToken,
  ) async {
    await _dio.delete(
      '/api/v1/events/$eventId',
      options: Options(headers: {
        'Authorization': 'Bearer $accessToken',
        'X-Dev-User': 'admin',
      }),
    );
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

  /// Cancels one of the attendee's own registrations. If it was paid for, the
  /// backend starts a full refund in the same call.
  ///
  /// [idempotencyKey] (8 to 128 characters) must be the same on every retry
  /// of one user action, so a retry cannot start a second refund.
  Future<RefundStatus> cancelRegistration(
    int registrationId,
    String accessToken, {
    required String idempotencyKey,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/registrations/$registrationId/cancel',
      data: {'idempotency_key': idempotencyKey},
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return RefundStatus.fromJson(response.data ?? <String, dynamic>{});
  }

  /// The refund of one of the attendee's own registrations, or a status of
  /// `none` when nothing was paid.
  ///
  /// While a refund is still pending the backend asks the payment provider
  /// again before it answers, so calling this again is how to check on it.
  Future<RefundStatus> getRefundStatus(
    int registrationId,
    String accessToken,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/registrations/$registrationId/refund',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return RefundStatus.fromJson(response.data ?? <String, dynamic>{});
  }

  /// Registers the signed-in attendee for the event: one registration, one
  /// seat. `attendee_note` is the only field the backend accepts.
  Future<Map<String, dynamic>> registerForEvent(
    int eventId,
    String accessToken,
    String attendeeNote,
  ) async {
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

  Future<Map<String, dynamic>> getEventAttendees({
    required int eventId,
    required String accessToken,
    int page = 1,
    int perPage = 50,
    String? search,
    int? batchYear,
    String? branch,
  }) async {
    final queryParams = <String, dynamic>{
      'page': page,
      'per_page': perPage,
    };
    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }
    if (batchYear != null) {
      queryParams['batch_year'] = batchYear;
    }
    if (branch != null && branch.isNotEmpty) {
      queryParams['branch'] = branch;
    }
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/admin/events/$eventId/attendees',
      queryParameters: queryParams,
      options: Options(headers: {
        'Authorization': 'Bearer $accessToken',
        'X-Dev-User': 'admin',
      }),
    );
    return response.data ?? <String, dynamic>{};
  }

  // ==========================================
  // PAYMENTS (Razorpay hosted checkout)
  // ==========================================

  /// Creates (or reuses) the payment order for a registration.
  /// Returns `{order_id: "ORD-...", final_amount, currency, ...}`.
  Future<Map<String, dynamic>> createPaymentOrder(
    int registrationId,
    String accessToken, {
    required String idempotencyKey,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/registrations/$registrationId/payment-order',
      data: {'idempotency_key': idempotencyKey},
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return response.data ?? <String, dynamic>{};
  }

  /// Starts a payment attempt on our order. For Razorpay the response carries
  /// a `checkout` object: {provider_order_id, key_id, amount_minor, currency}.
  Future<Map<String, dynamic>> createPaymentAttempt(
    String orderId,
    String accessToken,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/payment-orders/$orderId/attempts',
      data: const <String, dynamic>{},
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return response.data ?? <String, dynamic>{};
  }

  /// Sends Razorpay's success payload to the backend, which re-verifies the
  /// signature and the provider status before confirming the registration.
  /// [orderId] is OUR order id (ORD-...), not Razorpay's order_... id.
  Future<Map<String, dynamic>> verifyCheckout(
    String orderId,
    String accessToken, {
    required String razorpayPaymentId,
    required String razorpayOrderId,
    required String razorpaySignature,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/payment-orders/$orderId/verify-checkout',
      data: {
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_order_id': razorpayOrderId,
        'razorpay_signature': razorpaySignature,
      },
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return response.data ?? <String, dynamic>{};
  }
}

final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  return EventsRepository();
});
