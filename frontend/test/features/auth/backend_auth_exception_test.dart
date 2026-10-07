// Regression tests for ISSUE-003: the backend's reason for refusing a login
// was lost before it reached the auth controller.
//
// These cover how a failed auth request is classified. The `detail` codes and
// statuses are the ones the backend raises in `app/api/auth.py` and
// `app/middleware/auth.py`.

import 'package:dio/dio.dart';
import 'package:event_app/features/auth/services/backend_auth_exception.dart';
import 'package:event_app/features/auth/services/backend_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_fakes.dart';

const _firebaseIdToken = 'secret-firebase-id-token';
const _backendToken = 'secret-backend-token';

/// A request as `BackendAuthService` sends it, credentials included.
RequestOptions _request() => RequestOptions(
  path: '/api/v1/auth/firebase',
  data: {'token': _firebaseIdToken},
  headers: {'Authorization': 'Bearer $_backendToken'},
);

BackendAuthException _fromResponse(int statusCode, Object? body) {
  final request = _request();
  return BackendAuthException.fromDio(
    DioException(
      requestOptions: request,
      response: Response<Object?>(
        requestOptions: request,
        statusCode: statusCode,
        data: body,
      ),
      type: DioExceptionType.badResponse,
    ),
  );
}

BackendAuthException _fromTransport(DioExceptionType type) {
  return BackendAuthException.fromDio(
    DioException(requestOptions: _request(), type: type),
  );
}

void main() {
  group('a backend rejection keeps its detail code and status', () {
    const cases = [
      (403, 'email_not_verified', BackendAuthFailure.emailNotVerified),
      (403, 'account_suspended', BackendAuthFailure.accountSuspended),
      (400, 'email_missing', BackendAuthFailure.emailMissing),
      (401, 'firebase_token_expired', BackendAuthFailure.sessionRejected),
      (401, 'invalid_firebase_token', BackendAuthFailure.sessionRejected),
      (400, 'firebase_uid_missing', BackendAuthFailure.sessionRejected),
      (401, 'invalid_or_expired_token', BackendAuthFailure.sessionRejected),
      (401, 'invalid_token', BackendAuthFailure.sessionRejected),
    ];

    for (final (statusCode, code, failure) in cases) {
      test('$statusCode $code is ${failure.name}', () {
        final exception = _fromResponse(statusCode, {'detail': code});

        expect(exception.failure, failure);
        expect(exception.code, code);
        expect(exception.statusCode, statusCode);
      });
    }
  });

  group('a rejection with no known code is classified by its status', () {
    test('401 is a rejected session', () {
      final exception = _fromResponse(401, {'detail': 'some_new_code'});

      expect(exception.failure, BackendAuthFailure.sessionRejected);
      expect(exception.code, 'some_new_code');
    });

    test('403 from a missing bearer token is a rejected session', () {
      final exception = _fromResponse(403, {'detail': 'Not authenticated'});

      expect(exception.failure, BackendAuthFailure.sessionRejected);
    });

    test('500 is a server failure, even with a detail code', () {
      final exception = _fromResponse(500, {
        'detail': 'firebase_admin_not_installed',
      });

      expect(exception.failure, BackendAuthFailure.server);
      expect(exception.code, 'firebase_admin_not_installed');
      expect(exception.statusCode, 500);
    });

    test('503 with an HTML body is a server failure', () {
      final exception = _fromResponse(503, '<html>Service Unavailable</html>');

      expect(exception.failure, BackendAuthFailure.server);
      expect(exception.code, isNull);
    });

    test('422 with a validation-error list is unknown', () {
      final exception = _fromResponse(422, {
        'detail': [
          {'loc': ['body', 'token'], 'msg': 'Field required'},
        ],
      });

      expect(exception.failure, BackendAuthFailure.unknown);
      expect(exception.code, isNull);
      expect(exception.statusCode, 422);
    });

    test('404 is unknown', () {
      final exception = _fromResponse(404, {'detail': 'Not Found'});

      expect(exception.failure, BackendAuthFailure.unknown);
    });
  });

  group('a request that gets no answer', () {
    const networkTypes = [
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.badCertificate,
    ];

    for (final type in networkTypes) {
      test('${type.name} is a network failure', () {
        final exception = _fromTransport(type);

        expect(exception.failure, BackendAuthFailure.network);
        expect(exception.code, isNull);
        expect(exception.statusCode, isNull);
      });
    }

    test('an unclassified Dio error is unknown', () {
      expect(
        _fromTransport(DioExceptionType.unknown).failure,
        BackendAuthFailure.unknown,
      );
      expect(
        _fromTransport(DioExceptionType.cancel).failure,
        BackendAuthFailure.unknown,
      );
    });
  });

  test('the exception text carries no token', () {
    final exceptions = [
      _fromResponse(403, {'detail': 'email_not_verified'}),
      _fromResponse(500, '<html>$_backendToken</html>'),
      _fromTransport(DioExceptionType.connectionError),
    ];

    for (final exception in exceptions) {
      expect(exception.toString(), isNot(contains(_firebaseIdToken)));
      expect(exception.toString(), isNot(contains(_backendToken)));
    }
    expect(
      exceptions.first.toString(),
      'BackendAuthException(emailNotVerified, code: email_not_verified, '
      'statusCode: 403)',
    );
  });

  group('BackendAuthService reports failures as BackendAuthException', () {
    late FakeBackend backend;
    late BackendAuthService service;

    setUp(() {
      backend = FakeBackend([accountA]);
      service = BackendAuthService(
        dio: Dio(BaseOptions(baseUrl: 'https://backend.test'))
          ..httpClientAdapter = backend,
      );
    });

    test('POST /auth/firebase refused with email_not_verified', () async {
      backend.loginFault = const BackendFault.http(403, 'email_not_verified');

      await expectLater(
        service.loginWithFirebaseToken(accountA.firebaseIdToken),
        throwsA(
          isA<BackendAuthException>()
              .having((e) => e.code, 'code', 'email_not_verified')
              .having((e) => e.statusCode, 'statusCode', 403)
              .having(
                (e) => e.failure,
                'failure',
                BackendAuthFailure.emailNotVerified,
              ),
        ),
      );
    });

    test('GET /auth/me refused with account_suspended', () async {
      backend.meFault = const BackendFault.http(403, 'account_suspended');

      await expectLater(
        service.validateAccessToken(accountA.backendToken),
        throwsA(
          isA<BackendAuthException>()
              .having((e) => e.code, 'code', 'account_suspended')
              .having(
                (e) => e.failure,
                'failure',
                BackendAuthFailure.accountSuspended,
              ),
        ),
      );
    });

    test('an unknown Firebase ID token is a rejected session', () async {
      await expectLater(
        service.loginWithFirebaseToken('not-a-known-token'),
        throwsA(
          isA<BackendAuthException>()
              .having((e) => e.code, 'code', 'invalid_firebase_token')
              .having(
                (e) => e.failure,
                'failure',
                BackendAuthFailure.sessionRejected,
              ),
        ),
      );
    });

    test('a gateway error page is a server failure', () async {
      backend.loginFault = const BackendFault.rawHttp(
        503,
        '<html>Service Unavailable</html>',
      );

      await expectLater(
        service.loginWithFirebaseToken(accountA.firebaseIdToken),
        throwsA(
          isA<BackendAuthException>()
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.failure, 'failure', BackendAuthFailure.server),
        ),
      );
    });

    test('a dropped connection is a network failure', () async {
      backend.loginFault = const BackendFault.transport(
        DioExceptionType.connectionError,
      );

      await expectLater(
        service.loginWithFirebaseToken(accountA.firebaseIdToken),
        throwsA(
          isA<BackendAuthException>().having(
            (e) => e.failure,
            'failure',
            BackendAuthFailure.network,
          ),
        ),
      );
    });

    test('a valid token still returns the session', () async {
      final session = await service.loginWithFirebaseToken(
        accountA.firebaseIdToken,
      );
      final validated = await service.validateAccessToken(session.accessToken);

      expect(session.accessToken, accountA.backendToken);
      expect(validated.firebaseUid, accountA.uid);
      expect(validated.email, accountA.email);
    });
  });
}
