import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/app_palette.dart';
import '../../domain/refund_status.dart';
import '../providers/cancellation_outcome.dart';
import '../providers/refund_status_provider.dart';

/// Opens the refund status of one of the attendee's registrations.
///
/// With [known], the answer to a cancellation just made, the dialog shows
/// that and nothing is sent. Without it the backend is asked once.
Future<void> showRefundStatus(
  BuildContext context,
  WidgetRef ref, {
  required int registrationId,
  RefundStatus? known,
}) async {
  final provider = refundStatusProvider(registrationId);
  // Held until the dialog closes, so that what is put in here is what the
  // dialog shows first.
  final hold = ref.listenManual(provider, (_, _) {});
  final notifier = ref.read(provider.notifier);
  if (known != null) {
    notifier.show(known);
  } else {
    unawaited(notifier.check());
  }
  try {
    await showDialog<void>(
      context: context,
      builder: (context) => RefundStatusDialog(registrationId: registrationId),
    );
  } finally {
    hold.close();
  }
}

/// The "View refund" action for the message shown after a cancellation, or
/// null when the cancellation left nothing to refund.
SnackBarAction? viewRefundAction(
  BuildContext context,
  WidgetRef ref, {
  required CancellationOutcome outcome,
  required int registrationId,
}) {
  final refund = outcome.refund;
  if (refund == null || !refund.hasRefund) return null;
  return SnackBarAction(
    label: 'View refund',
    onPressed: () {
      if (!context.mounted) return;
      showRefundStatus(
        context,
        ref,
        registrationId: registrationId,
        known: refund,
      );
    },
  );
}

/// Shows [refundStatusProvider] for one registration. Open it with
/// [showRefundStatus].
class RefundStatusDialog extends ConsumerWidget {
  const RefundStatusDialog({super.key, required this.registrationId});

  final int registrationId;

  static const _unavailable =
      'We could not read the refund status. Please check again in a moment.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = refundStatusProvider(registrationId);
    // The notifier is replaced when the signed-in session changes. What this
    // dialog was showing belonged to the previous session, so it closes.
    final route = ModalRoute.of(context);
    ref.listen(provider.notifier, (previous, next) {
      if (route != null && route.isCurrent) Navigator.of(context).pop();
    });

    final state = ref.watch(provider);
    final refund = state.refund;
    final error = state.errorMessage;
    final isFirstLoad = refund == null && state.isLoading;
    final canCheck =
        !isFirstLoad && (error != null || refund == null || _mayChange(refund));

    return AlertDialog(
      title: Text(refund == null ? 'Refund status' : _headline(refund)),
      content: isFirstLoad
          ? const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (refund != null)
                  ..._details(context, refund)
                else if (error == null)
                  const Text(_unavailable),
                if (error != null) ...[
                  if (refund != null) const SizedBox(height: 12),
                  Text(error, style: TextStyle(color: context.palette.error)),
                ],
              ],
            ),
      actions: [
        if (canCheck)
          TextButton(
            onPressed: state.isLoading
                ? null
                : () => ref.read(provider.notifier).check(),
            child: Text(state.isLoading ? 'Checking…' : 'Check refund status'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  /// Whether asking again can give a different answer. A processed or failed
  /// refund is final, and the backend has no way to retry a failed one.
  static bool _mayChange(RefundStatus refund) {
    return switch (refund.status) {
      RefundStatus.processed || RefundStatus.failed || RefundStatus.none => false,
      _ => true,
    };
  }

  static String _headline(RefundStatus refund) {
    return switch (refund.status) {
      RefundStatus.pending => 'Refund in progress',
      RefundStatus.processed => 'Refunded',
      RefundStatus.failed => 'Refund could not be completed',
      RefundStatus.none => 'No refund',
      _ => 'Refund status unavailable',
    };
  }

  static List<Widget> _details(BuildContext context, RefundStatus refund) {
    switch (refund.status) {
      case RefundStatus.none:
        return const [
          Text('No payment was taken, so there is nothing to refund.'),
        ];
      case RefundStatus.pending:
      case RefundStatus.processed:
      case RefundStatus.failed:
        break;
      default:
        return const [Text(_unavailable)];
    }

    final amount = _formatAmount(refund);
    final requestedAt = refund.requestedAt;
    final finalizedAt = refund.finalizedAt;
    var message = refund.safeMessage?.trim() ?? '';
    if (message.isEmpty && refund.status == RefundStatus.failed) {
      message = 'The refund could not be completed automatically. Please '
          'contact support.';
    }
    return [
      if (amount != null) _DetailRow(label: 'Amount', value: amount),
      if (refund.status == RefundStatus.pending && requestedAt != null)
        _DetailRow(label: 'Requested on', value: _formatDateTime(requestedAt)),
      if (refund.status == RefundStatus.processed && finalizedAt != null)
        _DetailRow(label: 'Refunded on', value: _formatDateTime(finalizedAt)),
      if (message.isNotEmpty) ...[
        if (amount != null) const SizedBox(height: 8),
        Text(message),
      ],
    ];
  }

  /// The backend's amount as it is, never recomputed here.
  static String? _formatAmount(RefundStatus refund) {
    final amount = refund.amount;
    if (amount == null) return null;
    final figure = amount == amount.roundToDouble()
        ? '${amount.toInt()}'
        : amount.toStringAsFixed(2);
    final currency = refund.currency;
    if (currency == null || currency.toUpperCase() == 'INR') return '₹$figure';
    return '$figure $currency';
  }

  static String _formatDateTime(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:$minute $period';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
