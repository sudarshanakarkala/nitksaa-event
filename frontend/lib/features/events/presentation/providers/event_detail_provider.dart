import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/event.dart';

const _kUnsetValue = Object();

class EventDetailState {
  const EventDetailState({
    this.event,
    this.isLoading = false,
    this.errorMessage,
    this.eligibilityStatus,
    this.eligibilityMessage,
    this.myRegistration,
    this.isRegistering = false,
    this.alumniProfile,
  });

  final AppEvent? event;
  final bool isLoading;
  final String? errorMessage;
  final String? eligibilityStatus;
  final String? eligibilityMessage;
  final Map<String, dynamic>? myRegistration;
  final bool isRegistering;
  final Map<String, dynamic>? alumniProfile;

  // The user-scoped fields take a sentinel default so that passing null clears
  // them; omitting the argument keeps the current value.
  EventDetailState copyWith({
    AppEvent? event,
    bool? isLoading,
    String? errorMessage,
    dynamic eligibilityStatus = _kUnsetValue,
    dynamic eligibilityMessage = _kUnsetValue,
    dynamic myRegistration = _kUnsetValue,
    bool? isRegistering,
    dynamic alumniProfile = _kUnsetValue,
  }) {
    return EventDetailState(
      event: event ?? this.event,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      eligibilityStatus: identical(eligibilityStatus, _kUnsetValue) ? this.eligibilityStatus : eligibilityStatus as String?,
      eligibilityMessage: identical(eligibilityMessage, _kUnsetValue) ? this.eligibilityMessage : eligibilityMessage as String?,
      myRegistration: identical(myRegistration, _kUnsetValue) ? this.myRegistration : myRegistration as Map<String, dynamic>?,
      isRegistering: isRegistering ?? this.isRegistering,
      alumniProfile: identical(alumniProfile, _kUnsetValue) ? this.alumniProfile : alumniProfile as Map<String, dynamic>?,
    );
  }
}

class EventDetailNotifier extends StateNotifier<EventDetailState> {
  EventDetailNotifier(this._repository, this._accessToken)
      : super(const EventDetailState(isLoading: true));

  final EventsRepository _repository;

  /// Access token of the session this notifier was created for, or null when
  /// signed out. [eventDetailProvider] builds a new notifier whenever the
  /// session changes, so the state held here only ever belongs to this one
  /// session.
  final String? _accessToken;

  Future<void> fetchEventDetails(int eventId) async {
    if (!mounted) return;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final event = await _repository.getPublicEvent(eventId);
      if (!mounted) return;
      state = state.copyWith(event: event);

      // Check auth for registration details
      final token = _accessToken;
      if (token != null) {
        // Each result below replaces the field outright, so an empty result or
        // a failed call clears it instead of leaving the previous value.

        // Fetch eligibility
        Map<String, dynamic>? elig;
        try {
          elig = await _repository.getRegistrationEligibility(eventId, token);
        } catch (_) {
          // If eligibility fails, fallback
        }
        if (!mounted) return;
        state = state.copyWith(
          eligibilityStatus: elig?['eligibility_status']?.toString(),
          eligibilityMessage: elig?['message']?.toString(),
        );

        // Fetch my registration
        Map<String, dynamic>? reg;
        try {
          reg = await _repository.getMyEventRegistration(eventId, token);
        } catch (_) {
          // If registration fails, fallback
        }
        if (!mounted) return;
        state = state.copyWith(myRegistration: reg);

        // Fetch alumni profile details
        Map<String, dynamic>? profile;
        try {
          profile = await _repository.getAlumniProfile(token);
        } catch (_) {
          // If profile fails, fallback
        }
        if (!mounted) return;
        state = state.copyWith(alumniProfile: profile);
      }

      state = state.copyWith(isLoading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<bool> register(int eventId, String attendeeNote, {int? quantity}) async {
    final token = _accessToken;
    if (token == null || !mounted) {
      return false;
    }

    state = state.copyWith(isRegistering: true);
    try {
      final regResponse = await _repository.registerForEvent(eventId, token, attendeeNote, quantity: quantity);
      if (!mounted) return false;
      state = state.copyWith(
        isRegistering: false,
        myRegistration: regResponse,
        eligibilityStatus: 'already_registered',
        eligibilityMessage: 'You are registered for this event.',
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        isRegistering: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }
}

final eventDetailProvider = StateNotifierProvider.autoDispose.family<EventDetailNotifier, EventDetailState, int>((ref, eventId) {
  final repo = ref.watch(eventsRepositoryProvider);
  // Eligibility, registration and profile belong to one signed-in session.
  // Watching the session's token rebuilds this provider on logout, login and
  // user switch, discarding everything fetched for the previous session.
  final accessToken = ref.watch(
    authControllerProvider.select(
      (auth) => auth.isAuthenticated ? auth.session?.accessToken : null,
    ),
  );
  final notifier = EventDetailNotifier(repo, accessToken);
  // Auto fetch
  Future.microtask(() => notifier.fetchEventDetails(eventId));
  return notifier;
});
