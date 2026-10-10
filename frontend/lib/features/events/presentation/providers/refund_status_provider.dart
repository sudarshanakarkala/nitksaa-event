import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/refund_status.dart';

/// What is known about the refund of one registration.
class RefundStatusState {
  const RefundStatusState({
    this.refund,
    this.isLoading = false,
    this.errorMessage,
  });

  /// The last answer from the backend. Null until there is one.
  final RefundStatus? refund;
  final bool isLoading;

  /// Why the last check failed, in words for the attendee. Null when it did
  /// not fail.
  final String? errorMessage;
}

class RefundStatusNotifier extends StateNotifier<RefundStatusState> {
  RefundStatusNotifier(this._repository, this._accessToken, this._registrationId)
      : super(const RefundStatusState());

  final EventsRepository _repository;

  /// Access token of the session this notifier was created for, or null when
  /// signed out. [refundStatusProvider] builds a new notifier whenever the
  /// session changes, so the refund held here only ever belongs to this one
  /// session.
  final String? _accessToken;
  final int _registrationId;

  /// Takes a refund status the app already has, such as the answer to the
  /// cancellation that started the refund. Nothing is sent.
  void show(RefundStatus refund) {
    if (!mounted) return;
    state = RefundStatusState(refund: refund);
  }

  /// Asks the backend once. For a refund that is still pending this is also
  /// what makes the backend ask the payment provider again.
  Future<void> check() async {
    final token = _accessToken;
    if (token == null || !mounted || state.isLoading) return;

    state = RefundStatusState(refund: state.refund, isLoading: true);
    try {
      final refund = await _repository.getRefundStatus(_registrationId, token);
      if (!mounted) return;
      state = RefundStatusState(refund: refund);
    } catch (error) {
      if (!mounted) return;
      state = RefundStatusState(
        refund: state.refund,
        errorMessage: refundStatusErrorMessage(error),
      );
    }
  }
}

/// The message to show when the refund status could not be loaded.
///
/// Only ever returns one of the fixed strings below: no exception text, HTTP
/// status or backend code reaches the attendee. This covers the refund status
/// only.
String refundStatusErrorMessage(Object error) {
  const generic = 'Could not load the refund status. Please try again.';
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
    'registration_not_found' =>
      "We couldn't find this registration. Please refresh and try again.",
    _ => generic,
  };
}

/// The refund of one registration, by registration id.
///
/// It fetches nothing by itself: whoever shows a refund calls
/// [RefundStatusNotifier.check] or [RefundStatusNotifier.show]. It is thrown
/// away when nothing shows it any more, so opening it again asks again.
final refundStatusProvider = StateNotifierProvider.autoDispose
    .family<RefundStatusNotifier, RefundStatusState, int>((ref, registrationId) {
  final repo = ref.watch(eventsRepositoryProvider);
  // A refund belongs to one signed-in session. Watching the session's token
  // rebuilds this provider on logout, login and user switch, discarding what
  // was fetched for the previous session.
  final accessToken = ref.watch(
    authControllerProvider.select(
      (auth) => auth.isAuthenticated ? auth.session?.accessToken : null,
    ),
  );
  return RefundStatusNotifier(repo, accessToken, registrationId);
});
