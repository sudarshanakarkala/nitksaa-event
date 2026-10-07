import 'package:dio/dio.dart';

/// Why the backend half of a sign-in did not produce a session.
enum BackendAuthFailure {
  /// The Firebase account's email address has not been verified.
  emailNotVerified,

  /// The backend has suspended this user.
  accountSuspended,

  /// The Firebase account has no email address.
  emailMissing,

  /// The backend refused the Firebase ID token or its own access token.
  sessionRejected,

  /// The backend could not be reached, or did not answer in time.
  network,

  /// The backend answered with a 5xx.
  server,

  /// Anything that fits none of the above.
  unknown,
}

/// A failed call to `POST /api/v1/auth/firebase` or `GET /api/v1/auth/me`.
///
/// Keeps the backend's `detail` code and the HTTP status so callers can tell
/// the failures apart. It does not keep the request or the response: they
/// hold the Firebase ID token and the bearer token, and this exception is
/// logged.
class BackendAuthException implements Exception {
  const BackendAuthException(this.failure, {this.code, this.statusCode});

  factory BackendAuthException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return const BackendAuthException(BackendAuthFailure.network);
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        break;
    }

    final response = error.response;
    if (response == null) {
      return const BackendAuthException(BackendAuthFailure.unknown);
    }

    final statusCode = response.statusCode;
    final data = response.data;
    final detail = data is Map ? data['detail'] : null;
    final code = detail is String ? detail : null;
    return BackendAuthException(
      _classify(code, statusCode),
      code: code,
      statusCode: statusCode,
    );
  }

  final BackendAuthFailure failure;

  /// The backend's `detail` code, such as `email_not_verified`. Null when the
  /// backend sent none, or sent something other than a string.
  final String? code;

  /// Null when the backend did not answer.
  final int? statusCode;

  /// The codes are the ones `app/api/auth.py` and `app/middleware/auth.py`
  /// raise. An unrecognised code falls back to the HTTP status.
  static BackendAuthFailure _classify(String? code, int? statusCode) {
    switch (code) {
      case 'email_not_verified':
        return BackendAuthFailure.emailNotVerified;
      case 'account_suspended':
        return BackendAuthFailure.accountSuspended;
      case 'email_missing':
        return BackendAuthFailure.emailMissing;
      case 'firebase_token_expired':
      case 'invalid_firebase_token':
      case 'firebase_uid_missing':
      case 'invalid_or_expired_token':
      case 'invalid_token':
        return BackendAuthFailure.sessionRejected;
    }
    if (statusCode == 401 || statusCode == 403) {
      return BackendAuthFailure.sessionRejected;
    }
    if (statusCode != null && statusCode >= 500) {
      return BackendAuthFailure.server;
    }
    return BackendAuthFailure.unknown;
  }

  @override
  String toString() =>
      'BackendAuthException(${failure.name}, code: $code, '
      'statusCode: $statusCode)';
}
