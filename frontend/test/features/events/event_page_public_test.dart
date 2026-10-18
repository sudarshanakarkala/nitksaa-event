// The event page signed out (public), and the guest ✕ rule.
//
// - Signed out, the page opens and Register reads "Sign in to register",
//   which goes to sign-in and remembers the event for afterwards.
// - Signed out on a full or closed event, the page says so (from the event's
//   own status), with no sign-in button.
// - A guest's ✕ shows until the event starts and is hidden after that, like
//   Unregister.
// - A readable link (/e/<slug>) opens the event page; an unknown one says so.
// - Copy link (no share sheet in tests) and a Markdown description.
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/presentation/screens/event_detail_screen.dart';
import 'package:event_app/features/events/presentation/screens/event_link_screen.dart';
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
  String? initialLocation,
}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: initialLocation ?? '/events/$eventX',
    routes: [
      GoRoute(
        path: AppRoutes.eventLink,
        builder: (context, state) =>
            EventLinkScreen(slug: state.pathParameters['slug'] ?? ''),
      ),
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

  testWidgets('an event image that fails to load leaves no grey box (F9)', (
    tester,
  ) async {
    // Test runs answer every image request with an error.
    final backend = FakeRegistrationBackend(
      isFree: true,
      bannerUrl: 'https://example.invalid/banner.png',
    );
    await _openEventPage(tester, backend, signedIn: false);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.photo), findsNothing);
    expect(find.text('Sign in to register'), findsOneWidget);
  });

  testWidgets('paid, still being confirmed: says so, with no QR and no '
      'Complete payment (ISSUE-010)', (tester) async {
    // The server's eligibility says already_registered for this status.
    final backend = FakeRegistrationBackend()
      ..eligibilityOverride = (status: 'already_registered', message: '');
    backend.seedRegistration(sessionA.accessToken,
        status: 'payment_verification', paid: true);
    await _openEventPage(tester, backend);

    expect(find.text('Payment received, confirming…'), findsOneWidget);
    expect(find.textContaining('You are registered'), findsNothing);
    expect(find.text('View QR badge'), findsNothing);
    expect(find.text('Complete payment'), findsNothing);
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

  group('readable links', () {
    testWidgets('/e/<slug> opens the event page', (tester) async {
      final backend = FakeRegistrationBackend(isFree: true);
      final router = await _openEventPage(
        tester, backend, signedIn: false, initialLocation: '/e/event-$eventX');
      await tester.pumpAndSettle();
      expect(_at(router), '/events/$eventX');
      expect(find.text('Sign in to register'), findsOneWidget);
    });

    testWidgets('an unknown link says so', (tester) async {
      final backend = FakeRegistrationBackend(isFree: true);
      await _openEventPage(
        tester, backend, signedIn: false, initialLocation: '/e/no-such-event');
      await tester.pumpAndSettle();
      expect(find.text('This event isn\'t available'), findsOneWidget);
      expect(find.text('Go to Events'), findsOneWidget);
    });
  });

  testWidgets('Copy link, and the description shown as Markdown', (tester) async {
    final backend = FakeRegistrationBackend(
      isFree: true,
      description: 'A **vegetarian** breakfast.\nSecond line',
    );
    await _openEventPage(tester, backend, signedIn: false);
    await tester.pumpAndSettle();

    expect(find.text('Copy link'), findsOneWidget);
    expect(find.textContaining('**', findRichText: true), findsNothing);
    expect(find.textContaining('vegetarian', findRichText: true), findsOneWidget);
    // A new line as typed stays a new line.
    expect(
      find.textContaining('breakfast.\nSecond line', findRichText: true),
      findsOneWidget,
    );
  });
}
