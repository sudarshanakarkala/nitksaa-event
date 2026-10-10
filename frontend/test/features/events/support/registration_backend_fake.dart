import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lets requests to a [FakeRegistrationBackend] finish and the screen
/// rebuild.
///
/// A widget test runs on fake time. On the VM, pumping is enough for Dio. In
/// Chrome it is not: Dio reads a response body with `await for`, which there
/// ends on a real microtask that fake time never runs. So real time is let
/// through between pumps.
Future<void> settleRequests(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A request the fake backend received.
class RecordedRequest {
  RecordedRequest(this.method, this.path, this.bearer, this.rawBody);

  final String method;
  final String path;

  /// The `Authorization` header, or null when the request carried none.
  final String? bearer;

  /// The body exactly as it was sent; empty when there was none.
  final String rawBody;

  String get line => '$method $path';

  Map<String, dynamic> get json => rawBody.isEmpty
      ? const <String, dynamic>{}
      : jsonDecode(rawBody) as Map<String, dynamic>;
}

/// Stands in for the registration and payment endpoints of the backend, for
/// one event. Plug it into a [Dio] as its `httpClientAdapter`, or use
/// [repository].
///
/// It keeps the backend's rules that ISSUE-006 depends on:
///
/// - `POST /register` reads `attendee_note` and nothing else. Any other key
///   is dropped without an error, as Pydantic does for `RegisterRequest`.
/// - One call makes one registration for the caller and takes one seat. A
///   second call from the same caller is refused with `already_registered`.
/// - The amount to pay is the backend's own [finalAmount]. No request can
///   change it, and [ticketPrice] (what the public event shows) need not
///   equal it.
///
/// And the ones ISSUE-004 depends on, from `refund_service.py`:
///
/// - `POST /registrations/{id}/cancel` is the only way to cancel. It needs
///   an `idempotency_key` of 8 to 128 characters and answers with a refund
///   status. `DELETE /events/{id}/my-registration` has no handler (405).
/// - A `registered` registration is cancelled. If its order is paid, one
///   full refund is made; the same key, or a second cancel, gets that refund
///   back and never a second one.
/// - A `cancelled` registration answers 200 with its current refund status.
/// - Any other status is refused with `409 registration_not_cancellable`.
/// - Somebody else's registration is `404 registration_not_found`.
/// - Every row is kept. `GET /my/registrations` lists them newest first, and
///   `GET /events/{id}/my-registration` gives the newest.
class FakeRegistrationBackend implements HttpClientAdapter {
  FakeRegistrationBackend({
    this.eventId = 7,
    this.isFree = false,
    this.ticketPrice = '100.00',
    this.finalAmount = '123.45',
  });

  final int eventId;
  final bool isFree;

  /// `ticket_price` of the public event, in rupees.
  final String ticketPrice;

  /// `final_amount` of every payment order, in rupees.
  final String finalAmount;

  final requests = <RecordedRequest>[];

  /// The newest registration of each attendee, by their bearer token.
  final registrations = <String, Map<String, dynamic>>{};

  /// The older registrations of each attendee for this event, newest first.
  final earlierRegistrations = <String, List<Map<String, dynamic>>>{};

  /// Payment orders by registration id.
  final orders = <int, Map<String, dynamic>>{};

  /// Refunds by registration id, as the attendee is shown them.
  final refunds = <int, Map<String, dynamic>>{};

  /// How many refunds were made. A repeated cancel must not add to it.
  int refundsCreated = 0;

  /// What the payment provider says about a new refund: `refund_pending`,
  /// `refund_processed` or `refund_failed`.
  String refundStatusOnCancel = 'refund_pending';

  /// When set, cancelling a paid registration is refused with this `detail`
  /// (`no_captured_payment`, `refund_not_supported`, `refund_mode_mismatch`).
  String? paidCancelRefusal;

  /// When set, every cancel is answered with this HTTP status and no usable
  /// `detail`, as a crashed or overloaded backend would.
  int? cancelServerError;

  /// This many of the next cancel requests never reach the backend.
  int cancelRequestsToDrop = 0;

  /// The next cancel is carried out, but its response is lost on the way.
  bool loseNextCancelResponse = false;

  /// The `checkout` object of each payment attempt handed out.
  final checkouts = <Map<String, dynamic>>[];

  int _lastRegistrationId = 500;

  /// A repository that talks to this backend.
  EventsRepository get repository => EventsRepository(
    dio: Dio(
      BaseOptions(
        baseUrl: 'https://backend.test',
        headers: const {'Content-Type': 'application/json'},
      ),
    )..httpClientAdapter = this,
  );

  /// One registration holds one seat, until it is cancelled.
  int get seatsTaken =>
      registrations.values.where((r) => r['status'] != 'cancelled').length;

  /// [finalAmount] in paise, as the backend's `rupees_to_paise` gives it.
  int get finalAmountMinor => (double.parse(finalAmount) * 100).round();

  Iterable<RecordedRequest> requestsTo(String method, String path) =>
      requests.where((r) => r.method == method && r.path == path);

  List<RecordedRequest> get registerRequests =>
      requestsTo('POST', '/api/v1/events/$eventId/register').toList();

  List<RecordedRequest> get paymentOrderRequests => requests
      .where((r) => r.method == 'POST' && r.path.endsWith('/payment-order'))
      .toList();

  List<RecordedRequest> get paymentAttemptRequests => requests
      .where((r) => r.method == 'POST' && r.path.endsWith('/attempts'))
      .toList();

  List<RecordedRequest> get verifyCheckoutRequests => requests
      .where((r) => r.method == 'POST' && r.path.endsWith('/verify-checkout'))
      .toList();

  List<RecordedRequest> get cancelRequests => requests
      .where((r) => r.path.startsWith('/api/v1/registrations/'))
      .where((r) => r.path.endsWith('/cancel'))
      .toList();

  /// Gives [token]'s attendee a registration made before the test started.
  /// A second call makes a newer one and keeps the first as history. With
  /// [paid], the registration has a paid order to refund.
  Map<String, dynamic> seedRegistration(
    String token, {
    required String status,
    bool paid = false,
  }) {
    _shelveRegistration(token);
    final registration = _newRegistration(status: status, note: null);
    if (status == 'cancelled') {
      registration['cancelled_at'] = '2098-12-02T10:00:00Z';
    }
    if (paid) {
      final registrationId = registration['registration_id'] as int;
      orders[registrationId] = _newOrder(
        registrationId,
        status: 'paid',
        registrationStatus: status,
      );
    }
    return registrations[token] = registration;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = [
      if (requestStream != null) ...(await requestStream.toList()).expand((c) => c),
    ];
    final bearer = options.headers['Authorization']?.toString();
    final request = RecordedRequest(
      options.method,
      options.path,
      bearer,
      utf8.decode(bytes),
    );
    requests.add(request);
    final token = bearer?.replaceFirst('Bearer ', '');
    final path = options.path;

    if (request.line == 'GET /api/v1/events/public/$eventId') {
      return _json(200, {'event': _publicEvent()});
    }
    if (request.line == 'GET /api/v1/events/public') {
      // The event is in 2099, so it is never a past one.
      final events = [
        if (options.queryParameters['period'] != 'past') _publicEvent(),
      ];
      return _json(200, {
        'events': events,
        'total': events.length,
        'page': 1,
        'per_page': 100,
      });
    }
    if (token == null) return _json(401, {'detail': 'not_authenticated'});

    if (request.line == 'GET /api/v1/events/$eventId/registration-eligibility') {
      final registered = _hasLiveRegistration(token);
      return _json(200, {
        'event_id': eventId,
        'eligibility_status': registered ? 'already_registered' : 'eligible',
        'message': registered
            ? 'You are registered for this event.'
            : 'You can register for this event.',
      });
    }
    if (request.line == 'GET /api/v1/events/$eventId/my-registration') {
      final registration = registrations[token];
      if (registration == null) {
        return _json(404, {'detail': 'registration_not_found'});
      }
      return _json(200, registration);
    }
    if (path == '/api/v1/events/$eventId/my-registration') {
      // Only GET is routed. This is what production answers to the DELETE
      // the app used to send.
      return _json(405, {'detail': 'Method Not Allowed'});
    }
    if (request.line == 'GET /api/v1/my/registrations') {
      final rows = [
        for (final registration in _registrationsOf(token))
          {...registration, 'event': _eventSummary()},
      ];
      return _json(200, {'registrations': rows, 'total': rows.length});
    }
    if (request.line == 'GET /api/v1/alumni/me') {
      return _json(200, {
        'ref_id': 'REF-1',
        'fullname': 'Alice Alumna',
        'email': 'alice@example.com',
        'phone': '+91 90000 00001',
        'is_active': true,
      });
    }
    if (request.line == 'POST /api/v1/events/$eventId/register') {
      if (_hasLiveRegistration(token)) {
        return _json(409, {'detail': 'already_registered'});
      }
      _shelveRegistration(token);
      final registration = _newRegistration(
        status: isFree ? 'registered' : 'seat_held',
        note: request.json['attendee_note'] as String?,
      );
      registrations[token] = registration;
      return _json(201, registration);
    }

    final orderPath = RegExp(
      r'^/api/v1/registrations/(\d+)/payment-order$',
    ).firstMatch(path);
    if (options.method == 'POST' && orderPath != null) {
      final registrationId = int.parse(orderPath.group(1)!);
      final registration = registrations[token];
      if (registration?['registration_id'] != registrationId) {
        return _json(404, {'detail': 'registration_not_found'});
      }
      // The backend reuses the registration's active order.
      final order = orders.putIfAbsent(registrationId, () {
        registration!['status'] = 'payment_pending';
        return _newOrder(
          registrationId,
          status: 'created',
          registrationStatus: 'payment_pending',
        );
      });
      return _json(200, order);
    }

    final cancelPath = RegExp(
      r'^/api/v1/registrations/(\d+)/cancel$',
    ).firstMatch(path);
    if (options.method == 'POST' && cancelPath != null) {
      if (cancelRequestsToDrop > 0) {
        cancelRequestsToDrop--;
        throw _connectionError(options);
      }
      final response = _cancel(
        int.parse(cancelPath.group(1)!),
        token,
        request.json['idempotency_key'],
      );
      if (loseNextCancelResponse) {
        loseNextCancelResponse = false;
        throw _connectionError(options);
      }
      return response;
    }

    final attemptPath = RegExp(
      r'^/api/v1/payment-orders/([^/]+)/attempts$',
    ).firstMatch(path);
    if (options.method == 'POST' && attemptPath != null) {
      final order = _orderOf(attemptPath.group(1)!, token);
      if (order == null) return _json(404, {'detail': 'order_not_found'});
      final checkout = {
        'provider': 'razorpay',
        'provider_order_id': 'order_FAKE${checkouts.length + 1}',
        'key_id': 'rzp_test_fakekey',
        'amount_minor': finalAmountMinor,
        'currency': 'INR',
      };
      checkouts.add(checkout);
      return _json(200, {
        'attempt_id': 'ATT-${checkouts.length}',
        'order_id': order['order_id'],
        'attempt_number': checkouts.length,
        'gateway': 'razorpay',
        'status': 'initiated',
        'checkout': checkout,
        'payment_mode': 'test',
        'real_money': false,
      });
    }

    final verifyPath = RegExp(
      r'^/api/v1/payment-orders/([^/]+)/verify-checkout$',
    ).firstMatch(path);
    if (options.method == 'POST' && verifyPath != null) {
      final order = _orderOf(verifyPath.group(1)!, token);
      if (order == null) return _json(404, {'detail': 'order_not_found'});
      order['status'] = 'paid';
      registrations[token]!['status'] = 'registered';
      return _json(200, {
        'order_id': order['order_id'],
        'attempt_id': 'ATT-${checkouts.length}',
        'order_status': 'paid',
        'registration_status': 'registered',
        'payment_confirmed': true,
        'safe_message': 'Payment confirmed.',
      });
    }

    return _json(404, {'detail': 'not_found'});
  }

  @override
  void close({bool force = false}) {}

  /// `refund_service.cancel_registration`, in the same order of checks.
  ResponseBody _cancel(int registrationId, String token, Object? key) {
    if (key is! String || key.length < 8 || key.length > 128) {
      return _json(422, {
        'detail': [
          {
            'loc': ['body', 'idempotency_key'],
            'msg': 'String should have between 8 and 128 characters',
          },
        ],
      });
    }
    if (cancelServerError != null) {
      return _json(cancelServerError!, {'detail': 'Internal Server Error'});
    }
    // Not found and not owned look the same from outside.
    final registration = _registrationsOf(
      token,
    ).where((r) => r['registration_id'] == registrationId).firstOrNull;
    if (registration == null) {
      return _json(404, {'detail': 'registration_not_found'});
    }
    if (registration['status'] == 'cancelled') {
      return _json(200, _refundView(registrationId));
    }
    if (registration['status'] != 'registered') {
      return _json(409, {'detail': 'registration_not_cancellable'});
    }

    final order = orders[registrationId];
    if (order?['status'] == 'paid') {
      if (paidCancelRefusal != null) {
        return _json(409, {'detail': paidCancelRefusal});
      }
      refundsCreated++;
      refunds[registrationId] = {
        'refund_id': 'RFND-$registrationId',
        'registration_id': registrationId,
        'status': refundStatusOnCancel,
        'amount': finalAmount,
        'currency': 'INR',
        'requested_at': '2098-12-03T10:00:00Z',
        'finalized_at': refundStatusOnCancel == 'refund_processed'
            ? '2098-12-03T10:00:05Z'
            : null,
        'safe_message': _safeMessages[refundStatusOnCancel],
        'payment_mode': 'test',
        'real_money': false,
        'idempotency_key': key,
      };
    }
    registration['status'] = 'cancelled';
    registration['cancelled_at'] = '2098-12-03T10:00:00Z';
    return _json(200, _refundView(registrationId));
  }

  /// `RefundStatusResponse` for a registration.
  Map<String, dynamic> _refundView(int registrationId) {
    final refund = refunds[registrationId];
    if (refund != null) return {...refund}..remove('idempotency_key');
    return {
      'refund_id': null,
      'registration_id': registrationId,
      'status': 'none',
      'amount': null,
      'currency': null,
      'requested_at': null,
      'finalized_at': null,
      'safe_message': _safeMessages['none'],
      'payment_mode': null,
      'real_money': false,
    };
  }

  /// The backend's `_safe_message`, word for word.
  static const _safeMessages = {
    'refund_pending':
        'Your registration is cancelled. Your refund is being processed.',
    'refund_processed':
        'Your cancellation is confirmed and the refund has been processed by '
        'the payment provider.',
    'refund_failed':
        'Your registration is cancelled, but the refund could not be '
        'completed automatically. Our team will follow up.',
    'none':
        'Your registration is cancelled. No payment was collected, so there '
        'is nothing to refund.',
  };

  /// What Dio reports when the backend cannot be reached.
  DioException _connectionError(RequestOptions options) {
    return DioException.connectionError(
      requestOptions: options,
      reason: 'The XMLHttpRequest onError callback was called.',
    );
  }

  /// Every registration of an attendee, newest first.
  List<Map<String, dynamic>> _registrationsOf(String token) => [
    if (registrations[token] != null) registrations[token]!,
    ...?earlierRegistrations[token],
  ];

  /// Whether the attendee holds a seat: a cancelled registration does not.
  bool _hasLiveRegistration(String token) {
    final registration = registrations[token];
    return registration != null && registration['status'] != 'cancelled';
  }

  /// Moves the attendee's newest registration into their history.
  void _shelveRegistration(String token) {
    final registration = registrations.remove(token);
    if (registration == null) return;
    earlierRegistrations.putIfAbsent(token, () => []).insert(0, registration);
  }

  Map<String, dynamic>? _orderOf(String orderId, String token) {
    final registrationId = registrations[token]?['registration_id'];
    final order = orders[registrationId];
    return order?['order_id'] == orderId ? order : null;
  }

  Map<String, dynamic> _newRegistration({
    required String status,
    required String? note,
  }) {
    final id = ++_lastRegistrationId;
    return {
      'registration_id': id,
      'registration_number': 'NITKSAA-2099-000$id',
      'event_id': eventId,
      'status': status,
      'attendee_note': note,
      // A later registration has a later time.
      'registered_at': DateTime.utc(
        2098,
        12,
      ).add(Duration(minutes: id)).toIso8601String(),
      'cancelled_at': null,
    };
  }

  Map<String, dynamic> _newOrder(
    int registrationId, {
    required String status,
    required String registrationStatus,
  }) {
    return {
      'order_id': 'ORD-$registrationId',
      'registration_id': registrationId,
      'event_id': eventId,
      'currency': 'INR',
      'final_amount': finalAmount,
      'status': status,
      'registration_status': registrationStatus,
      'payment_mode': 'test',
      'real_money': false,
    };
  }

  /// The `event` object of a row of `GET /my/registrations`.
  Map<String, dynamic> _eventSummary() {
    final event = _publicEvent();
    return {
      for (final key in const [
        'event_id',
        'title',
        'start_datetime',
        'end_datetime',
        'timezone',
        'is_virtual',
      ])
        key: event[key],
    };
  }

  Map<String, dynamic> _publicEvent() {
    return {
      'event_id': eventId,
      'slug': 'event-$eventId',
      'title': 'Annual Alumni Meet',
      'status': 'published',
      'start_datetime': '2099-01-10T12:30:00Z',
      'end_datetime': '2099-01-10T15:30:00Z',
      'timezone': 'Asia/Kolkata',
      'is_virtual': false,
      'is_free': isFree,
      'ticket_price': isFree ? null : ticketPrice,
      'registration_status': 'open',
      'registered_count': seatsTaken,
    };
  }

  ResponseBody _json(int statusCode, Map<String, dynamic> body) {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
