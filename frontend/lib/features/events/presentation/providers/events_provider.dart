import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/events_repository.dart';
import '../../domain/event.dart';

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
  });

  final List<AppEvent> events;
  final int total;
  final int page;
  final int perPage;
  final String period; // 'upcoming' or 'past'
  final String searchQuery;
  final bool isLoading;
  final String? errorMessage;

  EventsState copyWith({
    List<AppEvent>? events,
    int? total,
    int? page,
    int? perPage,
    String? period,
    String? searchQuery,
    bool? isLoading,
    String? errorMessage,
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
}

final eventsProvider = StateNotifierProvider<EventsNotifier, EventsState>((ref) {
  final repo = ref.watch(eventsRepositoryProvider);
  return EventsNotifier(repo);
});

final filteredEventsProvider = Provider<List<AppEvent>>((ref) {
  final state = ref.watch(eventsProvider);
  if (state.searchQuery.isEmpty) {
    return state.events;
  }
  final query = state.searchQuery.toLowerCase();
  return state.events.where((event) {
    final titleMatch = event.title.toLowerCase().contains(query);
    final descMatch = event.description?.toLowerCase().contains(query) ?? false;
    final taglineMatch = event.tagline?.toLowerCase().contains(query) ?? false;
    final locationMatch = event.locationText?.toLowerCase().contains(query) ?? false;
    return titleMatch || descMatch || taglineMatch || locationMatch;
  }).toList();
});
