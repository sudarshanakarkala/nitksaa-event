// Regression tests for ISSUE-006 on the real CheckoutScreen: checkout is for
// one registration. It shows no pass count and no price multiplied by one,
// registers once, and opens Razorpay with the amount the backend gave.
//
// Browser-only, for the same reason as checkout_auth_isolation_test.dart
// (ISSUE-016), and because the Razorpay checkout is driven through a fake
// `window.Razorpay`. Run it with:
//
//   flutter test --platform chrome test/features/events/checkout_single_registration_test.dart
@TestOn('browser')
library;

import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/presentation/screens/checkout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/auth_isolation_fakes.dart';
import 'support/fake_razorpay_web.dart';
import 'support/registration_backend_fake.dart';

final _passOrQuantityWording = RegExp(
  r'\bpass(es)?\b|quantity',
  caseSensitive: false,
);

void main() {
  tearDown(FakeRazorpay.uninstall);

  /// Opens checkout the way the app's router does, on top of the event page,
  /// so that checkout can close itself when it is done.
  Future<void> openCheckout(
    WidgetTester tester,
    FakeRegistrationBackend backend, {
    String notes = '',
  }) async {
    final router = GoRouter(
      initialLocation: '/events/$eventX',
      routes: [
        GoRoute(
          path: '/events/:id',
          builder: (context, state) => const Scaffold(body: Text('event page')),
        ),
        GoRoute(
          path: '/events/:id/checkout',
          builder: (context, state) => CheckoutScreen(
            eventId: eventX,
            notes: state.uri.queryParameters['notes'] ?? '',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    final auth = FakeAuthController()..logIn(sessionA);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          eventsRepositoryProvider.overrideWithValue(backend.repository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push(
      '/events/$eventX/checkout?notes=${Uri.encodeComponent(notes)}',
    );
    await settleRequests(tester);
    expect(find.text('Fee Summary'), findsOneWidget);
  }

  /// Presses the checkout button and waits for the flow to end. The button
  /// is found by type so that these tests do not depend on its wording.
  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byType(ElevatedButton));
    await settleRequests(tester);
  }

  group('ISSUE-006: checkout screen', () {
    testWidgets('Test E: a paid event shows one registration fee, with no '
        'pass count and no multiplied total', (tester) async {
      final backend = FakeRegistrationBackend(ticketPrice: '100.00');
      await openCheckout(tester, backend);

      expect(find.text('Registration Fee'), findsOneWidget);
      // The public fee is shown once: not again as a total, nor on the button.
      expect(find.textContaining('₹100'), findsOneWidget);
      for (final multiplied in ['₹200', '₹300', '₹400']) {
        expect(find.textContaining(multiplied), findsNothing);
      }
      expect(find.text('No of passes'), findsNothing);
      expect(find.textContaining(_passOrQuantityWording), findsNothing);
      expect(find.text('Grand Total'), findsNothing);
      expect(find.textContaining('Confirm & Pay'), findsNothing);
      expect(find.text('Proceed to Payment'), findsOneWidget);
    });

    testWidgets('a free event has no pass count either', (tester) async {
      await openCheckout(tester, FakeRegistrationBackend(isFree: true));

      expect(find.text('Free Event'), findsOneWidget);
      expect(find.textContaining(_passOrQuantityWording), findsNothing);
      expect(find.text('Grand Total'), findsNothing);
      expect(find.text('Confirm Registration'), findsOneWidget);
    });
  });

  group('ISSUE-006: paid registration', () {
    late FakeRegistrationBackend backend;

    setUp(() {
      // The backend's amount (123.45) is deliberately not the public ticket
      // price (100.00), nor a multiple of it.
      backend = FakeRegistrationBackend(
        ticketPrice: '100.00',
        finalAmount: '123.45',
      );
      FakeRazorpay.install();
    });

    testWidgets('Test C: the registration request is attendee_note and '
        'nothing else', (tester) async {
      await openCheckout(tester, backend, notes: 'Vegetarian meal');
      await confirm(tester);

      final request = backend.registerRequests.single;
      expect(request.json, {'attendee_note': 'Vegetarian meal'});
      expect(request.rawBody, isNot(contains('quantity')));
    });

    testWidgets('Test D: one confirmation makes one registration request and '
        'takes one seat', (tester) async {
      await openCheckout(tester, backend);
      await confirm(tester);

      expect(backend.registerRequests, hasLength(1));
      expect(backend.registrations, hasLength(1));
      expect(backend.seatsTaken, 1);
    });

    testWidgets('Test F: one payment order is created, for that '
        'registration', (tester) async {
      await openCheckout(tester, backend);
      await confirm(tester);

      final registrationId = backend.registrations[tokenA]!['registration_id'];
      expect(
        backend.paymentOrderRequests.map((r) => r.path),
        ['/api/v1/registrations/$registrationId/payment-order'],
      );
      expect(backend.orders.keys, [registrationId]);
      expect(backend.paymentAttemptRequests, hasLength(1));
    });

    testWidgets("Test G: Razorpay is opened with the backend's amount_minor, "
        'not a price worked out by the app', (tester) async {
      await openCheckout(tester, backend);
      await confirm(tester);

      final opened = FakeRazorpay.opened.single;
      expect(opened['amount'], 12345);
      expect(opened['amount'], isNot(10000)); // ticket_price in paise
    });

    testWidgets('Test H: the order amount, the attempt amount and the '
        'Razorpay amount are the same', (tester) async {
      await openCheckout(tester, backend);
      await confirm(tester);

      final order = backend.orders.values.single;
      final checkout = backend.checkouts.single;
      final opened = FakeRazorpay.opened.single;
      expect(order['final_amount'], '123.45');
      expect(checkout['amount_minor'], 12345);
      expect(opened['amount'], checkout['amount_minor']);
      expect(opened['currency'], checkout['currency']);
      expect(opened['order_id'], checkout['provider_order_id']);
      expect(opened['key'], checkout['key_id']);
    });

    testWidgets('Test J: register, order, attempt, Razorpay and '
        'verification each happen once, in that order', (tester) async {
      await openCheckout(tester, backend);
      await confirm(tester);

      final registrationId = backend.registrations[tokenA]!['registration_id'];
      final posts = backend.requests.where((r) => r.method == 'POST');
      expect(posts.map((r) => r.path), [
        '/api/v1/events/$eventX/register',
        '/api/v1/registrations/$registrationId/payment-order',
        '/api/v1/payment-orders/ORD-$registrationId/attempts',
        '/api/v1/payment-orders/ORD-$registrationId/verify-checkout',
      ]);
      expect(FakeRazorpay.opened, hasLength(1));
      expect(backend.verifyCheckoutRequests.single.json, {
        'razorpay_payment_id': FakeRazorpay.paymentId,
        'razorpay_order_id': backend.checkouts.single['provider_order_id'],
        'razorpay_signature': FakeRazorpay.signature,
      });
      expect(backend.registrations[tokenA]!['status'], 'registered');
      // Checkout has closed and the event page is showing again.
      expect(find.text('event page'), findsOneWidget);
    });

    testWidgets('Test J: closing Razorpay without paying leaves one '
        'registration and one order', (tester) async {
      FakeRazorpay.install(outcome: FakeRazorpayOutcome.dismissed);
      await openCheckout(tester, backend);
      await confirm(tester);

      expect(FakeRazorpay.opened.single['amount'], 12345);
      expect(backend.registerRequests, hasLength(1));
      expect(backend.paymentOrderRequests, hasLength(1));
      expect(backend.verifyCheckoutRequests, isEmpty);
      expect(backend.seatsTaken, 1);
      expect(find.textContaining('Payment cancelled'), findsOneWidget);
    });

    testWidgets('Test K: a seat already held is paid for, without a second '
        'registration', (tester) async {
      final held = backend.seedRegistration(tokenA, status: 'seat_held');
      await openCheckout(tester, backend);
      await confirm(tester);

      expect(backend.registerRequests, isEmpty);
      expect(
        backend.paymentOrderRequests.map((r) => r.path),
        ['/api/v1/registrations/${held['registration_id']}/payment-order'],
      );
      expect(backend.seatsTaken, 1);
      expect(FakeRazorpay.opened.single['amount'], 12345);
    });

    testWidgets("Test K: the backend's refusal of a duplicate is shown, and "
        'nothing more is requested', (tester) async {
      await openCheckout(tester, backend);
      // The attendee registers somewhere else after this screen loaded.
      backend.seedRegistration(tokenA, status: 'registered');
      await confirm(tester);

      expect(backend.registerRequests, hasLength(1));
      expect(backend.seatsTaken, 1);
      expect(backend.paymentOrderRequests, isEmpty);
      expect(FakeRazorpay.opened, isEmpty);
      expect(find.textContaining('Registration failed'), findsOneWidget);
    });
  });

  group('ISSUE-006: free registration', () {
    testWidgets('Test I: one registration request, no payment and no '
        'Razorpay', (tester) async {
      final backend = FakeRegistrationBackend(isFree: true);
      FakeRazorpay.install();
      await openCheckout(tester, backend, notes: 'Wheelchair access');
      await confirm(tester);

      final request = backend.registerRequests.single;
      expect(request.json, {'attendee_note': 'Wheelchair access'});
      expect(request.rawBody, isNot(contains('quantity')));
      expect(backend.seatsTaken, 1);
      expect(backend.registrations[tokenA]!['status'], 'registered');
      expect(backend.paymentOrderRequests, isEmpty);
      expect(backend.paymentAttemptRequests, isEmpty);
      expect(FakeRazorpay.opened, isEmpty);
      expect(find.text('event page'), findsOneWidget);
    });
  });
}
