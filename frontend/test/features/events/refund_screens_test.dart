// Tests for ISSUE-005: after a paid registration was cancelled the attendee
// could not see what became of the refund. The app showed one message and
// never called `GET /api/v1/registrations/{registration_id}/refund`.
//
// These tests use the real My Events and event list screens and read what
// went on the wire. Only the HTTP transport is a fake. The provider's own
// rules are in refund_api_test.dart.

import 'dart:async';

import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/presentation/screens/event_list_screen.dart';
import 'package:event_app/features/events/presentation/screens/my_events_screen.dart';
import 'package:event_app/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/auth_isolation_fakes.dart';
import 'support/event_card_menu.dart';
import 'support/registration_backend_fake.dart';

const _viewRefundStatus = 'View refund status';
const _checkRefundStatus = 'Check refund status';
const _pendingMessage =
    'Your registration is cancelled. Your refund is being processed.';
const _processedMessage =
    'Your cancellation is confirmed and the refund has been processed by the '
    'payment provider.';
const _failedMessage =
    'Your registration is cancelled, but the refund could not be completed '
    'automatically. Our team will follow up.';
const _nothingToRefund = 'No payment was taken, so there is nothing to refund.';
const _notFound =
    "We couldn't find this registration. Please refresh and try again.";
const _noConnection =
    'Unable to connect to the server. Check your internet connection and try '
    'again.';
const _couldNotLoad = 'Could not load the refund status. Please try again.';
const _cancelledAndRefunding =
    'Your registration has been cancelled. Your refund has been initiated.';

/// A date and time as the refund view writes it, in whatever time zone the
/// test runs in.
final _dateAndTime = RegExp(r'^\d{1,2} Dec 2098, \d{1,2}:\d{2} [AP]M$');

/// What must never be shown to an attendee.
final _technicalWording = RegExp(
  r'exception|dio|status code|registration_not_found|\b[45]\d\d\b',
  caseSensitive: false,
);

/// The app as these tests run it: its router and who is signed in.
class _App {
  _App(this.router, this.auth);

  final GoRouter router;
  final FakeAuthController auth;
}

/// Starts the app at [location] with user A signed in.
Future<_App> _openApp(
  WidgetTester tester,
  FakeRegistrationBackend backend, {
  String location = AppRoutes.myEvents,
  Size windowSize = const Size(1400, 2400),
}) async {
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
  return _App(router, auth);
}

/// Opens the refund status from the cancelled card on My Events.
Future<void> _viewRefund(WidgetTester tester) async {
  await tester.tap(find.text(_viewRefundStatus));
  await settleRequests(tester);
}

Future<void> _check(WidgetTester tester) async {
  await tester.tap(find.text(_checkRefundStatus));
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

/// Text inside the refund status dialog.
Finder _inDialog(String text) {
  return find.descendant(of: find.byType(AlertDialog), matching: find.text(text));
}

/// Nothing in the dialog offers to try the refund again.
void _expectNoRetry() {
  for (final label in ['Retry', 'Retry refund', 'Try again', _checkRefundStatus]) {
    expect(_inDialog(label), findsNothing);
  }
}

void main() {
  group('ISSUE-005: refund status from a cancelled card on My Events', () {
    testWidgets('Test A: one GET /registrations/{id}/refund with the bearer '
        'token and no body', (tester) async {
      final backend = FakeRegistrationBackend();
      final registration = backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_pending',
      );
      await _openApp(tester, backend);

      await _viewRefund(tester);

      final request = backend.refundStatusRequests.single;
      expect(
        request.line,
        'GET /api/v1/registrations/${registration['registration_id']}/refund',
      );
      expect(request.bearer, 'Bearer $tokenA');
      expect(request.rawBody, isEmpty);
      expect(backend.requests.where((r) => r.method != 'GET'), isEmpty);
    });

    testWidgets('Test B: a pending refund shows "Refund on its way", the '
        "amount, the backend's message and a way to check again", (
      tester,
    ) async {
      final backend = FakeRegistrationBackend(finalAmount: '123.45');
      backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_pending',
      );
      await _openApp(tester, backend);

      await _viewRefund(tester);

      expect(_inDialog('Refund on its way'), findsOneWidget);
      expect(_inDialog('₹123.45'), findsOneWidget);
      expect(_inDialog('Requested on: '), findsOneWidget);
      expect(find.textContaining(_dateAndTime), findsOneWidget);
      expect(_inDialog(_pendingMessage), findsOneWidget);
      expect(_inDialog(_checkRefundStatus), findsOneWidget);
    });

    testWidgets('Test C: "Check refund status" asks again and shows the '
        'refund as processed once the payment provider says so', (
      tester,
    ) async {
      final backend = FakeRegistrationBackend(finalAmount: '1.00');
      backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_pending',
      );
      await _openApp(tester, backend);
      await _viewRefund(tester);
      expect(_inDialog('Refund on its way'), findsOneWidget);
      expect(_inDialog('₹1'), findsOneWidget);

      backend.razorpayNowSays = 'refund_processed';
      await _check(tester);

      expect(backend.refundStatusRequests, hasLength(2));
      expect(_inDialog('Refunded'), findsOneWidget);
      expect(_inDialog('Refund on its way'), findsNothing);
      expect(_inDialog(_processedMessage), findsOneWidget);
      expect(_inDialog(_checkRefundStatus), findsNothing);
    });

    testWidgets('Test D: a processed refund shows "Refunded", the amount and '
        'when, with nothing left to check', (tester) async {
      final backend = FakeRegistrationBackend(finalAmount: '499.00');
      backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_processed',
      );
      await _openApp(tester, backend);

      await _viewRefund(tester);

      expect(_inDialog('Refunded'), findsOneWidget);
      expect(_inDialog('₹499'), findsOneWidget);
      expect(_inDialog('Refunded on: '), findsOneWidget);
      expect(find.textContaining(_dateAndTime), findsOneWidget);
      expect(_inDialog(_processedMessage), findsOneWidget);
      expect(_inDialog(_checkRefundStatus), findsNothing);
    });

    testWidgets('Test E: a failed refund shows "Refund could not be '
        "completed\" and the backend's message, with no retry", (tester) async {
      final backend = FakeRegistrationBackend();
      backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_failed',
      );
      await _openApp(tester, backend);

      await _viewRefund(tester);

      expect(_inDialog('Refund needs attention'), findsOneWidget);
      expect(_inDialog(_failedMessage), findsOneWidget);
      _expectNoRetry();
    });

    testWidgets('Test E2: a delayed refund says it is retrying, with the '
        'references and a way to check again', (tester) async {
      final backend = FakeRegistrationBackend(finalAmount: '100.00');
      final registration = backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_delayed',
      );
      await _openApp(tester, backend);

      await _viewRefund(tester);

      expect(_inDialog('Refund delayed, retrying'), findsOneWidget);
      expect(_inDialog('₹100'), findsOneWidget);
      expect(_inDialog('Requested on: '), findsOneWidget);
      expect(find.textContaining(_dateAndTime), findsOneWidget);
      expect(_inDialog('pay_test${registration['registration_id']}'), findsOneWidget);
      expect(find.byTooltip('Copy Payment reference'), findsOneWidget);
      expect(find.textContaining('retrying automatically'), findsOneWidget);
      expect(_inDialog(_checkRefundStatus), findsOneWidget);
    });

    testWidgets('Test F: a cancelled free registration has no refund action', (
      tester,
    ) async {
      final backend = FakeRegistrationBackend(isFree: true);
      backend.seedRegistration(tokenA, status: 'cancelled');
      await _openApp(tester, backend);

      expect(find.text('Unregistered'), findsOneWidget);
      expect(find.text(_viewRefundStatus), findsNothing);
      expect(backend.refundStatusRequests, isEmpty);
    });

    testWidgets('Test F: a registration whose payment was never made shows '
        '"No refund" when opened', (tester) async {
      final backend = FakeRegistrationBackend();
      // A seat hold that ran out: cancelled, with an order nobody paid.
      backend.seedRegistration(tokenA, status: 'cancelled', unpaidOrder: true);
      await _openApp(tester, backend);

      await _viewRefund(tester);

      expect(_inDialog('No refund'), findsOneWidget);
      expect(_inDialog(_nothingToRefund), findsOneWidget);
      _expectNoRetry();
    });

    testWidgets('a registered or payment-pending registration has no refund '
        'action', (tester) async {
      final backend = FakeRegistrationBackend();
      backend.seedRegistration(tokenA, status: 'payment_failed', unpaidOrder: true);
      backend.seedRegistration(tokenA, status: 'registered', paid: true);
      await _openApp(tester, backend);

      // One card per event (ISSUE-011): the registered one.
      expect(find.text('View Details'), findsOneWidget);
      expect(find.text(_viewRefundStatus), findsNothing);
    });

    testWidgets('Test H: several cancelled paid registrations send no refund '
        'request until one is opened, and then one', (tester) async {
      final backend = FakeRegistrationBackend();
      for (final refund in ['refund_processed', 'refund_failed', 'refund_pending']) {
        backend.seedRegistration(tokenA, status: 'cancelled', refund: refund);
      }
      final newest = backend.registrations[tokenA]!;
      await _openApp(tester, backend);

      // One card per event (ISSUE-011); its refund link is the newest
      // registration's.
      expect(find.text(_viewRefundStatus), findsOneWidget);
      expect(backend.refundStatusRequests, isEmpty);

      await tester.tap(find.text(_viewRefundStatus));
      await settleRequests(tester);

      expect(
        backend.refundStatusRequests.single.path,
        '/api/v1/registrations/${newest['registration_id']}/refund',
      );
      expect(_inDialog('Refund on its way'), findsOneWidget);
    });

    testWidgets('there is no polling: a pending refund left open for five '
        'minutes is asked about once', (tester) async {
      final backend = FakeRegistrationBackend();
      backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_pending',
      );
      await _openApp(tester, backend);
      await _viewRefund(tester);

      backend.razorpayNowSays = 'refund_processed';
      await tester.pump(const Duration(minutes: 5));
      await settleRequests(tester);

      expect(backend.refundStatusRequests, hasLength(1));
      expect(_inDialog('Refund on its way'), findsOneWidget);
    });

    testWidgets('Test K: each "Check refund status" sends one GET, and '
        'nothing else is ever sent', (tester) async {
      final backend = FakeRegistrationBackend();
      backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_pending',
      );
      await _openApp(tester, backend);
      await _viewRefund(tester);
      expect(backend.refundStatusRequests, hasLength(1));

      for (var taps = 1; taps <= 3; taps++) {
        await _check(tester);
        expect(backend.refundStatusRequests, hasLength(1 + taps));
        expect(_inDialog('Refund on its way'), findsOneWidget);
      }

      expect(backend.requests.where((r) => r.method != 'GET'), isEmpty);
      expect(backend.refundsCreated, 0);
    });

    testWidgets('closing the view and opening it again asks again', (
      tester,
    ) async {
      final backend = FakeRegistrationBackend();
      backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_pending',
      );
      await _openApp(tester, backend);
      await _viewRefund(tester);
      await tester.tap(_inDialog('Close'));
      await settleRequests(tester);
      expect(find.byType(AlertDialog), findsNothing);

      backend.razorpayNowSays = 'refund_processed';
      await _viewRefund(tester);

      expect(backend.refundStatusRequests, hasLength(2));
      expect(_inDialog('Refunded'), findsOneWidget);
    });
  });

  group('ISSUE-005: errors loading the refund status', () {
    testWidgets('Test I: 404 registration_not_found', (tester) async {
      final backend = FakeRegistrationBackend();
      backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_pending',
      );
      await _openApp(tester, backend);
      // The registration now belongs to nobody this token can see.
      backend.registrations[tokenB] = backend.registrations.remove(tokenA)!;

      await _viewRefund(tester);

      expect(_inDialog(_notFound), findsOneWidget);
      expect(find.textContaining(_technicalWording), findsNothing);
      expect(_inDialog('Refund on its way'), findsNothing);
    });

    testWidgets('Test I: no connection, and the check works once it is back', (
      tester,
    ) async {
      final backend = FakeRegistrationBackend()..refundStatusRequestsToDrop = 1;
      backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_processed',
      );
      await _openApp(tester, backend);

      await _viewRefund(tester);

      expect(_inDialog(_noConnection), findsOneWidget);
      expect(find.textContaining(_technicalWording), findsNothing);
      expect(_inDialog('Refunded'), findsNothing);

      await _check(tester);

      expect(backend.refundStatusRequests, hasLength(2));
      expect(_inDialog('Refunded'), findsOneWidget);
      expect(_inDialog(_noConnection), findsNothing);
    });

    testWidgets('Test I: a 500 from the backend', (tester) async {
      final backend = FakeRegistrationBackend()..refundStatusServerError = 500;
      backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_pending',
      );
      await _openApp(tester, backend);

      await _viewRefund(tester);

      expect(_inDialog(_couldNotLoad), findsOneWidget);
      expect(find.textContaining(_technicalWording), findsNothing);
      expect(_inDialog(_checkRefundStatus), findsOneWidget);
    });

    testWidgets('a failed check keeps the refund that was already shown', (
      tester,
    ) async {
      final backend = FakeRegistrationBackend(finalAmount: '250.00');
      backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_pending',
      );
      await _openApp(tester, backend);
      await _viewRefund(tester);

      backend.refundStatusRequestsToDrop = 1;
      await _check(tester);

      expect(_inDialog('Refund on its way'), findsOneWidget);
      expect(_inDialog('₹250'), findsOneWidget);
      expect(_inDialog(_noConnection), findsOneWidget);
      expect(_inDialog(_checkRefundStatus), findsOneWidget);
    });
  });

  group('ISSUE-005: right after a paid cancellation', () {
    for (final screen in const [
      (name: 'My Events', location: AppRoutes.myEvents, size: Size(1400, 2400)),
      (
        name: 'the event list',
        location: '${AppRoutes.home}?mine=1',
        size: Size(700, 2400),
      ),
    ]) {
      testWidgets('Test G, from ${screen.name}: the message offers "View '
          'refund", which shows the cancel response without another request', (
        tester,
      ) async {
        final backend = FakeRegistrationBackend(finalAmount: '123.45');
        backend.seedRegistration(tokenA, status: 'registered', paid: true);
        await _openApp(
          tester,
          backend,
          location: screen.location,
          windowSize: screen.size,
        );

        await _unregister(tester);
        expect(backend.cancelRequests, hasLength(1));
        // Were the view to ask the backend, it would now hear "processed".
        backend.razorpayNowSays = 'refund_processed';

        await tester.tap(find.text('View refund'));
        await settleRequests(tester);

        expect(backend.refundStatusRequests, isEmpty);
        expect(_inDialog('Refund on its way'), findsOneWidget);
        expect(_inDialog('₹123.45'), findsOneWidget);
        expect(_inDialog(_pendingMessage), findsOneWidget);

        // From here on it is the same view: checking asks the backend.
        await _check(tester);
        expect(backend.refundStatusRequests, hasLength(1));
        expect(_inDialog('Refunded'), findsOneWidget);
      });

      testWidgets('from ${screen.name}: cancelling a free registration '
          'offers no "View refund"', (tester) async {
        final backend = FakeRegistrationBackend(isFree: true);
        backend.seedRegistration(tokenA, status: 'registered');
        await _openApp(
          tester,
          backend,
          location: screen.location,
          windowSize: screen.size,
        );

        await _unregister(tester);

        expect(find.text('Your registration has been cancelled.'), findsOneWidget);
        expect(find.text('View refund'), findsNothing);
        expect(find.text(_viewRefundStatus), findsNothing);
        expect(backend.refundStatusRequests, isEmpty);
      });

      testWidgets('from ${screen.name}: the message with "View refund" '
          'closes by itself after the usual four seconds', (tester) async {
        final backend = FakeRegistrationBackend();
        backend.seedRegistration(tokenA, status: 'registered', paid: true);
        await _openApp(
          tester,
          backend,
          location: screen.location,
          windowSize: screen.size,
        );

        await _unregister(tester);
        // It has been up for about two seconds by now.
        await tester.pump(const Duration(seconds: 1));
        expect(find.text(_cancelledAndRefunding), findsOneWidget);
        expect(find.text('View refund'), findsOneWidget);

        await tester.pump(const Duration(seconds: 3));
        await settleRequests(tester);

        expect(find.text(_cancelledAndRefunding), findsNothing);
        expect(find.text('View refund'), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(backend.refundStatusRequests, isEmpty);
      });

      testWidgets('from ${screen.name}: pressed before it closes, "View '
          'refund" shows the refund without a request, and the message goes', (
        tester,
      ) async {
        final backend = FakeRegistrationBackend(finalAmount: '123.45');
        backend.seedRegistration(tokenA, status: 'registered', paid: true);
        await _openApp(
          tester,
          backend,
          location: screen.location,
          windowSize: screen.size,
        );

        await _unregister(tester);
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text('View refund'));
        await settleRequests(tester);

        expect(_inDialog('Refund on its way'), findsOneWidget);
        expect(_inDialog('₹123.45'), findsOneWidget);
        expect(backend.refundStatusRequests, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
      });
    }

    testWidgets('once the message has closed, the refund is still reached '
        'from the card on My Events', (tester) async {
      final backend = FakeRegistrationBackend();
      backend.seedRegistration(tokenA, status: 'registered', paid: true);
      await _openApp(tester, backend);
      await _unregister(tester);
      await tester.pump(const Duration(seconds: 4));
      await settleRequests(tester);
      expect(find.byType(SnackBar), findsNothing);

      await _viewRefund(tester);

      expect(backend.refundStatusRequests, hasLength(1));
      expect(_inDialog('Refund on its way'), findsOneWidget);
    });

    testWidgets('after a paid cancellation the card on My Events has "View '
        'refund status"', (tester) async {
      final backend = FakeRegistrationBackend();
      backend.seedRegistration(tokenA, status: 'registered', paid: true);
      await _openApp(tester, backend);
      expect(find.text(_viewRefundStatus), findsNothing);

      await _unregister(tester);

      expect(find.text(_viewRefundStatus), findsOneWidget);
      expect(await cardUnregisterEnabled(tester), isNull);
    });
  });

  group('ISSUE-005: one user never sees another user\'s refund', () {
    testWidgets('Test J: user A has the refund open, logs out, user B logs '
        'in: the view is gone and nothing is asked for with A\'s token', (
      tester,
    ) async {
      final backend = FakeRegistrationBackend(finalAmount: '777.00');
      backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_pending',
      );
      final app = await _openApp(tester, backend);
      await _viewRefund(tester);
      expect(_inDialog('Refund on its way'), findsOneWidget);
      expect(_inDialog('₹777'), findsOneWidget);
      final requestsAsA = backend.requests.length;

      await app.auth.signOut();
      app.auth.logIn(sessionB);
      await settleRequests(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('₹777'), findsNothing);
      expect(find.text('Refund on its way'), findsNothing);
      expect(find.text(_pendingMessage), findsNothing);
      // B has no registrations, so no card and no refund action.
      expect(find.text(_viewRefundStatus), findsNothing);

      final afterSwitch = backend.requests.skip(requestsAsA);
      expect(afterSwitch.where((r) => r.bearer == 'Bearer $tokenA'), isEmpty);
      expect(afterSwitch.where((r) => r.path.endsWith('/refund')), isEmpty);
    });

    testWidgets('Test J: an answer for user A that arrives after the switch '
        'to user B is not shown', (tester) async {
      final backend = FakeRegistrationBackend(finalAmount: '777.00')
        ..heldRefundStatus = Completer<void>();
      backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_processed',
      );
      final app = await _openApp(tester, backend);
      await _viewRefund(tester);
      // A's request is on its way; nothing is shown yet.
      expect(backend.refundStatusRequests, hasLength(1));
      expect(find.text('Refunded'), findsNothing);

      await app.auth.signOut();
      app.auth.logIn(sessionB);
      await settleRequests(tester);
      backend.heldRefundStatus!.complete();
      await settleRequests(tester);

      expect(find.text('Refunded'), findsNothing);
      expect(find.textContaining('₹777'), findsNothing);
      expect(find.text(_processedMessage), findsNothing);
      expect(backend.refundStatusRequests, hasLength(1));
    });
  });
}
