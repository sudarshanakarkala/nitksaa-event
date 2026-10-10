// ISSUE-004: an attendee who cancelled can register again. Here the whole
// path runs on the real screens: the event page's Register button, the
// registration form, and the real CheckoutScreen.
//
// Browser-only, for the same reason as checkout_single_registration_test.dart
// (ISSUE-016). Run it with:
//
//   flutter test --platform chrome test/features/events/cancellation_reregister_checkout_test.dart
@TestOn('browser')
library;

import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/presentation/screens/checkout_screen.dart';
import 'package:event_app/features/events/presentation/screens/event_detail_screen.dart';
import 'package:event_app/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/auth_isolation_fakes.dart';
import 'support/fake_razorpay_web.dart';
import 'support/registration_backend_fake.dart';

void main() {
  tearDown(FakeRazorpay.uninstall);

  /// Opens the event page for user A, on a router with the app's event and
  /// checkout routes.
  Future<void> openEventPage(
    WidgetTester tester,
    FakeRegistrationBackend backend,
  ) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/events/$eventX',
      routes: [
        GoRoute(
          path: AppRoutes.eventDetail,
          builder: (context, state) => const EventDetailScreen(eventId: eventX),
        ),
        GoRoute(
          path: AppRoutes.checkout,
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
    await settleRequests(tester);
  }

  /// Register on the event page, through the form, to the end of checkout.
  Future<void> registerAgain(WidgetTester tester) async {
    expect(find.text('You cancelled your earlier registration.'), findsOneWidget);
    await tester.tap(find.text('Register'));
    await settleRequests(tester);
    await tester.tap(find.text('Proceed to Checkout'));
    await settleRequests(tester);
    expect(find.text('Fee Summary'), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton));
    await settleRequests(tester);
  }

  testWidgets('free event: registering again after a cancellation makes a new '
      'registration, with no payment', (tester) async {
    final backend = FakeRegistrationBackend(isFree: true);
    final old = backend.seedRegistration(tokenA, status: 'cancelled');
    FakeRazorpay.install();
    await openEventPage(tester, backend);

    await registerAgain(tester);

    expect(backend.registerRequests, hasLength(1));
    final current = backend.registrations[tokenA]!;
    expect(current['status'], 'registered');
    expect(current['registration_id'], isNot(old['registration_id']));
    expect(old['status'], 'cancelled');
    expect(backend.seatsTaken, 1);
    expect(backend.paymentOrderRequests, isEmpty);
    expect(FakeRazorpay.opened, isEmpty);

    // Checkout has closed and the event page shows the new registration.
    expect(find.text('Fee Summary'), findsNothing);
    expect(find.text('Registered Successfully'), findsOneWidget);
    expect(
      find.text('Badge #: ${current['registration_number']}'),
      findsOneWidget,
    );
    expect(find.text('You cancelled your earlier registration.'), findsNothing);
  });

  testWidgets('paid event: the payment order is for the new registration, not '
      'the cancelled one', (tester) async {
    final backend = FakeRegistrationBackend();
    final old = backend.seedRegistration(
      tokenA,
      status: 'cancelled',
      paid: true,
    );
    FakeRazorpay.install();
    await openEventPage(tester, backend);

    await registerAgain(tester);

    final current = backend.registrations[tokenA]!;
    final currentId = current['registration_id'];
    expect(currentId, isNot(old['registration_id']));
    final posts = backend.requests.where((r) => r.method == 'POST');
    expect(posts.map((r) => r.path), [
      '/api/v1/events/$eventX/register',
      '/api/v1/registrations/$currentId/payment-order',
      '/api/v1/payment-orders/ORD-$currentId/attempts',
      '/api/v1/payment-orders/ORD-$currentId/verify-checkout',
    ]);
    expect(FakeRazorpay.opened, hasLength(1));
    expect(current['status'], 'registered');
    expect(old['status'], 'cancelled');
    expect(find.text('Fee Summary'), findsNothing);
  });
}
