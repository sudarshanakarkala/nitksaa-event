// Regression tests for ISSUE-006: the app offered a "No of passes" choice
// (1 to 4), multiplied the price by it and sent it as `quantity`, but the
// backend makes one registration, holds one seat and charges for one
// registration whatever the app sends.
//
// These tests cover the registration form and the registration request. The
// checkout screen is covered by checkout_single_registration_test.dart, which
// needs a browser.

import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/presentation/providers/event_detail_provider.dart';
import 'package:event_app/features/events/presentation/screens/event_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/auth_isolation_fakes.dart';
import 'support/registration_backend_fake.dart';

const _notesHint = 'Dietary preferences, accessibility needs…';

final _passOrQuantityWording = RegExp(
  r'\bpass(es)?\b|quantity',
  caseSensitive: false,
);

void main() {
  group('ISSUE-006: registration form', () {
    const bothForms = TargetPlatformVariant({
      TargetPlatform.android, // the Material dialog
      TargetPlatform.iOS, // the Cupertino sheet
    });

    /// Opens the event page on a router that has the app's two event routes,
    /// and returns the list that each visit to checkout is added to.
    Future<List<Uri>> pumpEventPage(
      WidgetTester tester,
      FakeRegistrationBackend backend,
    ) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final checkoutVisits = <Uri>[];
      final router = GoRouter(
        initialLocation: '/events/$eventX',
        routes: [
          GoRoute(
            path: '/events/:id',
            builder: (context, state) => const EventDetailScreen(eventId: eventX),
          ),
          GoRoute(
            path: '/events/:id/checkout',
            builder: (context, state) {
              checkoutVisits.add(state.uri);
              return const Scaffold(body: Text('checkout page'));
            },
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
      return checkoutVisits;
    }

    Future<void> openRegistrationForm(WidgetTester tester) async {
      await tester.tap(find.text('Register'));
      await settleRequests(tester);
      expect(find.text('Badge name'), findsOneWidget);
    }

    testWidgets('Test A: the form has no pass count to choose, and '
        'registration goes ahead without one', (tester) async {
      final visits = await pumpEventPage(tester, FakeRegistrationBackend());
      await openRegistrationForm(tester);

      expect(find.text('No of passes'), findsNothing);
      expect(find.textContaining(_passOrQuantityWording), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is DropdownButtonFormField || w is DropdownButton,
        ),
        findsNothing,
      );

      await tester.tap(find.text('Proceed to Checkout'));
      await settleRequests(tester);

      expect(find.text('checkout page'), findsOneWidget);
      expect(visits, hasLength(1));
    }, variant: bothForms);

    testWidgets('Test B: the checkout route carries no quantity, and still '
        'carries the notes', (tester) async {
      final visits = await pumpEventPage(tester, FakeRegistrationBackend());
      await openRegistrationForm(tester);
      await tester.enterText(
        find.widgetWithText(TextField, _notesHint),
        'Vegetarian meal',
      );

      await tester.tap(find.text('Proceed to Checkout'));
      await settleRequests(tester);

      final location = visits.single;
      expect(location.path, '/events/$eventX/checkout');
      expect(location.toString().toLowerCase(), isNot(contains('quantity')));
      // The notes still travel in the URL. Moving them is ISSUE-019.
      expect(location.queryParameters, {'notes': 'Vegetarian meal'});
    }, variant: bothForms);
  });

  group('ISSUE-006: registration request', () {
    /// A signed-in attendee with the event open, as the checkout screen has
    /// it when the attendee confirms.
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
      return notifier;
    }

    test('Test C: the request body is attendee_note and nothing else', () async {
      final backend = FakeRegistrationBackend();
      final notifier = await openEvent(backend);

      expect(await notifier.register(eventX, 'Vegetarian meal'), isTrue);

      final request = backend.registerRequests.single;
      expect(request.json, {'attendee_note': 'Vegetarian meal'});
      expect(request.rawBody, isNot(contains('quantity')));
      expect(request.bearer, 'Bearer $tokenA');
    });

    test('Test C: an empty note is still sent on its own', () async {
      final backend = FakeRegistrationBackend();
      final notifier = await openEvent(backend);

      expect(await notifier.register(eventX, ''), isTrue);

      expect(backend.registerRequests.single.json, {'attendee_note': ''});
    });

    test('Test D: one registration takes one request and one seat', () async {
      final backend = FakeRegistrationBackend();
      final notifier = await openEvent(backend);

      expect(await notifier.register(eventX, ''), isTrue);

      expect(backend.registerRequests, hasLength(1));
      expect(backend.registrations, hasLength(1));
      expect(backend.seatsTaken, 1);
      expect(notifier.state.myRegistration?['status'], 'seat_held');
    });

    test('Test I: a free event is registered with one request and no '
        'payment', () async {
      final backend = FakeRegistrationBackend(isFree: true);
      final notifier = await openEvent(backend);

      expect(await notifier.register(eventX, ''), isTrue);

      expect(backend.registerRequests, hasLength(1));
      expect(backend.registerRequests.single.json, {'attendee_note': ''});
      expect(backend.seatsTaken, 1);
      expect(notifier.state.myRegistration?['status'], 'registered');
      expect(backend.paymentOrderRequests, isEmpty);
    });

    test('Test K: a second registration is refused by the backend and is not '
        'retried', () async {
      final backend = FakeRegistrationBackend();
      final notifier = await openEvent(backend);
      expect(await notifier.register(eventX, ''), isTrue);

      expect(await notifier.register(eventX, ''), isFalse);

      expect(backend.registerRequests, hasLength(2));
      expect(backend.registrations, hasLength(1));
      expect(backend.seatsTaken, 1);
      expect(notifier.state.errorMessage, isNotNull);
    });
  });
}
