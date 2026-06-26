import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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

  static Future<User?> signInWithGoogle() async {
    AppLogger.info('signInWithGoogle called');

    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      provider.addScope('email');
      provider.addScope('profile');
      provider.setCustomParameters({'prompt': 'select_account'});
      final userCredential = await FirebaseAuth.instance.signInWithPopup(
        provider,
      );
      return userCredential.user;
    }

    await GoogleSignInInitializer.ensureInitialized();
    final googleUser = await GoogleSignIn.instance.authenticate();
    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    final userCredential = await FirebaseAuth.instance.signInWithCredential(
      credential,
    );
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
