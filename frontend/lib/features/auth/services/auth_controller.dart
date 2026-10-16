import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger/app_logger.dart';
import '../domain/auth_session.dart';
import 'auth_error_messages.dart';
import 'auth_session_store.dart';
import 'auth_tab_channel.dart';
import 'backend_auth_service.dart';
import 'email_link_store.dart';
import 'email_link_url.dart';
import 'firebase_auth_service.dart';

enum AuthStatus { checking, unauthenticated, authenticating, authenticated }

class AuthController extends ChangeNotifier {
  AuthController._({
    BackendAuthService? backendAuthService,
    AuthSessionStore? sessionStore,
    AuthTabChannel? tabs,
  }) : _backendAuthService = backendAuthService ?? BackendAuthService(),
       _sessionStore = sessionStore ?? AuthSessionStore(),
       _tabs = tabs ?? const AuthTabChannel();

  /// A controller that is separate from [instance], for tests that supply
  /// their own backend or session store.
  @visibleForTesting
  AuthController.forTesting({
    BackendAuthService? backendAuthService,
    AuthSessionStore? sessionStore,
    AuthTabChannel? tabs,
  }) : this._(
         backendAuthService: backendAuthService,
         sessionStore: sessionStore,
         tabs: tabs,
       );

  /// What tabs tell each other (see [AuthTabChannel]).
  static const tabSignedOut = 'signed-out';
  static const tabSignedInPrefix = 'signed-in:';

  /// How long before the session ends it is renewed.
  static const renewBefore = Duration(minutes: 10);

  static final AuthController instance = AuthController._();

  final BackendAuthService _backendAuthService;
  final AuthSessionStore _sessionStore;
  final AuthTabChannel _tabs;

  /// Runs when another tab signed out, just before this tab drops its
  /// session: the app moves off a page that needs sign-in (to Events), so
  /// that page isn't remembered as one to come back to.
  VoidCallback? onSignedOutElsewhere;

  Timer? _renewTimer;
  Future<bool>? _renewing;

  StreamSubscription<User?>? _firebaseAuthSubscription;
  AuthStatus _status = AuthStatus.checking;
  AuthSession? _session;
  String? _errorMessage;
  bool _initialized = false;

  /// A sign-in link opened on a device that doesn't know which email it was
  /// sent to: the login screen asks for the email to finish.
  String? _pendingEmailLink;

  /// Why an opened sign-in link didn't sign the user in; the login screen
  /// shows it.
  String? _emailLinkNotice;

  AuthStatus get status => _status;
  AuthSession? get session => _session;
  String? get errorMessage => _errorMessage;
  bool get isChecking => _status == AuthStatus.checking;
  bool get isAuthenticating => _status == AuthStatus.authenticating;
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated && _session?.isValid == true;
  String? get pendingEmailLink => _pendingEmailLink;
  String? get emailLinkNotice => _emailLinkNotice;

  /// Startup should open the login screen rather than Events: a sign-in
  /// link needs the email, or it failed and the user should see why.
  bool get needsLoginScreen =>
      !isAuthenticated && (_pendingEmailLink != null || _emailLinkNotice != null);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _setStatus(AuthStatus.checking);

    await _sessionStore.initialize();
    _tabs.listen(_onTabMessage);
    _tabs.onPageShown(_renewIfDue);
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
      // Usually it has just run out. Firebase keeps its own sign-in much
      // longer: if it is still the same person, renew instead of asking
      // them to sign in again.
      final renewed = await _renewedFrom(storedSession);
      if (renewed != null) {
        await _setAuthenticated(renewed);
        return;
      }
      await _clearStoredSession();
      _errorMessage = friendlyAuthError(error);
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

  /// Emails a sign-in link to [email] and remembers the email on this
  /// device. Throws on failure, with [errorMessage] set.
  Future<void> sendSignInLink(String email) async {
    _errorMessage = null;
    _emailLinkNotice = null;
    try {
      await FirebaseAuthService.sendSignInLink(email);
      await EmailLinkStore.save(email);
    } catch (error, stackTrace) {
      AppLogger.error('Sending the sign-in link failed', error, stackTrace);
      _errorMessage = friendlyAuthError(error);
      notifyListeners();
      rethrow;
    }
  }

  /// Run once at startup, after [initialize]: if the page was opened from a
  /// sign-in link, complete it. Never throws.
  ///
  /// The link's parameters are removed from the address bar straight away,
  /// so a refresh doesn't retry a link that is single-use.
  Future<void> handleIncomingEmailLink() async {
    if (!kIsWeb) return;
    final link = Uri.base.toString();
    try {
      if (!FirebaseAuthService.isSignInLink(link)) return;
    } catch (error) {
      AppLogger.warning('Sign-in link check failed: $error');
      return;
    }
    // Cosmetic and refresh-safety only: never let it stop the sign-in.
    try {
      removeSignInLinkFromUrl();
    } catch (error) {
      AppLogger.warning('Could not clean the sign-in link from the URL: $error');
    }

    final email = EmailLinkStore.load();
    if (email == null) {
      // Opened on another device (or storage was cleared).
      _pendingEmailLink = link;
      notifyListeners();
      return;
    }
    try {
      await completeEmailLinkSignIn(email: email, link: link);
    } catch (_) {
      // completeEmailLinkSignIn has set the notice for the login screen.
    }
  }

  /// Signs in with a sign-in link: [link] or the pending one. Throws on
  /// failure, with [errorMessage] and [emailLinkNotice] set.
  Future<void> completeEmailLinkSignIn({
    required String email,
    String? link,
  }) async {
    final emailLink = link ?? _pendingEmailLink;
    if (emailLink == null) {
      throw StateError('No sign-in link to complete.');
    }
    _emailLinkNotice = null;
    try {
      await _runLoginFlow(
        () => FirebaseAuthService.signInWithEmailLink(
          email: email,
          link: emailLink,
        ),
      );
      _pendingEmailLink = null;
      await EmailLinkStore.clear();
    } on FirebaseAuthException catch (error) {
      _emailLinkNotice = _errorMessage;
      // A wrong email can be retried with the same link; a used or expired
      // link can't, so the user starts again.
      if (error.code != 'invalid-email') {
        _pendingEmailLink = null;
        await EmailLinkStore.clear();
      }
      notifyListeners();
      rethrow;
    } catch (_) {
      _emailLinkNotice = _errorMessage;
      notifyListeners();
      rethrow;
    }
  }

  /// Clears a pending link or notice when the user moves on.
  void dismissEmailLink() {
    if (_pendingEmailLink == null && _emailLinkNotice == null) return;
    _pendingEmailLink = null;
    _emailLinkNotice = null;
    notifyListeners();
  }

  Future<void> signOut() async {
    _errorMessage = null;
    _renewTimer?.cancel();
    // End this browser's token on the server too (best effort, quick).
    final token = _session?.accessToken;
    if (token != null) await _backendAuthService.logout(token);
    await _clearStoredSession();
    try {
      await FirebaseAuthService.signOut();
    } catch (error, stackTrace) {
      AppLogger.error('Sign out failed', error, stackTrace);
      _errorMessage = friendlyAuthError(error);
    }
    // Only an explicit sign-out tells the other tabs; a sign-in that failed
    // and was rolled back never does.
    _tabs.post(tabSignedOut);
    _setStatus(AuthStatus.unauthenticated);
  }

  /// Renews the session from Firebase if it ends within [renewBefore].
  /// Never throws.
  Future<void> _renewIfDue() async {
    final expiresAt = _session?.expiresAt;
    if (expiresAt == null || !isAuthenticated) return;
    if (expiresAt.difference(DateTime.now().toUtc()) > renewBefore) return;
    await renewSession();
  }

  /// Swaps the session for a new one, from Firebase's sign-in, if Firebase
  /// is still signed in as the same person. Returns whether it did. Never
  /// throws; one renewal at a time.
  Future<bool> renewSession() {
    final running = _renewing;
    if (running != null) return running;
    final renewal = _renew();
    _renewing = renewal;
    renewal.whenComplete(() {
      if (identical(_renewing, renewal)) _renewing = null;
    });
    return renewal;
  }

  Future<bool> _renew() async {
    final current = _session;
    if (current == null) return false;
    final renewed = await _renewedFrom(current);
    // Signed out, or someone else, while this was running: leave it.
    if (renewed == null || _session?.firebaseUid != current.firebaseUid) {
      return false;
    }
    await _setAuthenticated(renewed);
    notifyListeners();
    return true;
  }

  /// A new session for the person of [previous], exchanged from Firebase's
  /// sign-in, or null if Firebase isn't signed in as them (signed out, or
  /// someone else) or the exchange fails. Only ever replaces an existing
  /// session: after a sign-out there is nothing to renew.
  Future<AuthSession?> _renewedFrom(AuthSession previous) async {
    try {
      final uid = await FirebaseAuthService.restoredUid();
      if (uid == null || uid != previous.firebaseUid) return null;
      final firebaseToken = await FirebaseAuthService.idToken();
      final backendSession = await _backendAuthService.loginWithFirebaseToken(
        firebaseToken,
      );
      final validated = await _backendAuthService.validateAccessToken(
        backendSession.accessToken,
      );
      if (validated.firebaseUid != previous.firebaseUid) return null;
      AppLogger.info('Backend session renewed.');
      return validated;
    } catch (error) {
      AppLogger.warning('Session renewal failed: $error');
      return null;
    }
  }

  void _scheduleRenewal() {
    _renewTimer?.cancel();
    final expiresAt = _session?.expiresAt;
    if (expiresAt == null) return;
    var wait = expiresAt.difference(DateTime.now().toUtc()) - renewBefore;
    if (wait.isNegative) wait = Duration.zero;
    _renewTimer = Timer(wait, () => unawaited(renewSession()));
  }

  /// What another tab of this site said (see [AuthTabChannel]).
  @visibleForTesting
  void onTabMessage(String message) => _onTabMessage(message);

  void _onTabMessage(String message) {
    if (message == tabSignedOut) {
      // Signed out there: out here too. The stored session is already gone.
      final session = _session;
      if (session == null) return;
      // This tab's token can differ from the one that tab ended (each tab
      // renews its own): end it too.
      unawaited(_backendAuthService.logout(session.accessToken));
      onSignedOutElsewhere?.call();
      _renewTimer?.cancel();
      _setUnauthenticated();
      return;
    }
    if (message.startsWith(tabSignedInPrefix)) {
      // Signed in there as someone else: reload as them, so nothing of the
      // previous person stays on screen. A tab that is signed out, or
      // already signed in as them, stays as it is (a tab waiting for an
      // emailed sign-in link must not take the page it will go back to).
      final uid = message.substring(tabSignedInPrefix.length);
      final mine = _session?.firebaseUid;
      if (mine != null && mine != uid) _tabs.reload();
    }
  }

  /// Re-reads the signed-in user (and their admin rights) from `/auth/me`,
  /// e.g. when the Admin page opens, so a role change shows without a
  /// reload. Keeps the current session if the refresh fails.
  Future<void> refreshSession() async {
    final current = _session;
    if (current == null || !isAuthenticated) return;
    try {
      final refreshed = await _backendAuthService.validateAccessToken(
        current.accessToken,
      );
      _session = refreshed;
      await _sessionStore.save(refreshed);
      notifyListeners();
    } catch (error) {
      AppLogger.warning('Session refresh failed: $error');
    }
  }

  Future<void> _runLoginFlow(Future<User?> Function() firebaseLogin) async {
    _errorMessage = null;
    _setStatus(AuthStatus.authenticating);

    try {
      final user = await firebaseLogin();
      if (user == null) {
        throw StateError('Firebase login did not return a user.');
      }

      final firebaseToken = await FirebaseAuthService.idToken();
      final backendSession = await _backendAuthService.loginWithFirebaseToken(
        firebaseToken,
      );
      final validatedSession = await _backendAuthService.validateAccessToken(
        backendSession.accessToken,
      );
      await _setAuthenticated(validatedSession);
      _tabs.post('$tabSignedInPrefix${validatedSession.firebaseUid}');
      AppLogger.info('Backend-authenticated login completed.');
    } catch (error, stackTrace) {
      AppLogger.error('Login failed', error, stackTrace);
      // Set before the rollback: signing out of Firebase can notify
      // listeners, and they must already find the reason for the failure.
      _errorMessage = friendlyAuthError(error);
      await _rollBackLogin();
      _setStatus(AuthStatus.unauthenticated);
      rethrow;
    }
  }

  /// Undoes a login that did not complete.
  ///
  /// Firebase is usually signed in by the time the backend refuses the
  /// exchange, so it is signed out as well: a login is either fully
  /// established or fully rolled back. A cleanup step that fails is logged
  /// and skipped, so it cannot replace the error that caused the rollback.
  Future<void> _rollBackLogin() async {
    _session = null;
    try {
      await _sessionStore.clear();
    } catch (error, stackTrace) {
      AppLogger.error(
        'Could not clear the stored session after a failed login',
        error,
        stackTrace,
      );
    }
    try {
      await FirebaseAuthService.signOut();
    } catch (error, stackTrace) {
      AppLogger.error(
        'Could not sign out of Firebase after a failed login',
        error,
        stackTrace,
      );
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
    _scheduleRenewal();
    _setStatus(AuthStatus.authenticated);
  }

  Future<void> _clearStoredSession() async {
    _renewTimer?.cancel();
    _session = null;
    await _sessionStore.clear();
  }

  void _setUnauthenticated() {
    _renewTimer?.cancel();
    _session = null;
    _setStatus(AuthStatus.unauthenticated);
  }

  void _setStatus(AuthStatus status) {
    if (_status == status) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _renewTimer?.cancel();
    _firebaseAuthSubscription?.cancel();
    super.dispose();
  }
}

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  return AuthController.instance;
});
