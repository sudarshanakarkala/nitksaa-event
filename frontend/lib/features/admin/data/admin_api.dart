import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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

class AdminUserPage {
  const AdminUserPage({
    required this.users,
    required this.total,
    required this.page,
    required this.perPage,
  });

  final List<AdminUser> users;
  final int total;
  final int page;
  final int perPage;

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

  static String get _defaultBackendBaseUrl {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  Options _auth(String accessToken) =>
      Options(headers: {'Authorization': 'Bearer $accessToken'});

  /// Overall admin only. [query] matches name or email.
  Future<AdminUserPage> searchUsers({
    required String accessToken,
    String? query,
    int page = 1,
    int perPage = 25,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/admin/users',
      queryParameters: {
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
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
        if (isAdmin != null) 'is_admin': isAdmin,
        if (isEventCreator != null) 'is_event_creator': isEventCreator,
      },
      options: _auth(accessToken),
    );
    return AdminUser.fromJson(response.data ?? <String, dynamic>{});
  }
}

final adminApiProvider = Provider<AdminApi>((ref) => AdminApi());
