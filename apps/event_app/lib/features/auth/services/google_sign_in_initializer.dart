import 'package:google_sign_in/google_sign_in.dart';

class GoogleSignInInitializer {
  GoogleSignInInitializer._();

  static final Future<void> _initialization = GoogleSignIn.instance
      .initialize();

  static Future<void> ensureInitialized() => _initialization;
}
