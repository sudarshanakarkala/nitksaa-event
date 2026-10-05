// Regression tests for ISSUE-002: after logout, "Sign in with Google" on web
// signed the previous Google account straight back in without showing the
// account chooser.
//
// Plain `flutter test` runs the first test. The others exercise the real web
// code path (`kIsWeb`) and need a browser:
//
//   flutter test --platform chrome test/features/auth/google_sign_in_account_chooser_test.dart

import 'package:event_app/features/auth/services/firebase_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_fakes.dart';

void main() {
  final firebase = FakeFirebaseAuthPlatform();

  setUpAll(() => installFakeFirebase(firebase));
  setUp(firebase.reset);

  test('Test A: the Google popup asks Google to show the account '
      'chooser', () async {
    await FirebaseAuthService.signInWithGooglePopup();

    expect(oauthParameters(firebase.popupProviders.single), {
      'prompt': 'select_account',
    });
  });

  test('Test A: signInWithGoogle on web opens that popup', () async {
    await FirebaseAuthService.signInWithGoogle();

    expect(oauthParameters(firebase.popupProviders.single), {
      'prompt': 'select_account',
    });
  }, testOn: 'browser');

  test('web logout signs out of Firebase and nothing else', () async {
    firebase.browserGoogleAccount = accountA;

    await FirebaseAuthService.signOut();

    expect(firebase.signOutCalls, 1);
    expect(firebase.browserGoogleAccount, accountA);
  }, testOn: 'browser');
}
