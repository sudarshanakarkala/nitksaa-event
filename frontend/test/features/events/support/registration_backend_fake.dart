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

  /// Registrations by the bearer token of the attendee who owns them.
  final registrations = <String, Map<String, dynamic>>{};

  /// Payment orders by registration id.
  final orders = <int, Map<String, dynamic>>{};

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

  /// One registration holds one seat.
  int get seatsTaken => registrations.length;

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

  /// Gives [token]'s attendee a registration made before the test started.
  Map<String, dynamic> seedRegistration(String token, {required String status}) {
    return registrations[token] = _newRegistration(status: status, note: null);
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
    if (token == null) return _json(401, {'detail': 'not_authenticated'});

    if (request.line == 'GET /api/v1/events/$eventId/registration-eligibility') {
      final registered = registrations.containsKey(token);
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
      if (registrations.containsKey(token)) {
        return _json(409, {'detail': 'already_registered'});
      }
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
        return {
          'order_id': 'ORD-$registrationId',
          'registration_id': registrationId,
          'event_id': eventId,
          'currency': 'INR',
          'final_amount': finalAmount,
          'status': 'created',
          'registration_status': 'payment_pending',
          'payment_mode': 'test',
          'real_money': false,
        };
      });
      return _json(200, order);
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
