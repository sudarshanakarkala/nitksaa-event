import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_widgets.dart';
import '../domain/public_event.dart';
import '../services/public_event_service.dart';

class EventListScreen extends StatefulWidget {
  const EventListScreen({super.key, this.eventService});

  final PublicEventService? eventService;

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen>
    with SingleTickerProviderStateMixin {
  late final PublicEventService _eventService;
  late final TabController _tabController;
  final Map<EventPeriod, _EventListState> _states = {
    for (final period in EventPeriod.values) period: const _EventListState(),
  };

  @override
  void initState() {
    super.initState();
    _eventService = widget.eventService ?? DioPublicEventService();
    _tabController = TabController(
      length: EventPeriod.values.length,
      vsync: this,
    )..addListener(_handleTabChange);
    _load(EventPeriod.upcoming);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChange)
      ..dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    final period = EventPeriod.values[_tabController.index];
    if (!_states[period]!.hasLoaded) _load(period);
  }

  Future<void> _load(EventPeriod period) async {
    if (_states[period]!.isLoading) return;
    setState(() {
      _states[period] = _states[period]!.copyWith(
        isLoading: true,
        clearError: true,
      );
    });

    try {
      final events = await _eventService.listEvents(period);
      if (!mounted) return;
      setState(() {
        _states[period] = _EventListState(events: events, hasLoaded: true);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _states[period] = _states[period]!.copyWith(
          isLoading: false,
          hasLoaded: true,
          errorMessage: _errorMessage(error),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Events',
      automaticallyImplyLeading: false,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Upcoming'),
                Tab(text: 'Past'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPeriodView(EventPeriod.upcoming),
                _buildPeriodView(EventPeriod.past),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodView(EventPeriod period) {
    final state = _states[period]!;
    if (state.isLoading && !state.hasLoaded) {
      return const AppLoadingView(
        title: 'Loading events',
        message: 'Finding published NITKSAA events.',
        icon: Icons.event_outlined,
      );
    }

    if (state.errorMessage != null) {
      return AppErrorView(
        title: 'Unable to load events',
        message: state.errorMessage!,
        action: AppPrimaryButton(
          label: 'Retry',
          icon: Icons.refresh_outlined,
          onPressed: () => _load(period),
        ),
      );
    }

    if (state.events.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(period),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.6,
              child: AppEmptyView(
                title: period == EventPeriod.upcoming
                    ? 'No upcoming events'
                    : 'No past events',
                message: 'Pull down to refresh.',
                icon: Icons.event_busy_outlined,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(period),
      child: ListView.separated(
        padding: const EdgeInsets.all(24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.events.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, index) => _EventCard(
          event: state.events[index],
          onTap: _showDetailPlaceholder,
        ),
      ),
    );
  }

  void _showDetailPlaceholder() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Event detail will be implemented in Phase 7.'),
        ),
      );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});

  final PublicEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final location = event.isVirtual
        ? 'Online'
        : event.locationText ?? 'Location to be announced';

    return Semantics(
      button: true,
      label: 'Open ${event.title}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(event.title, style: textTheme.titleLarge),
                  ),
                  const SizedBox(width: 12),
                  _Badge(
                    label: event.eventTypeLabel,
                    color: event.isVirtual
                        ? colorScheme.tertiary
                        : colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _InfoRow(
                icon: Icons.calendar_today_outlined,
                label: _formatDateRange(context, event),
              ),
              const SizedBox(height: 10),
              _InfoRow(
                icon: event.isVirtual
                    ? Icons.videocam_outlined
                    : Icons.location_on_outlined,
                label: location,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    icon: Icons.people_outline,
                    label: 'Capacity: ${event.capacityLabel}',
                  ),
                  _MetricChip(
                    icon: Icons.how_to_reg_outlined,
                    label: 'Registration: ${event.registrationStatusLabel}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateRange(BuildContext context, PublicEvent event) {
    final localizations = MaterialLocalizations.of(context);
    final start = event.startDateTime.toLocal();
    final end = event.endDateTime.toLocal();
    final startDate = localizations.formatMediumDate(start);
    final startTime = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(start),
    );
    final endTime = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(end));
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;

    if (sameDay) return '$startDate, $startTime - $endTime';
    return '$startDate, $startTime - '
        '${localizations.formatMediumDate(end)}, $endTime';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _EventListState {
  const _EventListState({
    this.events = const [],
    this.isLoading = false,
    this.hasLoaded = false,
    this.errorMessage,
  });

  final List<PublicEvent> events;
  final bool isLoading;
  final bool hasLoaded;
  final String? errorMessage;

  _EventListState copyWith({
    List<PublicEvent>? events,
    bool? isLoading,
    bool? hasLoaded,
    String? errorMessage,
    bool clearError = false,
  }) {
    return _EventListState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

String _errorMessage(Object error) {
  if (error is DioException) {
    if (error.response?.statusCode != null) {
      return 'The server returned ${error.response!.statusCode}. Please retry.';
    }
    return 'Check your connection and try again.';
  }
  if (error is FormatException) {
    return 'The server returned an unexpected response.';
  }
  return 'Something went wrong. Please try again.';
}
