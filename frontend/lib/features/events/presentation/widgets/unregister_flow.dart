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
      content: Text(_unregisterText(registration, eventTitle)),
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

/// "This will unregister you from X." With guests still coming, it says they
/// go too: the whole group is cancelled and refunded.
String _unregisterText(MyEventRegistration registration, String eventTitle) {
  final guests = registration.activeGuests.length;
  if (guests == 0) return 'This will unregister you from $eventTitle.';
  final who = guests == 1 ? 'you and your guest' : 'you and your $guests guests';
  return 'This will unregister $who from $eventTitle.';
}

/// Cancel one guest (only the registrant can): asks first, then cancels that
/// guest's seat and QR, with their share refunded on a paid event.
/// [refundLabel] is the amount to say, e.g. "₹500"; null on a free event.
/// [onDone] runs after a successful cancel, to refresh the page.
Future<void> confirmAndCancelGuest(
  BuildContext context,
  WidgetRef ref, {
  required EventGuest guest,
  String? refundLabel,
  Future<void> Function()? onDone,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Cancel ${guest.name}?'),
      content: Text(
        refundLabel == null
            ? '${guest.name}\'s seat will be freed and their QR code will stop working.'
            : '${guest.name}\'s seat will be freed and their QR code will stop working. '
                '$refundLabel will be refunded.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Cancel guest'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final outcome = await ref
      .read(myEventsProvider.notifier)
      .cancelRegistration(guest.registrationId);
  if (!context.mounted) return;
  if (outcome.cancelled) await onDone?.call();
  if (!context.mounted) return;
  final refundStatus = outcome.refund?.status;
  showNotice(
    context,
    !outcome.cancelled
        ? outcome.message
        : switch (refundStatus) {
            RefundStatus.pending || RefundStatus.processed =>
              '${guest.name} is cancelled. Their refund has been started.',
            RefundStatus.delayed || RefundStatus.failed => outcome.message,
            _ => '${guest.name} is cancelled.',
          },
    kind: !outcome.cancelled
        ? NoticeKind.error
        : (refundStatus == RefundStatus.failed || refundStatus == RefundStatus.delayed)
            ? NoticeKind.warning
            : NoticeKind.success,
    persist: outcome.cancelled ? false : null,
    action: viewRefundAction(
      context,
      ref,
      outcome: outcome,
      registrationId: guest.registrationId,
    ),
  );
}
