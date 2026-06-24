import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_widgets.dart';
import '../../../routes/app_routes.dart';
import '../domain/registration.dart';
import '../services/registration_service.dart';

class MyRegistrationsScreen extends StatefulWidget {
  const MyRegistrationsScreen({super.key});

  @override
  State<MyRegistrationsScreen> createState() => _MyRegistrationsScreenState();
}

class _MyRegistrationsScreenState extends State<MyRegistrationsScreen> {
  final RegistrationService _service = RegistrationService();

  bool _loading = true;
  List<Registration> _registrations = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final regs = await _service.getMyRegistrations();
      if (!mounted) return;
      setState(() {
        _registrations = regs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = registrationErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'My Registrations',
      padding: EdgeInsets.zero,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const AppLoadingView(
        title: 'Loading registrations',
        message: 'Fetching your event registrations.',
        icon: Icons.list_alt_outlined,
      );
    }

    if (_error != null) {
      return AppErrorView(
        title: 'Unable to load registrations',
        message: _error!,
        action: AppPrimaryButton(
          label: 'Retry',
          icon: Icons.refresh_outlined,
          onPressed: _load,
        ),
      );
    }

    if (_registrations.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 400,
              child: AppEmptyView(
                title: 'No registrations yet',
                message: 'Register for an event to see it here.',
                icon: Icons.event_busy_outlined,
                action: AppSecondaryButton(
                  label: 'Browse Events',
                  icon: Icons.search_outlined,
                  onPressed: () => context.go(AppRoutes.events),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _registrations.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) =>
            _RegistrationCard(registration: _registrations[index]),
      ),
    );
  }
}

class _RegistrationCard extends StatelessWidget {
  const _RegistrationCard({required this.registration});

  final Registration registration;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final event = registration.event;
    final isVirtual = event?.isVirtual ?? false;
    final showJoinLink = registration.isActive &&
        isVirtual &&
        registration.joinUrl != null;

    final (statusColor, statusBg, statusLabel) = switch (registration.status) {
      'registered' => (
          Colors.green.shade700,
          Colors.green.withValues(alpha: 0.10),
          'Registered',
        ),
      'cancelled' => (
          cs.onErrorContainer,
          cs.errorContainer,
          'Cancelled',
        ),
      _ => (
          cs.onSurfaceVariant,
          cs.surfaceContainerHighest,
          registration.status,
        ),
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event?.title ?? 'Event #${registration.eventId}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (registration.registrationNumber != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        registration.registrationNumber!,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontFamily: 'monospace',
                                ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          if (event != null) ...[
            const SizedBox(height: 12),
            _EventInfoRow(event: event),
          ],
          if (showJoinLink) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.videocam_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(
                    registration.joinUrl!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.primary,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EventInfoRow extends StatelessWidget {
  const _EventInfoRow({required this.event});

  final RegistrationEventSummary event;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final local = event.startDateTime.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final dateStr = localizations.formatMediumDate(local);
    final timeStr =
        localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local));

    return Column(
      children: [
        Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              '$dateStr at $timeStr',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              event.isVirtual
                  ? Icons.videocam_outlined
                  : Icons.location_on_outlined,
              size: 14,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                event.isVirtual
                    ? 'Online'
                    : event.locationText ?? 'Location to be announced',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
