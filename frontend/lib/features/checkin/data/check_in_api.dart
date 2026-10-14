import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the backend says about one entry pass (`GET …/check-ins/verify`).
@immutable
class EntryPassCheck {
  const EntryPassCheck({
    required this.valid,
    required this.alreadyCheckedIn,
    required this.message,
    this.fullName,
    this.registrationStatus,
  });

  factory EntryPassCheck.fromJson(Map<String, dynamic> json) => EntryPassCheck(
        valid: json['valid'] == true,
        alreadyCheckedIn: json['already_checked_in'] == true,
        message: json['message']?.toString() ?? '',
        fullName: json['full_name']?.toString(),
        registrationStatus: json['registration_status']?.toString(),
      );

  final bool valid;
  final bool alreadyCheckedIn;

  /// `ready_to_checkin`, `already_checked_in`, `invalid_qr_token`,
  /// `token_belongs_to_different_event` or `registration_not_eligible`.
  final String message;
  final String? fullName;
  final String? registrationStatus;
}

/// Check-in by entry pass, for an event's admins (the backend checks).
class CheckInApi {
  CheckInApi({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;

  static Dio _createDio() {
    const configured = String.fromEnvironment('BACKEND_BASE_URL');
    const devConfigured = String.fromEnvironment('DEV_BACKEND_BASE_URL');
    final baseUrl = configured.isNotEmpty
        ? configured
        : devConfigured.isNotEmpty
            ? devConfigured
            : 'http://127.0.0.1:8000';
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: const {'Content-Type': 'application/json'},
      ),
    );
  }

  Options _auth(String accessToken) =>
      Options(headers: {'Authorization': 'Bearer $accessToken'});

  Future<EntryPassCheck> verify({
    required int eventId,
    required String qrToken,
    required String accessToken,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/admin/events/$eventId/check-ins/verify',
      queryParameters: {'qr_token': qrToken},
      options: _auth(accessToken),
    );
    return EntryPassCheck.fromJson(response.data ?? const {});
  }

  Future<void> checkIn({
    required int eventId,
    required String qrToken,
    required String accessToken,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/admin/events/$eventId/check-ins',
      data: {'qr_token': qrToken},
      options: _auth(accessToken),
    );
  }
}

final checkInApiProvider = Provider<CheckInApi>((ref) => CheckInApi());
