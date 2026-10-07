// Regression tests for ISSUE-003: every backend login failure was shown as
// "Sign in failed. Please try again."
//
// These cover the message a user sees for each kind of failure.

import 'package:dio/dio.dart';
import 'package:event_app/features/auth/services/auth_error_messages.dart';
import 'package:event_app/features/auth/services/backend_auth_exception.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

const _verifyEmail = 'Please verify your email address before signing in.';
const _suspended =
    'Your account is currently suspended. Please contact support if you '
    'believe this is an error.';
const _emailRequired =
    'An email address is required to sign in. Please use an account with a '
    'valid email address.';
const _sessionNotVerified =
    'Your sign-in session could not be verified. Please sign in again.';
const _cannotConnect =
    'Unable to connect to the server. Check your internet connection and try '
    'again.';
const _serverUnavailable =
    'The server is temporarily unavailable. Please try again shortly.';
const _generic = 'Sign in failed. Please try again.';

void main() {
  group('backend failures', () {
    const cases = [
      (BackendAuthFailure.emailNotVerified, _verifyEmail),
      (BackendAuthFailure.accountSuspended, _suspended),
      (BackendAuthFailure.emailMissing, _emailRequired),
      (BackendAuthFailure.sessionRejected, _sessionNotVerified),
      (BackendAuthFailure.network, _cannotConnect),
      (BackendAuthFailure.server, _serverUnavailable),
      (BackendAuthFailure.unknown, _generic),
    ];

    for (final (failure, message) in cases) {
      test('${failure.name} has its own message', () {
        expect(friendlyAuthError(BackendAuthException(failure)), message);
      });
    }

    test('every kind of failure is covered above', () {
      expect(
        cases.map((c) => c.$1).toSet(),
        BackendAuthFailure.values.toSet(),
      );
    });

    test('only the unknown failure gets the generic message', () {
      for (final failure in BackendAuthFailure.values) {
        if (failure == BackendAuthFailure.unknown) continue;
        expect(
          friendlyAuthError(BackendAuthException(failure)),
          isNot(_generic),
          reason: failure.name,
        );
      }
    });

    test('the message never shows the backend code or the status', () {
      const exception = BackendAuthException(
        BackendAuthFailure.emailNotVerified,
        code: 'email_not_verified',
        statusCode: 403,
      );

      final message = friendlyAuthError(exception);

      expect(message, isNot(contains('email_not_verified')));
      expect(message, isNot(contains('403')));
      expect(message, isNot(contains('Exception')));
    });
  });

  group('Firebase failures keep their own messages', () {
    const cases = [
      ('invalid-email', 'Enter a valid email address.'),
      ('user-disabled', 'This account has been disabled.'),
      ('user-not-found', 'No account was found for that email.'),
      ('wrong-password', 'The password is incorrect.'),
      ('invalid-credential', 'The email or password is incorrect.'),
      (
        'too-many-requests',
        'Too many attempts. Please wait a moment and try again.',
      ),
      (
        'network-request-failed',
        'A network error occurred. Check your connection and try again.',
      ),
      (
        'popup-blocked',
        'Sign-in popup was blocked. Please allow popups and try again.',
      ),
      (
        'popup-closed-by-user',
        'Sign in failed. Please try again or use Google Sign-In.',
      ),
    ];

    for (final (code, message) in cases) {
      test(code, () {
        expect(friendlyAuthError(FirebaseAuthException(code: code)), message);
      });
    }
  });

  group('anything else gets the generic message, never its own text', () {
    test('a StateError', () {
      expect(
        friendlyAuthError(StateError('Firebase login did not return a user.')),
        _generic,
      );
    });

    test('a raw DioException', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/v1/auth/firebase'),
        type: DioExceptionType.badResponse,
        message: 'status code of 403',
      );

      expect(friendlyAuthError(error), _generic);
    });

    test('a plain Exception', () {
      expect(friendlyAuthError(Exception('boom')), _generic);
    });
  });
}
