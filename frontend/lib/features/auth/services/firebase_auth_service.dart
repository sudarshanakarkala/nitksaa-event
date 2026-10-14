import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../../../core/logger/app_logger.dart';

abstract class FirebaseAuthService {
  static Future<User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    AppLogger.info('signInWithEmail called for: $email');
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return credential.user;
  }

  /// Signs in with Google through Firebase's OAuth popup (the app is
  /// web-only, so no GoogleSignIn SDK is needed).
  static Future<User?> signInWithGoogle() async {
    AppLogger.info('signInWithGoogle called');
    return signInWithGooglePopup();
  }

  /// Web Google sign-in through Firebase's OAuth popup.
  ///
  /// Logging out on web ends the Firebase session but leaves the browser
  /// signed in to Google, so without `prompt=select_account` Google hands the
  /// previous account straight back and the user cannot switch accounts.
  @visibleForTesting
  static Future<User?> signInWithGooglePopup() async {
    final provider = GoogleAuthProvider();
    provider.setCustomParameters({'prompt': 'select_account'});
    final userCredential =
        await FirebaseAuth.instance.signInWithPopup(provider);
    return userCredential.user;
  }

  /// Emails a one-time sign-in link (website's magic link).
  ///
  /// The continue URL is the site's origin with no `#/` route: Firebase
  /// appends `?apiKey=…&oobCode=…&mode=signIn` to it, and a query after a
  /// `#` fragment would be lost.
  static Future<void> sendSignInLink(String email) async {
    AppLogger.info('sendSignInLink called');
    await FirebaseAuth.instance.sendSignInLinkToEmail(
      email: email,
      actionCodeSettings: ActionCodeSettings(
        url: '${Uri.base.origin}/',
        handleCodeInApp: true,
      ),
    );
  }

  /// Whether [link] (normally the page's own URL) is a Firebase sign-in link.
  ///
  /// Checked here, not with `FirebaseAuth.isSignInWithEmailLink`: on the web
  /// the FlutterFire plugin calls Firebase's JS `isSignInWithEmailLink`
  /// without the auth instance it requires, so it always answers false and
  /// the link is ignored. This is Firebase's own rule: `mode=signIn` with an
  /// `oobCode`, either on the URL itself or inside a `link` parameter.
  static bool isSignInLink(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null) return false;
    final params = uri.queryParameters;
    if (params['mode'] == 'signIn' && (params['oobCode'] ?? '').isNotEmpty) {
      return true;
    }
    final nested = params['link'];
    return nested != null && nested != link && isSignInLink(nested);
  }

  /// Completes a sign-in link for [email].
  static Future<User?> signInWithEmailLink({
    required String email,
    required String link,
  }) async {
    AppLogger.info('signInWithEmailLink called');
    final credential = await FirebaseAuth.instance.signInWithEmailLink(
      email: email,
      emailLink: link,
    );
    return credential.user;
  }

  static Future<String> freshIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken(true);
    if (user == null || token == null || token.isEmpty) {
      throw StateError('Firebase user or ID token is unavailable.');
    }
    return token;
  }

  static Future<void> signOut() async {
    AppLogger.info('signOut called');
    await FirebaseAuth.instance.signOut();
  }
}
