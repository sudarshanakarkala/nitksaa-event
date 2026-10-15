// Regression tests for ISSUE-018: attendees saw backend codes and Dio's own
// text ("Could not register: registration closed.", "DioException
// [connection error]: …") instead of plain words.
//
// The codes the backend sends on the attendee's paths, the register call as
// the event page and checkout make it, and the two lists that load on
// opening. Checkout's payment errors are in checkout_errors_test.dart (it
// runs in a browser). Unregister's messages are ISSUE-004's
// (cancellation_screens_test.dart) and sign-in's are ISSUE-003's
// (test/features/auth/).

import 'package:dio/dio.dart';
import 'package:event_app/core/errors/api_error_message.dart';
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/presentation/providers/event_detail_provider.dart';
import 'package:event_app/features/events/presentation/screens/event_list_screen.dart';
import 'package:event_app/features/events/presentation/screens/my_events_screen.dart';
import 'package:event_app/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/auth_isolation_fakes.dart';
import 'support/registration_backend_fake.dart';

const _phone = '+91 98450 12345';
const _noConnection =
    'Could not reach the server. Check your connection and try again.';
const _sessionExpired = 'Your session has expired. Please sign in again.';

/// What the attendee must never see: Dio's text, a backend code, a status.
final _technical = RegExp(
  r'DioException|XMLHttpRequest|Exception|HTTP \d|[a-z]+_[a-z_]+',
);

final _request = RequestOptions(path: '/x');

DioException _refusal(int status, String detail) => DioException(
      requestOptions: _request,
      response: Response<Object?>(
        requestOptions: _request,
        statusCode: status,
        data: {'detail': detail},
      ),
      type: DioExceptionType.badResponse,
    );

void main() {
  group('ISSUE-018: the codes on the attendee paths are plain words', () {
    const expected = <String, (int, String)>{
      // Registering.
      'already_registered': (409, 'You\'re already registered for this event.'),
      'event_full': (409, 'The event is full.'),
      'registration_closed': (409, 'Registration for this event has closed.'),
      'registration_not_open_yet':
          (409, 'Registration for this event hasn\'t opened yet.'),
      'payment_not_configured':
          (409, 'Payment isn\'t set up for this event yet. Please try again later.'),
      // Paying.
      'payment_attempt_active': (
        409,
        'A payment for this registration is already in progress. Please wait '
            'a few minutes and try again.',
      ),
      'seat_hold_expired':
          (409, 'The time to pay for your seat ran out. Please register again.'),
      'payment_gateway_unavailable': (
        503,
        'The payment service isn\'t responding. Please try again in a few '
            'minutes.',
      ),
      // Signed-in session.
      'invalid_or_expired_token': (401, _sessionExpired),
      'invalid_token': (401, _sessionExpired),
      'firebase_token_expired': (401, _sessionExpired),
      'invalid_firebase_token': (401, _sessionExpired),
      'Not authenticated': (403, _sessionExpired),
    };
    for (final MapEntry(key: code, value: (status, message)) in expected.entries) {
      test('$status $code', () {
        expect(apiErrorMessage(_refusal(status, code), action: 'register'), message);
      });
    }

    // Every code the backend can send while registering
    // (registration_service.py), paying (payment_service.py) or with a
    // session it does not accept (middleware/auth.py).
    const attendeeCodes = [
      'already_registered', 'event_full', 'not_enough_seats',
      'registration_closed', 'registration_not_open_yet', 'event_not_published',
      'event_not_found',
      'payment_not_configured', 'too_many_guests', 'name_required',
      'phone_required', 'phone_invalid', 'guest_name_required',
      'registration_not_found', 'payment_attempt_active',
      'payment_order_creation_conflict', 'payment_verification_in_progress',
      'payment_already_completed', 'seat_hold_expired', 'payment_order_expired',
      'registration_not_payable', 'payment_order_not_payable',
      'payment_gateway_error', 'payment_gateway_unavailable',
      'checkout_signature_invalid', 'checkout_order_mismatch',
      'checkout_amount_mismatch', 'invalid_or_expired_token', 'invalid_token',
      'firebase_token_expired', 'invalid_firebase_token', 'account_suspended',
    ];
    for (final code in attendeeCodes) {
      test('$code: no code, no "Could not …: <code>"', () {
        final message =
            apiErrorMessage(_refusal(409, code), action: 'complete the payment');
        expect(message, isNot(contains(code)));
        // Not the fallback for an unknown code: "Could not …: <code>."
        expect(message, isNot(startsWith('Could not complete the payment:')));
        expect(message, isNot(matches(_technical)));
      });
    }
  });

  group('ISSUE-018: registering', () {
    /// A signed-in attendee with the event open and the form filled in, as
    /// the event page (free) and checkout (paid) have it.
    Future<EventDetailNotifier> openEvent(FakeRegistrationBackend backend) async {
      final auth = FakeAuthController()..logIn(sessionA);
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          eventsRepositoryProvider.overrideWithValue(backend.repository),
        ],
      );
      addTearDown(container.dispose);
      container.listen(eventDetailProvider(eventX), (_, _) {});
      final notifier = container.read(eventDetailProvider(eventX).notifier);
      await notifier.fetchEventDetails(eventX);
      notifier.setRegistrationDraft(const RegistrationDraft(phone: _phone));
      return notifier;
    }

    test('already registered (from another tab)', () async {
      final backend = FakeRegistrationBackend(isFree: true);
      final notifier = await openEvent(backend);
      backend.seedRegistration(tokenA, status: 'registered');

      expect(await notifier.register(eventX), isFalse);
      expect(notifier.state.errorMessage,
          'You\'re already registered for this event.');
    });

    const refusals = <String, (int, String?, String)>{
      'registration closed': (409, 'registration_closed',
          'Registration for this event has closed.'),
      'event full': (409, 'event_full', 'The event is full.'),
      'session expired': (401, 'invalid_or_expired_token', _sessionExpired),
      'no network': (0, null, _noConnection),
    };
    for (final MapEntry(key: label, value: (status, detail, message))
        in refusals.entries) {
      test(label, () async {
        final backend = FakeRegistrationBackend(isFree: true);
        final notifier = await openEvent(backend);
        backend.failures['POST /api/v1/events/$eventX/register'] =
            (status: status, detail: detail);

        expect(await notifier.register(eventX), isFalse);
        expect(notifier.state.errorMessage, message);
        expect(notifier.state.errorMessage, isNot(matches(_technical)));
      });
    }
  });

  group('ISSUE-018: lists that fail to load', () {
    Future<void> openApp(
      WidgetTester tester,
      FakeRegistrationBackend backend,
      String location,
    ) async {
      tester.view.physicalSize = const Size(1400, 2400);
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
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => Material(child: child),
          ),
        ),
      );
      await settleRequests(tester);
    }

    testWidgets('no network: the event list says so in plain words', (
      tester,
    ) async {
      final backend = FakeRegistrationBackend()
        ..failures[r'^GET /api/v1/events/public$'] = (status: 0, detail: null);
      await openApp(tester, backend, AppRoutes.home);

      expect(find.text('Couldn\'t load events'), findsOneWidget);
      expect(find.text(_noConnection), findsOneWidget);
      expect(find.textContaining(_technical), findsNothing);
    });

    testWidgets('no network: My Events says so in plain words', (tester) async {
      final backend = FakeRegistrationBackend()
        ..failures['GET /api/v1/my/registrations'] = (status: 0, detail: null);
      await openApp(tester, backend, AppRoutes.myEvents);

      expect(find.text('Could not load your registrations'), findsOneWidget);
      expect(find.text(_noConnection), findsOneWidget);
      expect(find.textContaining(_technical), findsNothing);
    });

    testWidgets('session expired: My Events says to sign in again', (
      tester,
    ) async {
      final backend = FakeRegistrationBackend()
        ..failures['GET /api/v1/my/registrations'] =
            (status: 401, detail: 'invalid_or_expired_token');
      await openApp(tester, backend, AppRoutes.myEvents);

      expect(find.text(_sessionExpired), findsOneWidget);
      expect(find.textContaining(_technical), findsNothing);
    });
  });
}
