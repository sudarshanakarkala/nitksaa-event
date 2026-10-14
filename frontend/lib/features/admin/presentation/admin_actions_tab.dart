import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_error_message.dart';
import '../../../shared/widgets/list_page.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/domain/admin_access.dart';
import '../../auth/services/auth_controller.dart';
import '../data/actions_api.dart';
import '../domain/registration_filters.dart' show formatDate, formatDateTime;
import '../../../shared/widgets/state_message.dart';

/// Admin → Actions (the default tab): what needs attention, website
/// "Needs attention" pattern. Each row is a queue with a count and
/// **Review →**, which opens the right tab with its filters applied.
///
/// The first rows need someone to act and make up the Admin badge. The
/// last two (closing soon, nearly full) are for information and don't
/// count toward it. Queues tied to particular events list them, each a
/// link of its own.
class AdminActionsTab extends ConsumerStatefulWidget {
  const AdminActionsTab({super.key});

  @override
  ConsumerState<AdminActionsTab> createState() => _AdminActionsTabState();
}

class _AdminActionsTabState extends ConsumerState<AdminActionsTab> {
  @override
  void initState() {
    super.initState();
    // Fresh numbers whenever the tab opens.
    Future.microtask(() {
      if (mounted) ref.invalidate(pendingCountProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingCountProvider);
    final access = ref.watch(authControllerProvider).session?.access ?? AdminAccess.none;
    final counts = pending.valueOrNull;

    return ListPage(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pending.isLoading && counts != null) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: counts != null
                ? _list(counts, access)
                : pending.hasError
                ? StateMessage(
                    icon: Icons.error_outline,
                    title: 'Couldn\'t load the actions',
                    body: apiErrorMessage(pending.error!, action: 'load the actions'),
                    action: TextButton(
                      onPressed: () => ref.invalidate(pendingCountProvider),
                      child: const Text('Try again'),
                    ),
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }

  Widget _list(PendingCounts c, AdminAccess access) {
    final queues = _queues(c, access);
    final allClear = queues.every((q) => q.count == 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = ListPage.contentPadding(context, constraints.maxWidth);
        if (allClear) return const _AllClear();
        final needsAction = queues.where((q) => q.needsAction).toList();
        final info = queues.where((q) => !q.needsAction).toList();
        return ListView(
          padding: padding,
          children: [
            for (final q in needsAction) ...[
              _QueueRow(queue: q),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 14),
            const _SectionLabel('For your information'),
            const SizedBox(height: 10),
            for (final q in info) ...[
              _QueueRow(queue: q),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  List<_Queue> _queues(PendingCounts c, AdminAccess access) => [
        _Queue(
          title: 'Drafts not published',
          description: 'Events still in draft. Publish them, move them to a new date, or delete them.',
          count: c.drafts,
          needsAction: true,
          review: '/admin/events?filter=draft',
        ),
        _Queue(
          title: 'Confirmation emails failed',
          description: 'People registered for upcoming events whose confirmation email didn\'t send.',
          count: c.failedEmails,
          needsAction: true,
          review: '/admin/registrations?email=failed',
          events: [
            for (final e in c.failedEmailEvents)
              _QueueEvent(
                title: e.title,
                detail: '${formatDate(e.start)} · ${e.failed} failed',
                path: '/admin/registrations?event=${e.eventId}&email=failed',
              ),
          ],
        ),
        if (access.canSeePayments) ...[
          _Queue(
            title: 'Payments stuck',
            description: 'Payments started but still pending after 30 minutes.',
            count: c.stuckPayments,
            needsAction: true,
            review: '/admin/payments?view=orders&status=stuck',
          ),
          _Queue(
            title: 'Refunds need attention',
            description: 'Refunds that couldn\'t be sent automatically. Those attendees haven\'t been paid back.',
            count: c.failedRefunds,
            needsAction: true,
            review: '/admin/payments?view=refunds&status=failed',
          ),
        ],
        _Queue(
          title: 'Registration closing soon',
          description: 'Published events whose registration closes in the next 72 hours.',
          count: c.closingSoon,
          review: '/admin/events',
          events: [
            for (final e in c.closingSoonEvents)
              _QueueEvent(
                title: e.title,
                detail: [
                  if (e.closesAt != null) 'Closes ${formatDateTime(e.closesAt!)}',
                  e.capacity == null ? '${e.registered} registered' : '${e.registered} / ${e.capacity}',
                ].join(' · '),
                path: '/events/${e.eventId}',
              ),
          ],
        ),
        _Queue(
          title: 'Nearly full',
          description: 'Upcoming events with 90 % or more of their seats taken.',
          count: c.nearCapacity,
          review: '/admin/events',
          events: [
            for (final e in c.nearCapacityEvents)
              _QueueEvent(
                title: e.title,
                detail: '${formatDate(e.start)} · ${e.registered} / ${e.capacity ?? '–'}'
                    '${e.capacity != null && e.registered >= e.capacity! ? ' · Full' : ''}',
                path: '/admin/registrations?event=${e.eventId}',
              ),
          ],
        ),
        if (access.canSeePayments)
          _Queue(
            title: 'Refunds delayed',
            description: 'Refunds Razorpay couldn\'t take yet for a temporary reason. Retrying automatically.',
            count: c.delayedRefunds,
            review: '/admin/payments?view=refunds&status=delayed',
          ),
      ];
}

class _QueueEvent {
  const _QueueEvent({required this.title, required this.detail, required this.path});

  final String title;
  final String detail;
  final String path;
}

class _Queue {
  const _Queue({
    required this.title,
    required this.description,
    required this.count,
    required this.review,
    this.needsAction = false,
    this.events = const [],
  });

  final String title;
  final String description;
  final int count;

  /// Counts toward the Admin badge.
  final bool needsAction;

  /// Where Review goes when the queue isn't a single event.
  final String review;
  final List<_QueueEvent> events;

  /// One event: Review opens it directly.
  String get reviewPath => events.length == 1 ? events.single.path : review;
}

/// Website `.mgmt-row` action card: title and one line of description,
/// then the count and Review →. A gold left edge while something needs
/// doing.
class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.queue});

  final _Queue queue;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final q = queue;
    final pending = q.count > 0;
    final accent = pending && q.needsAction;
    final narrow = MediaQuery.sizeOf(context).width < 600;

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(q.title, style: AppTextStyles.titleSmall.copyWith(color: p.textPrimary)),
        const SizedBox(height: 2),
        Text(q.description, style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary)),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${q.count}',
          style: AppTextStyles.titleSmall.copyWith(
            fontWeight: FontWeight.w700,
            color: pending ? p.primary : p.textMuted,
          ),
        ),
        const SizedBox(width: 14),
        OutlinedButton(
          onPressed: () => context.go(q.reviewPath),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            minimumSize: const Size(0, 32),
            foregroundColor: p.textPrimary,
            side: BorderSide(color: p.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            textStyle: AppTextStyles.labelMedium.copyWith(fontSize: 12.8),
          ),
          child: const Text('Review →'),
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: accent ? p.primary : Colors.transparent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(17, 14, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (narrow) ...[
                      info,
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerRight, child: actions),
                    ] else
                      Row(
                        children: [
                          Expanded(child: info),
                          const SizedBox(width: 16),
                          actions,
                        ],
                      ),
                    if (q.events.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Divider(height: 1, color: p.border),
                      const SizedBox(height: 4),
                      for (final e in q.events) _EventLine(event: e),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventLine extends StatelessWidget {
  const _EventLine({required this.event});

  final _QueueEvent event;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: () => context.go(event.path),
      borderRadius: BorderRadius.circular(6),
      hoverColor: p.surfaceHover,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: event.title,
                      style: AppTextStyles.bodyMedium.copyWith(color: p.textPrimary),
                    ),
                    TextSpan(
                      text: '  ·  ${event.detail}',
                      style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward, size: 16, color: p.primary),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: context.palette.textMuted,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      );
}

/// Website empty state: shield, "All clear".
class _AllClear extends StatelessWidget {
  const _AllClear();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: 40, color: p.textMuted),
            const SizedBox(height: 12),
            Text('All clear', style: AppTextStyles.titleMedium.copyWith(color: p.textPrimary)),
            const SizedBox(height: 6),
            Text(
              'Nothing needs attention right now.',
              style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
