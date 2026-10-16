// Staying signed in, and signing out, across tabs and over a long day, on
// the real AuthController (Firebase and the backend are fakes).
//
// Tabs:
// - Sign out in one tab tells the other tabs; a tab that hears it drops its
//   session (and leaves a page that needs sign-in, through the app's hook).
// - A sign-in tells the other tabs who signed in; a tab signed in as someone
//   else reloads; a signed-out tab (e.g. one waiting for an emailed sign-in
//   link) does nothing.
// - A sign-in that fails and is rolled back tells nobody.
//
// Renewal:
// - The app's session runs out after a few hours; Firebase's sign-in lasts
//   much longer. A session that ran out is renewed from Firebase if it is
//   still the same person, with no sign-in screen.
// - Nothing is renewed after a sign-out, for someone else, or when the
//   exchange fails (then it is as before: sign in again).
//
// Runs under plain `flutter test` and in a browser.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:event_app/features/auth/domain/auth_session.dart';
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/auth/services/auth_session_store.dart';
import 'package:event_app/features/auth/services/auth_tab_channel.dart';
import 'package:event_app/features/auth/services/backend_auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_fakes.dart';

/// Records what would go to the other tabs, and reloads.
class _FakeTabs extends AuthTabChannel {
  final posted = <String>[];
  int reloads = 0;

  @override
  void post(String message) => posted.add(message);

  @override
  void listen(void Function(String message) onMessage) {}

  @override
  void onPageShown(void Function() onShown) {}

  @override
  void reload() => reloads++;
}

/// A session the backend no longer accepts (it ran out).
AuthSession _expired(TestAccount account) => AuthSession(
  accessToken: 'expired-token-${account.uid}',
  firebaseUid: account.uid,
  userType: account.userType,
  email: account.email,
);

void main() {
  final firebase = FakeFirebaseAuthPlatform();
  late FakeBackend backend;
  late _FakeTabs tabs;

  AuthController newController() {
    final dio = Dio(BaseOptions(baseUrl: 'https://backend.test'))
      ..httpClientAdapter = backend;
    final controller = AuthController.forTesting(
      backendAuthService: BackendAuthService(dio: dio),
      tabs: tabs,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> signIn(AuthController auth, TestAccount account) =>
      auth.signInWithEmail(email: account.email, password: account.password);

  /// Firebase signed in as [account] with no app session, as after a page
  /// load where the stored session has run out.
  Future<void> firebaseSignedInAs(TestAccount account) =>
      FirebaseAuth.instance.signInWithEmailAndPassword(
        email: account.email,
        password: account.password,
      );

  int exchanges() =>
      backend.requests.where((r) => r == 'POST /api/v1/auth/firebase').length;

  setUpAll(() async {
    await installFakeFirebase(firebase);
    installTestSessionStorage();
  });

  setUp(() async {
    firebase.reset();
    firebase.emailAccounts.addAll([accountA, accountB]);
    backend = FakeBackend([accountA, accountB]);
    tabs = _FakeTabs();
    await AuthSessionStore().clear();
  });

  group('tabs', () {
    test('a sign-in tells the other tabs who it is', () async {
      await signIn(newController(), accountA);
      expect(tabs.posted, ['signed-in:${accountA.uid}']);
    });

    test('sign out tells the other tabs', () async {
      final auth = newController();
      await signIn(auth, accountA);
      await auth.signOut();
      expect(tabs.posted.last, 'signed-out');
    });

    test('sign out ends the token on the server, and still signs out if '
        'that fails', () async {
      final auth = newController();
      await signIn(auth, accountA);
      // FakeBackend has no logout endpoint: it answers 404, like an error.
      await auth.signOut();
      expect(backend.requests, contains('POST /api/v1/auth/logout'));
      expect(auth.isAuthenticated, isFalse);
      expect(await AuthSessionStore().load(), isNull);
    });

    test('signed out in another tab: this tab ends its own token too',
        () async {
      final auth = newController();
      await signIn(auth, accountA);
      backend.requests.clear();
      auth.onTabMessage('signed-out');
      await Future<void>.delayed(Duration.zero);
      expect(backend.requests, ['POST /api/v1/auth/logout']);
    });

    test('a failed sign-in, rolled back, tells nobody', () async {
      backend.loginFault = const BackendFault.http(403, 'account_suspended');
      try {
        await signIn(newController(), accountA);
      } catch (_) {}
      expect(tabs.posted, isEmpty);
    });

    test('signed out in another tab: out here too, via the hook', () async {
      final auth = newController();
      await signIn(auth, accountA);
      var hookCalls = 0;
      auth.onSignedOutElsewhere = () => hookCalls++;

      auth.onTabMessage('signed-out');

      expect(hookCalls, 1);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.session, isNull);
      expect(auth.status, AuthStatus.unauthenticated);
    });

    test('signed out in another tab while signed out here: nothing', () {
      final auth = newController();
      var hookCalls = 0;
      auth.onSignedOutElsewhere = () => hookCalls++;
      auth.onTabMessage('signed-out');
      expect(hookCalls, 0);
    });

    test('someone else signs in in another tab: this tab reloads', () async {
      final auth = newController();
      await signIn(auth, accountA);
      auth.onTabMessage('signed-in:${accountB.uid}');
      expect(tabs.reloads, 1);
    });

    test('the same person signs in in another tab: no reload', () async {
      final auth = newController();
      await signIn(auth, accountA);
      auth.onTabMessage('signed-in:${accountA.uid}');
      expect(tabs.reloads, 0);
    });

    test('a signed-out tab (e.g. waiting for a sign-in link) does nothing '
        'when another tab signs in', () {
      final auth = newController();
      auth.onTabMessage('signed-in:${accountA.uid}');
      expect(tabs.reloads, 0);
      expect(auth.isAuthenticated, isFalse);
    });
  });

  group('renewal', () {
    test('a stored session that ran out is renewed from Firebase, same '
        'person, with no sign-in', () async {
      await firebaseSignedInAs(accountA);
      await AuthSessionStore().save(_expired(accountA));

      final auth = newController();
      await auth.initialize();

      expect(auth.status, AuthStatus.authenticated);
      expect(auth.session?.firebaseUid, accountA.uid);
      expect(auth.session?.accessToken, accountA.backendToken);
      expect((await AuthSessionStore().load())?.accessToken,
          accountA.backendToken);
      expect(exchanges(), 1);
      // Renewal is not a new sign-in: other tabs aren't told.
      expect(tabs.posted, isEmpty);
    });

    test('not renewed when Firebase is someone else', () async {
      await firebaseSignedInAs(accountB);
      await AuthSessionStore().save(_expired(accountA));

      final auth = newController();
      await auth.initialize();

      expect(auth.isAuthenticated, isFalse);
      expect(exchanges(), 0);
      expect(await AuthSessionStore().load(), isNull);
    });

    test('not renewed when Firebase is signed out', () async {
      await AuthSessionStore().save(_expired(accountA));

      final auth = newController();
      await auth.initialize();

      expect(auth.isAuthenticated, isFalse);
      expect(exchanges(), 0);
    });

    test('after sign out, a reload stays signed out', () async {
      final auth = newController();
      await signIn(auth, accountA);
      await auth.signOut();
      backend.requests.clear();

      final afterReload = newController();
      await afterReload.initialize();

      expect(afterReload.isAuthenticated, isFalse);
      expect(backend.requests, isEmpty);
    });

    test('after sign out, even if Firebase failed to sign out, nothing is '
        'renewed', () async {
      final auth = newController();
      await signIn(auth, accountA);
      firebase.signOutError = FirebaseAuthException(code: 'network-request-failed');
      await auth.signOut();
      expect(FirebaseAuth.instance.currentUser?.uid, accountA.uid);
      backend.requests.clear();

      final afterReload = newController();
      await afterReload.initialize();

      expect(afterReload.isAuthenticated, isFalse);
      expect(exchanges(), 0);
    });

    test('renewal that fails: sign in again, as before', () async {
      await firebaseSignedInAs(accountA);
      await AuthSessionStore().save(_expired(accountA));
      backend.loginFault =
          const BackendFault.transport(DioExceptionType.connectionError);

      final auth = newController();
      await auth.initialize();

      expect(auth.isAuthenticated, isFalse);
      expect(await AuthSessionStore().load(), isNull);
    });

    test('mid-session: renewed while Firebase is the same person', () async {
      final auth = newController();
      await signIn(auth, accountA);

      expect(await auth.renewSession(), isTrue);
      expect(auth.session?.firebaseUid, accountA.uid);
      expect(auth.isAuthenticated, isTrue);
    });

    test('mid-session: not renewed once Firebase has signed out (another '
        'tab signed out); the session is left alone', () async {
      final auth = newController();
      await signIn(auth, accountA);
      await FirebaseAuth.instance.signOut();

      expect(await auth.renewSession(), isFalse);
      expect(auth.session?.firebaseUid, accountA.uid);
    });

    test('mid-session: a renewal that fails keeps the session', () async {
      final auth = newController();
      await signIn(auth, accountA);
      backend.loginFault = const BackendFault.http(503);

      expect(await auth.renewSession(), isFalse);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.session?.accessToken, accountA.backendToken);
    });
  });

  group('AuthSession.expiresAt', () {
    String jwt(Map<String, dynamic> payload) {
      String part(Object o) =>
          base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
      return '${part({'alg': 'HS256'})}.${part(payload)}.sig';
    }

    AuthSession withToken(String token) =>
        AuthSession(accessToken: token, firebaseUid: 'u', userType: 'alumni');

    test('read from the token', () {
      expect(
        withToken(jwt({'sub': 'u', 'exp': 1800000000})).expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000, isUtc: true),
      );
    });

    test('null when it can\'t be read', () {
      expect(withToken('not-a-jwt').expiresAt, isNull);
      expect(withToken(jwt({'sub': 'u'})).expiresAt, isNull);
      expect(withToken('a.%%%.c').expiresAt, isNull);
    });
  });
}
