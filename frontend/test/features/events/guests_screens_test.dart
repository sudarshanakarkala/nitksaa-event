// Guests (step 4) on the real event page and registration form. Only the
// HTTP transport is a fake (FakeRegistrationBackend).
//
// - An event without guests shows no GUESTS section.
// - With guests allowed, "Add a guest" adds a name field each (up to the
//   limit), the names go to the server, and the event page then shows each
//   guest with their own QR.
// - On a paid event the total follows the number of people.
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/presentation/screens/event_detail_screen.dart';
import 'package:event_app/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/auth_isolation_fakes.dart';
import 'support/registration_backend_fake.dart';

Future<void> _openEventPage(WidgetTester tester, FakeRegistrationBackend backend) async {
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
        builder: (context, state) => const Scaffold(body: Text('checkout')),
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

Future<void> _openForm(WidgetTester tester) async {
  await tester.tap(find.text('Register'));
  await settleRequests(tester);
  expect(find.text('YOUR DETAILS'), findsOneWidget);
}

final _addGuest = find.byKey(const ValueKey('registration-add-guest'));

void main() {
  testWidgets('no guests allowed: no GUESTS section', (tester) async {
    await _openEventPage(tester, FakeRegistrationBackend(isFree: true));
    await _openForm(tester);

    expect(find.text('GUESTS'), findsNothing);
    expect(_addGuest, findsNothing);
  });

  testWidgets('free event: add two guests, register, each guest has a QR', (tester) async {
    final backend = FakeRegistrationBackend(isFree: true, maxGuests: 2);
    await _openEventPage(tester, backend);
    await _openForm(tester);

    expect(find.text('GUESTS'), findsOneWidget);
    expect(find.text('Add a guest (up to 2)'), findsOneWidget);
    await tester.tap(_addGuest);
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('registration-guest-0')), 'Asha Warrier');
    await tester.tap(_addGuest);
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('registration-guest-1')), 'Kiran Warrier');
    // At the limit: no more "Add a guest".
    expect(_addGuest, findsNothing);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Register').last);
    await settleRequests(tester);

    final request = backend.registerRequests.single.json;
    expect(request['guests'], [
      {'name': 'Asha Warrier'},
      {'name': 'Kiran Warrier'},
    ]);
    expect(find.text('You + 2 guests'), findsOneWidget);
    expect(find.text('Asha Warrier'), findsOneWidget);
    expect(find.text('Kiran Warrier'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'QR'), findsNWidgets(2));
  });

  testWidgets('a guest needs a name', (tester) async {
    final backend = FakeRegistrationBackend(isFree: true, maxGuests: 1);
    await _openEventPage(tester, backend);
    await _openForm(tester);

    await tester.tap(_addGuest);
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Register').last);
    await tester.pump();

    expect(find.text("Please enter the guest's name."), findsOneWidget);
    expect(backend.registerRequests, isEmpty);

    // Removing the empty guest lets the registrant register alone.
    await tester.tap(find.byTooltip('Remove guest'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Register').last);
    await settleRequests(tester);
    expect(backend.registerRequests, hasLength(1));
    expect(backend.registerRequests.single.json.containsKey('guests'), isFalse);
  });

  testWidgets('paid event: the total is price x people', (tester) async {
    final backend = FakeRegistrationBackend(ticketPrice: '500.00', finalAmount: '500.00', maxGuests: 4);
    await _openEventPage(tester, backend);
    await _openForm(tester);

    expect(find.text('₹500'), findsWidgets);
    await tester.tap(_addGuest);
    await tester.pump();
    await tester.tap(_addGuest);
    await tester.pump();
    expect(find.text('3 people × ₹500 = ₹1,500'), findsOneWidget);
    expect(find.text('Continue to payment'), findsOneWidget);
  });
}
