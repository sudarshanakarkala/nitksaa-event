import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/logger/app_logger.dart';
import 'google_sign_in_initializer.dart';

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

  /// Signs in with Google.
  ///
  /// On **web**: uses [FirebaseAuth.signInWithPopup] with [GoogleAuthProvider]
  /// (no GoogleSignIn SDK needed — avoids the `authenticate()` restriction).
  ///
  /// On **mobile**: uses the GoogleSignIn SDK flow.
  static Future<User?> signInWithGoogle() async {
    AppLogger.info('signInWithGoogle called (kIsWeb=$kIsWeb)');

    if (kIsWeb) {
      // Web: use Firebase's own OAuth popup — no GoogleSignIn SDK required.
      final provider = GoogleAuthProvider();
      final userCredential =
          await FirebaseAuth.instance.signInWithPopup(provider);
      return userCredential.user;
    }

    // Mobile (Android / iOS) — v7 API: authenticate() is the correct method.
    await GoogleSignInInitializer.ensureInitialized();
    final GoogleSignInAccount googleUser =
        await GoogleSignIn.instance.authenticate();

    // In google_sign_in v7, .authentication is synchronous (not a Future).
    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      // accessToken was removed in v7 — idToken alone is sufficient.
    );
    final userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);
    return userCredential.user;
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
    if (!kIsWeb) {
      try {
        await GoogleSignInInitializer.ensureInitialized();
        await GoogleSignIn.instance.signOut();
      } catch (error, stackTrace) {
        AppLogger.warning('Google sign-out skipped or failed: $error');
        AppLogger.debug(stackTrace.toString());
      }
    }
    await FirebaseAuth.instance.signOut();
  }
}
