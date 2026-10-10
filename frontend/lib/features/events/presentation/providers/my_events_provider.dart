import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/my_event_registration.dart';
import '../../domain/refund_status.dart';
import 'cancellation_outcome.dart';

class MyEventsState {
  const MyEventsState({
    required this.registrations,
    required this.isLoading,
    this.errorMessage,
    this.cancellingRegistrationIds = const {},
  });

  final List<MyEventRegistration> registrations;
  final bool isLoading;
  final String? errorMessage;

  /// Registrations with a cancel request in flight. Keyed by registration,
  /// not by event: an event can have several registrations of the same user.
  final Set<int> cancellingRegistrationIds;

  bool isCancelling(int registrationId) =>
      cancellingRegistrationIds.contains(registrationId);

  MyEventsState copyWith({
    List<MyEventRegistration>? registrations,
    bool? isLoading,
    String? errorMessage,
    Set<int>? cancellingRegistrationIds,
  }) {
    return MyEventsState(
      registrations: registrations ?? this.registrations,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      cancellingRegistrationIds:
          cancellingRegistrationIds ?? this.cancellingRegistrationIds,
    );
  }
}

class MyEventsNotifier extends StateNotifier<MyEventsState> {
  MyEventsNotifier(this._repository, this._auth)
      : super(const MyEventsState(registrations: [], isLoading: false));

  final EventsRepository _repository;
  final AuthController _auth;

  /// Idempotency key of the cancellation still open for a registration.
  final Map<int, String> _cancelKeys = {};

  Future<void> fetchMyEvents() async {
    final token = _auth.session?.accessToken;
    if (!_auth.isAuthenticated || token == null) {
      state = state.copyWith(
        registrations: [],
        isLoading: false,
        errorMessage: 'Please log in to view your registered events.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final registrations = await _repository.getMyRegistrations(token);
      state = state.copyWith(
        registrations: registrations,
        isLoading: false,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// Cancels one of the attendee's registrations, then reloads the list.
  ///
  /// Call it once the attendee has confirmed. The result carries the message
  /// to show; a failure leaves the list and [MyEventsState.errorMessage] as
  /// they were.
  Future<CancellationOutcome> cancelRegistration(int registrationId) async {
    final token = _auth.session?.accessToken;
    if (token == null) return CancellationOutcome.failed(null);

    // One key per user action. It is made on the first attempt and kept until
    // the backend answers, so a retry after a lost response repeats the same
    // cancellation instead of starting a second one (and a second refund).
    final key = _cancelKeys.putIfAbsent(
      registrationId,
      () => 'cancel-$registrationId-${DateTime.now().millisecondsSinceEpoch}',
    );
    _setCancelling(registrationId, true);
    final RefundStatus refund;
    try {
      refund = await _repository.cancelRegistration(
        registrationId,
        token,
        idempotencyKey: key,
      );
    } catch (error) {
      if (CancellationOutcome.isRefusal(error)) {
        _cancelKeys.remove(registrationId);
      }
      _setCancelling(registrationId, false);
      return CancellationOutcome.failed(error);
    }

    // Cancelled from here on, whatever happens to the reload.
    _cancelKeys.remove(registrationId);
    try {
      if (mounted) await fetchMyEvents();
    } finally {
      _setCancelling(registrationId, false);
    }
    return CancellationOutcome.cancelled(refund);
  }

  void _setCancelling(int registrationId, bool cancelling) {
    if (!mounted) return;
    final ids = {...state.cancellingRegistrationIds};
    if (cancelling) {
      ids.add(registrationId);
    } else {
      ids.remove(registrationId);
    }
    state = state.copyWith(
      errorMessage: state.errorMessage,
      cancellingRegistrationIds: ids,
    );
  }
}

final myEventsProvider =
    StateNotifierProvider<MyEventsNotifier, MyEventsState>((ref) {
  return MyEventsNotifier(
    ref.watch(eventsRepositoryProvider),
    ref.watch(authControllerProvider),
  );
});
