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
    this.guestOf,
  });

  factory EntryPassCheck.fromJson(Map<String, dynamic> json) => EntryPassCheck(
        valid: json['valid'] == true,
        alreadyCheckedIn: json['already_checked_in'] == true,
        message: json['message']?.toString() ?? '',
        fullName: json['full_name']?.toString(),
        registrationStatus: json['registration_status']?.toString(),
        guestOf: json['guest_of']?.toString(),
      );

  final bool valid;
  final bool alreadyCheckedIn;

  /// `ready_to_checkin`, `already_checked_in`, `invalid_qr_token`,
  /// `token_belongs_to_different_event` or `registration_not_eligible`.
  final String message;
  final String? fullName;
  final String? registrationStatus;

  /// The registrant's name, when this pass is a guest's.
  final String? guestOf;

  /// The name to show at the door: "Asha Warrier, guest of Padmanand Warrier".
  String? get displayName {
    if (fullName == null) return null;
    return guestOf == null ? fullName : '$fullName, guest of $guestOf';
  }
}

/// One check-in just made: what Undo needs.
@immutable
class CheckInDone {
  const CheckInDone({required this.checkinId, required this.registrationId, this.checkedInAt});

  factory CheckInDone.fromJson(Map<String, dynamic> json) => CheckInDone(
        checkinId: (json['checkin_id'] as num?)?.toInt() ?? 0,
        registrationId: (json['registration_id'] as num?)?.toInt() ?? 0,
        checkedInAt: DateTime.tryParse(json['checked_in_at']?.toString() ?? '')?.toLocal(),
      );

  final int checkinId;
  final int registrationId;
  final DateTime? checkedInAt;
}

/// Check-in for an event's admins (the backend checks): by entry pass
/// (a scan), by registration (the Check-in list), and Undo.
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

  Future<CheckInDone> checkIn({
    required int eventId,
    required String qrToken,
    required String accessToken,
  }) =>
      _create(eventId, {'qr_token': qrToken}, accessToken);

  Future<CheckInDone> checkInRegistration({
    required int eventId,
    required int registrationId,
    required String accessToken,
  }) =>
      _create(eventId, {'registration_id': registrationId}, accessToken);

  Future<CheckInDone> _create(int eventId, Map<String, dynamic> body, String accessToken) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/admin/events/$eventId/check-ins',
      data: body,
      options: _auth(accessToken),
    );
    return CheckInDone.fromJson(response.data ?? const {});
  }

  /// Undoes a mistaken check-in.
  Future<void> undo({
    required int eventId,
    required int checkinId,
    required String accessToken,
  }) async {
    await _dio.delete<void>(
      '/api/v1/admin/events/$eventId/check-ins/$checkinId',
      options: _auth(accessToken),
    );
  }
}

final checkInApiProvider = Provider<CheckInApi>((ref) => CheckInApi());
