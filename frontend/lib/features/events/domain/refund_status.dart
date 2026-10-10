/// The backend's `RefundStatusResponse`: what cancelling a registration did
/// about the attendee's payment.
class RefundStatus {
  const RefundStatus({
    this.refundId,
    this.registrationId,
    required this.status,
    this.amount,
    this.currency,
    this.requestedAt,
    this.finalizedAt,
    this.safeMessage,
    this.paymentMode,
    this.realMoney = false,
  });

  /// Nothing was paid, so there is nothing to refund.
  static const none = 'none';
  static const pending = 'refund_pending';
  static const processed = 'refund_processed';
  static const failed = 'refund_failed';

  final String? refundId;
  final int? registrationId;

  /// One of [none], [pending], [processed] or [failed].
  final String status;
  final double? amount;
  final String? currency;
  final DateTime? requestedAt;
  final DateTime? finalizedAt;

  /// The backend's own wording for [status], written to be shown as it is.
  final String? safeMessage;

  /// `test` or `live`. Null when there is no refund.
  final String? paymentMode;
  final bool realMoney;

  /// A refund exists, in whatever state. False when nothing was paid.
  bool get hasRefund => status != none;

  /// Never throws: by the time there is a response to parse the registration
  /// is already cancelled, and a field this app cannot read must not turn
  /// that into a failure.
  factory RefundStatus.fromJson(Map<String, dynamic> json) {
    final registrationId = json['registration_id'];
    return RefundStatus(
      refundId: json['refund_id']?.toString(),
      registrationId: registrationId is num ? registrationId.toInt() : null,
      status: json['status']?.toString() ?? none,
      amount: _parseAmount(json['amount']),
      currency: json['currency']?.toString(),
      requestedAt: _parseDate(json['requested_at']),
      finalizedAt: _parseDate(json['finalized_at']),
      safeMessage: json['safe_message']?.toString(),
      paymentMode: json['payment_mode']?.toString(),
      realMoney: json['real_money'] == true,
    );
  }

  /// `amount` is a Decimal on the backend, which may arrive as a JSON number
  /// or as a string.
  static double? _parseAmount(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}
