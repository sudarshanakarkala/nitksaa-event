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
    this.paymentReference,
    this.bankReference,
    this.groupRefunds = const [],
    this.groupPaid,
  });

  /// Nothing was paid, so there is nothing to refund.
  static const none = 'none';
  static const pending = 'refund_pending';

  /// The provider couldn't take it yet (temporary); retried automatically
  /// when new payments come in, or by an admin.
  static const delayed = 'refund_delayed';
  static const processed = 'refund_processed';
  static const failed = 'refund_failed';

  final String? refundId;
  final int? registrationId;

  /// One of [none], [pending], [delayed], [processed] or [failed].
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

  /// The provider's id for the original payment (e.g. Razorpay `pay_…`).
  final String? paymentReference;

  /// The reference the attendee quotes to their bank (ARN), once sent.
  final String? bankReference;

  /// Every refund on the registration's group (a guest cancelled alone, and
  /// the rest), oldest first. Empty for someone registered alone.
  final List<GroupRefund> groupRefunds;

  /// What the group paid, when it has [groupRefunds].
  final double? groupPaid;

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
      paymentReference: _text(json['payment_reference']),
      bankReference: _text(json['bank_reference']),
      groupRefunds: [
        for (final r in (json['group_refunds'] is List ? json['group_refunds'] as List : const []))
          if (r is Map<String, dynamic>) GroupRefund.fromJson(r),
      ],
      groupPaid: _parseAmount(json['group_paid']),
    );
  }

  /// `amount` is a Decimal on the backend, which may arrive as a JSON number
  /// or as a string.
  static double? _parseAmount(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static String? _text(dynamic value) {
    final s = value?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}

/// One refund in a group: whose, how much, and where it stands.
class GroupRefund {
  const GroupRefund({
    required this.refundId,
    this.name,
    this.isGuest = false,
    required this.status,
    this.amount,
    this.currency,
    this.paymentReference,
    this.bankReference,
  });

  final String refundId;
  final String? name;
  final bool isGuest;

  /// One of RefundStatus' statuses.
  final String status;
  final double? amount;
  final String? currency;
  final String? paymentReference;
  final String? bankReference;

  factory GroupRefund.fromJson(Map<String, dynamic> json) => GroupRefund(
        refundId: json['refund_id']?.toString() ?? '',
        name: RefundStatus._text(json['name']),
        isGuest: json['is_guest'] == true,
        status: json['status']?.toString() ?? RefundStatus.pending,
        amount: RefundStatus._parseAmount(json['amount']),
        currency: json['currency']?.toString(),
        paymentReference: RefundStatus._text(json['payment_reference']),
        bankReference: RefundStatus._text(json['bank_reference']),
      );
}
