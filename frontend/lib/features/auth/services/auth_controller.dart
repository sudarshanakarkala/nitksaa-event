import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger/app_logger.dart';
import '../domain/auth_session.dart';
import 'auth_session_store.dart';
import 'backend_auth_service.dart';
import 'firebase_auth_service.dart';

enum AuthStatus { checking, unauthenticated, authenticating, authenticated }

class AuthController extends ChangeNotifier {
  AuthController._({
    BackendAuthService? backendAuthService,
    AuthSessionStore? sessionStore,
  }) : _backendAuthService = backendAuthService ?? BackendAuthService(),
       _sessionStore = sessionStore ?? AuthSessionStore();

  static final AuthController instance = AuthController._();

  final BackendAuthService _backendAuthService;
  final AuthSessionStore _sessionStore;

  StreamSubscription<User?>? _firebaseAuthSubscription;
  AuthStatus _status = AuthStatus.checking;
  AuthSession? _session;
  String? _errorMessage;
  bool _initialized = false;

  AuthStatus get status => _status;
  AuthSession? get session => _session;
  String? get errorMessage => _errorMessage;
  bool get isChecking => _status == AuthStatus.checking;
  bool get isAuthenticating => _status == AuthStatus.authenticating;
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated && _session?.isValid == true;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _setStatus(AuthStatus.checking);

    await _sessionStore.initialize();
    _firebaseAuthSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _handleFirebaseAuthChanged,
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error(
          'Firebase auth state listener failed',
          error,
          stackTrace,
        );
      },
    );

    final storedSession = await _sessionStore.load();
    if (storedSession == null) {
      _setUnauthenticated();
      return;
    }

    try {
      final validatedSession = await _backendAuthService.validateAccessToken(
        storedSession.accessToken,
      );
      await _setAuthenticated(validatedSession);
    } catch (error, stackTrace) {
      AppLogger.warning('Stored backend session validation failed: $error');
      await _clearStoredSession();
      _errorMessage = _friendlyAuthError(error);
      _setStatus(AuthStatus.unauthenticated);
      AppLogger.error(
        'Stored backend session could not be restored',
        error,
        stackTrace,
      );
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _runLoginFlow(
      () =>
          FirebaseAuthService.signInWithEmail(email: email, password: password),
    );
  }

  Future<void> signInWithGoogle() async {
    await _runLoginFlow(FirebaseAuthService.signInWithGoogle);
  }

  Future<void> signOut() async {
    _errorMessage = null;
    await _clearStoredSession();
    try {
      await FirebaseAuthService.signOut();
    } catch (error, stackTrace) {
      AppLogger.error('Sign out failed', error, stackTrace);
      _errorMessage = _friendlyAuthError(error);
    }
    _setStatus(AuthStatus.unauthenticated);
  }

  Future<void> _runLoginFlow(Future<User?> Function() firebaseLogin) async {
    _errorMessage = null;
    _setStatus(AuthStatus.authenticating);

    try {
      final user = await firebaseLogin();
      if (user == null) {
        throw StateError('Firebase login did not return a user.');
      }

      final firebaseToken = await FirebaseAuthService.freshIdToken();
      final backendSession = await _backendAuthService.loginWithFirebaseToken(
        firebaseToken,
      );
      final validatedSession = await _backendAuthService.validateAccessToken(
        backendSession.accessToken,
      );
      await _setAuthenticated(validatedSession);
      AppLogger.info('Backend-authenticated login completed.');
    } catch (error, stackTrace) {
      AppLogger.error('Login failed', error, stackTrace);
      await _clearStoredSession();
      _errorMessage = _friendlyAuthError(error);
      _setStatus(AuthStatus.unauthenticated);
      rethrow;
    }
  }

  Future<void> _handleFirebaseAuthChanged(User? user) async {
    if (user == null) {
      // Startup can briefly report a null Firebase user while a valid backend
      // JWT still exists. Production auth is owned by backend session
      // validation, and explicit logout clears both Firebase and the JWT.
      if (_session == null && _status != AuthStatus.checking) {
        _setStatus(AuthStatus.unauthenticated);
      }
      return;
    }

    // Firebase alone is not production auth. A signed-in Firebase user is only
    // useful if a backend JWT has already been validated or is being exchanged.
    if (_session == null && _status != AuthStatus.authenticating) {
      _setStatus(AuthStatus.unauthenticated);
    }
  }

  Future<void> _setAuthenticated(AuthSession session) async {
    _session = session;
    _errorMessage = null;
    await _sessionStore.save(session);
    _setStatus(AuthStatus.authenticated);
  }

  Future<void> _clearStoredSession() async {
    _session = null;
    await _sessionStore.clear();
  }

  void _setUnauthenticated() {
    _session = null;
    _setStatus(AuthStatus.unauthenticated);
  }

  void _setStatus(AuthStatus status) {
    if (_status == status) return;
    _status = status;
    notifyListeners();
  }

  String _friendlyAuthError(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-email' => 'Enter a valid email address.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' => 'No account was found for that email.',
        'wrong-password' => 'The password is incorrect.',
        'invalid-credential' => 'The email or password is incorrect.',
        'too-many-requests' => 'Too many attempts. Please wait a moment and try again.',
        'network-request-failed' => 'A network error occurred. Check your connection and try again.',
        'popup-blocked' => 'Sign-in popup was blocked. Please allow popups and try again.',
        _ => 'Sign in failed. Please try again or use Google Sign-In.',
      };
    }
    return 'Sign in failed. Please try again.';
  }

  @override
  void dispose() {
    _firebaseAuthSubscription?.cancel();
    super.dispose();
  }
}

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  return AuthController.instance;
});
