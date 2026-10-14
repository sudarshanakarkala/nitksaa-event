import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audit_api.dart';

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String? _text(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// One payment order (`GET /api/v1/admin/payments/orders`).
@immutable
class AdminOrder {
  const AdminOrder({
    required this.orderNumber,
    required this.eventId,
    required this.eventTitle,
    required this.amount,
    required this.amountPaid,
    required this.status,
    required this.mode,
    required this.createdAt,
    required this.stuck,
    this.fullname,
    this.email,
    this.registrationNumber,
    this.paidAt,
    this.providerRefs = const [],
  });

  final String orderNumber;
  final int eventId;
  final String eventTitle;
  final String? fullname;
  final String? email;
  final String? registrationNumber;
  final double amount;
  final double amountPaid;

  /// created / payment_pending / paid / expired / cancelled.
  final String status;

  /// test / live.
  final String mode;
  final DateTime createdAt;
  final DateTime? paidAt;

  /// Pending for over 30 minutes.
  final bool stuck;

  /// Razorpay ids for this order (order_…, pay_…, rfnd_…), for search.
  final List<String> providerRefs;

  String get displayName => fullname ?? email ?? registrationNumber ?? orderNumber;

  /// What the Orders search matches: name, email, numbers, event, Razorpay ids.
  String get searchText => [fullname, email, registrationNumber, orderNumber, eventTitle, ...providerRefs]
      .whereType<String>()
      .join(' ')
      .toLowerCase();

  factory AdminOrder.fromJson(Map<String, dynamic> j) => AdminOrder(
        orderNumber: j['public_order_number']?.toString() ?? '',
        eventId: _int(j['event_id']),
        eventTitle: j['event_title']?.toString() ?? '',
        fullname: _text(j['fullname']),
        email: _text(j['email']),
        registrationNumber: _text(j['registration_number']),
        amount: _num(j['final_amount']),
        amountPaid: _num(j['amount_paid']),
        status: j['status']?.toString() ?? '',
        mode: j['payment_mode']?.toString() ?? 'test',
        createdAt: _date(j['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        paidAt: _date(j['paid_at']),
        stuck: j['stuck'] == true,
        providerRefs: [for (final r in j['provider_refs'] as List<dynamic>? ?? const []) r.toString()],
      );
}

/// One payment try on an order (order details window).
@immutable
class OrderAttempt {
  const OrderAttempt({
    required this.number,
    required this.status,
    this.method,
    this.instrument,
    this.failureText,
    this.orderRef,
    this.paymentRef,
    this.bankReference,
  });

  final int number;
  final String status;
  final String? method;
  final String? instrument;
  final String? failureText;

  /// Razorpay order_… and pay_… ids.
  final String? orderRef;
  final String? paymentRef;
  final String? bankReference;

  factory OrderAttempt.fromJson(Map<String, dynamic> j) => OrderAttempt(
        number: _int(j['attempt_number']),
        status: j['status']?.toString() ?? '',
        method: _text(j['payment_method']),
        instrument: _text(j['payment_instrument']),
        failureText: _text(j['failure_text']),
        orderRef: _text(j['gateway_order_ref']),
        paymentRef: _text(j['gateway_payment_ref']),
        bankReference: _text(j['bank_reference']),
      );
}

/// An order's payment tries, refunds and history
/// (`GET /api/v1/admin/payments/orders/{order number}`).
@immutable
class OrderDetails {
  const OrderDetails({required this.attempts, required this.refunds, required this.timeline});

  final List<OrderAttempt> attempts;
  final List<AdminRefund> refunds;
  final List<AuditEntry> timeline;
}

/// One refund (`GET /api/v1/admin/payments/refunds`).
@immutable
class AdminRefund {
  const AdminRefund({
    required this.refundNumber,
    required this.eventId,
    required this.eventTitle,
    required this.amount,
    required this.status,
    required this.mode,
    required this.requestedAt,
    this.orderNumber,
    this.fullname,
    this.email,
    this.providerRef,
    this.failureReason,
    this.updatedAt,
    this.paymentRef,
    this.bankReference,
    this.reasonText,
    this.attemptCount = 1,
    this.canRetry = false,
  });

  final String refundNumber;
  final String? orderNumber;
  final int eventId;
  final String eventTitle;
  final String? fullname;
  final String? email;
  final double amount;

  /// pending / processing / delayed (retrying automatically) / processed /
  /// failed (needs a person).
  final String status;
  final String mode;
  final String? providerRef;
  final String? failureReason;
  final DateTime requestedAt;
  final DateTime? updatedAt;

  /// The provider's id for the original payment (Razorpay `pay_…`).
  final String? paymentRef;

  /// The bank reference (ARN) once the refund has been sent.
  final String? bankReference;

  /// [failureReason] in plain words, from the backend.
  final String? reasonText;
  final int attemptCount;

  /// Delayed or failed: Retry now is possible.
  final bool canRetry;

  String get displayName => fullname ?? email ?? refundNumber;

  factory AdminRefund.fromJson(Map<String, dynamic> j) => AdminRefund(
        refundNumber: j['public_refund_number']?.toString() ?? '',
        orderNumber: _text(j['public_order_number']),
        eventId: _int(j['event_id']),
        eventTitle: j['event_title']?.toString() ?? '',
        fullname: _text(j['fullname']),
        email: _text(j['email']),
        amount: _num(j['amount']),
        status: j['status']?.toString() ?? '',
        mode: j['payment_mode']?.toString() ?? 'test',
        providerRef: _text(j['provider_refund_id']),
        failureReason: _text(j['failure_reason']),
        requestedAt: _date(j['requested_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: _date(j['updated_at']),
        paymentRef: _text(j['provider_payment_id']),
        bankReference: _text(j['bank_reference']),
        reasonText: _text(j['reason_text']),
        attemptCount: j['attempt_count'] == null ? 1 : _int(j['attempt_count']),
        canRetry: j['can_retry'] == true,
      );
}

/// What Retry now did (`POST …/refunds/{number}/retry`).
@immutable
class RefundRetryResult {
  const RefundRetryResult({required this.status, this.reasonText});

  /// processed / pending / processing / delayed / failed.
  final String status;
  final String? reasonText;

  factory RefundRetryResult.fromJson(Map<String, dynamic> j) => RefundRetryResult(
        status: j['status']?.toString() ?? '',
        reasonText: _text(j['reason_text']),
      );
}

/// How an event charges: its published payment setup.
@immutable
class EventPricing {
  const EventPricing({
    required this.eventId,
    required this.baseAmount,
    required this.gstEnabled,
    required this.gstRate,
    required this.gstMode,
    required this.feeEnabled,
    required this.feeType,
    required this.feeValue,
    required this.gateway,
    required this.mode,
    required this.version,
    this.updatedAt,
  });

  final int eventId;
  final double baseAmount;
  final bool gstEnabled;
  final double gstRate;

  /// inclusive / exclusive.
  final String gstMode;
  final bool feeEnabled;

  /// fixed / percentage.
  final String feeType;
  final double feeValue;
  final String gateway;
  final String mode;
  final int version;
  final DateTime? updatedAt;

  /// What an attendee pays: price, plus GST when it's added on top, plus
  /// the convenience fee.
  double get finalAmount {
    var total = baseAmount;
    if (gstEnabled && gstMode == 'exclusive') total += baseAmount * gstRate / 100;
    if (feeEnabled) total += feeType == 'percentage' ? baseAmount * feeValue / 100 : feeValue;
    return total;
  }

  factory EventPricing.fromJson(Map<String, dynamic> j) => EventPricing(
        eventId: _int(j['event_id']),
        baseAmount: _num(j['base_amount']),
        gstEnabled: j['gst_enabled'] == true,
        gstRate: _num(j['gst_rate']),
        gstMode: j['gst_mode']?.toString() ?? 'exclusive',
        feeEnabled: j['convenience_fee_enabled'] == true,
        feeType: j['convenience_fee_type']?.toString() ?? 'fixed',
        feeValue: _num(j['convenience_fee_value']),
        gateway: j['gateway']?.toString() ?? '',
        mode: j['payment_mode']?.toString() ?? 'test',
        version: _int(j['version']),
        updatedAt: _date(j['updated_at']) ?? _date(j['created_at']),
      );
}

class PaymentsApi {
  PaymentsApi({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;

  static Dio _createDio() {
    const configured = String.fromEnvironment('BACKEND_BASE_URL');
    const devConfigured = String.fromEnvironment('DEV_BACKEND_BASE_URL');
    final baseUrl = configured.isNotEmpty
        ? configured
        : devConfigured.isNotEmpty
        ? devConfigured
        : 'http://127.0.0.1:8000';
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 90),
        headers: const {'Content-Type': 'application/json'},
      ),
    );
  }

  Options _auth(String token) => Options(headers: {'Authorization': 'Bearer $token'});

  Future<List<T>> _allPages<T>(
    String path,
    String key,
    String token,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final rows = <T>[];
    for (var page = 1; page <= 50; page++) {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: {'page': page, 'per_page': 500},
        options: _auth(token),
      );
      final data = response.data ?? const <String, dynamic>{};
      final list = data[key] as List<dynamic>? ?? const [];
      rows.addAll(list.whereType<Map<String, dynamic>>().map(parse));
      final total = (data['total'] as num?)?.toInt() ?? rows.length;
      if (list.isEmpty || rows.length >= total) break;
    }
    return rows;
  }

  Future<List<AdminOrder>> orders(String token) =>
      _allPages('/api/v1/admin/payments/orders', 'orders', token, AdminOrder.fromJson);

  Future<OrderDetails> orderDetails(String token, String orderNumber) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/admin/payments/orders/${Uri.encodeComponent(orderNumber)}',
      options: _auth(token),
    );
    final data = response.data ?? const <String, dynamic>{};
    final order = data['order'] as Map<String, dynamic>? ?? const {};
    List<Map<String, dynamic>> list(String key) =>
        (data[key] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    return OrderDetails(
      attempts: [for (final a in list('attempts')) OrderAttempt.fromJson(a)],
      refunds: [
        for (final r in list('refunds'))
          AdminRefund.fromJson({...r, 'event_id': order['event_id'], 'event_title': order['event_title']}),
      ],
      timeline: [for (final t in list('timeline')) AuditEntry.fromJson(t)],
    );
  }

  Future<List<AdminRefund>> refunds(String token) =>
      _allPages('/api/v1/admin/payments/refunds', 'refunds', token, AdminRefund.fromJson);

  /// Try a delayed or failed refund again now. The backend first checks
  /// what Razorpay already holds, so this never refunds twice.
  Future<RefundRetryResult> retryRefund(String token, String refundNumber) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/admin/payments/refunds/${Uri.encodeComponent(refundNumber)}/retry',
      options: _auth(token),
    );
    return RefundRetryResult.fromJson(response.data ?? const <String, dynamic>{});
  }

  /// The event's published payment setup, or null if it has none yet.
  Future<EventPricing?> pricing(String token, int eventId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/admin/events/$eventId/payment-configurations',
      options: _auth(token),
    );
    final rows = response.data?['configurations'] as List<dynamic>? ?? const [];
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      if (row['status'] == 'published') return EventPricing.fromJson(row);
    }
    return null;
  }
}

final paymentsApiProvider = Provider<PaymentsApi>((ref) => PaymentsApi());
