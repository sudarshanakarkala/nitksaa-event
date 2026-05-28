import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/logger/app_logger.dart';

abstract class FirebaseAuthService {
  static Future<User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    // TODO: Implement email/password sign-in
    AppLogger.info('signInWithEmail called for: $email');
    return null;
  }

  static Future<User?> signInWithGoogle() async {
    try {
      AppLogger.info('signInWithGoogle called');
      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        final UserCredential userCredential =
            await FirebaseAuth.instance.signInWithPopup(googleProvider);
        return userCredential.user;
      } else {
        final GoogleSignIn googleSignIn = GoogleSignIn();
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          AppLogger.info('Google Sign-In cancelled by user');
          return null;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final UserCredential userCredential =
            await FirebaseAuth.instance.signInWithCredential(credential);
        return userCredential.user;
      }
    } catch (e, st) {
      AppLogger.error('Google Sign-In failed', e, st);
      rethrow;
    }
  }

  static Future<void> signOut() async {
    AppLogger.info('signOut called');
    await FirebaseAuth.instance.signOut();
  }
}
