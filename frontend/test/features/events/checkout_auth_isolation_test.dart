// Regression test for ISSUE-001 on the real CheckoutScreen: after a user
// switch, checkout must not pay for the previous user's registration.
//
// Browser-only. CheckoutScreen imports razorpay_payment.dart, whose dart:io
// variant needs the razorpay_flutter package that is not in pubspec.yaml yet
// (ISSUE-016), so this file cannot compile for the Dart VM. Run it with:
//
//   flutter test --platform chrome test/features/events/checkout_auth_isolation_test.dart
@TestOn('browser')
library;

import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/presentation/screens/checkout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_isolation_fakes.dart';

void main() {
  testWidgets("Test E: checkout pays for user B's own registration, never "
      "user A's", (tester) async {
    // A holds a seat that still owes payment - the case checkout reuses.
    final backend = buildBackend(registrationStatusA: 'payment_pending');
    backend.accounts[tokenB]!.eligibility = {
      'eligibility_status': 'eligible',
      'message': 'You can register for this event.',
    };
    final auth = FakeAuthController()..logIn(sessionA);

    // The screen stays mounted across the switch, so the same
    // eventDetailProvider(eventX) is in use the whole time.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          eventsRepositoryProvider.overrideWithValue(backend),
        ],
        child: const MaterialApp(home: CheckoutScreen(eventId: eventX)),
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.calls, contains((endpoint: 'my-registration', token: tokenA)));

    await auth.signOut();
    auth.logIn(sessionB);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Confirm & Pay'));
    await tester.pumpAndSettle();

    expect(backend.paymentOrders, hasLength(1));
    final order = backend.paymentOrders.single;
    expect(order.token, tokenB);
    expect(order.registrationId, isNot(registrationIdA));
    expect(
      order.registrationId,
      backend.accounts[tokenB]!.registration?['registration_id'],
    );
    expect(find.textContaining('registration_not_found'), findsNothing);
  });
}
