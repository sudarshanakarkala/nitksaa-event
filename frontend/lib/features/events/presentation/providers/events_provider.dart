import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/events_repository.dart';
import '../../domain/event.dart';

const _kUnsetValue = Object();

class EventsState {
  const EventsState({
    required this.events,
    required this.total,
    required this.page,
    required this.perPage,
    required this.period,
    required this.searchQuery,
    required this.isLoading,
    this.errorMessage,
    this.dateRangeStart,
    this.dateRangeEnd,
    this.filterModes = const {'physical': true, 'virtual': true},
    this.filterRegistrationStatus = const {'open': true, 'closed': true},
  });

  final List<AppEvent> events;
  final int total;
  final int page;
  final int perPage;
  final String period; // 'upcoming' or 'past'
  final String searchQuery;
  final bool isLoading;
  final String? errorMessage;
  final DateTime? dateRangeStart;
  final DateTime? dateRangeEnd;
  final Map<String, bool> filterModes; // {'physical': bool, 'virtual': bool}
  final Map<String, bool> filterRegistrationStatus; // {'open': bool, 'closed': bool}

  EventsState copyWith({
    List<AppEvent>? events,
    int? total,
    int? page,
    int? perPage,
    String? period,
    String? searchQuery,
    bool? isLoading,
    String? errorMessage,
    dynamic dateRangeStart = _kUnsetValue,
    dynamic dateRangeEnd = _kUnsetValue,
    Map<String, bool>? filterModes,
    Map<String, bool>? filterRegistrationStatus,
  }) {
    return EventsState(
      events: events ?? this.events,
      total: total ?? this.total,
      page: page ?? this.page,
      perPage: perPage ?? this.perPage,
      period: period ?? this.period,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      dateRangeStart: identical(dateRangeStart, _kUnsetValue) ? this.dateRangeStart : dateRangeStart as DateTime?,
      dateRangeEnd: identical(dateRangeEnd, _kUnsetValue) ? this.dateRangeEnd : dateRangeEnd as DateTime?,
      filterModes: filterModes ?? this.filterModes,
      filterRegistrationStatus: filterRegistrationStatus ?? this.filterRegistrationStatus,
    );
  }
}

class EventsNotifier extends StateNotifier<EventsState> {
  EventsNotifier(this._repository)
      : super(const EventsState(
          events: [],
          total: 0,
          page: 1,
          perPage: 100, // retrieve a good page size for public events list
          period: 'upcoming',
          searchQuery: '',
          isLoading: false,
        )) {
    fetchEvents();
  }

  final EventsRepository _repository;

  Future<void> fetchEvents({bool isRefresh = false}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final data = await _repository.getPublicEvents(
        page: isRefresh ? 1 : state.page,
        perPage: state.perPage,
        period: state.period,
      );

      final rawEvents = data['events'] as List<dynamic>? ?? [];
      final parsedEvents = rawEvents
          .map((json) => AppEvent.fromJson(json as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        events: parsedEvents,
        total: data['total'] as int? ?? 0,
        page: isRefresh ? 1 : state.page,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  void setPeriod(String period) {
    if (state.period == period) return;
    state = state.copyWith(period: period, page: 1);
    fetchEvents(isRefresh: true);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setDateRangeStart(DateTime? date) {
    state = state.copyWith(dateRangeStart: date);
  }

  void setDateRangeEnd(DateTime? date) {
    state = state.copyWith(dateRangeEnd: date);
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

  void clearFilters() {
    state = state.copyWith(
      dateRangeStart: null,
      dateRangeEnd: null,
      filterModes: const {'physical': true, 'virtual': true},
      filterRegistrationStatus: const {'open': true, 'closed': true},
      searchQuery: '',
    );
  }
}

final eventsProvider = StateNotifierProvider<EventsNotifier, EventsState>((ref) {
  final repo = ref.watch(eventsRepositoryProvider);
  return EventsNotifier(repo);
});

final filteredEventsProvider = Provider<List<AppEvent>>((ref) {
  final state = ref.watch(eventsProvider);
  
  var filtered = state.events;

  // Apply search filter
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

  // Apply date range filter
  if (state.dateRangeStart != null || state.dateRangeEnd != null) {
    filtered = filtered.where((event) {
      final eventDate = event.startDatetime;
      
      if (state.dateRangeStart != null && eventDate.isBefore(state.dateRangeStart!)) {
        return false;
      }
      
      if (state.dateRangeEnd != null) {
        final endOfDay = state.dateRangeEnd!.add(const Duration(days: 1));
        if (eventDate.isAfter(endOfDay)) {
          return false;
        }
      }
      
      return true;
    }).toList();
  }

  // Apply mode filter (Physical/Virtual)
  final hasPhysical = state.filterModes?['physical'] ?? true;
  final hasVirtual = state.filterModes?['virtual'] ?? true;
  
  if (!(hasPhysical && hasVirtual)) {
    filtered = filtered.where((event) {
      if (hasPhysical && !event.isVirtual) return true;
      if (hasVirtual && event.isVirtual) return true;
      return false;
    }).toList();
  }

  // Apply registration status filter
  final hasOpen = state.filterRegistrationStatus?['open'] ?? true;
  final hasClosed = state.filterRegistrationStatus?['closed'] ?? true;
  
  if (!(hasOpen && hasClosed)) {
    filtered = filtered.where((event) {
      if (hasOpen && event.registrationStatus == 'open') return true;
      if (hasClosed && event.registrationStatus != 'open') return true;
      return false;
    }).toList();
  }

  return filtered;
});
