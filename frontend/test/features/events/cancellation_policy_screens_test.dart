// Regression tests for ISSUE-012 on the screens: Unregister is offered on
// an active registration until the event starts, whether or not the event's
// registration window is still open, on every card that offers it.
//
// The real screens against a fake HTTP transport, as in
// cancellation_screens_test.dart. The rule itself, at a fixed time, is in
// cancellation_policy_test.dart. Here the event times are hours or days from
// the real clock, so a slow run cannot cross them.

import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/presentation/screens/event_list_screen.dart';
import 'package:event_app/features/events/presentation/screens/my_events_screen.dart';
import 'package:event_app/routes/app_routes.dart';
import 'package:event_app/shared/widgets/quick_filter_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/auth_isolation_fakes.dart';
import 'support/event_card_menu.dart';
import 'support/registration_backend_fake.dart';

const _title = 'Annual Alumni Meet';
const _cancelled = 'Your registration has been cancelled.';
const _cancelledAndRefunding =
    'Your registration has been cancelled. Your refund has been initiated.';
const _notCancellable =
    "This registration can't be cancelled while payment is in progress.";

/// A screen with an Unregister button.
enum _Screen {
  /// The My Events page.
  myEvents('My Events', AppRoutes.myEvents, Size(1400, 2400)),

  /// The event list narrowed to "Registered by me" (`/home?mine=1`).
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

/// [fromNow] from the real clock, as the backend sends it.
String _at(Duration fromNow) =>
    DateTime.now().toUtc().add(fromNow).toIso8601String();

/// An event that started an hour ago and ends in two hours.
FakeRegistrationBackend _startedEvent({String registrationStatus = 'open'}) =>
    FakeRegistrationBackend(
      isFree: true,
      registrationStatus: registrationStatus,
      startDatetime: _at(const Duration(hours: -1)),
      endDatetime: _at(const Duration(hours: 2)),
    );

/// An event that ended three days ago.
FakeRegistrationBackend _endedEvent({String registrationStatus = 'closed'}) =>
    FakeRegistrationBackend(
      isFree: true,
      registrationStatus: registrationStatus,
      startDatetime: _at(const Duration(days: -3)),
      endDatetime: _at(const Duration(days: -3, hours: 3)),
    );

/// Starts the app at [location] (default: the screen's own) with user A
/// signed in.
Future<void> _openApp(
  WidgetTester tester,
  FakeRegistrationBackend backend,
  _Screen screen, {
  String? location,
}) async {
  tester.view.physicalSize = screen.windowSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: location ?? screen.location,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const EventListScreen(),
      ),
      GoRoute(
        path: AppRoutes.myEvents,
        builder: (context, state) => const MyEventsScreen(),
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
        // In the app every page sits inside AppShell's Scaffold.
        builder: (context, child) => Material(child: child),
      ),
    ),
  );
  await settleRequests(tester);
}

/// Presses Unregister in the card's ⋯ menu, then Unregister in the dialog.
Future<void> _unregister(WidgetTester tester) async {
  await tapCardUnregister(tester);
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Unregister'),
    ),
  );
  await settleRequests(tester);
}

/// The event's card is on screen, without Unregister in its ⋯ menu.
Future<void> _expectCardWithoutUnregister(WidgetTester tester) async {
  expect(find.text(_title), findsWidgets);
  expect(await cardUnregisterEnabled(tester), isNull);
}

void main() {
  for (final screen in _Screen.values) {
    group('ISSUE-012: Unregister on ${screen.label}', () {
      testWidgets('Test A: registration open, event ahead: Unregister is '
          'offered and sends POST /registrations/{id}/cancel', (tester) async {
        final backend = FakeRegistrationBackend(isFree: true);
        final registration = backend.seedRegistration(
          tokenA,
          status: 'registered',
        );
        await _openApp(tester, backend, screen);
        expect(await cardUnregisterEnabled(tester), isTrue);

        await _unregister(tester);

        expect(
          backend.cancelRequests.single.line,
          'POST /api/v1/registrations/${registration['registration_id']}/cancel',
        );
        expect(find.text(_cancelled), findsOneWidget);
        expect(registration['status'], 'cancelled');
      });

      testWidgets('Test B: registration closed, event ahead: Unregister is '
          'offered and works', (tester) async {
        final backend = FakeRegistrationBackend(
          isFree: true,
          registrationStatus: 'closed',
        );
        final registration = backend.seedRegistration(
          tokenA,
          status: 'registered',
        );
        await _openApp(tester, backend, screen);
        expect(await cardUnregisterEnabled(tester), isTrue);

        await _unregister(tester);

        expect(
          backend.cancelRequests.single.line,
          'POST /api/v1/registrations/${registration['registration_id']}/cancel',
        );
        expect(find.text(_cancelled), findsOneWidget);
        expect(registration['status'], 'cancelled');
      });

      testWidgets('Test B: registration closed, paid: Unregister starts the '
          'refund (refund_pending)', (tester) async {
        final backend = FakeRegistrationBackend(registrationStatus: 'closed');
        final registration = backend.seedRegistration(
          tokenA,
          status: 'registered',
          paid: true,
        );
        await _openApp(tester, backend, screen);

        await _unregister(tester);

        expect(backend.cancelRequests, hasLength(1));
        expect(find.text(_cancelledAndRefunding), findsOneWidget);
        expect(find.text('View refund'), findsOneWidget);
        expect(registration['status'], 'cancelled');
        expect(backend.refundsCreated, 1);
        expect(
          backend.refunds[registration['registration_id']]!['status'],
          'refund_pending',
        );
      });

      for (final window in const ['open', 'closed']) {
        testWidgets('Test C: the event has started (registration $window): '
            'no Unregister', (tester) async {
          final backend = _startedEvent(registrationStatus: window);
          backend.seedRegistration(tokenA, status: 'registered');
          await _openApp(tester, backend, screen);

          await _expectCardWithoutUnregister(tester);
          expect(find.text('Registered'), findsOneWidget);
          expect(backend.cancelRequests, isEmpty);
        });

        testWidgets('Test D: the event has ended (registration $window): no '
            'Unregister', (tester) async {
          final backend = _endedEvent(registrationStatus: window);
          backend.seedRegistration(tokenA, status: 'registered');
          await _openApp(tester, backend, screen);
          if (screen == _Screen.eventList) {
            // The list opens on Upcoming; an ended event is under Past.
            await tester.tap(find.widgetWithText(QuickFilterPill, 'Past'));
            await settleRequests(tester);
          }

          await _expectCardWithoutUnregister(tester);
          expect(backend.cancelRequests, isEmpty);
        });
      }

      for (final status in const ['cancelled', 'seat_held', 'payment_failed']) {
        testWidgets('Test E: a $status registration: no Unregister', (
          tester,
        ) async {
          final backend = FakeRegistrationBackend();
          backend.seedRegistration(tokenA, status: status);
          // "Registered by me" lists active registrations only, so the event
          // list is opened unfiltered.
          await _openApp(
            tester,
            backend,
            screen,
            location: screen == _Screen.eventList ? AppRoutes.home : null,
          );

          await _expectCardWithoutUnregister(tester);
          expect(backend.cancelRequests, isEmpty);
        });
      }

      testWidgets('Test G: registration closed, the backend refuses (409 '
          'registration_not_cancellable): a plain message, the card stays as '
          'it was', (tester) async {
        final backend = FakeRegistrationBackend(registrationStatus: 'closed');
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
        expect(find.textContaining('registration_not_cancellable'), findsNothing);
        expect(find.textContaining('409'), findsNothing);
        expect(find.textContaining('Exception'), findsNothing);
        expect(await cardUnregisterEnabled(tester), isTrue);
        expect(find.text('Registered'), findsOneWidget);
      });
    });
  }
}
