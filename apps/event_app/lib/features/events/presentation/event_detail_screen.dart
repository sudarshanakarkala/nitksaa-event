import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_widgets.dart';
import '../../../routes/app_routes.dart';
import '../../auth/services/auth_controller.dart';
import '../domain/public_event_detail.dart';
import '../services/public_event_detail_service.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.eventId,
    this.eventService,
    this.isAuthenticated,
    this.onLoginRequired,
  });

  final int eventId;
  final PublicEventDetailService? eventService;
  final bool Function()? isAuthenticated;
  final VoidCallback? onLoginRequired;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  late final PublicEventDetailService _eventService;
  PublicEventDetail? _event;
  bool _isLoading = true;
  bool _notFound = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _eventService = widget.eventService ?? DioPublicEventDetailService();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _notFound = false;
      _errorMessage = null;
    });

    try {
      final event = await _eventService.getEvent(widget.eventId);
      if (!mounted) return;
      setState(() {
        _event = event;
        _isLoading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 404) {
        setState(() {
          _isLoading = false;
          _notFound = true;
        });
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = error.response?.statusCode == null
            ? 'Check your connection and try again.'
            : 'The server returned ${error.response!.statusCode}. Please retry.';
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'The server returned an unexpected response.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  void _register() {
    final authenticated =
        widget.isAuthenticated?.call() ??
        AuthController.instance.isAuthenticated;
    if (!authenticated) {
      if (widget.onLoginRequired != null) {
        widget.onLoginRequired!();
      } else {
        context.go(AppRoutes.login);
      }
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Registration will be available in Week 3.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Event Details',
      maxContentWidth: 900,
      padding: const EdgeInsets.all(24),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const AppLoadingView(
        title: 'Loading event',
        message: 'Fetching published event details.',
        icon: Icons.event_note_outlined,
      );
    }

    if (_notFound) {
      return AppEmptyView(
        title: 'Event not found',
        message: 'This event is unavailable or no longer published.',
        icon: Icons.event_busy_outlined,
        action: AppSecondaryButton(
          label: 'Back to Events',
          icon: Icons.arrow_back,
          onPressed: () => context.go(AppRoutes.events),
        ),
      );
    }

    if (_errorMessage != null) {
      return AppErrorView(
        title: 'Unable to load event',
        message: _errorMessage!,
        action: AppPrimaryButton(
          label: 'Retry',
          icon: Icons.refresh_outlined,
          onPressed: _load,
        ),
      );
    }

    final event = _event;
    if (event == null) {
      return const AppEmptyView(
        title: 'Event unavailable',
        message: 'No event details were returned.',
        icon: Icons.event_busy_outlined,
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EventSummaryCard(event: event),
          const SizedBox(height: 16),
          _EventInformationCard(event: event),
          const SizedBox(height: 16),
          _SpeakersCard(speakers: event.speakers),
          const SizedBox(height: 24),
          AppPrimaryButton(
            label: 'Register',
            icon: Icons.how_to_reg_outlined,
            onPressed: _register,
          ),
        ],
      ),
    );
  }
}

class _EventSummaryCard extends StatelessWidget {
  const _EventSummaryCard({required this.event});

  final PublicEventDetail event;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(event.title, style: textTheme.headlineSmall),
              ),
              const SizedBox(width: 12),
              _DetailBadge(
                label: event.eventTypeLabel,
                color: event.isVirtual
                    ? colorScheme.tertiary
                    : colorScheme.primary,
              ),
            ],
          ),
          if (event.tagline != null) ...[
            const SizedBox(height: 8),
            Text(
              event.tagline!,
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            event.description ?? 'Event description will be added soon.',
            style: textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _EventInformationCard extends StatelessWidget {
  const _EventInformationCard({required this.event});

  final PublicEventDetail event;

  @override
  Widget build(BuildContext context) {
    final start = event.startDateTime.toLocal();
    final end = event.endDateTime.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final startDate = localizations.formatMediumDate(start);
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    final date = sameDay
        ? startDate
        : '$startDate - ${localizations.formatMediumDate(end)}';
    final startTime = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(start),
    );
    final endTime = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(end));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Event Information',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 18),
          _DetailRow(
            icon: Icons.calendar_today_outlined,
            label: 'Date',
            value: date,
          ),
          _DetailRow(
            icon: Icons.schedule_outlined,
            label: 'Start Time',
            value: startTime,
          ),
          _DetailRow(icon: Icons.schedule, label: 'End Time', value: endTime),
          _DetailRow(
            icon: Icons.public_outlined,
            label: 'Timezone',
            value: event.timezone,
          ),
          _DetailRow(
            icon: event.isVirtual
                ? Icons.videocam_outlined
                : Icons.location_on_outlined,
            label: event.isVirtual ? 'Location' : 'Venue',
            value: event.isVirtual
                ? 'Online'
                : event.locationText ?? 'Location to be announced',
          ),
          _DetailRow(
            icon: Icons.people_outline,
            label: 'Capacity',
            value: event.capacityLimitLabel,
          ),
          _DetailRow(
            icon: Icons.groups_outlined,
            label: 'Registered Count',
            value: event.registeredCount.toString(),
          ),
          _DetailRow(
            icon: Icons.how_to_reg_outlined,
            label: 'Registration Status',
            value: event.registrationStatusLabel,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _SpeakersCard extends StatelessWidget {
  const _SpeakersCard({required this.speakers});

  final List<PublicEventSpeaker> speakers;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Speakers', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          if (speakers.isEmpty)
            Text(
              'Speakers will be announced soon.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final speaker in speakers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const CircleAvatar(child: Icon(Icons.person_outline)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            speaker.name,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          if (speaker.title != null)
                            Text(
                              speaker.title!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

class _DetailBadge extends StatelessWidget {
  const _DetailBadge({required this.label, required this.color});

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
