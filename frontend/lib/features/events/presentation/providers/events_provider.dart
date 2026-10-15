import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_error_message.dart';
import '../../data/events_repository.dart';
import '../../domain/event.dart';

/// The Events page's list: every published event, upcoming and past, loaded
/// once, with the search and the Filters rail (mode, registration, price).
/// The pills, dates and order live on the page, as on Admin → Events.
class EventsState {
  const EventsState({
    required this.events,
    required this.searchQuery,
    required this.isLoading,
    this.errorMessage,
    this.filterModes = const {'physical': true, 'virtual': true},
    this.filterRegistrationStatus = const {'open': true, 'closed': true},
    this.filterPrice = const {'free': true, 'paid': true},
  });

  final List<AppEvent> events;
  final String searchQuery;
  final bool isLoading;
  final String? errorMessage;
  final Map<String, bool> filterModes; // {'physical': bool, 'virtual': bool}
  final Map<String, bool> filterRegistrationStatus; // {'open': bool, 'closed': bool}
  final Map<String, bool> filterPrice; // {'free': bool, 'paid': bool}

  EventsState copyWith({
    List<AppEvent>? events,
    String? searchQuery,
    bool? isLoading,
    String? errorMessage,
    Map<String, bool>? filterModes,
    Map<String, bool>? filterRegistrationStatus,
    Map<String, bool>? filterPrice,
  }) {
    return EventsState(
      events: events ?? this.events,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      filterModes: filterModes ?? this.filterModes,
      filterRegistrationStatus: filterRegistrationStatus ?? this.filterRegistrationStatus,
      filterPrice: filterPrice ?? this.filterPrice,
    );
  }
}

class EventsNotifier extends StateNotifier<EventsState> {
  EventsNotifier(this._repository)
      : super(const EventsState(events: [], searchQuery: '', isLoading: false)) {
    fetchEvents();
  }

  final EventsRepository _repository;

  /// Every published event, upcoming and past ([isRefresh] is kept for the
  /// callers that reload after an admin change; it always reloads all).
  Future<void> fetchEvents({bool isRefresh = false}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final events = await _repository.getAllPublicEvents();
      state = state.copyWith(events: events, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: apiErrorMessage(e, action: 'load events'),
      );
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void toggleFilterMode(String mode) {
    final updated = Map<String, bool>.from(state.filterModes);
    updated[mode] = !(updated[mode] ?? true);
    state = state.copyWith(filterModes: updated);
  }

  void toggleFilterRegistrationStatus(String status) {
    final updated = Map<String, bool>.from(state.filterRegistrationStatus);
    updated[status] = !(updated[status] ?? true);
    state = state.copyWith(filterRegistrationStatus: updated);
  }

  void toggleFilterPrice(String price) {
    final updated = Map<String, bool>.from(state.filterPrice);
    updated[price] = !(updated[price] ?? true);
    state = state.copyWith(filterPrice: updated);
  }

  void clearFilters() {
    state = state.copyWith(
      filterModes: const {'physical': true, 'virtual': true},
      filterRegistrationStatus: const {'open': true, 'closed': true},
      filterPrice: const {'free': true, 'paid': true},
      searchQuery: '',
    );
  }
}

final eventsProvider = StateNotifierProvider<EventsNotifier, EventsState>((ref) {
  final repo = ref.watch(eventsRepositoryProvider);
  return EventsNotifier(repo);
});

/// The events after the search and the Filters rail; the page's pills and
/// date line apply on top.
final filteredEventsProvider = Provider<List<AppEvent>>((ref) {
  final state = ref.watch(eventsProvider);

  var filtered = state.events;

  if (state.searchQuery.isNotEmpty) {
    final query = state.searchQuery.toLowerCase();
    filtered = filtered.where((event) {
      final titleMatch = event.title.toLowerCase().contains(query);
      final descMatch = event.description?.toLowerCase().contains(query) ?? false;
      final taglineMatch = event.tagline?.toLowerCase().contains(query) ?? false;
      final locationMatch = event.locationText?.toLowerCase().contains(query) ?? false;
      return titleMatch || descMatch || taglineMatch || locationMatch;
    }).toList();
  }

  // Mode (Physical / Virtual).
  final hasPhysical = state.filterModes['physical'] ?? true;
  final hasVirtual = state.filterModes['virtual'] ?? true;
  if (!(hasPhysical && hasVirtual)) {
    filtered = filtered.where((event) => event.isVirtual ? hasVirtual : hasPhysical).toList();
  }

  // Registration status.
  final hasOpen = state.filterRegistrationStatus['open'] ?? true;
  final hasClosed = state.filterRegistrationStatus['closed'] ?? true;
  if (!(hasOpen && hasClosed)) {
    filtered = filtered
        .where((event) => event.registrationStatus == 'open' ? hasOpen : hasClosed)
        .toList();
  }

  // Price (Free / Paid).
  final hasFree = state.filterPrice['free'] ?? true;
  final hasPaid = state.filterPrice['paid'] ?? true;
  if (!(hasFree && hasPaid)) {
    filtered = filtered.where((event) => event.isPaid ? hasPaid : hasFree).toList();
  }

  return filtered;
});
