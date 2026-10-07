// Regression tests for ISSUE-003 that drive the real AuthController: a login
// the backend refuses must say why, and must leave nobody signed in.
//
// Before the fix every backend failure read "Sign in failed. Please try
// again.", and Firebase stayed signed in with no backend session.
//
// These run under plain `flutter test` and in a browser:
//
//   flutter test --platform chrome test/features/auth/login_failure_rollback_test.dart
//
// The one test that goes through Google sign-in is browser-only, because the
// web sign-in path is selected by `kIsWeb`.

import 'package:dio/dio.dart';
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/auth/services/auth_session_store.dart';
import 'package:event_app/features/auth/services/backend_auth_exception.dart';
import 'package:event_app/features/auth/services/backend_auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_fakes.dart';

const _verifyEmail = 'Please verify your email address before signing in.';
const _suspended =
    'Your account is currently suspended. Please contact support if you '
    'believe this is an error.';
const _emailRequired =
    'An email address is required to sign in. Please use an account with a '
    'valid email address.';
const _sessionNotVerified =
    'Your sign-in session could not be verified. Please sign in again.';
const _cannotConnect =
    'Unable to connect to the server. Check your internet connection and try '
    'again.';
const _serverUnavailable =
    'The server is temporarily unavailable. Please try again shortly.';
const _generic = 'Sign in failed. Please try again.';

typedef _FailureCase = ({
  String name,
  BackendFault fault,
  String? code,
  String message,
});

/// The ways `POST /api/v1/auth/firebase` can fail.
const _loginFailures = <_FailureCase>[
  (
    name: 'Test B: an unverified email',
    fault: BackendFault.http(403, 'email_not_verified'),
    code: 'email_not_verified',
    message: _verifyEmail,
  ),
  (
    name: 'Test C: a suspended account',
    fault: BackendFault.http(403, 'account_suspended'),
    code: 'account_suspended',
    message: _suspended,
  ),
  (
    name: 'Test D: an account with no email',
    fault: BackendFault.http(400, 'email_missing'),
    code: 'email_missing',
    message: _emailRequired,
  ),
  (
    name: 'Test E: an expired Firebase token',
    fault: BackendFault.http(401, 'firebase_token_expired'),
    code: 'firebase_token_expired',
    message: _sessionNotVerified,
  ),
  (
    name: 'Test E: an invalid Firebase token',
    fault: BackendFault.http(401, 'invalid_firebase_token'),
    code: 'invalid_firebase_token',
    message: _sessionNotVerified,
  ),
  (
    name: 'Test F: a dropped connection',
    fault: BackendFault.transport(DioExceptionType.connectionError),
    code: null,
    message: _cannotConnect,
  ),
  (
    name: 'Test G: a connection timeout',
    fault: BackendFault.transport(DioExceptionType.connectionTimeout),
    code: null,
    message: _cannotConnect,
  ),
  (
    name: 'Test G: a response timeout',
    fault: BackendFault.transport(DioExceptionType.receiveTimeout),
    code: null,
    message: _cannotConnect,
  ),
  (
    name: 'Test H: a server error',
    fault: BackendFault.http(500, 'firebase_admin_not_installed'),
    code: 'firebase_admin_not_installed',
    message: _serverUnavailable,
  ),
  (
    name: 'Test H: a gateway error page',
    fault: BackendFault.rawHttp(503, '<html>Service Unavailable</html>'),
    code: null,
    message: _serverUnavailable,
  ),
  (
    name: 'a failure that cannot be classified',
    fault: BackendFault.http(422, [
      {'msg': 'Field required'},
    ]),
    code: null,
    message: _generic,
  ),
];

/// The ways `GET /api/v1/auth/me` can fail after the login exchange worked.
const _meFailures = <_FailureCase>[
  (
    name: 'the new access token is refused',
    fault: BackendFault.http(401, 'invalid_or_expired_token'),
    code: 'invalid_or_expired_token',
    message: _sessionNotVerified,
  ),
  (
    name: 'the account turns out to be suspended',
    fault: BackendFault.http(403, 'account_suspended'),
    code: 'account_suspended',
    message: _suspended,
  ),
  (
    name: 'the server fails',
    fault: BackendFault.http(500),
    code: null,
    message: _serverUnavailable,
  ),
  (
    name: 'the connection drops',
    fault: BackendFault.transport(DioExceptionType.connectionError),
    code: null,
    message: _cannotConnect,
  ),
];

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

  Future<void> signIn(AuthController auth, TestAccount account) {
    return auth.signInWithEmail(
      email: account.email,
      password: account.password,
    );
  }

  /// Signs in, expecting it to fail, and returns what the login threw.
  Future<Object> failedSignIn(AuthController auth, TestAccount account) async {
    Object? thrown;
    try {
      await signIn(auth, account);
    } catch (error) {
      thrown = error;
    }
    expect(thrown, isNotNull, reason: 'the login should have failed');
    return thrown!;
  }

  /// Nothing of a login may outlive its failure.
  Future<void> expectNobodySignedIn(AuthController auth) async {
    expect(auth.status, AuthStatus.unauthenticated);
    expect(auth.isAuthenticated, isFalse);
    expect(auth.session, isNull);
    expect(await AuthSessionStore().load(), isNull);
    expect(FirebaseAuth.instance.currentUser, isNull);
  }

  Future<void> expectSignedInAs(AuthController auth, TestAccount account) async {
    expect(auth.status, AuthStatus.authenticated);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.errorMessage, isNull);
    expect(auth.session?.firebaseUid, account.uid);
    expect(auth.session?.email, account.email);
    expect(auth.session?.accessToken, account.backendToken);
    final stored = await AuthSessionStore().load();
    expect(stored?.firebaseUid, account.uid);
    expect(stored?.accessToken, account.backendToken);
    expect(FirebaseAuth.instance.currentUser?.uid, account.uid);
  }

  setUpAll(() async {
    await installFakeFirebase(firebase);
    installTestSessionStorage();
  });

  setUp(() async {
    firebase.reset();
    firebase.emailAccounts.addAll([accountA, accountB]);
    backend = FakeBackend([accountA, accountB]);
    await AuthSessionStore().clear();
  });

  test('Test A: a verified, active user signs in and the session is '
      'stored', () async {
    final auth = newController();

    await signIn(auth, accountA);

    await expectSignedInAs(auth, accountA);
    expect(auth.session?.userType, accountA.userType);
    expect(backend.requests, [
      'POST /api/v1/auth/firebase',
      'GET /api/v1/auth/me',
    ]);
    expect(backend.firebaseTokensReceived, [accountA.firebaseIdToken]);
    expect(firebase.signOutCalls, 0);
  });

  group('a login the backend refuses says why and leaves nobody signed '
      'in:', () {
    for (final failure in _loginFailures) {
      test(failure.name, () async {
        backend.loginFault = failure.fault;
        final auth = newController();

        final thrown = await failedSignIn(auth, accountA);

        expect(
          thrown,
          isA<BackendAuthException>().having(
            (e) => e.code,
            'code',
            failure.code,
          ),
        );
        expect(auth.errorMessage, failure.message);
        await expectNobodySignedIn(auth);
        expect(firebase.signOutCalls, 1);
        expect(backend.requests, ['POST /api/v1/auth/firebase']);
      });
    }
  });

  group('Test I: the login exchange works but /auth/me fails, and nothing '
      'of the login is kept:', () {
    for (final failure in _meFailures) {
      test(failure.name, () async {
        backend.meFault = failure.fault;
        final auth = newController();

        final thrown = await failedSignIn(auth, accountA);

        expect(
          thrown,
          isA<BackendAuthException>().having(
            (e) => e.code,
            'code',
            failure.code,
          ),
        );
        expect(backend.requests, [
          'POST /api/v1/auth/firebase',
          'GET /api/v1/auth/me',
        ]);
        expect(auth.errorMessage, failure.message);
        await expectNobodySignedIn(auth);
        expect(firebase.signOutCalls, 1);
      });
    }
  });

  test('Test J: the same user signs in normally once the backend stops '
      'refusing', () async {
    backend.loginFault = const BackendFault.http(403, 'email_not_verified');
    final auth = newController();
    await failedSignIn(auth, accountA);
    expect(auth.errorMessage, _verifyEmail);
    await expectNobodySignedIn(auth);

    backend.loginFault = null;
    await signIn(auth, accountA);

    await expectSignedInAs(auth, accountA);
    expect(firebase.signOutCalls, 1);
  });

  test('Test K: user B signs in after user A was refused, and nothing of A '
      'remains', () async {
    backend.loginFaultByUid[accountA.uid] = const BackendFault.http(
      403,
      'account_suspended',
    );
    final auth = newController();
    await failedSignIn(auth, accountA);
    expect(auth.errorMessage, _suspended);
    await expectNobodySignedIn(auth);

    await signIn(auth, accountB);

    await expectSignedInAs(auth, accountB);
    expect(backend.firebaseTokensReceived, [
      accountA.firebaseIdToken,
      accountB.firebaseIdToken,
    ]);
  });

  test('Test K: after Google account A is refused the chooser is shown '
      'again and B signs in', () async {
    firebase.chooserPicks.addAll([accountA, accountB]);
    backend.loginFaultByUid[accountA.uid] = const BackendFault.http(
      403,
      'email_not_verified',
    );
    final auth = newController();

    await expectLater(
      auth.signInWithGoogle(),
      throwsA(isA<BackendAuthException>()),
    );
    expect(auth.errorMessage, _verifyEmail);
    await expectNobodySignedIn(auth);
    // Rolling back signs out of Firebase, not of Google.
    expect(firebase.browserGoogleAccount, accountA);

    await auth.signInWithGoogle();

    expect(firebase.choosersShown, 2);
    expect(oauthParameters(firebase.popupProviders.last), {
      'prompt': 'select_account',
    });
    await expectSignedInAs(auth, accountB);
  }, testOn: 'browser');

  test('a refused login also signs out whoever was signed in '
      'before', () async {
    final auth = newController();
    await signIn(auth, accountA);
    await expectSignedInAs(auth, accountA);
    backend.loginFaultByUid[accountB.uid] = const BackendFault.http(
      403,
      'account_suspended',
    );

    await failedSignIn(auth, accountB);

    expect(auth.errorMessage, _suspended);
    await expectNobodySignedIn(auth);
  });

  test('a failure to sign out of Firebase does not hide why the login was '
      'refused', () async {
    backend.loginFault = const BackendFault.http(403, 'email_not_verified');
    firebase.signOutError = FirebaseAuthException(code: 'internal-error');
    final auth = newController();

    final thrown = await failedSignIn(auth, accountA);

    expect(thrown, isA<BackendAuthException>());
    expect(auth.errorMessage, _verifyEmail);
    expect(auth.status, AuthStatus.unauthenticated);
    expect(auth.session, isNull);
    expect(await AuthSessionStore().load(), isNull);
    expect(firebase.signOutCalls, 1);
  });

  test('listeners find the reason as soon as they see the app signed out, '
      'and never see it signed in', () async {
    backend.loginFault = const BackendFault.http(403, 'account_suspended');
    final auth = newController();
    final seen = <(AuthStatus, String?)>[];
    auth.addListener(() => seen.add((auth.status, auth.errorMessage)));

    await failedSignIn(auth, accountA);

    expect(seen, [
      (AuthStatus.authenticating, null),
      (AuthStatus.unauthenticated, _suspended),
    ]);
  });

  test('a wrong password keeps its Firebase message and never reaches the '
      'backend', () async {
    final auth = newController();

    Object? thrown;
    try {
      await auth.signInWithEmail(email: accountA.email, password: 'wrong');
    } catch (error) {
      thrown = error;
    }

    expect(
      thrown,
      isA<FirebaseAuthException>().having(
        (e) => e.code,
        'code',
        'invalid-credential',
      ),
    );
    expect(auth.errorMessage, 'The email or password is incorrect.');
    expect(backend.requests, isEmpty);
    await expectNobodySignedIn(auth);
  });

  test('Test L: logout clears the stored session, signs out of Firebase and '
      'leaves the app signed out', () async {
    final auth = newController();
    await signIn(auth, accountA);
    await expectSignedInAs(auth, accountA);

    await auth.signOut();

    expect(auth.errorMessage, isNull);
    await expectNobodySignedIn(auth);
    expect(firebase.signOutCalls, 1);
  });

  test('Test M: a reload restores a valid stored session', () async {
    await signIn(newController(), accountB);
    backend.requests.clear();

    final afterReload = newController();
    await afterReload.initialize();

    expect(afterReload.status, AuthStatus.authenticated);
    expect(afterReload.isAuthenticated, isTrue);
    expect(afterReload.errorMessage, isNull);
    expect(afterReload.session?.firebaseUid, accountB.uid);
    expect(afterReload.session?.email, accountB.email);
    expect(backend.requests, ['GET /api/v1/auth/me']);
    expect((await AuthSessionStore().load())?.firebaseUid, accountB.uid);
  });

  test('Test M: a reload with a stored session the backend no longer '
      'accepts removes it and starts signed out', () async {
    await signIn(newController(), accountB);
    backend.requests.clear();
    backend.meFault = const BackendFault.http(401, 'invalid_or_expired_token');

    final afterReload = newController();
    await afterReload.initialize();

    expect(afterReload.status, AuthStatus.unauthenticated);
    expect(afterReload.isAuthenticated, isFalse);
    expect(afterReload.session, isNull);
    expect(await AuthSessionStore().load(), isNull);
    expect(backend.requests, ['GET /api/v1/auth/me']);
  });

  test('Test M: a reload with no stored session starts signed out without '
      'calling the backend', () async {
    final afterReload = newController();
    await afterReload.initialize();

    expect(afterReload.status, AuthStatus.unauthenticated);
    expect(afterReload.session, isNull);
    expect(afterReload.errorMessage, isNull);
    expect(backend.requests, isEmpty);
  });
}
