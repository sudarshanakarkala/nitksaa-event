// Regression tests for ISSUE-004: "Unregister" sent
// `DELETE /api/v1/events/{event_id}/my-registration`. The backend has no
// handler for it (405), so no registration could be cancelled from the app.
// The real call is `POST /api/v1/registrations/{registration_id}/cancel`.
//
// These tests press the real Unregister buttons on the real screens and read
// what went on the wire. Only the HTTP transport is a fake. The notifier's own
// rules (idempotency key, messages) are in cancellation_api_test.dart.
//
// They also cover what the event page shows once a registration is
// cancelled: the attendee can register again when the backend allows it.

import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/presentation/providers/event_detail_provider.dart';
import 'package:event_app/features/events/presentation/screens/event_detail_screen.dart';
import 'package:event_app/features/events/presentation/screens/event_list_screen.dart';
import 'package:event_app/features/events/presentation/screens/my_events_screen.dart';
import 'package:event_app/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/auth_isolation_fakes.dart';
import 'support/registration_backend_fake.dart';

const _cancelled = 'Your registration has been cancelled.';
const _cancelledAndRefunding =
    'Your registration has been cancelled. Your refund has been initiated.';
const _notCancellable =
    "This registration can't be cancelled while payment is in progress.";
const _notFound =
    "We couldn't find this registration. Please refresh and try again.";
const _noConnection =
    'Unable to connect to the server. Check your internet connection and try '
    'again.';
const _cancelledEarlier = 'You cancelled your earlier registration.';
const _unregisteredBanner = 'Unregistered from this event';

/// A window the event page fits in with the test font.
const _eventPageWindow = Size(800, 3000);

/// A screen with an Unregister button.
///
/// Each has a window size at which its layout has room for the test font,
/// whose letters are much wider than the app's.
enum _Screen {
  /// The My Events page.
  myEvents('My Events', AppRoutes.myEvents, Size(1400, 2400)),

  /// The event list narrowed to "Registered by me", as the account menu's
  /// "My Events" link opens it.
  eventList(
    'the event list "Registered by me" card',
    '${AppRoutes.home}?mine=1',
    Size(700, 2400),
  );

  const _Screen(this.label, this.location, this.windowSize);

  final String label;
  final String location;
  final Size windowSize;
}

/// Stands in for CheckoutScreen, which cannot compile for the Dart VM
/// (ISSUE-016). For a free event it does what that screen does: it registers
/// through the event page's notifier and closes. The real screen is used in
/// cancellation_reregister_checkout_test.dart, in a browser.
class _CheckoutStandIn extends ConsumerWidget {
  const _CheckoutStandIn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async {
            await ref
                .read(eventDetailProvider(eventX).notifier)
                .register(eventX, '');
            if (context.mounted) context.pop();
          },
          child: const Text('Confirm Registration'),
        ),
      ),
    );
  }
}

/// Starts the app on [screen] with user A signed in.
Future<GoRouter> _openApp(
  WidgetTester tester,
  FakeRegistrationBackend backend,
  _Screen screen, {
  Size? windowSize,
}) {
  return _pumpApp(
    tester,
    backend,
    screen.location,
    windowSize ?? screen.windowSize,
  );
}

/// Starts the app on the event page with user A signed in.
Future<GoRouter> _openEventPage(
  WidgetTester tester,
  FakeRegistrationBackend backend,
) {
  return _pumpApp(tester, backend, '/events/$eventX', _eventPageWindow);
}

Future<GoRouter> _pumpApp(
  WidgetTester tester,
  FakeRegistrationBackend backend,
  String location,
  Size windowSize,
) async {
  tester.view.physicalSize = windowSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const EventListScreen(),
      ),
      GoRoute(
        path: AppRoutes.myEvents,
        builder: (context, state) => const MyEventsScreen(),
      ),
      GoRoute(
        path: AppRoutes.eventDetail,
        builder: (context, state) => const EventDetailScreen(eventId: eventX),
      ),
      GoRoute(
        path: AppRoutes.checkout,
        builder: (context, state) => const _CheckoutStandIn(),
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
      child: MaterialApp.router(
        routerConfig: router,
        // In the app every page sits inside AppShell's Scaffold. The iOS
        // event page has no Material of its own to take a text style from.
        builder: (context, child) => Material(child: child),
      ),
    ),
  );
  await settleRequests(tester);
  return router;
}

/// Presses Unregister on the card, then Unregister in the dialog.
Future<void> _unregister(WidgetTester tester) async {
  await tester.tap(find.text('Unregister'));
  await settleRequests(tester);
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Unregister'),
    ),
  );
  await settleRequests(tester);
}

/// The Unregister button on the card: a FilledButton on My Events, a
/// TextButton on the event list.
ButtonStyleButton _unregisterButton(WidgetTester tester) {
  return tester.widget(
    find.ancestor(
      of: find.text('Unregister'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ),
  );
}

/// The screen shows the attendee's registration as it was before the tap:
/// still registered, with a working Unregister button, and no error page.
void _expectStillRegistered(WidgetTester tester) {
  expect(_unregisterButton(tester).onPressed, isNotNull);
  expect(find.text('Registered'), findsOneWidget);
  expect(find.text('Could not load registrations'), findsNothing);
  expect(find.textContaining('Exception'), findsNothing);
  expect(find.textContaining('status code'), findsNothing);
}

/// The screen no longer shows an active registration.
void _expectNotRegistered(WidgetTester tester, _Screen screen) {
  expect(find.text('Unregister'), findsNothing);
  expect(find.text('Registered'), findsNothing);
  switch (screen) {
    case _Screen.myEvents:
      expect(find.text('Unregistered'), findsWidgets);
      expect(find.text('0 active registrations'), findsOneWidget);
    case _Screen.eventList:
      // "Registered by me" is on, and nothing is registered any more.
      expect(find.text('No Events Found'), findsOneWidget);
  }
}

void main() {
  for (final screen in _Screen.values) {
    group('ISSUE-004: Unregister from ${screen.label}', () {
      testWidgets('Tests A, B, K: one POST /registrations/{id}/cancel with '
          'the bearer token and an idempotency key, and no DELETE', (
        tester,
      ) async {
        final backend = FakeRegistrationBackend(isFree: true);
        final registration = backend.seedRegistration(
          tokenA,
          status: 'registered',
        );
        await _openApp(tester, backend, screen);

        await _unregister(tester);

        final cancel = backend.cancelRequests.single;
        expect(
          cancel.line,
          'POST /api/v1/registrations/${registration['registration_id']}/cancel',
        );
        expect(cancel.bearer, 'Bearer $tokenA');
        expect(cancel.json.keys, ['idempotency_key']);
        expect(
          (cancel.json['idempotency_key'] as String).length,
          inInclusiveRange(8, 128),
        );

        expect(backend.requests.where((r) => r.method == 'DELETE'), isEmpty);
        expect(
          backend.requests.where(
            (r) => r.path.contains('my-registration') && r.method != 'GET',
          ),
          isEmpty,
        );
      });

      testWidgets('Test C: with an old cancelled registration and a current '
          'one for the same event, the current one is cancelled', (
        tester,
      ) async {
        final backend = FakeRegistrationBackend(isFree: true);
        final old = backend.seedRegistration(tokenA, status: 'cancelled');
        final current = backend.seedRegistration(tokenA, status: 'registered');
        expect(old['event_id'], current['event_id']);
        await _openApp(tester, backend, screen);

        await _unregister(tester);

        expect(
          backend.cancelRequests.single.path,
          '/api/v1/registrations/${current['registration_id']}/cancel',
        );
        expect(current['status'], 'cancelled');
        expect(find.text(_cancelled), findsOneWidget);
      });

      testWidgets('Test D: a free registration is cancelled, the list is '
          'reloaded and no longer shows it as registered', (tester) async {
        final backend = FakeRegistrationBackend(isFree: true);
        final registration = backend.seedRegistration(
          tokenA,
          status: 'registered',
        );
        await _openApp(tester, backend, screen);
        expect(find.text('Registered'), findsOneWidget);

        await _unregister(tester);

        expect(find.text(_cancelled), findsOneWidget);
        expect(registration['status'], 'cancelled');
        expect(backend.refundsCreated, 0);
        expect(backend.seatsTaken, 0);
        // The list was fetched again after the cancel.
        final lines = backend.requests.map((r) => r.line).toList();
        expect(
          lines.lastIndexOf('GET /api/v1/my/registrations'),
          greaterThan(lines.indexOf(backend.cancelRequests.single.line)),
        );
        _expectNotRegistered(tester, screen);
      });

      testWidgets('Test E: a paid registration is cancelled and the attendee '
          'is told the refund has started', (tester) async {
        final backend = FakeRegistrationBackend();
        final registration = backend.seedRegistration(
          tokenA,
          status: 'registered',
          paid: true,
        );
        await _openApp(tester, backend, screen);

        await _unregister(tester);

        expect(find.text(_cancelledAndRefunding), findsOneWidget);
        expect(registration['status'], 'cancelled');
        expect(backend.refundsCreated, 1);
        expect(
          backend.refunds[registration['registration_id']]!['status'],
          'refund_pending',
        );
        // Until ISSUE-005 the message was the only mention of a refund. It
        // now leads to the refund status (refund_screens_test.dart).
        expect(find.text('View refund'), findsOneWidget);
        _expectNotRegistered(tester, screen);
      });

      testWidgets('Tests F, J: a network failure shows the connection '
          'message and leaves the button usable; the retry carries the same '
          'idempotency key', (tester) async {
        final backend = FakeRegistrationBackend()..cancelRequestsToDrop = 1;
        backend.seedRegistration(tokenA, status: 'registered', paid: true);
        await _openApp(tester, backend, screen);

        await _unregister(tester);

        expect(find.text(_noConnection), findsOneWidget);
        _expectStillRegistered(tester);

        await _unregister(tester);

        expect(find.text(_cancelledAndRefunding), findsOneWidget);
        final keys = backend.cancelRequests
            .map((r) => r.json['idempotency_key'])
            .toList();
        expect(keys, hasLength(2));
        expect(keys.first, keys.last);
        expect(backend.refundsCreated, 1);
        _expectNotRegistered(tester, screen);
      });

      testWidgets('Test G: a registration that is already cancelled on the '
          'backend is reported as cancelled', (tester) async {
        final backend = FakeRegistrationBackend(isFree: true);
        final registration = backend.seedRegistration(
          tokenA,
          status: 'registered',
        );
        await _openApp(tester, backend, screen);
        // Cancelled from another device while this screen was open.
        registration['status'] = 'cancelled';

        await _unregister(tester);

        expect(backend.cancelRequests, hasLength(1));
        expect(find.text(_cancelled), findsOneWidget);
        _expectNotRegistered(tester, screen);
      });

      testWidgets('Test H: 409 registration_not_cancellable shows a plain '
          'message and changes nothing on screen', (tester) async {
        final backend = FakeRegistrationBackend();
        final registration = backend.seedRegistration(
          tokenA,
          status: 'registered',
        );
        await _openApp(tester, backend, screen);
        // The screen still holds 'registered'; the backend has moved on.
        registration['status'] = 'payment_verification';

        await _unregister(tester);

        expect(backend.cancelRequests, hasLength(1));
        expect(find.text(_notCancellable), findsOneWidget);
        expect(registration['status'], 'payment_verification');
        _expectStillRegistered(tester);
      });

      testWidgets('Test I: 404 registration_not_found shows a plain message', (
        tester,
      ) async {
        final backend = FakeRegistrationBackend(isFree: true);
        backend.seedRegistration(tokenA, status: 'registered');
        await _openApp(tester, backend, screen);
        // The registration now belongs to nobody this token can see.
        backend.registrations[tokenB] = backend.registrations.remove(tokenA)!;

        await _unregister(tester);

        expect(backend.cancelRequests, hasLength(1));
        expect(find.text(_notFound), findsOneWidget);
        expect(backend.registrations[tokenB]!['status'], 'registered');
        _expectStillRegistered(tester);
      });
    });
  }

  group('ISSUE-004: the event page after a cancellation', () {
    const bothForms = TargetPlatformVariant({
      TargetPlatform.android, // the Material page and dialog
      TargetPlatform.iOS, // the Cupertino button and sheet
    });

    testWidgets('Test L: opening the event again shows the attendee as not '
        'registered, with Register available', (tester) async {
      final backend = FakeRegistrationBackend(isFree: true);
      backend.seedRegistration(tokenA, status: 'registered');
      final router = await _openApp(
        tester,
        backend,
        _Screen.myEvents,
        windowSize: _eventPageWindow,
      );
      int myRegistrationFetches() => backend
          .requestsTo('GET', '/api/v1/events/$eventX/my-registration')
          .length;

      await tester.tap(find.text('View Details'));
      await settleRequests(tester);
      expect(find.text('Registered Successfully'), findsOneWidget);
      expect(find.textContaining('Badge #'), findsOneWidget);
      expect(find.text('Register'), findsNothing);
      expect(myRegistrationFetches(), 1);

      router.pop();
      await settleRequests(tester);
      await _unregister(tester);
      expect(find.text(_cancelled), findsOneWidget);

      await tester.tap(find.text('View Details'));
      await settleRequests(tester);

      // The page asked again instead of showing what it had.
      expect(myRegistrationFetches(), 2);
      expect(find.text('Registered Successfully'), findsNothing);
      expect(find.textContaining('Badge #'), findsNothing);
      expect(find.text('View QR badge'), findsNothing);
      // The backend says the attendee may register again.
      expect(find.text(_cancelledEarlier), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
      expect(find.text(_unregisteredBanner), findsNothing);
    });

    testWidgets('cancelled and eligible: Register is shown, and registering '
        'again makes a new registration', (tester) async {
      final backend = FakeRegistrationBackend(isFree: true);
      final old = backend.seedRegistration(tokenA, status: 'cancelled');
      await _openEventPage(tester, backend);

      expect(find.text(_cancelledEarlier), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
      expect(find.text(_unregisteredBanner), findsNothing);
      expect(find.text('Registered Successfully'), findsNothing);

      await tester.tap(find.text('Register'));
      await settleRequests(tester);
      expect(find.text('Badge name'), findsOneWidget);
      await tester.tap(find.text('Proceed to Checkout'));
      await settleRequests(tester);
      await tester.tap(find.text('Confirm Registration'));
      await settleRequests(tester);

      expect(backend.registerRequests, hasLength(1));
      final current = backend.registrations[tokenA]!;
      expect(current['status'], 'registered');
      expect(current['registration_id'], isNot(old['registration_id']));
      // The cancelled registration is history; it was not brought back.
      expect(backend.earlierRegistrations[tokenA], [old]);
      expect(old['status'], 'cancelled');
      expect(backend.seatsTaken, 1);

      expect(find.text('Registered Successfully'), findsOneWidget);
      expect(
        find.text('Badge #: ${current['registration_number']}'),
        findsOneWidget,
      );
      expect(find.text(_cancelledEarlier), findsNothing);
      expect(find.text('Register'), findsNothing);
    }, variant: bothForms);

    for (final refusal in const [
      (status: 'ineligible', message: 'Alumni account is not active.'),
      (status: 'full', message: 'Event is at full capacity.'),
      (status: 'closed', message: 'Registration is closed.'),
      (status: 'not_open_yet', message: 'Registration has not opened yet.'),
    ]) {
      testWidgets('cancelled and ${refusal.status}: no Register button, and '
          'the page is as it was before', (tester) async {
        final backend = FakeRegistrationBackend(isFree: true)
          ..eligibilityOverride = refusal;
        backend.seedRegistration(tokenA, status: 'cancelled');
        await _openEventPage(tester, backend);

        expect(find.text('Register'), findsNothing);
        expect(find.text(_cancelledEarlier), findsNothing);
        expect(find.text(_unregisteredBanner), findsOneWidget);
      }, variant: bothForms);
    }

    testWidgets('cancelled and eligibility unknown: no Register button', (
      tester,
    ) async {
      final backend = FakeRegistrationBackend(isFree: true)
        ..eligibilityFails = true;
      backend.seedRegistration(tokenA, status: 'cancelled');
      await _openEventPage(tester, backend);

      expect(find.text('Register'), findsNothing);
      expect(find.text(_cancelledEarlier), findsNothing);
      expect(find.text(_unregisteredBanner), findsOneWidget);
    });

    testWidgets('never registered: the Register button has no note about a '
        'cancellation', (tester) async {
      await _openEventPage(tester, FakeRegistrationBackend(isFree: true));

      expect(find.text('Register'), findsOneWidget);
      expect(find.text(_cancelledEarlier), findsNothing);
    });
  });
}
