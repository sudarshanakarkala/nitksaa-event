// The event page signed out (public), and the guest ✕ rule.
//
// - Signed out, the page opens and Register reads "Sign in to register",
//   which goes to sign-in and remembers the event for afterwards.
// - Signed out on a full or closed event, the page says so (from the event's
//   own status), with no sign-in button.
// - A guest's ✕ shows until the event starts and is hidden after that, like
//   Unregister.
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/presentation/screens/event_detail_screen.dart';
import 'package:event_app/routes/app_routes.dart';
import 'package:event_app/routes/return_after_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/auth_isolation_fakes.dart';
import 'support/registration_backend_fake.dart';

Future<GoRouter> _openEventPage(
  WidgetTester tester,
  FakeRegistrationBackend backend, {
  bool signedIn = true,
}) async {
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
        path: AppRoutes.login,
        builder: (context, state) => const Scaffold(body: Text('sign-in page')),
      ),
    ],
  );
  addTearDown(router.dispose);
  final auth = FakeAuthController();
  signedIn ? auth.logIn(sessionA) : auth.restore(null);

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
  return router;
}

String _at(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

/// [token]'s registration with one active guest.
void _seedWithGuest(FakeRegistrationBackend backend) {
  final registration =
      backend.seedRegistration(sessionA.accessToken, status: 'registered');
  registration['guests'] = [
    {
      'registration_id': 9001,
      'name': 'Asha Warrier',
      'status': 'registered',
      'qr_token': 'guest-qr-1',
    },
  ];
}

final _guestX = find.byTooltip('Cancel Asha Warrier');

void main() {
  setUp(ReturnAfterSignIn.take);

  group('signed out', () {
    testWidgets('the page opens with "Sign in to register"', (tester) async {
      final backend = FakeRegistrationBackend(isFree: true);
      final router = await _openEventPage(tester, backend, signedIn: false);

      expect(_at(router), '/events/$eventX');
      expect(find.text('Sign in to register'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Register'), findsNothing);
      // Nothing personal is asked for without a session.
      expect(
        backend.requests.where((r) => r.bearer != null),
        isEmpty,
      );

      await tester.tap(find.text('Sign in to register'));
      await tester.pumpAndSettle();

      expect(_at(router), AppRoutes.login);
      expect(ReturnAfterSignIn.take(), '/events/$eventX');
    });

    for (final (status, message) in [
      ('full', 'Event is at full capacity.'),
      ('closed', 'Registration is closed.'),
    ]) {
      testWidgets('a $status event says so, with no sign-in button', (
        tester,
      ) async {
        final backend =
            FakeRegistrationBackend(isFree: true, registrationStatus: status);
        await _openEventPage(tester, backend, signedIn: false);

        expect(find.text(message), findsOneWidget);
        expect(find.text('Sign in to register'), findsNothing);
      });
    }
  });

  group('guest ✕', () {
    testWidgets('shows before the event starts', (tester) async {
      final backend = FakeRegistrationBackend(isFree: true, maxGuests: 2);
      _seedWithGuest(backend);
      await _openEventPage(tester, backend);

      expect(find.text('Asha Warrier'), findsOneWidget);
      expect(_guestX, findsOneWidget);
    });

    testWidgets('is hidden once the event has started', (tester) async {
      final backend = FakeRegistrationBackend(
        isFree: true,
        maxGuests: 2,
        startDatetime: DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
        endDatetime: DateTime.now()
            .toUtc()
            .add(const Duration(hours: 2))
            .toIso8601String(),
      );
      _seedWithGuest(backend);
      await _openEventPage(tester, backend);

      expect(find.text('Asha Warrier'), findsOneWidget);
      expect(_guestX, findsNothing);
    });
  });
}
