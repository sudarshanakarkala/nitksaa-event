// A group's refunds (a guest cancelled alone, then the rest) come with every
// refund status, so the refund window can show each one and their total.
import 'package:event_app/features/events/domain/refund_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group refunds and what was paid are read from the response', () {
    final refund = RefundStatus.fromJson({
      'registration_id': 10,
      'status': 'refund_processed',
      'amount': '1000.00',
      'currency': 'INR',
      'safe_message': 'Sent.',
      'group_paid': '1500.00',
      'group_refunds': [
        {
          'refund_id': 'RFND-a',
          'registration_id': 11,
          'name': 'Asha',
          'is_guest': true,
          'status': 'refund_processed',
          'amount': 500,
          'currency': 'INR',
          'bank_reference': 'ARN1',
        },
        {
          'refund_id': 'RFND-b',
          'registration_id': 10,
          'name': 'Padma',
          'is_guest': false,
          'status': 'refund_pending',
          'amount': '1000.00',
          'currency': 'INR',
        },
        'not a refund',
      ],
    });
    expect(refund.groupPaid, 1500);
    expect(refund.groupRefunds.map((g) => g.refundId), ['RFND-a', 'RFND-b']);
    expect(refund.groupRefunds.first.isGuest, isTrue);
    expect(refund.groupRefunds.first.amount, 500);
    expect(refund.groupRefunds.first.bankReference, 'ARN1');
    expect(refund.groupRefunds.last.status, RefundStatus.pending);
  });

  test('someone alone has no group list', () {
    final refund = RefundStatus.fromJson({'registration_id': 1, 'status': 'none'});
    expect(refund.groupRefunds, isEmpty);
    expect(refund.groupPaid, isNull);
  });
}
