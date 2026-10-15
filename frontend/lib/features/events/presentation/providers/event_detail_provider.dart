import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_error_message.dart';
import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/event.dart';

const _kUnsetValue = Object();

/// What the registration form collected, handed to checkout inside the app
/// (never in the page address). [fullname] is null for alumni: the server
/// takes their name from the alumni record.
class RegistrationDraft {
  const RegistrationDraft({this.fullname, required this.phone, this.note = ''});

  final String? fullname;
  final String phone;
  final String note;
}

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
    this.registrationDraft,
    this.lastDetails,
  });

  final AppEvent? event;
  final bool isLoading;
  final String? errorMessage;
  final String? eligibilityStatus;
  final String? eligibilityMessage;
  final Map<String, dynamic>? myRegistration;
  final bool isRegistering;
  final Map<String, dynamic>? alumniProfile;
  final RegistrationDraft? registrationDraft;

  /// Name and phone from the person's newest earlier registration, to fill
  /// in the form. Null when signed out or never registered.
  final ({String? fullname, String phone})? lastDetails;

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
    dynamic registrationDraft = _kUnsetValue,
    dynamic lastDetails = _kUnsetValue,
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
      registrationDraft: identical(registrationDraft, _kUnsetValue)
          ? this.registrationDraft
          : registrationDraft as RegistrationDraft?,
      lastDetails: identical(lastDetails, _kUnsetValue)
          ? this.lastDetails
          : lastDetails as ({String? fullname, String phone})?,
    );
  }
}

class EventDetailNotifier extends StateNotifier<EventDetailState> {
  EventDetailNotifier(this._repository, this._accessToken, {this.canAdmin = false})
      : super(const EventDetailState(isLoading: true));

  final EventsRepository _repository;

  /// True when the signed-in person is an admin of this event. They get the
  /// full (admin) version, which includes the meeting link.
  final bool canAdmin;

  /// Access token of the session this notifier was created for, or null when
  /// signed out. [eventDetailProvider] builds a new notifier whenever the
  /// session changes, so the state held here only ever belongs to this one
  /// session.
  final String? _accessToken;

  Future<void> fetchEventDetails(int eventId) async {
    if (!mounted) return;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final event = await _loadEvent(eventId);
      if (!mounted) return;
      state = state.copyWith(event: event);

      // Not published (draft, cancelled…): only its admins get here, and
      // there is nothing to register for.
      if (event.status != 'published') {
        state = state.copyWith(isLoading: false);
        return;
      }

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

        // Name and phone from the last registration, for the form.
        ({String? fullname, String phone})? last;
        try {
          last = await _repository.getLastRegistrationDetails(token);
        } catch (_) {
          // No prefill then.
        }
        if (!mounted) return;
        state = state.copyWith(lastDetails: last);
      }

      state = state.copyWith(isLoading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: _isNotFound(e)
            ? notAvailableMessage
            : apiErrorMessage(e, action: 'load the event'),
      );
    }
  }

  /// Shown for an event that doesn't exist or isn't published (and you
  /// aren't one of its admins).
  static const notAvailableMessage =
      'This event isn\'t available. It may not be published yet, or it was '
      'removed.';

  static bool _isNotFound(Object e) =>
      e is DioException &&
      (e.response?.statusCode == 404 || e.response?.statusCode == 403);

  /// The public page only has published events. For anything else, the
  /// event's admins (and overall admins) get it through the admin API;
  /// everyone else gets the public API's 404.
  Future<AppEvent> _loadEvent(int eventId) async {
    final adminToken = _accessToken;
    if (canAdmin && adminToken != null) {
      try {
        return await _repository.getAdminEvent(eventId, adminToken);
      } catch (_) {
        // Fall back to the public version below.
      }
    }
    try {
      return await _repository.getPublicEvent(eventId);
    } on DioException catch (e) {
      final token = _accessToken;
      if (token == null || e.response?.statusCode != 404) rethrow;
      // A 403/404 here means it isn't theirs to see either.
      return _repository.getAdminEvent(eventId, token);
    }
  }

  /// Keeps what the registration form collected, for checkout.
  void setRegistrationDraft(RegistrationDraft draft) {
    if (!mounted) return;
    state = state.copyWith(registrationDraft: draft);
  }

  /// Registers with the form's draft. On failure, [EventDetailState.errorMessage]
  /// holds a plain-words message.
  Future<bool> register(int eventId) async {
    final token = _accessToken;
    if (token == null || !mounted) return false;
    final draft = state.registrationDraft;
    if (draft == null) return false;

    state = state.copyWith(isRegistering: true);
    try {
      final regResponse = await _repository.registerForEvent(
        eventId,
        token,
        attendeeNote: draft.note,
        fullname: draft.fullname,
        phone: draft.phone,
      );
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
        errorMessage: apiErrorMessage(e, action: 'register'),
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
  final canAdmin = ref.read(authControllerProvider).session?.access.canAdminEvent(eventId) ?? false;
  final notifier = EventDetailNotifier(repo, accessToken, canAdmin: canAdmin);
  // Auto fetch
  Future.microtask(() => notifier.fetchEventDetails(eventId));
  return notifier;
});
