import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/event.dart';

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

  EventDetailState copyWith({
    AppEvent? event,
    bool? isLoading,
    String? errorMessage,
    String? eligibilityStatus,
    String? eligibilityMessage,
    Map<String, dynamic>? myRegistration,
    bool? isRegistering,
    Map<String, dynamic>? alumniProfile,
    bool clearRegistration = false,
  }) {
    return EventDetailState(
      event: event ?? this.event,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      eligibilityStatus: eligibilityStatus ?? this.eligibilityStatus,
      eligibilityMessage: eligibilityMessage ?? this.eligibilityMessage,
      myRegistration: clearRegistration ? null : (myRegistration ?? this.myRegistration),
      isRegistering: isRegistering ?? this.isRegistering,
      alumniProfile: alumniProfile ?? this.alumniProfile,
    );
  }
}

class EventDetailNotifier extends StateNotifier<EventDetailState> {
  EventDetailNotifier(this._repository, this._ref) : super(const EventDetailState());

  final EventsRepository _repository;
  final Ref _ref;

  Future<void> fetchEventDetails(int eventId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final event = await _repository.getPublicEvent(eventId);
      state = state.copyWith(event: event);

      // Check auth for registration details
      final auth = _ref.read(authControllerProvider);
      if (auth.isAuthenticated && auth.session?.accessToken != null) {
        final token = auth.session!.accessToken;
        
        // Fetch eligibility
        try {
          final elig = await _repository.getRegistrationEligibility(eventId, token);
          state = state.copyWith(
            eligibilityStatus: elig['eligibility_status']?.toString(),
            eligibilityMessage: elig['message']?.toString(),
          );
        } catch (_) {
          // If eligibility fails, fallback
        }

        // Fetch my registration
        try {
          final reg = await _repository.getMyEventRegistration(eventId, token);
          state = state.copyWith(myRegistration: reg);
        } catch (_) {
          // If registration fails, fallback
        }

        // Fetch alumni profile details
        try {
          final profile = await _repository.getAlumniProfile(token);
          state = state.copyWith(alumniProfile: profile);
        } catch (_) {
          // If profile fails, fallback
        }
      }
      
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<bool> register(int eventId, String attendeeNote) async {
    final auth = _ref.read(authControllerProvider);
    if (!auth.isAuthenticated || auth.session?.accessToken == null) {
      return false;
    }
    final token = auth.session!.accessToken;

    state = state.copyWith(isRegistering: true);
    try {
      final regResponse = await _repository.registerForEvent(eventId, token, attendeeNote);
      state = state.copyWith(
        isRegistering: false,
        myRegistration: regResponse,
        eligibilityStatus: 'already_registered',
        eligibilityMessage: 'You are registered for this event.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isRegistering: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }
}

final eventDetailProvider = StateNotifierProvider.family<EventDetailNotifier, EventDetailState, int>((ref, eventId) {
  final repo = ref.watch(eventsRepositoryProvider);
  final notifier = EventDetailNotifier(repo, ref);
  // Auto fetch
  Future.microtask(() => notifier.fetchEventDetails(eventId));
  return notifier;
});
