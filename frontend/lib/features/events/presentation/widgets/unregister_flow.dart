import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/notice.dart';
import '../../domain/my_event_registration.dart';
import '../../domain/refund_status.dart';
import '../providers/my_events_provider.dart';
import 'refund_status_dialog.dart';

/// Unregister from an event card (Events page, My Events): asks first, then
/// cancels and says how it went, with "View refund" when there is one. One
/// place, so both pages always ask and answer the same way.
Future<void> confirmAndUnregister(
  BuildContext context,
  WidgetRef ref, {
  required MyEventRegistration registration,
  required String eventTitle,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Unregister?'),
      content: Text('This will unregister you from $eventTitle.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Unregister'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final outcome = await ref
      .read(myEventsProvider.notifier)
      .cancelRegistration(registration.registrationId);
  if (!context.mounted) return;
  final refundStatus = outcome.refund?.status;
  showNotice(
    context,
    outcome.message,
    kind: !outcome.cancelled
        ? NoticeKind.error
        : (refundStatus == RefundStatus.failed || refundStatus == RefundStatus.delayed)
            ? NoticeKind.warning
            : NoticeKind.success,
    // A notice with an action would otherwise stay up until pressed.
    persist: outcome.cancelled ? false : null,
    action: viewRefundAction(
      context,
      ref,
      outcome: outcome,
      registrationId: registration.registrationId,
    ),
  );
}
