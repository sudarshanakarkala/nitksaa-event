// My Events fixes before the freeze (16 Oct):
//
// - ISSUE-010: an unfinished payment shows "Payment due" (with Complete
//   payment), a payment being confirmed shows "Confirming payment"; only a
//   cancelled registration says "Unregistered", and only those are under
//   the Cancelled pill.
// - A QR badge button opens everyone's QR in the registration.
// - The list stays through sign-in updates for the same person (session
//   renewal, other tabs); a different person still gets an empty list.
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/presentation/screens/my_events_screen.dart';
import 'package:event_app/features/events/presentation/widgets/entry_pass_qr.dart';
import 'package:event_app/routes/app_routes.dart';
import 'package:event_app/shared/widgets/quick_filter_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/auth_isolation_fakes.dart';
import 'support/registration_backend_fake.dart';

Future<FakeAuthController> _openMyEvents(
  WidgetTester tester,
  FakeRegistrationBackend backend,
) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: AppRoutes.myEvents,
    routes: [
      GoRoute(
        path: AppRoutes.myEvents,
        builder: (context, state) => const MyEventsScreen(),
      ),
      GoRoute(
        path: AppRoutes.eventDetail,
        builder: (context, state) =>
            Scaffold(body: Text('event ${state.pathParameters['id']}')),
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
  return auth;
}

void main() {
  group('ISSUE-010: labels', () {
    testWidgets('an unfinished payment is "Payment due", not Unregistered, '
        'and not under Cancelled', (tester) async {
      final backend = FakeRegistrationBackend();
      backend.seedRegistration(tokenA, status: 'seat_held', unpaidOrder: true);
      await _openMyEvents(tester, backend);

      expect(find.text('Payment due'), findsOneWidget);
      expect(find.text('Unregistered'), findsNothing);
      expect(find.text('Complete payment'), findsOneWidget);
      expect(find.text('QR badge'), findsNothing);

      await tester.tap(find.text('Complete payment'));
      await tester.pumpAndSettle();
      expect(find.text('event $eventX'), findsOneWidget);
    });

    testWidgets('the Cancelled pill leaves out an unfinished payment', (
      tester,
    ) async {
      final backend = FakeRegistrationBackend();
      backend.seedRegistration(tokenA, status: 'payment_failed', unpaidOrder: true);
      await _openMyEvents(tester, backend);
      expect(find.text('Payment due'), findsOneWidget);

      // On computers the pills are in the Filters rail.
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(QuickFilterPill, 'Cancelled'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close filters'));
      await tester.pumpAndSettle();
      expect(find.text('Payment due'), findsNothing);
    });

    testWidgets('a payment being confirmed is "Confirming payment"', (
      tester,
    ) async {
      final backend = FakeRegistrationBackend();
      backend.seedRegistration(tokenA, status: 'payment_verification', paid: true);
      await _openMyEvents(tester, backend);

      expect(find.text('Confirming payment'), findsOneWidget);
      expect(find.text('Unregistered'), findsNothing);
      expect(find.text('Complete payment'), findsNothing);
    });

    testWidgets('a cancelled registration still says Unregistered', (
      tester,
    ) async {
      final backend = FakeRegistrationBackend(isFree: true);
      backend.seedRegistration(tokenA, status: 'cancelled');
      await _openMyEvents(tester, backend);
      expect(find.text('Unregistered'), findsOneWidget);
    });
  });

  testWidgets('QR badge shows a QR for you and each guest', (tester) async {
    final backend = FakeRegistrationBackend(isFree: true, maxGuests: 2);
    final reg = backend.seedRegistration(tokenA, status: 'registered');
    reg['guests'] = [
      {
        'registration_id': 901,
        'registration_number': 'NITKSAA-2099-0901',
        'name': 'Asha Warrier',
        'status': 'registered',
        'qr_token': 'qr-guest-901',
      },
      {
        'registration_id': 902,
        'name': 'Gone Guest',
        'status': 'cancelled',
      },
    ];
    await _openMyEvents(tester, backend);

    await tester.tap(find.text('QR badge'));
    await tester.pumpAndSettle();

    expect(find.text('Your QR badges'), findsOneWidget);
    expect(find.text('Test Attendee'), findsOneWidget);
    expect(find.text('Asha Warrier'), findsOneWidget);
    expect(find.text('Guest of Test Attendee'), findsOneWidget);
    expect(find.text('Gone Guest'), findsNothing);
    expect(find.byType(EntryPassQr), findsNWidgets(2));
  });

  group('the list through sign-in updates', () {
    testWidgets('an update for the same person keeps the list', (tester) async {
      final backend = FakeRegistrationBackend(isFree: true);
      backend.seedRegistration(tokenA, status: 'registered');
      final auth = await _openMyEvents(tester, backend);
      expect(find.text('QR badge'), findsOneWidget);

      // As session renewal or another tab would.
      auth.notifyWithoutChange();
      await settleRequests(tester);

      expect(find.text('No registrations yet'), findsNothing);
      expect(find.text('QR badge'), findsOneWidget);
    });

    testWidgets('a different person gets an empty list, not the last one',
        (tester) async {
      final backend = FakeRegistrationBackend(isFree: true);
      backend.seedRegistration(tokenA, status: 'registered');
      final auth = await _openMyEvents(tester, backend);
      expect(find.text('QR badge'), findsOneWidget);

      await auth.signOut();
      auth.logIn(sessionB);
      await settleRequests(tester);

      expect(find.text('QR badge'), findsNothing);
    });
  });
}
