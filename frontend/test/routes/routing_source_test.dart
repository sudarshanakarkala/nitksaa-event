// Guard for ISSUE-021, for the parts routing_test.dart cannot run: AppRouter,
// the splash and the login screen use the app's one AuthController. It reads
// the source files, so it runs on the VM only.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ISSUE-021: wiring that needs the app\'s AuthController', () {
    String source(String path) => File(path).readAsStringSync();

    test('AppRouter uses the guard, the not-found page and the not-admin '
        'route', () {
      final router = source('lib/routes/app_router.dart');
      expect(router, contains('redirect: RouteGuards.redirect,'));
      expect(
        router,
        contains('errorBuilder: (context, state) => const NotFoundPage()'),
      );
      expect(router, contains('path: AppRoutes.notAdmin'));
      expect(router, contains('path: AppRoutes.checkout'));
    });

    test('the splash goes where the guard says', () {
      expect(
        source('lib/features/auth/presentation/screens/splash_screen.dart'),
        contains('RouteGuards.afterSplash(auth)'),
      );
    });

    test('the login screen leaves the next page to the guard', () {
      final login = source(
        'lib/features/auth/presentation/screens/login_screen.dart',
      );
      expect(login, isNot(contains('context.go(AppRoutes.home)')));
    });
  });
}
