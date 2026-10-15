import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

import '../../../../theme/app_palette.dart';
import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/event.dart';
import '../providers/event_detail_provider.dart';
import '../services/razorpay_payment.dart';
import '../../../../shared/widgets/notice.dart';
import '../../../../shared/format.dart';

/// Checkout for one registration: the signed-in attendee's own.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.eventId,
  });

  final int eventId;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  var _isSubmitting = false;
  var _leaving = false;

  /// What the server will charge (line items and total), loaded once for a
  /// paid event. Null while loading or if it couldn't be loaded.
  Map<String, dynamic>? _pricing;
  var _pricingRequested = false;

  /// How many people this checkout pays for (the registrant and guests).
  var _people = 1;

  Future<void> _loadPricing(AppEvent event) async {
    if (_pricingRequested || !_isPaidEvent(event)) return;
    _pricingRequested = true;
    final token = ref.read(authControllerProvider).session?.accessToken;
    if (token == null) return;
    // The whole group pays: the form's guests, or (Complete payment) the
    // guests of the held registration.
    final state = ref.read(eventDetailProvider(widget.eventId));
    final draft = state.registrationDraft;
    final held = _canReuse(state.myRegistration) ? state.myRegistration : null;
    final heldGuests = (held?['guests'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .where((g) => g['status'] != 'cancelled')
        .length;
    final people = held != null ? 1 + heldGuests : (draft?.people ?? 1);
    _people = people;
    try {
      final pricing = await ref
          .read(eventsRepositoryProvider)
          .getPaymentPricing(event.eventId, token, people: people);
      if (mounted) setState(() => _pricing = pricing);
    } catch (_) {
      // The table falls back to the event's listed price.
    }
  }

  /// True when a registration already holds a seat and owes payment
  /// ("Complete payment"): checkout reuses it and needs no form details.
  static bool _canReuse(Map<String, dynamic>? registration) =>
      registration?['registration_id'] != null &&
      _payableStatuses.contains(registration?['status'] as String?);

  /// Without the form's details (e.g. the page was refreshed here) and with
  /// nothing to reuse, there is nothing to register with: back to the event.
  void _backToEventIfNoDetails(EventDetailState state) {
    if (_leaving || _isSubmitting || state.isLoading) return;
    if (state.registrationDraft != null || _canReuse(state.myRegistration)) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/events/${widget.eventId}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(eventDetailProvider(widget.eventId));

    if (state.isLoading && state.event == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.errorMessage != null && state.event == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: context.palette.error),
                const SizedBox(height: 16),
                Text(
                  'Failed to load event details:\n${state.errorMessage}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref
                      .read(eventDetailProvider(widget.eventId).notifier)
                      .fetchEventDetails(widget.eventId),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final event = state.event;
    if (event == null) {
      return const Scaffold(
        body: Center(child: Text('Event not found')),
      );
    }
    _backToEventIfNoDetails(state);
    _loadPricing(event);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        backgroundColor: context.palette.background,
        foregroundColor: context.palette.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEventHeader(event, isDark),
                  const SizedBox(height: 20),
                  _buildFeeSummarySection(event),
                  const SizedBox(height: 24),
                  _buildSubmitButton(event),
                  const SizedBox(height: 16),
                  _buildInfoBox(isDark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
// ==========================================
  // FEE SUMMARY (mirrors the Create Event fee table)
  // ==========================================
  Widget _feeTableHeaderCell(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _feeTableCell(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildFeeSummarySection(AppEvent event) {
    // The server's line items and total when loaded; until then (or if they
    // can't be loaded) the event's listed price. The amount charged is always
    // the server's, taken from the payment attempt in _confirmRegistration.
    final rows = <(String, String)>[];
    String totalText;
    final items = _pricing?['line_items'] as List<dynamic>?;
    if (!_isPaidEvent(event)) {
      rows.add(('Free event', formatMoney(0)));
      totalText = 'Free';
    } else if (items != null && items.isNotEmpty) {
      for (final item in items.whereType<Map>()) {
        final amount = double.tryParse(item['amount']?.toString() ?? '') ?? 0;
        rows.add((item['label']?.toString() ?? '', formatMoney(amount)));
      }
      final total =
          double.tryParse(_pricing?['final_amount']?.toString() ?? '') ?? 0;
      totalText = formatMoney(total);
    } else {
      rows.add((
        _people > 1 ? 'Registration fee × $_people people' : 'Registration fee',
        formatMoney(event.ticketPrice! * _people),
      ));
      totalText = formatMoney(event.ticketPrice! * _people);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fee Summary',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: context.palette.primary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: context.palette.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: IntrinsicColumnWidth(),
              },
              border: TableBorder(
                horizontalInside:
                    BorderSide(color: context.palette.border, width: 1),
              ),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: context.palette.primary.withValues(alpha: 0.08),
                  ),
                  children: [
                    _feeTableHeaderCell('Item'),
                    _feeTableHeaderCell('Amount'),
                  ],
                ),
                for (final row in rows)
                  TableRow(
                    children: [
                      _feeTableCell(row.$1),
                      _feeTableCell(row.$2),
                    ],
                  ),
                TableRow(
                  children: [
                    _feeTableCell('Total', bold: true),
                    _feeTableCell(totalText, bold: true),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
// ==========================================
  // SUBMIT REGISTRATION
  // ==========================================
  Widget _buildSubmitButton(AppEvent event) {
    final label = _isSubmitting
        ? 'Processing...'
        : (_isPaidEvent(event) ? 'Proceed to Payment' : 'Confirm Registration');

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: context.palette.primary,
          foregroundColor: context.palette.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          disabledBackgroundColor:
              context.palette.primary.withValues(alpha: 0.6),
        ),
        onPressed: _isSubmitting ? null : _confirmRegistration,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  /// Registration statuses where the seat is held and payment is still due.
  static const _payableStatuses = {
    'seat_held',
    'payment_pending',
    'payment_failed',
  };

  Future<void> _confirmRegistration() async {
    final detail = ref.read(eventDetailProvider(widget.eventId));
    final event = detail.event;
    if (event == null) return;

    setState(() => _isSubmitting = true);
    try {
      final notifier = ref.read(eventDetailProvider(widget.eventId).notifier);

      // 1. Register - or reuse an existing registration that still owes payment.
      var registration = detail.myRegistration;
      if (!_canReuse(registration)) {
        final ok = await notifier.register(widget.eventId);
        if (!ok) {
          final state = ref.read(eventDetailProvider(widget.eventId));
          _showMessage(
            state.errorMessage ?? 'Could not register. Please try again.',
            kind: NoticeKind.error,
          );
          return;
        }
        registration = ref.read(eventDetailProvider(widget.eventId)).myRegistration;
      }

      // Free event, or registration already confirmed: done.
      final status = registration?['status'] as String?;
      if (!_isPaidEvent(event) || !_payableStatuses.contains(status)) {
        _showMessage('Registration confirmed successfully!', kind: NoticeKind.success);
        if (mounted) context.pop();
        return;
      }

      // 2. Paid event: order -> attempt -> Razorpay -> verify.
      final token = ref.read(authControllerProvider).session?.accessToken;
      if (token == null) {
        _showMessage('Your session has expired. Please sign in again.', kind: NoticeKind.warning);
        return;
      }
      final repo = ref.read(eventsRepositoryProvider);
      final registrationId = (registration!['registration_id'] as num).toInt();

      final order = await repo.createPaymentOrder(
        registrationId,
        token,
        idempotencyKey:
            'reg-$registrationId-${DateTime.now().millisecondsSinceEpoch}',
      );
      final orderId = order['order_id'] as String; // our ORD-...

      final attempt = await repo.createPaymentAttempt(orderId, token);
      final checkout = attempt['checkout'] as Map<String, dynamic>?;
      if (checkout == null) {
        _showMessage('Online payment is not available for this event.', kind: NoticeKind.error);
        return;
      }

      final result = await openRazorpayCheckout(
        RazorpayCheckoutOptions(
          keyId: checkout['key_id'] as String,
          // Razorpay's order id (order_...), NOT our ORD-... id.
          orderId: checkout['provider_order_id'] as String,
          amountMinor: (checkout['amount_minor'] as num).toInt(),
          currency: (checkout['currency'] as String?) ?? 'INR',
          name: 'NITKSAA',
          description: event.title,
        ),
      );

      final verify = await repo.verifyCheckout(
        orderId,
        token,
        razorpayPaymentId: result.paymentId,
        razorpayOrderId: result.orderId,
        razorpaySignature: result.signature,
      );

      // Refresh so the event page shows the new registration status.
      await notifier.fetchEventDetails(widget.eventId);

      if (verify['payment_confirmed'] == true) {
        _showMessage('Payment successful - your registration is confirmed!', kind: NoticeKind.success);
        if (mounted) context.pop();
      } else {
        // e.g. verification still pending; the webhook will finish it.
        _showMessage(
          (verify['safe_message'] as String?) ??
              'Payment received - confirmation is in progress.',
        );
      }
    } on RazorpayCheckoutCancelledException {
      _showMessage('Payment cancelled. Your seat is held for a short time.', kind: NoticeKind.warning);
      await _backToEvent();
    } on RazorpayCheckoutFailureException catch (e) {
      _showMessage('Payment could not be completed: ${e.message}', kind: NoticeKind.error);
      await _backToEvent();
    } on DioException catch (e) {
      _showMessage('Payment could not be completed: ${_apiError(e)}', kind: NoticeKind.error);
    } catch (e) {
      _showMessage('Payment could not be completed: $e', kind: NoticeKind.error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// After a cancelled or failed payment, go back to the event page, as a
  /// successful one does: that's where the person sees where they stand
  /// ("Complete payment"). The notice stays on screen across the move.
  Future<void> _backToEvent() async {
    try {
      await ref.read(eventDetailProvider(widget.eventId).notifier).fetchEventDetails(widget.eventId);
    } catch (_) {
      // The event page loads itself anyway.
    }
    if (!mounted) return;
    // Opened directly (e.g. after a refresh): there's no page to go back to.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/events/${widget.eventId}');
    }
  }

  void _showMessage(String message, {NoticeKind kind = NoticeKind.info}) {
    if (!mounted) return;
    showNotice(context, message, kind: kind);
  }

  String _apiError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] != null) {
      final detail = data['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) return first['msg'].toString();
      }
      return detail.toString();
    }
    return e.message ?? 'Network error';
  }

  Widget _buildInfoBox(bool isDark) {
    final infoBg = context.palette.info.withValues(alpha: 0.08);
    final infoText = context.palette.textSecondary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: infoBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: infoText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Your QR code for entry will be on the event page and in My Events.",
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: infoText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // HELPERS
  // ==========================================
  bool _isPaidEvent(AppEvent event) {
    return !(event.isFree ?? true) &&
        (event.ticketPrice?.isFinite ?? false) &&
        (event.ticketPrice! > 0);
  }

  Widget _buildEventHeader(AppEvent event, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event.title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_formatDate(event.startDatetime)} · ${_formatTime(event.startDatetime, event.endDatetime)}',
          style: TextStyle(
            fontSize: 12,
            color: context.palette.textSecondary,
          ),
        ),
        if (event.locationText != null || event.isVirtual) ...[
          const SizedBox(height: 4),
          Text(
            event.locationText ?? (event.isVirtual ? 'Virtual Event' : ''),
            style: TextStyle(
              fontSize: 12,
              color: context.palette.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTime(DateTime start, DateTime? end) {
    String formatSingle(DateTime dt) {
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute $period';
    }

    if (end == null) {
      return formatSingle(start);
    }
    return '${formatSingle(start)} – ${formatSingle(end)}';
  }
}