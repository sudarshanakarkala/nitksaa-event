import 'package:dio/dio.dart';

import '../../domain/refund_status.dart';

/// How one attempt to cancel a registration ended, and what to tell the
/// attendee about it.
///
/// [message] is one of the fixed strings below or the backend's
/// `safe_message`: no exception text, HTTP status or backend code reaches the
/// attendee. This covers cancellation only.
class CancellationOutcome {
  const CancellationOutcome._({
    required this.cancelled,
    required this.message,
    this.refund,
  });

  /// The backend cancelled the registration, or it was cancelled already.
  factory CancellationOutcome.cancelled(RefundStatus refund) {
    const cancelled = 'Your registration has been cancelled.';
    final safeMessage = refund.safeMessage?.trim() ?? '';
    final message = switch (refund.status) {
      RefundStatus.pending ||
      RefundStatus.processed => '$cancelled Your refund has been initiated.',
      // The backend's wording for a failed refund already says that the
      // registration is cancelled.
      RefundStatus.failed =>
        safeMessage.isNotEmpty
            ? safeMessage
            : '$cancelled The refund could not be completed automatically. '
                  'Please contact support.',
      _ => cancelled,
    };
    return CancellationOutcome._(
      cancelled: true,
      message: message,
      refund: refund,
    );
  }

  /// The registration was not cancelled, as far as the app can tell.
  factory CancellationOutcome.failed(Object? error) {
    return CancellationOutcome._(
      cancelled: false,
      message: _failureMessage(error),
    );
  }

  final bool cancelled;
  final String message;

  /// Null when the registration was not cancelled.
  final RefundStatus? refund;

  /// True when the backend answered and said no. Any other failure leaves it
  /// unknown whether the cancellation went through.
  static bool isRefusal(Object error) {
    if (error is! DioException) return false;
    final statusCode = error.response?.statusCode;
    return statusCode != null && statusCode >= 400 && statusCode < 500;
  }

  /// The codes are the ones `app/services/refund_service.py` raises.
  static String _failureMessage(Object? error) {
    const generic = 'Could not cancel your registration. Please try again.';
    if (error is! DioException) return generic;

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return 'Unable to connect to the server. Check your internet '
            'connection and try again.';
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        break;
    }

    final data = error.response?.data;
    final detail = data is Map ? data['detail'] : null;
    return switch (detail) {
      'registration_not_cancellable' =>
        "This registration can't be cancelled while payment is in progress.",
      'registration_not_found' =>
        "We couldn't find this registration. Please refresh and try again.",
      'no_captured_payment' ||
      'refund_not_supported' ||
      'refund_mode_mismatch' =>
        "We couldn't cancel this registration automatically. Please contact "
            'support.',
      _ => generic,
    };
  }
}
