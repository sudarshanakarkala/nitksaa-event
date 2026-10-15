// Regression tests for ISSUE-021: signed-out access was inconsistent. My
// Events showed its own "Sign in" box instead of sending people to sign-in;
// pages that did send them there forgot the page; a refresh landed on
// Events; signing out went to the login page; a non-admin at /admin was sent
// to Events without a word; and an unknown address showed the router's own
// error.
//
// The real RouteGuards, return-after-sign-in, not-found and not-admin pages
// and SiteHeader, in a router built like AppRouter's around a fake sign-in.
// AppRouter itself, the splash and the login screen use the app's one
// AuthController, which cannot run under `flutter test`; what they do is
// checked in their source, in routing_source_test.dart.

import 'package:event_app/features/admin/admin_tabs.dart';
import 'package:event_app/features/admin/data/actions_api.dart';
import 'package:event_app/features/auth/domain/admin_access.dart';
import 'package:event_app/features/auth/domain/auth_session.dart';
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/routes/app_routes.dart';
import 'package:event_app/routes/return_after_sign_in.dart';
import 'package:event_app/routes/route_guards.dart';
import 'package:event_app/routes/route_pages.dart';
import 'package:event_app/shared/widgets/site_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../features/events/support/auth_isolation_fakes.dart';

final _admin = sessionA.copyWith(access: const AdminAccess(isAdmin: true));

FakeAuthController _signedOut() => FakeAuthController()..restore(null);

FakeAuthController _signedIn([AuthSession session = sessionA]) =>
    FakeAuthController()..restore(session);

String? _guard(FakeAuthController auth, String location) =>
    RouteGuards.redirectFor(auth, Uri.parse(location));

/// A page in the test router: its name, to find on screen.
Widget _page(String name) => Center(child: Text(name));

/// A router built like AppRouter's: the real guard and pages, with the
/// attendee pages inside a shell that has the real header.
GoRouter _router(FakeAuthController auth, String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: auth,
    redirect: (context, state) => RouteGuards.redirectFor(auth, state.uri),
    errorBuilder: (context, state) => const NotFoundPage(),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => _page('splash')),
      GoRoute(path: AppRoutes.login, builder: (_, _) => _page('sign-in page')),
      ShellRoute(
        builder: (context, state, child) => Scaffold(
          body: Column(
            children: [
              const SiteHeader(showThemeToggle: false),
              Expanded(child: child),
            ],
          ),
        ),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (_, _) => _page('events page'),
          ),
          GoRoute(
            path: AppRoutes.myEvents,
            builder: (_, _) => _page('my events page'),
          ),
          GoRoute(
            path: AppRoutes.admin,
            redirect: (_, _) =>
                '${AdminTab.landing.path}?${AdminTab.landingQuery}',
          ),
          GoRoute(
            path: AppRoutes.adminTab,
            builder: (_, state) =>
                _page('admin ${state.pathParameters['tab']} tab'),
          ),
          GoRoute(
            path: AppRoutes.eventDetail,
            builder: (_, state) => _page('event ${state.pathParameters['id']}'),
          ),
          GoRoute(
            path: AppRoutes.checkout,
            builder: (_, state) =>
                _page('checkout ${state.pathParameters['id']}'),
          ),
          GoRoute(
            path: AppRoutes.checkIn,
            builder: (_, _) => _page('check-in page'),
          ),
          GoRoute(
            path: AppRoutes.privacy,
            builder: (_, _) => _page('privacy page'),
          ),
          GoRoute(
            path: AppRoutes.notAdmin,
            builder: (_, _) => const NotAdminPage(),
          ),
        ],
      ),
    ],
  );
}

Future<GoRouter> _open(
  WidgetTester tester,
  FakeAuthController auth,
  String location,
) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = _router(auth, location);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth),
        // The admin header's badge; nothing goes to a server here.
        pendingCountProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

String _at(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  // Nothing remembered from one test leaks into the next.
  setUp(ReturnAfterSignIn.take);

  group('ISSUE-021: signed out, a page that needs sign-in', () {
    for (final page in [
      AppRoutes.myEvents,
      '/events/$eventX',
      '/events/$eventX/checkout',
      '/admin',
      '/admin/payments',
      '/admin/registrations?event=$eventX',
    ]) {
      test('$page: to sign-in, and remembered', () {
        expect(_guard(_signedOut(), page), AppRoutes.login);
        expect(ReturnAfterSignIn.take(), page);
      });
    }

    testWidgets('/my-events: sign-in, then back to My Events', (tester) async {
      final auth = _signedOut();
      final router = await _open(tester, auth, AppRoutes.myEvents);
      expect(_at(router), AppRoutes.login);
      expect(find.text('sign-in page'), findsOneWidget);

      auth.logIn(sessionA);
      await tester.pumpAndSettle();

      expect(_at(router), AppRoutes.myEvents);
      expect(find.text('my events page'), findsOneWidget);
    });

    testWidgets('an event page: sign-in, then back to the event', (
      tester,
    ) async {
      final auth = _signedOut();
      final router = await _open(tester, auth, '/events/$eventX');
      expect(_at(router), AppRoutes.login);

      auth.logIn(sessionA);
      await tester.pumpAndSettle();

      expect(_at(router), '/events/$eventX');
    });

    testWidgets('/admin: sign-in, then an admin lands on Admin', (
      tester,
    ) async {
      final auth = _signedOut();
      final router = await _open(tester, auth, '/admin/payments');
      expect(_at(router), AppRoutes.login);

      auth.logIn(_admin);
      await tester.pumpAndSettle();

      expect(_at(router), '/admin/payments');
      expect(find.text('admin payments tab'), findsOneWidget);
    });

    testWidgets('/admin: sign-in, then a non-admin is told plainly', (
      tester,
    ) async {
      final auth = _signedOut();
      final router = await _open(tester, auth, AppRoutes.admin);
      expect(_at(router), AppRoutes.login);

      auth.logIn(sessionA);
      await tester.pumpAndSettle();

      expect(_at(router), AppRoutes.notAdmin);
      expect(find.text('Not an admin'), findsOneWidget);
      await tester.tap(find.text('Go to Events'));
      await tester.pumpAndSettle();
      expect(_at(router), AppRoutes.home);
    });
  });

  group('ISSUE-021: pages that stay as they are', () {
    for (final page in [
      AppRoutes.home,
      '${AppRoutes.home}?mine=1',
      AppRoutes.privacy,
      AppRoutes.terms,
      AppRoutes.refund,
      AppRoutes.disclaimer,
      AppRoutes.feedback,
    ]) {
      test('$page is public', () {
        expect(_guard(_signedOut(), page), isNull);
        expect(ReturnAfterSignIn.take(), isNull);
      });
    }

    test('a check-in link stays on its page, signed out or checking', () {
      expect(_guard(_signedOut(), '/checkin/$eventX/qr-1'), isNull);
      expect(_guard(FakeAuthController(), '/checkin/$eventX/qr-1'), isNull);
    });

    test('signed in: the protected pages open', () {
      for (final page in [
        AppRoutes.myEvents,
        '/events/$eventX',
        '/events/$eventX/checkout',
      ]) {
        expect(_guard(_signedIn(), page), isNull, reason: page);
      }
    });

    test('signed in at sign-in: back to the remembered page, else Events', () {
      ReturnAfterSignIn.save('/events/$eventX');
      expect(_guard(_signedIn(), AppRoutes.login), '/events/$eventX');
      expect(_guard(_signedIn(), AppRoutes.login), AppRoutes.home);
    });

    test('a non-admin at /admin… goes to the not-admin page', () {
      expect(_guard(_signedIn(), '/admin'), AppRoutes.notAdmin);
      expect(_guard(_signedIn(), '/admin/payments'), AppRoutes.notAdmin);
    });
  });

  group('ISSUE-021: refresh', () {
    for (final page in [
      '/events/$eventX',
      AppRoutes.myEvents,
      '/admin/registrations?event=$eventX',
    ]) {
      test('$page: the splash comes back to it', () {
        final auth = FakeAuthController(); // sign-in still being checked
        expect(_guard(auth, page), AppRoutes.splash);
        auth.restore(_admin);
        expect(RouteGuards.afterSplash(auth), page);
        expect(_guard(auth, page), isNull);
      });
    }

    test('signed out after the check: the page asks for sign-in', () {
      final auth = FakeAuthController();
      expect(_guard(auth, AppRoutes.myEvents), AppRoutes.splash);
      auth.restore(null);
      expect(RouteGuards.afterSplash(auth), AppRoutes.myEvents);
      expect(_guard(auth, AppRoutes.myEvents), AppRoutes.login);
    });

    test('opened at the root: a remembered page, else Events', () {
      final auth = _signedIn();
      expect(RouteGuards.afterSplash(auth), AppRoutes.home);
      ReturnAfterSignIn.save('/checkin/$eventX/qr-1');
      expect(RouteGuards.afterSplash(auth), '/checkin/$eventX/qr-1');
    });
  });

  group('ISSUE-021: signing out', () {
    for (final page in [
      AppRoutes.myEvents,
      '/events/$eventX',
      '/admin/payments',
      AppRoutes.privacy,
    ]) {
      testWidgets('from $page: lands on Events', (tester) async {
        final auth = _signedIn(_admin);
        final router = await _open(tester, auth, page);
        expect(_at(router), page);

        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();

        expect(auth.isAuthenticated, isFalse);
        expect(_at(router), AppRoutes.home);
        expect(find.text('events page'), findsOneWidget);
        // The page left behind is not where the next sign-in goes.
        expect(ReturnAfterSignIn.take(), isNull);
      });
    }
  });

  group('ISSUE-021: an unknown address', () {
    for (final page in ['/volunteer', '/more', '/events', '/nope/at/all']) {
      testWidgets('$page: a page that says so', (tester) async {
        final router = await _open(tester, _signedIn(), page);

        expect(find.text('Page not found'), findsOneWidget);
        expect(find.textContaining('GoException'), findsNothing);
        expect(find.textContaining('no routes'), findsNothing);
        await tester.tap(find.text('Go to Events'));
        await tester.pumpAndSettle();
        expect(_at(router), AppRoutes.home);
      });
    }
  });
}
