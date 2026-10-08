import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/event.dart';
import '../providers/event_detail_provider.dart';
import '../services/razorpay_payment.dart';

/// Checkout for one registration: the signed-in attendee's own.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.eventId,
    this.notes = '',
  });

  final int eventId;
  final String notes;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  var _isSubmitting = false;

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
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
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

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        backgroundColor: isDark ? const Color(0xFF0D1B3E) : Colors.white,
        foregroundColor: isDark ? Colors.white : const Color(0xFF0D1B3E),
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
    // The public event fee. The amount charged is the backend's own, taken
    // from the payment attempt in _confirmRegistration.
    final fee = _isPaidEvent(event) ? event.ticketPrice! : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fee Summary',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFFC9952A),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 460,
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2.2),
                    1: FlexColumnWidth(1.6),
                    2: FlexColumnWidth(1.4),
                  },
                  border: TableBorder(
                    horizontalInside:
                        BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: const Color(0xFFC9952A).withValues(alpha: 0.08),
                      ),
                      children: [
                        _feeTableHeaderCell('Item'),
                        _feeTableHeaderCell('Details'),
                        _feeTableHeaderCell('Amount'),
                      ],
                    ),
                    TableRow(
                      children: [
                        _feeTableCell(
                          _isPaidEvent(event) ? 'Registration Fee' : 'Free Event',
                          bold: true,
                        ),
                        _feeTableCell(
                          _isPaidEvent(event)
                              ? 'Event fee'
                              : 'Complimentary registration',
                        ),
                        _feeTableCell(_formatAmount(fee)),
                      ],
                    ),
                  ],
                ),
              ),
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
          backgroundColor: const Color(0xFF0D1B3E),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          disabledBackgroundColor:
              const Color(0xFF0D1B3E).withValues(alpha: 0.6),
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
      final existingStatus = registration?['status'] as String?;
      final reuse = registration?['registration_id'] != null &&
          _payableStatuses.contains(existingStatus);
      if (!reuse) {
        final ok = await notifier.register(widget.eventId, widget.notes);
        if (!ok) {
          final state = ref.read(eventDetailProvider(widget.eventId));
          _showMessage(
            'Registration failed: ${state.errorMessage ?? 'Unknown error'}',
          );
          return;
        }
        registration = ref.read(eventDetailProvider(widget.eventId)).myRegistration;
      }

      // Free event, or registration already confirmed: done.
      final status = registration?['status'] as String?;
      if (!_isPaidEvent(event) || !_payableStatuses.contains(status)) {
        _showMessage('Registration confirmed successfully!');
        if (mounted) context.pop();
        return;
      }

      // 2. Paid event: order -> attempt -> Razorpay -> verify.
      final token = ref.read(authControllerProvider).session?.accessToken;
      if (token == null) {
        _showMessage('Your session has expired. Please sign in again.');
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
        _showMessage('Online payment is not available for this event.');
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
        _showMessage('Payment successful - your registration is confirmed!');
        if (mounted) context.pop();
      } else {
        // e.g. verification still pending; the webhook will finish it.
        _showMessage(
          (verify['safe_message'] as String?) ??
              'Payment received - confirmation is in progress.',
        );
      }
    } on RazorpayCheckoutCancelledException {
      _showMessage('Payment cancelled. Your seat is held for a short time.');
    } on RazorpayCheckoutFailureException catch (e) {
      _showMessage('Payment could not be completed: ${e.message}');
    } on DioException catch (e) {
      _showMessage('Payment could not be completed: ${_apiError(e)}');
    } catch (e) {
      _showMessage('Payment could not be completed: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    final infoBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF3FA);
    final infoText = isDark ? const Color(0xFF8B9AB8) : const Color(0xFF5A6A8A);

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
              "You'll receive a confirmation email. Your QR badge will appear in My Events.",
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

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return '₹${amount.toInt()}';
    }
    return '₹${amount.toStringAsFixed(2)}';
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
            color: isDark ? Colors.white : const Color(0xFF0D1B3E),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_formatDate(event.startDatetime)} · ${_formatTime(event.startDatetime, event.endDatetime)}',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
          ),
        ),
        if (event.locationText != null || event.isVirtual) ...[
          const SizedBox(height: 4),
          Text(
            event.locationText ?? (event.isVirtual ? 'Virtual Event' : ''),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
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