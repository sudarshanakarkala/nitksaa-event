// Regression tests for ISSUE-002 that drive the real AuthController through
// Google sign-in on web: the account switch after logout, the unchanged login
// exchange with the backend, logout, and session restore.
//
// Browser-only, because the web sign-in path is selected by `kIsWeb`:
//
//   flutter test --platform chrome test/features/auth/google_login_flow_test.dart
@TestOn('browser')
library;

import 'package:dio/dio.dart';
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/auth/services/auth_session_store.dart';
import 'package:event_app/features/auth/services/backend_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_fakes.dart';

void main() {
  final firebase = FakeFirebaseAuthPlatform();
  late FakeBackend backend;

  /// A controller as the app would have after a page load, talking to the
  /// fake backend and the real session store.
  AuthController newController() {
    final dio = Dio(BaseOptions(baseUrl: 'https://backend.test'))
      ..httpClientAdapter = backend;
    final controller = AuthController.forTesting(
      backendAuthService: BackendAuthService(dio: dio),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  setUpAll(() => installFakeFirebase(firebase));

  setUp(() async {
    firebase.reset();
    backend = FakeBackend([accountA, accountB]);
    await AuthSessionStore().clear();
  });

  test('user A logs out, picks user B in the account chooser, and the '
      'session becomes B', () async {
    firebase.chooserPicks.addAll([accountA, accountB]);
    final auth = newController();

    await auth.signInWithGoogle();
    expect(auth.session?.email, accountA.email);
    await auth.signOut();
    await auth.signInWithGoogle();

    expect(firebase.choosersShown, 2);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.session?.firebaseUid, accountB.uid);
    expect(auth.session?.email, accountB.email);
    expect(auth.session?.accessToken, accountB.backendToken);
    expect((await AuthSessionStore().load())?.firebaseUid, accountB.uid);
  });

  test('a first Google login shows the chooser and signs in', () async {
    firebase.chooserPicks.add(accountA);
    final auth = newController();

    await auth.signInWithGoogle();

    expect(firebase.choosersShown, 1);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.session?.email, accountA.email);
  });

  test('Test B: Google sign-in still exchanges the Firebase ID token for a '
      'validated backend session', () async {
    firebase.chooserPicks.add(accountA);
    final auth = newController();

    await auth.signInWithGoogle();

    expect(backend.requests, [
      'POST /api/v1/auth/firebase',
      'GET /api/v1/auth/me',
    ]);
    expect(backend.firebaseTokensReceived, [accountA.firebaseIdToken]);
    expect(auth.status, AuthStatus.authenticated);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.session?.accessToken, accountA.backendToken);
    expect(auth.session?.firebaseUid, accountA.uid);
    expect(auth.session?.email, accountA.email);
    expect(auth.session?.userType, accountA.userType);
    final stored = await AuthSessionStore().load();
    expect(stored?.accessToken, accountA.backendToken);
  });

  test('Test C: logout clears the stored session, signs out of Firebase '
      'and leaves the app signed out', () async {
    firebase.chooserPicks.add(accountA);
    final auth = newController();
    await auth.signInWithGoogle();
    expect(await AuthSessionStore().load(), isNotNull);

    await auth.signOut();

    expect(auth.status, AuthStatus.unauthenticated);
    expect(auth.isAuthenticated, isFalse);
    expect(auth.session, isNull);
    expect(await AuthSessionStore().load(), isNull);
    expect(firebase.signOutCalls, 1);
  });

  test('a reload restores the signed-in session without a Google '
      'popup', () async {
    firebase.chooserPicks.add(accountB);
    await newController().signInWithGoogle();
    firebase.popupProviders.clear();
    backend.requests.clear();

    final afterReload = newController();
    await afterReload.initialize();

    expect(afterReload.isAuthenticated, isTrue);
    expect(afterReload.session?.firebaseUid, accountB.uid);
    expect(afterReload.session?.email, accountB.email);
    expect(firebase.popupProviders, isEmpty);
    expect(backend.requests, ['GET /api/v1/auth/me']);
  });
}
