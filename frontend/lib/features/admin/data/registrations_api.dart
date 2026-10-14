import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One registration in the Admin → Registrations tab.
///
/// Registered people come from `GET /admin/events/{id}/attendees` (which has
/// batch, branch, phone and the confirmation-email status); cancelled ones
/// from `GET /admin/events/{id}/registrations?status=cancelled` (which has
/// the cancelled date but no batch, branch or phone).
@immutable
class AdminRegistration {
  const AdminRegistration({
    required this.registrationId,
    required this.eventId,
    required this.status,
    required this.registeredAt,
    this.registrationNumber,
    this.fullname,
    this.email,
    this.phone,
    this.batchYear,
    this.branch,
    this.confirmationEmailStatus,
    this.cancelledAt,
  });

  final int registrationId;
  final int eventId;
  final String status;
  final DateTime registeredAt;
  final String? registrationNumber;
  final String? fullname;
  final String? email;
  final String? phone;
  final int? batchYear;
  final String? branch;
  final String? confirmationEmailStatus;
  final DateTime? cancelledAt;

  bool get isCancelled => status == 'cancelled';

  /// Name to show; falls back to the email, then the registration number.
  String get displayName {
    final name = fullname?.trim();
    if (name != null && name.isNotEmpty) return name;
    final mail = email?.trim();
    if (mail != null && mail.isNotEmpty) return mail;
    return registrationNumber ?? 'Registration $registrationId';
  }

  factory AdminRegistration.fromJson(Map<String, dynamic> json, int eventId) {
    return AdminRegistration(
      registrationId: _int(json['registration_id']) ?? 0,
      eventId: eventId,
      status: json['status']?.toString() ?? 'registered',
      registeredAt: _date(json['registered_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      registrationNumber: _text(json['registration_number']),
      fullname: _text(json['fullname_snapshot']),
      email: _text(json['email_snapshot']),
      phone: _text(json['phone_snapshot']),
      batchYear: _int(json['batch_year_snapshot']),
      branch: _text(json['branch_snapshot']),
      confirmationEmailStatus: _text(json['confirmation_email_status']),
      cancelledAt: _date(json['cancelled_at']),
    );
  }
}

/// One door check-in (`GET /admin/events/{id}/check-ins`).
@immutable
class AdminCheckIn {
  const AdminCheckIn({
    required this.checkinId,
    required this.eventId,
    required this.registrationId,
    required this.checkedInAt,
    required this.result,
    this.sessionId,
  });

  final int checkinId;
  final int eventId;
  final int registrationId;
  final DateTime checkedInAt;
  final String result;
  final int? sessionId;

  factory AdminCheckIn.fromJson(Map<String, dynamic> json) {
    return AdminCheckIn(
      checkinId: _int(json['checkin_id']) ?? 0,
      eventId: _int(json['event_id']) ?? 0,
      registrationId: _int(json['registration_id']) ?? 0,
      checkedInAt: _date(json['checked_in_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      result: json['result']?.toString() ?? '',
      sessionId: _int(json['session_id']),
    );
  }
}

/// Everything the tab shows for one event.
@immutable
class EventRegistrationData {
  const EventRegistrationData({
    required this.eventId,
    required this.registered,
    required this.cancelled,
    required this.checkIns,
  });

  final int eventId;
  final List<AdminRegistration> registered;
  final List<AdminRegistration> cancelled;
  final List<AdminCheckIn> checkIns;
}

int? _int(Object? v) => v is int ? v : (v == null ? null : int.tryParse(v.toString()));

String? _text(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

DateTime? _date(Object? v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString())?.toLocal();
}

/// Admin calls for registrations, check-ins and the CSV export. All of them
/// are scoped by the backend: event admins only reach their own events.
class RegistrationsApi {
  RegistrationsApi({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;

  /// The largest page the backend allows.
  static const _pageSize = 200;

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

  Options _auth(String accessToken) =>
      Options(headers: {'Authorization': 'Bearer $accessToken'});

  /// Registered, cancelled and check-ins for one event, all pages.
  Future<EventRegistrationData> loadEvent({
    required String accessToken,
    required int eventId,
  }) async {
    final results = await Future.wait<Object>([
      _registered(accessToken, eventId),
      _cancelled(accessToken, eventId),
      checkIns(accessToken: accessToken, eventId: eventId),
    ]);
    return EventRegistrationData(
      eventId: eventId,
      registered: results[0] as List<AdminRegistration>,
      cancelled: results[1] as List<AdminRegistration>,
      checkIns: results[2] as List<AdminCheckIn>,
    );
  }

  Future<List<AdminRegistration>> _registered(String token, int eventId) =>
      _allPages(
        path: '/api/v1/admin/events/$eventId/attendees',
        listKey: 'attendees',
        token: token,
        eventId: eventId,
      );

  Future<List<AdminRegistration>> _cancelled(String token, int eventId) =>
      _allPages(
        path: '/api/v1/admin/events/$eventId/registrations',
        listKey: 'registrations',
        token: token,
        eventId: eventId,
        query: const {'status': 'cancelled'},
      );

  Future<List<AdminRegistration>> _allPages({
    required String path,
    required String listKey,
    required String token,
    required int eventId,
    Map<String, dynamic> query = const {},
  }) async {
    final rows = <AdminRegistration>[];
    for (var page = 1; page <= 100; page++) {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: {...query, 'page': page, 'per_page': _pageSize},
        options: _auth(token),
      );
      final data = response.data ?? const <String, dynamic>{};
      final list = data[listKey] as List<dynamic>? ?? const [];
      rows.addAll(
        list
            .whereType<Map<String, dynamic>>()
            .map((json) => AdminRegistration.fromJson(json, eventId)),
      );
      final total = (data['total'] as num?)?.toInt() ?? rows.length;
      if (list.isEmpty || rows.length >= total) break;
    }
    return rows;
  }

  Future<List<AdminCheckIn>> checkIns({
    required String accessToken,
    required int eventId,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/v1/admin/events/$eventId/check-ins',
      options: _auth(accessToken),
    );
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AdminCheckIn.fromJson)
        .toList();
  }

  /// The server's CSV of everyone registered for the event (UTF-8 with BOM,
  /// opens directly in Excel).
  Future<Uint8List> exportCsv({
    required String accessToken,
    required int eventId,
  }) async {
    final response = await _dio.get<List<int>>(
      '/api/v1/admin/events/$eventId/attendees/export',
      options: Options(
        headers: {'Authorization': 'Bearer $accessToken'},
        responseType: ResponseType.bytes,
      ),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }
}

final registrationsApiProvider = Provider<RegistrationsApi>((ref) => RegistrationsApi());
