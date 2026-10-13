// Admin → Payments: reading orders and refunds, and the price an attendee
// pays from an event's payment setup.

import 'package:event_app/features/admin/data/payments_api.dart';
import 'package:flutter_test/flutter_test.dart';

EventPricing _pricing({
  double base = 1000,
  bool gst = false,
  double rate = 18,
  String gstMode = 'exclusive',
  bool fee = false,
  String feeType = 'fixed',
  double feeValue = 0,
}) =>
    EventPricing.fromJson({
      'event_id': 1,
      'base_amount': base,
      'gst_enabled': gst,
      'gst_rate': rate,
      'gst_mode': gstMode,
      'convenience_fee_enabled': fee,
      'convenience_fee_type': feeType,
      'convenience_fee_value': feeValue,
      'gateway': 'razorpay',
      'payment_mode': 'test',
      'version': 2,
    });

void main() {
  test('reads an order, including stuck and mode', () {
    final o = AdminOrder.fromJson({
      'public_order_number': 'ORD-34',
      'event_id': 2,
      'event_title': 'Past Dinner',
      'fullname': 'Asha Rao',
      'email': 'asha@example.com',
      'final_amount': 500.0,
      'amount_paid': 0,
      'status': 'payment_pending',
      'payment_mode': 'live',
      'created_at': '2026-10-12T05:00:00+00:00',
      'paid_at': null,
      'stuck': true,
    });
    expect(o.displayName, 'Asha Rao');
    expect(o.amount, 500);
    expect(o.status, 'payment_pending');
    expect(o.mode, 'live');
    expect(o.stuck, isTrue);
    expect(o.paidAt, isNull);
  });

  test('reads a failed refund with its reason', () {
    final r = AdminRefund.fromJson({
      'public_refund_number': 'RF-3',
      'public_order_number': 'ORD-3',
      'event_id': 2,
      'event_title': 'Past Dinner',
      'email': 'p@example.com',
      'amount': 500,
      'status': 'failed',
      'payment_mode': 'test',
      'failure_reason': 'Gateway timeout',
      'requested_at': '2026-10-12T05:00:00+00:00',
    });
    expect(r.displayName, 'p@example.com');
    expect(r.status, 'failed');
    expect(r.failureReason, 'Gateway timeout');
  });

  test('reads a delayed refund: reason in words, tries, references', () {
    final r = AdminRefund.fromJson({
      'public_refund_number': 'RF-4',
      'event_id': 2,
      'event_title': 'Dinner',
      'amount': '100.00',
      'status': 'delayed',
      'payment_mode': 'test',
      'failure_reason': 'insufficient_balance',
      'reason_text': 'Razorpay balance too low to send the refund yet.',
      'provider_payment_id': 'pay_abc',
      'bank_reference': null,
      'attempt_count': 2,
      'can_retry': true,
      'requested_at': '2026-10-12T05:00:00+00:00',
    });
    expect(r.status, 'delayed');
    expect(r.reasonText, startsWith('Razorpay balance too low'));
    expect(r.paymentRef, 'pay_abc');
    expect(r.bankReference, isNull);
    expect(r.attemptCount, 2);
    expect(r.canRetry, isTrue);
  });

  test('older refund rows without the new fields still read', () {
    final r = AdminRefund.fromJson({
      'public_refund_number': 'RF-5', 'event_id': 1, 'amount': 1, 'status': 'processed',
      'requested_at': '2026-10-12T05:00:00+00:00',
    });
    expect(r.attemptCount, 1);
    expect(r.canRetry, isFalse);
  });

  group('what the attendee pays', () {
    test('just the price', () => expect(_pricing().finalAmount, 1000));
    test('GST added on top', () => expect(_pricing(gst: true).finalAmount, 1180));
    test('GST already included', () => expect(_pricing(gst: true, gstMode: 'inclusive').finalAmount, 1000));
    test('fixed fee', () => expect(_pricing(fee: true, feeValue: 25).finalAmount, 1025));
    test('percentage fee', () => expect(_pricing(fee: true, feeType: 'percentage', feeValue: 2).finalAmount, 1020));
  });
}
