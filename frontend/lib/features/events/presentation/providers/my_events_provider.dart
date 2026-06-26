import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/my_event_registration.dart';

class MyEventsState {
  const MyEventsState({
    required this.registrations,
    required this.isLoading,
    this.errorMessage,
    this.cancellingEventId,
  });

  final List<MyEventRegistration> registrations;
  final bool isLoading;
  final String? errorMessage;
  final int? cancellingEventId;

  MyEventsState copyWith({
    List<MyEventRegistration>? registrations,
    bool? isLoading,
    String? errorMessage,
    int? cancellingEventId,
  }) {
    return MyEventsState(
      registrations: registrations ?? this.registrations,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      cancellingEventId: cancellingEventId,
    );
  }
}

class MyEventsNotifier extends StateNotifier<MyEventsState> {
  MyEventsNotifier(this._repository, this._auth)
      : super(const MyEventsState(registrations: [], isLoading: false));

  final EventsRepository _repository;
  final AuthController _auth;

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

  Future<void> cancelRegistration(int eventId) async {
    final token = _auth.session?.accessToken;
    if (token == null) return;

    state = state.copyWith(cancellingEventId: eventId, errorMessage: null);
    try {
      await _repository.cancelMyRegistration(eventId, token);
      await fetchMyEvents();
    } catch (e) {
      state = state.copyWith(
        cancellingEventId: null,
        errorMessage: e.toString(),
      );
    }
  }
}

final myEventsProvider =
    StateNotifierProvider<MyEventsNotifier, MyEventsState>((ref) {
  return MyEventsNotifier(
    ref.watch(eventsRepositoryProvider),
    ref.watch(authControllerProvider),
  );
});
