import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_widgets.dart';
import '../../../routes/app_routes.dart';
import '../domain/registration.dart';

class ConfirmationScreen extends StatelessWidget {
  const ConfirmationScreen({super.key, required this.registration});

  final Registration registration;

  @override
  Widget build(BuildContext context) {
    final event = registration.event;
    return AppScaffold(
      title: 'Registration Confirmed',
      maxContentWidth: 720,
      padding: const EdgeInsets.all(24),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SuccessBanner(),
            const SizedBox(height: 16),
            _RegistrationCard(registration: registration),
            const SizedBox(height: 16),
            if (event != null) _EventCard(event: event, registration: registration),
            if (event != null) const SizedBox(height: 16),
            _EmailStatusCard(status: registration.confirmationEmailStatus),
            const SizedBox(height: 24),
            AppPrimaryButton(
              label: 'View My Registrations',
              icon: Icons.list_alt_outlined,
              onPressed: () => context.go(AppRoutes.myRegistrations),
            ),
            const SizedBox(height: 8),
            AppSecondaryButton(
              label: 'Back to Events',
              icon: Icons.event_outlined,
              onPressed: () => context.go(AppRoutes.events),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: Colors.green.withValues(alpha: 0.10),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: Colors.green.shade700,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'You\'re registered!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Your seat is confirmed. Check your email for confirmation.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Registration Details',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          if (registration.registrationNumber != null)
            _ConfirmRow(
              icon: Icons.confirmation_number_outlined,
              label: 'Registration No.',
              value: registration.registrationNumber!,
              highlight: true,
            ),
          _ConfirmRow(
            icon: Icons.person_outline,
            label: 'Name',
            value: registration.fullnameSnapshot ?? '—',
          ),
          _ConfirmRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: registration.emailSnapshot ?? '—',
            isLast: registration.joinUrl == null,
          ),
          if (registration.joinUrl != null)
            _ConfirmRow(
              icon: Icons.videocam_outlined,
              label: 'Join Link',
              value: registration.joinUrl!,
              isLast: true,
              isLink: true,
              linkColor: cs.primary,
            ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.registration});

  final RegistrationEventSummary event;
  final Registration registration;

  @override
  Widget build(BuildContext context) {
    final local = event.startDateTime.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final dateStr = localizations.formatMediumDate(local);
    final timeStr = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Event', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _ConfirmRow(
            icon: Icons.event_outlined,
            label: 'Title',
            value: event.title,
          ),
          _ConfirmRow(
            icon: Icons.calendar_today_outlined,
            label: 'Date',
            value: dateStr,
          ),
          _ConfirmRow(
            icon: Icons.schedule_outlined,
            label: 'Time',
            value: timeStr,
          ),
          _ConfirmRow(
            icon: event.isVirtual
                ? Icons.videocam_outlined
                : Icons.location_on_outlined,
            label: event.isVirtual ? 'Format' : 'Venue',
            value: event.isVirtual
                ? 'Online (join link above)'
                : event.locationText ?? 'Location to be announced',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _EmailStatusCard extends StatelessWidget {
  const _EmailStatusCard({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, icon, color) = switch (status) {
      'sent' => ('Confirmation email sent', Icons.mark_email_read_outlined, Colors.green.shade700),
      'failed' => ('Confirmation email failed to send', Icons.email_outlined, cs.error),
      'skipped' => ('Email notification skipped (log mode)', Icons.drafts_outlined, cs.onSurfaceVariant),
      _ => ('Email status unknown', Icons.help_outline, cs.onSurfaceVariant),
    };

    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
    this.isLast = false,
    this.isLink = false,
    this.linkColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlight;
  final bool isLast;
  final bool isLink;
  final Color? linkColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: highlight ? cs.primary : cs.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                    color: isLink ? linkColor : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
