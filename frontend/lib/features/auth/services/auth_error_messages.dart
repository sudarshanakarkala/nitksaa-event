import 'package:firebase_auth/firebase_auth.dart';

import 'backend_auth_exception.dart';

/// Shown when a sign-in failure cannot be classified.
const genericSignInError = 'Sign in failed. Please try again.';

/// The message to show a user whose sign-in failed.
///
/// Only ever returns one of the fixed strings below: no exception text, HTTP
/// status or backend code reaches the user.
String friendlyAuthError(Object error) {
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
      // Email sign-in links.
      'invalid-action-code' || 'expired-action-code' =>
        'This sign-in link has expired or was already used. Send yourself a new one.',
      'missing-email' => 'Enter the email address the sign-in link was sent to.',
      'quota-exceeded' =>
        'Too many sign-in emails were sent today. Please try again later or use Google Sign-In.',
      'operation-not-allowed' =>
        'Email sign-in links are not available right now. Please use Google Sign-In.',
      'unauthorized-continue-uri' || 'invalid-continue-uri' =>
        'Sign-in links are not set up for this site yet. Please use Google Sign-In.',
      _ => 'Sign in failed. Please try again or use Google Sign-In.',
    };
  }
  if (error is BackendAuthException) {
    return switch (error.failure) {
      BackendAuthFailure.emailNotVerified =>
        'Please verify your email address before signing in.',
      BackendAuthFailure.accountSuspended =>
        'Your account is currently suspended. Please contact support if you '
            'believe this is an error.',
      BackendAuthFailure.emailMissing =>
        'An email address is required to sign in. Please use an account with '
            'a valid email address.',
      BackendAuthFailure.sessionRejected =>
        'Your sign-in session could not be verified. Please sign in again.',
      BackendAuthFailure.network =>
        'Unable to connect to the server. Check your internet connection and '
            'try again.',
      BackendAuthFailure.server =>
        'The server is temporarily unavailable. Please try again shortly.',
      BackendAuthFailure.unknown => genericSignInError,
    };
  }
  return genericSignInError;
}
