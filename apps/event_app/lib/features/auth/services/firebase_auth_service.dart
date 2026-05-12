import 'package:firebase_auth/firebase_auth.dart';
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

  static Future<void> signOut() async {
    AppLogger.info('signOut called');
    await FirebaseAuth.instance.signOut();
  }
}
