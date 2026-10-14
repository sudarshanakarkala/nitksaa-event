import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One person in the Roles tab (`GET /api/v1/admin/users`).
class AdminUser {
  const AdminUser({
    required this.firebaseUid,
    required this.email,
    required this.fullname,
    required this.userType,
    required this.isAdmin,
    required this.isEventCreator,
    required this.isEmergencyAdmin,
    required this.adminEventIds,
  });

  final String firebaseUid;
  final String email;
  final String fullname;
  final String userType;
  final bool isAdmin;
  final bool isEventCreator;

  /// Overall admin through the Cloud Run emergency list; not changeable
  /// from the app.
  final bool isEmergencyAdmin;
  final List<int> adminEventIds;

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    final ids = json['admin_event_ids'];
    return AdminUser(
      firebaseUid: json['firebase_uid']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      fullname: json['fullname']?.toString() ?? '',
      userType: json['user_type']?.toString() ?? '',
      isAdmin: json['is_admin'] == true,
      isEventCreator: json['is_event_creator'] == true,
      isEmergencyAdmin: json['is_emergency_admin'] == true,
      adminEventIds: ids is List
          ? ids
              .map((e) => e is int ? e : int.tryParse(e.toString()))
              .whereType<int>()
              .toList(growable: false)
          : const [],
    );
  }
}

/// One admin of an event (`GET /api/v1/admin/events/{id}/admins`).
class EventAdmin {
  const EventAdmin({
    required this.firebaseUid,
    this.email,
    this.fullname,
    this.isCreator = false,
  });

  final String firebaseUid;
  final String? email;
  final String? fullname;
  final bool isCreator;

  factory EventAdmin.fromJson(Map<String, dynamic> json) => EventAdmin(
        firebaseUid: json['firebase_uid']?.toString() ?? '',
        email: json['email']?.toString(),
        fullname: json['fullname']?.toString(),
        isCreator: json['is_creator'] == true,
      );
}

/// One active payment-role grant (`GET /api/v1/admin/payment-roles`).
class PaymentRoleGrant {
  const PaymentRoleGrant({required this.id, required this.firebaseUid, required this.role});

  final int id;
  final String firebaseUid;

  /// platform_admin / finance_operator / auditor / support.
  final String role;

  factory PaymentRoleGrant.fromJson(Map<String, dynamic> json) => PaymentRoleGrant(
        id: (json['id'] as num?)?.toInt() ?? 0,
        firebaseUid: json['firebase_uid']?.toString() ?? '',
        role: json['role']?.toString() ?? '',
      );
}

class AdminUserPage {
  const AdminUserPage({
    required this.users,
    required this.total,
    required this.page,
    required this.perPage,
    this.counts = const {},
  });

  final List<AdminUser> users;
  final int total;
  final int page;
  final int perPage;

  /// People matching the search in each role (`overall_admin`,
  /// `event_admin`, `finance`, `any`, `everyone`): the Roles pills.
  final Map<String, int> counts;

  int get pages => total == 0 ? 1 : ((total + perPage - 1) ~/ perPage);
}

/// Admin read/write calls that aren't about a single event's content.
class AdminApi {
  AdminApi({Dio? dio}) : _dio = dio ?? _createDio();

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

  Options _auth(String accessToken) =>
      Options(headers: {'Authorization': 'Bearer $accessToken'});

  /// Overall admin only. [query] matches name or email.
  Future<AdminUserPage> searchUsers({
    required String accessToken,
    String? query,
    String? role,
    int page = 1,
    int perPage = 25,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/admin/users',
      queryParameters: {
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
        'role': ?role,
        'page': page,
        'per_page': perPage,
      },
      options: _auth(accessToken),
    );
    final data = response.data ?? <String, dynamic>{};
    final rows = data['users'] as List<dynamic>? ?? const [];
    return AdminUserPage(
      users: rows
          .whereType<Map<String, dynamic>>()
          .map(AdminUser.fromJson)
          .toList(),
      total: (data['total'] as num?)?.toInt() ?? rows.length,
      page: (data['page'] as num?)?.toInt() ?? page,
      perPage: (data['per_page'] as num?)?.toInt() ?? perPage,
      counts: {
        for (final e in (data['counts'] as Map<String, dynamic>? ?? const {}).entries)
          if (e.value is num) e.key: (e.value as num).toInt(),
      },
    );
  }

  /// Overall admin only. Returns the updated user.
  Future<AdminUser> updateUserRoles({
    required String accessToken,
    required String firebaseUid,
    bool? isAdmin,
    bool? isEventCreator,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/v1/admin/users/${Uri.encodeComponent(firebaseUid)}/roles',
      data: {
        'is_admin': ?isAdmin,
        'is_event_creator': ?isEventCreator,
      },
      options: _auth(accessToken),
    );
    return AdminUser.fromJson(response.data ?? <String, dynamic>{});
  }

  // ── Event admins (overall admins and the event's own admins) ────────────

  Future<List<EventAdmin>> listEventAdmins({
    required String accessToken,
    required int eventId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/admin/events/$eventId/admins',
      options: _auth(accessToken),
    );
    final rows = response.data?['admins'] as List<dynamic>? ?? const [];
    return rows.whereType<Map<String, dynamic>>().map(EventAdmin.fromJson).toList();
  }

  /// Adds the person who signs in with [email] as an admin of the event.
  Future<EventAdmin> grantEventAdmin({
    required String accessToken,
    required int eventId,
    required String email,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/admin/events/$eventId/admins',
      data: {'email': email.trim()},
      options: _auth(accessToken),
    );
    return EventAdmin.fromJson(response.data ?? const {});
  }

  // ── Payment roles (overall admins) ──────────────────────────────────────

  /// Active payment-role grants, e.g. finance_operator.
  Future<List<PaymentRoleGrant>> listPaymentRoles({required String accessToken}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/admin/payment-roles',
      options: _auth(accessToken),
    );
    final rows = response.data?['roles'] as List<dynamic>? ?? const [];
    return rows.whereType<Map<String, dynamic>>().map(PaymentRoleGrant.fromJson).toList();
  }

  Future<PaymentRoleGrant> grantPaymentRole({
    required String accessToken,
    required String firebaseUid,
    required String role,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/admin/payment-roles',
      data: {'firebase_uid': firebaseUid, 'role': role},
      options: _auth(accessToken),
    );
    return PaymentRoleGrant.fromJson(response.data ?? const {});
  }

  Future<void> revokePaymentRole({required String accessToken, required int grantId}) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/admin/payment-roles/$grantId/revoke',
      options: _auth(accessToken),
    );
  }

  Future<void> revokeEventAdmin({
    required String accessToken,
    required int eventId,
    required String firebaseUid,
  }) async {
    await _dio.delete<Map<String, dynamic>>(
      '/api/v1/admin/events/$eventId/admins/${Uri.encodeComponent(firebaseUid)}',
      options: _auth(accessToken),
    );
  }
}

final adminApiProvider = Provider<AdminApi>((ref) => AdminApi());
