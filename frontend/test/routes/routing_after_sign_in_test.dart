// Regression tests for two beta findings on ISSUE-021 (test/evening-batch,
// 2026-10-15):
//
// - 021-8: signed out, an event card on Events opened the sign-in page
//   (pushed, with a back arrow, the address still #/home); after signing in
//   it said "Signed in." and stayed there. (Since #64 the event page is
//   public; its "Sign in to register" must still come back to it.)
// - Right after signing in, My Events sometimes said "No registrations yet"
//   until a reload.
//
// The real Events and My Events screens, the real guard, and the fake
// backend; the sign-in page is a stand-in that, like the real one, does not
// navigate by itself.

import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/presentation/screens/event_list_screen.dart';
import 'package:event_app/features/events/presentation/screens/my_events_screen.dart';
import 'package:event_app/routes/app_routes.dart';
import 'package:event_app/routes/return_after_sign_in.dart';
import 'package:event_app/routes/route_guards.dart';
import 'package:event_app/routes/route_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../features/events/support/auth_isolation_fakes.dart';
import '../features/events/support/registration_backend_fake.dart';

const _title = 'Annual Alumni Meet';

Future<GoRouter> _open(
  WidgetTester tester,
  FakeAuthController auth,
  FakeRegistrationBackend backend,
  String location,
) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: location,
    refreshListenable: auth,
    redirect: (context, state) => RouteGuards.redirectFor(auth, state.uri),
    errorBuilder: (context, state) => const NotFoundPage(),
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const Scaffold(body: Text('sign-in page')),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const EventListScreen(),
      ),
      GoRoute(
        path: AppRoutes.myEvents,
        builder: (_, _) => const MyEventsScreen(),
      ),
      GoRoute(
        path: AppRoutes.eventDetail,
        builder: (_, state) =>
            Scaffold(body: Text('event ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
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
  return router;
}

void main() {
  setUp(ReturnAfterSignIn.take);

  testWidgets('021-8: signed out, an event card opens the event (public), '
      'and "Sign in to register" comes back to it', (tester) async {
    final auth = FakeAuthController()..restore(null);
    final backend = FakeRegistrationBackend(isFree: true);
    final router = await _open(tester, auth, backend, AppRoutes.home);

    await tester.tap(find.text(_title).first);
    await settleRequests(tester);
    // The event page is public: no sign-in on the way.
    expect(find.text('sign-in page'), findsNothing);
    expect(find.text('event $eventX'), findsOneWidget);

    // What "Sign in to register" does (event_page_public_test.dart taps it).
    ReturnAfterSignIn.save('/events/$eventX');
    router.go(AppRoutes.login);
    await settleRequests(tester);
    expect(find.text('sign-in page'), findsOneWidget);

    auth.logIn(sessionA);
    await settleRequests(tester);

    expect(find.text('sign-in page'), findsNothing);
    expect(find.text('event $eventX'), findsOneWidget);
  });

  test('signed in with a page waiting: the guard sends it from whichever '
      'page the router re-checks, once', () {
    final auth = FakeAuthController()..restore(sessionA);
    ReturnAfterSignIn.save('/events/$eventX');
    expect(RouteGuards.redirectFor(auth, Uri.parse(AppRoutes.home)),
        '/events/$eventX');
    // Used once: the next check stays where it is.
    expect(RouteGuards.redirectFor(auth, Uri.parse(AppRoutes.home)), isNull);
    // Already on that page: nothing to do.
    ReturnAfterSignIn.save('/events/$eventX');
    expect(RouteGuards.redirectFor(auth, Uri.parse('/events/$eventX')), isNull);
    expect(ReturnAfterSignIn.isPending, isFalse);
  });

  testWidgets('/my-events → sign-in → My Events lists the registration, '
      'without a reload', (tester) async {
    final auth = FakeAuthController()..restore(null);
    final backend = FakeRegistrationBackend(isFree: true);
    backend.seedRegistration(tokenA, status: 'registered');
    final router = await _open(tester, auth, backend, AppRoutes.myEvents);
    expect(find.text('sign-in page'), findsOneWidget);

    auth.logIn(sessionA);
    await settleRequests(tester);

    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.myEvents);
    expect(find.text('No registrations yet'), findsNothing);
    expect(find.text(_title), findsWidgets);
    expect(find.text('Registered'), findsOneWidget);
  });
}
