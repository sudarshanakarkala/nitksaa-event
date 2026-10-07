// The Firebase platform-interface packages are transitive dependencies. They
// are imported here only to put a fake in place of Firebase.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// A person with a Google account, as Firebase and the backend know them.
class TestAccount {
  const TestAccount({
    required this.uid,
    required this.email,
    required this.fullname,
    required this.userType,
  });

  final String uid;
  final String email;
  final String fullname;
  final String userType;

  String get password => 'password-$uid';
  String get firebaseIdToken => 'firebase-id-token-$uid';
  String get backendToken => 'backend-token-$uid';
}

const accountA = TestAccount(
  uid: 'uid-A',
  email: 'alice@example.com',
  fullname: 'Alice Alumna',
  userType: 'alumni',
);

const accountB = TestAccount(
  uid: 'uid-B',
  email: 'bob@example.com',
  fullname: 'Bob Guest',
  userType: 'other',
);

/// Stands in for Firebase Auth and for Google's side of the popup.
///
/// It follows the behaviour ISSUE-002 is about: a browser that is signed in
/// to one Google account hands that account back without asking, unless the
/// sign-in request carries `prompt=select_account`, in which case Google
/// shows the account chooser and the user's pick is used. Signing out of
/// Firebase does not sign the browser out of Google.
class FakeFirebaseAuthPlatform extends FirebaseAuthPlatform {
  /// The provider each popup sign-in was asked to use.
  final popupProviders = <AuthProvider>[];

  /// What the user picks each time the account chooser is shown.
  final chooserPicks = <TestAccount>[];

  /// The Google account the browser is signed in to.
  TestAccount? browserGoogleAccount;

  /// The accounts that can sign in with their email and password.
  final emailAccounts = <TestAccount>[];

  /// When set, signing out fails with this and the user stays signed in.
  Object? signOutError;

  int choosersShown = 0;
  int signOutCalls = 0;
  UserPlatform? _currentUser;

  void reset() {
    popupProviders.clear();
    chooserPicks.clear();
    emailAccounts.clear();
    browserGoogleAccount = null;
    signOutError = null;
    choosersShown = 0;
    signOutCalls = 0;
    _currentUser = null;
  }

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAuthPlatform setInitialValues({
    Object? currentUser,
    String? languageCode,
  }) => this;

  @override
  UserPlatform? get currentUser => _currentUser;

  @override
  Stream<UserPlatform?> authStateChanges() => const Stream.empty();

  @override
  Future<UserCredentialPlatform> signInWithPopup(AuthProvider provider) async {
    popupProviders.add(provider);
    final asksForChooser =
        provider is GoogleAuthProvider &&
        provider.parameters['prompt'] == 'select_account';

    TestAccount? account;
    if (asksForChooser || browserGoogleAccount == null) {
      choosersShown++;
      account = chooserPicks.isEmpty ? null : chooserPicks.removeAt(0);
      browserGoogleAccount = account ?? browserGoogleAccount;
    } else {
      account = browserGoogleAccount;
    }

    _currentUser = account == null ? null : _FakeFirebaseUser(this, account);
    return _FakeUserCredential(this, _currentUser);
  }

  @override
  Future<UserCredentialPlatform> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    for (final account in emailAccounts) {
      if (account.email == email && account.password == password) {
        _currentUser = _FakeFirebaseUser(this, account);
        return _FakeUserCredential(this, _currentUser);
      }
    }
    throw FirebaseAuthException(code: 'invalid-credential');
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    final error = signOutError;
    if (error != null) throw error;
    _currentUser = null;
  }
}

class _FakeFirebaseUser extends UserPlatform {
  _FakeFirebaseUser(FirebaseAuthPlatform auth, this.account)
    : super(
        auth,
        _NoMultiFactor(auth),
        InternalUserDetails(
          userInfo: InternalUserInfo(
            uid: account.uid,
            email: account.email,
            displayName: account.fullname,
            isAnonymous: false,
            isEmailVerified: true,
          ),
          providerData: [],
        ),
      );

  final TestAccount account;

  @override
  Future<String?> getIdToken(bool forceRefresh) async =>
      account.firebaseIdToken;
}

class _NoMultiFactor extends MultiFactorPlatform {
  _NoMultiFactor(super.auth);
}

class _FakeUserCredential extends UserCredentialPlatform {
  _FakeUserCredential(FirebaseAuthPlatform auth, UserPlatform? user)
    : super(auth: auth, user: user);
}

/// The OAuth parameters a recorded popup sign-in would send to Google.
Map<dynamic, dynamic> oauthParameters(AuthProvider provider) {
  expect(provider, isA<GoogleAuthProvider>());
  return (provider as GoogleAuthProvider).parameters;
}

/// Puts [firebase] in place of Firebase Auth for the current test file.
Future<void> installFakeFirebase(FakeFirebaseAuthPlatform firebase) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  await Firebase.initializeApp();
  FirebaseAuthPlatform.instance = firebase;
}

/// Gives Hive somewhere to keep the session box for the current test file.
///
/// A browser stores it in IndexedDB with no setup. The VM has no such
/// default, so it gets a temporary directory. Call from `setUpAll`.
void installTestSessionStorage() {
  if (kIsWeb) return;
  final directory = Directory.systemTemp.createTempSync('nitksaa_auth_test_');
  Hive.init(directory.path);
  addTearDown(() async {
    await Hive.close();
    directory.deleteSync(recursive: true);
  });
}

/// A way for one of [FakeBackend]'s endpoints to fail.
class BackendFault {
  /// The backend answers with [statusCode] and `{"detail": detail}`.
  const BackendFault.http(int this.statusCode, [this.detail])
    : transport = null,
      rawBody = null;

  /// Something in front of the backend answers with [statusCode] and a body
  /// that is not the backend's JSON, as a proxy or load balancer would.
  const BackendFault.rawHttp(int this.statusCode, String this.rawBody)
    : transport = null,
      detail = null;

  /// No answer arrives: the request fails in transit as [transport].
  const BackendFault.transport(DioExceptionType this.transport)
    : statusCode = null,
      detail = null,
      rawBody = null;

  final int? statusCode;
  final Object? detail;
  final String? rawBody;
  final DioExceptionType? transport;
}

/// Stands in for the backend's two auth endpoints. Plug it into a [Dio] as
/// its `httpClientAdapter`.
class FakeBackend implements HttpClientAdapter {
  FakeBackend(this.accounts);

  final List<TestAccount> accounts;

  /// Each request received, as `METHOD /path`.
  final requests = <String>[];

  /// The Firebase ID token of each login exchange received.
  final firebaseTokensReceived = <String?>[];

  /// When set, `POST /api/v1/auth/firebase` fails this way.
  BackendFault? loginFault;

  /// How `POST /api/v1/auth/firebase` fails for one account, by its uid.
  final loginFaultByUid = <String, BackendFault>{};

  /// When set, `GET /api/v1/auth/me` fails this way.
  BackendFault? meFault;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add('${options.method} ${options.path}');

    if (options.method == 'POST' && options.path == '/api/v1/auth/firebase') {
      final idToken = (options.data as Map)['token']?.toString();
      firebaseTokensReceived.add(idToken);
      final account = _find((a) => a.firebaseIdToken == idToken);
      final fault = loginFault ?? loginFaultByUid[account?.uid];
      if (fault != null) return _fail(fault, options);
      if (account == null) {
        return _json(401, {'detail': 'invalid_firebase_token'});
      }
      return _json(200, {
        'access_token': account.backendToken,
        'firebase_uid': account.uid,
        'user_type': account.userType,
        'fullname': account.fullname,
      });
    }

    if (options.method == 'GET' && options.path == '/api/v1/auth/me') {
      final fault = meFault;
      if (fault != null) return _fail(fault, options);
      final bearer = options.headers['Authorization'];
      final account = _find((a) => 'Bearer ${a.backendToken}' == bearer);
      if (account == null) {
        return _json(401, {'detail': 'invalid_or_expired_token'});
      }
      return _json(200, {
        'firebase_uid': account.uid,
        'email': account.email,
        'fullname': account.fullname,
        'user_type': account.userType,
      });
    }

    return _json(404, {'detail': 'not_found'});
  }

  @override
  void close({bool force = false}) {}

  TestAccount? _find(bool Function(TestAccount account) matches) {
    for (final account in accounts) {
      if (matches(account)) return account;
    }
    return null;
  }

  ResponseBody _fail(BackendFault fault, RequestOptions options) {
    final transport = fault.transport;
    if (transport != null) {
      throw DioException(requestOptions: options, type: transport);
    }
    final rawBody = fault.rawBody;
    if (rawBody != null) {
      return ResponseBody.fromString(
        rawBody,
        fault.statusCode!,
        headers: {
          Headers.contentTypeHeader: ['text/html'],
        },
      );
    }
    return _json(fault.statusCode!, {'detail': fault.detail});
  }

  ResponseBody _json(int statusCode, Map<String, dynamic> body) {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
