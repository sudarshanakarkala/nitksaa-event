// Regression tests for ISSUE-018 on the real CheckoutScreen: a payment that
// cannot go ahead is explained in plain words. Before, checkout showed the
// backend's code ("Payment could not be completed: payment_attempt_active"),
// Dio's own text for a lost connection, and Razorpay's reason code.
//
// Browser-only, like checkout_single_registration_test.dart: the Razorpay
// checkout is driven through a fake `window.Razorpay`. Run it with:
//
//   flutter test --platform chrome test/features/events/checkout_errors_test.dart
@TestOn('browser')
library;

import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/presentation/providers/event_detail_provider.dart';
import 'package:event_app/features/events/presentation/screens/checkout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/auth_isolation_fakes.dart';
import 'support/fake_razorpay_web.dart';
import 'support/registration_backend_fake.dart';

const _phone = '+91 98450 12345';
const _noConnection =
    'Could not reach the server. Check your connection and try again.';
const _sessionExpired = 'Your session has expired. Please sign in again.';

/// What the attendee must never see: Dio's text, a backend code, a status.
final _technical = RegExp(
  r'DioException|XMLHttpRequest|Exception|HTTP \d|[a-z]+_[a-z_]+',
);

void main() {
  tearDown(FakeRazorpay.uninstall);

  /// Opens checkout on top of the event page, as the app's router does.
  Future<void> openCheckout(
    WidgetTester tester,
    FakeRegistrationBackend backend,
  ) async {
    final router = GoRouter(
      initialLocation: '/events/$eventX',
      routes: [
        GoRoute(
          path: '/events/:id',
          builder: (context, state) => const Scaffold(body: Text('event page')),
        ),
        GoRoute(
          path: '/events/:id/checkout',
          builder: (context, state) => const CheckoutScreen(eventId: eventX),
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
    final container =
        ProviderScope.containerOf(tester.element(find.text('event page')));
    container.listen(eventDetailProvider(eventX), (_, _) {});
    container
        .read(eventDetailProvider(eventX).notifier)
        .setRegistrationDraft(const RegistrationDraft(phone: _phone));
    router.push('/events/$eventX/checkout');
    await settleRequests(tester);
    expect(find.text('Fee Summary'), findsOneWidget);
  }

  /// Presses the checkout button and waits for the flow to end.
  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byType(ElevatedButton));
    await settleRequests(tester);
  }

  group('ISSUE-018: checkout errors in plain words', () {
    late FakeRegistrationBackend backend;

    setUp(() {
      backend = FakeRegistrationBackend(
        ticketPrice: '100.00',
        finalAmount: '123.45',
      );
      FakeRazorpay.install();
    });

    testWidgets('a payment already in progress (409 payment_attempt_active)', (
      tester,
    ) async {
      backend.failures[r'^POST /api/v1/payment-orders/[^/]+/attempts$'] =
          (status: 409, detail: 'payment_attempt_active');
      await openCheckout(tester, backend);
      await confirm(tester);

      expect(
        find.text(
          'A payment for this registration is already in progress. Please '
          'wait a few minutes and try again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining(_technical), findsNothing);
      expect(FakeRazorpay.opened, isEmpty);
    });

    testWidgets('registration closed while the form was open', (tester) async {
      backend.failures['POST /api/v1/events/$eventX/register'] =
          (status: 409, detail: 'registration_closed');
      await openCheckout(tester, backend);
      await confirm(tester);

      expect(find.text('Registration for this event has closed.'), findsOneWidget);
      expect(find.textContaining(_technical), findsNothing);
      expect(backend.paymentOrderRequests, isEmpty);
    });

    testWidgets('no network when the payment is set up', (tester) async {
      backend.failures[r'^POST /api/v1/registrations/\d+/payment-order$'] =
          (status: 0, detail: null);
      await openCheckout(tester, backend);
      await confirm(tester);

      expect(find.text(_noConnection), findsOneWidget);
      expect(find.textContaining(_technical), findsNothing);
    });

    testWidgets('session expired when the payment is set up (401)', (
      tester,
    ) async {
      backend.failures[r'^POST /api/v1/registrations/\d+/payment-order$'] =
          (status: 401, detail: 'invalid_or_expired_token');
      await openCheckout(tester, backend);
      await confirm(tester);

      expect(find.text(_sessionExpired), findsOneWidget);
      expect(find.textContaining(_technical), findsNothing);
    });

    testWidgets("a payment Razorpay refuses: its words, not its reason code", (
      tester,
    ) async {
      FakeRazorpay.install(outcome: FakeRazorpayOutcome.failed);
      await openCheckout(tester, backend);
      await confirm(tester);

      expect(
        find.text(
          'Payment could not be completed: ${FakeRazorpay.failureDescription}',
        ),
        findsOneWidget,
      );
      expect(find.textContaining(FakeRazorpay.failureReason), findsNothing);
      expect(find.textContaining(_technical), findsNothing);
      expect(backend.verifyCheckoutRequests, isEmpty);
    });
  });
}
