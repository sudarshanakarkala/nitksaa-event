import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/event.dart';
import '../domain/event_sheet.dart';
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

  static String get _defaultBackendBaseUrl => 'http://127.0.0.1:8000';

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

  /// The Events page: every published event, upcoming and past, a page of
  /// 100 at a time.
  Future<List<AppEvent>> getAllPublicEvents() async {
    final events = <AppEvent>[];
    for (var page = 1; page <= 50; page++) {
      final data = await getPublicEvents(page: page, perPage: 100, period: 'all');
      final rows = data['events'] as List<dynamic>? ?? const [];
      events.addAll(rows.whereType<Map<String, dynamic>>().map(AppEvent.fromJson));
      final total = (data['total'] as num?)?.toInt() ?? events.length;
      if (rows.isEmpty || events.length >= total) break;
    }
    return events;
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

  // ── Speakers, sessions and fee tiers (event form) ────────────────────
  // One call each way: the form sends the full lists and the backend adds,
  // changes and removes to match.

  Future<Map<String, dynamic>> getEventDetails(int eventId, String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/admin/events/$eventId/details',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> putEventDetails(
    int eventId,
    String accessToken,
    Map<String, dynamic> content,
  ) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/v1/admin/events/$eventId/details',
      data: content,
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return response.data ?? <String, dynamic>{};
  }

  // ── The event's Google Sheet ──────────────────────────────────────
  // Failures come back as [SheetProblem] (plain words, nothing changed).

  Future<SheetInfo> getSheetInfo(String accessToken) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/admin/sheets/info',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return SheetInfo.fromJson(response.data ?? const {});
    } catch (error) {
      throw SheetProblem.from(error);
    }
  }

  /// Events → Import: reads the sheet without saving anything.
  Future<SheetPreview> previewSheet(String url, String accessToken) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/admin/sheets/preview',
        data: {'url': url},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return SheetPreview.fromJson(response.data ?? const {});
    } catch (error) {
      throw SheetProblem.from(error);
    }
  }

  /// Links [url] (or re-reads the linked sheet when null) and saves what it
  /// holds. If the sheet's Event tab would change the event, nothing is
  /// saved unless [confirm]: the result has `needsConfirm` and the changes.
  Future<SheetRefresh> refreshEventSheet(
    int eventId,
    String? url,
    String accessToken, {
    bool confirm = false,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/admin/events/$eventId/sheet/refresh',
        data: {'url': ?url, 'confirm': confirm},
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
          // Big sheets and the alumni lookup can take a while.
          receiveTimeout: const Duration(seconds: 120),
        ),
      );
      return SheetRefresh.fromJson(response.data ?? const {});
    } catch (error) {
      throw SheetProblem.from(error);
    }
  }

  /// Unlinks the sheet; what it saved stays, editable again.
  Future<void> unlinkEventSheet(int eventId, String accessToken) async {
    try {
      await _dio.delete<Map<String, dynamic>>(
        '/api/v1/admin/events/$eventId/sheet',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
    } catch (error) {
      throw SheetProblem.from(error);
    }
  }

  // ── Sponsors and partners ([kind] is 'sponsors' or 'partners') ────────
  // The event form saves these through their own endpoints: the event's
  // create/update body has no sponsor or partner fields.

  Future<List<Map<String, dynamic>>> listEventOrgs(
    int eventId,
    String kind,
    String accessToken,
  ) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/v1/events/$eventId/$kind',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<void> createEventOrg(
    int eventId,
    String kind,
    Map<String, dynamic> data,
    String accessToken,
  ) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/events/$eventId/$kind',
      data: data,
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
  }

  Future<void> updateEventOrg(
    int eventId,
    String kind,
    int id,
    Map<String, dynamic> data,
    String accessToken,
  ) async {
    await _dio.put<Map<String, dynamic>>(
      '/api/v1/events/$eventId/$kind/$id',
      data: data,
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
  }

  Future<void> deleteEventOrg(
    int eventId,
    String kind,
    int id,
    String accessToken,
  ) async {
    await _dio.delete<void>(
      '/api/v1/events/$eventId/$kind/$id',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
  }

  /// Admin list for the Events tab: every event the caller administers
  /// (all for an overall admin), any status, past and upcoming.
  Future<List<AppEvent>> getAllAdminEvents(String accessToken) async {
    final events = <AppEvent>[];
    for (var page = 1; page <= 50; page++) {
      final data = await getAdminEvents(
        page: page,
        perPage: 100,
        period: 'all',
        accessToken: accessToken,
      );
      final rows = data['events'] as List<dynamic>? ?? const [];
      events.addAll(rows.whereType<Map<String, dynamic>>().map(AppEvent.fromJson));
      final total = (data['total'] as num?)?.toInt() ?? events.length;
      if (rows.isEmpty || events.length >= total) break;
    }
    return events;
  }

  /// An event through the admin API: any status (draft, cancelled…), for
  /// its admins and overall admins only.
  Future<AppEvent> getAdminEvent(int eventId, String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/events/$eventId',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return AppEvent.fromJson(response.data?['event'] as Map<String, dynamic>);
  }

  /// The published event behind a readable link (`/e/<slug>`). Null when
  /// there is none (unknown, a draft, or mistyped).
  Future<int?> findPublicEventIdBySlug(String slug) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/events/public/by-slug/${Uri.encodeComponent(slug)}',
      );
      return (response.data?['event_id'] as num?)?.toInt();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
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

    // Each event once, however many of your registrations it has, and all
    // of them at the same time rather than one after another.
    Future<AppEvent?> fetch(int id) async {
      try {
        return await getPublicEvent(id);
      } on DioException {
        return null;
      }
    }

    final ids = {for (final r in registrations) r.eventId}.toList();
    final fetched = await Future.wait(ids.map(fetch));
    final events = {for (var i = 0; i < ids.length; i++) ids[i]: fetched[i]};
    return [
      for (final registration in registrations)
        events[registration.eventId] == null
            ? registration
            : registration.copyWith(publicEvent: events[registration.eventId]),
    ];
  }

  /// The name and phone from the attendee's newest registration that has a
  /// phone, to fill in the registration form. Null when there is none. Reads
  /// only the registrations list, not their events.
  Future<({String? fullname, String phone})?> getLastRegistrationDetails(
    String accessToken,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/my/registrations',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    final raw = response.data?['registrations'] as List<dynamic>? ?? [];
    final withPhone = raw
        .whereType<Map<String, dynamic>>()
        .where((r) => (r['phone_snapshot']?.toString().trim() ?? '').isNotEmpty)
        .toList()
      ..sort((a, b) => (b['registered_at']?.toString() ?? '')
          .compareTo(a['registered_at']?.toString() ?? ''));
    if (withPhone.isEmpty) return null;
    final newest = withPhone.first;
    final name = newest['fullname_snapshot']?.toString().trim();
    return (
      fullname: (name == null || name.isEmpty) ? null : name,
      phone: newest['phone_snapshot'].toString().trim(),
    );
  }

  /// What the server will charge [people] people for the event: line items
  /// and the final amount (GST and fees as set in the event's payment setup).
  Future<Map<String, dynamic>> getPaymentPricing(
    int eventId,
    String accessToken, {
    int people = 1,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/events/$eventId/payment-pricing',
      queryParameters: {if (people > 1) 'people': people},
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return response.data ?? <String, dynamic>{};
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
    String accessToken, {
    required String attendeeNote,
    String? fullname,
    required String phone,
    List<String> guests = const [],
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/events/$eventId/register',
      data: {
        'attendee_note': attendeeNote,
        'fullname': ?fullname,
        'phone': phone,
        if (guests.isNotEmpty) 'guests': [for (final g in guests) {'name': g}],
      },
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
