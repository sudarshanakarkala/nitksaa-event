// Tests for ISSUE-005 below the screens: the refund status request, the
// provider that holds its answer for one signed-in session, and the message
// each failure maps to.
//
// RefundStatusNotifier and EventsRepository are the real classes, on a real
// Dio client whose transport is the fake backend. The refund view itself is
// covered by refund_screens_test.dart.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:event_app/features/auth/domain/auth_session.dart';
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/domain/my_event_registration.dart';
import 'package:event_app/features/events/domain/refund_status.dart';
import 'package:event_app/features/events/presentation/providers/refund_status_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_isolation_fakes.dart';
import 'support/registration_backend_fake.dart';

const _notFound =
    "We couldn't find this registration. Please refresh and try again.";
const _noConnection =
    'Unable to connect to the server. Check your internet connection and try '
    'again.';
const _couldNotLoad = 'Could not load the refund status. Please try again.';

/// What must never be shown to an attendee.
final _technicalWording = RegExp(
  r'exception|dio|status code|\b[45]\d\d\b|_',
  caseSensitive: false,
);

/// A provider container wired to the fakes, with one refund view open: the
/// listener a mounted view would hold, and a record of every state it would
/// have rendered.
class _Harness {
  _Harness(this.backend, this.registrationId) {
    container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth),
        eventsRepositoryProvider.overrideWithValue(backend.repository),
      ],
    );
    addTearDown(container.dispose);
  }

  final FakeRegistrationBackend backend;
  final int registrationId;
  final auth = FakeAuthController();
  late final ProviderContainer container;
  final states = <RefundStatusState>[];
  ProviderSubscription<RefundStatusState>? _subscription;

  void openView() {
    _subscription = container.listen(
      refundStatusProvider(registrationId),
      (_, next) => states.add(next),
      fireImmediately: true,
    );
  }

  void closeView() {
    _subscription?.close();
    _subscription = null;
  }

  RefundStatusState get state =>
      container.read(refundStatusProvider(registrationId));

  RefundStatusNotifier get notifier =>
      container.read(refundStatusProvider(registrationId).notifier);

  /// Logout followed by another login, with no restart in between.
  Future<void> switchTo(AuthSession session) async {
    await auth.signOut();
    auth.logIn(session);
  }
}

int _idOf(Map<String, dynamic> registration) =>
    registration['registration_id'] as int;

/// A harness for user A, signed in, whose registration has [refund].
_Harness _harnessWithRefund(
  String? refund, {
  FakeRegistrationBackend? backend,
}) {
  backend ??= FakeRegistrationBackend();
  final registration = backend.seedRegistration(
    tokenA,
    status: 'cancelled',
    paid: true,
    refund: refund,
  );
  return _Harness(backend, _idOf(registration))..auth.logIn(sessionA);
}

void main() {
  group('ISSUE-005: refund status request', () {
    test('Test A: GET /registrations/{id}/refund with the bearer token and '
        'no body', () async {
      final backend = FakeRegistrationBackend(finalAmount: '123.45');
      final registration = backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_processed',
      );

      final refund = await backend.repository.getRefundStatus(
        _idOf(registration),
        tokenA,
      );

      final request = backend.requests.single;
      expect(
        request.line,
        'GET /api/v1/registrations/${_idOf(registration)}/refund',
      );
      expect(request.bearer, 'Bearer $tokenA');
      expect(request.rawBody, isEmpty);

      expect(refund.status, RefundStatus.processed);
      expect(refund.hasRefund, isTrue);
      expect(refund.refundId, 'RFND-${_idOf(registration)}');
      expect(refund.registrationId, _idOf(registration));
      expect(refund.amount, 123.45);
      expect(refund.currency, 'INR');
      expect(refund.requestedAt, isNotNull);
      expect(refund.finalizedAt, isNotNull);
      expect(refund.safeMessage, isNotEmpty);
    });

    test('Test F: a registration with no refund answers none', () async {
      final backend = FakeRegistrationBackend(isFree: true);
      final registration = backend.seedRegistration(tokenA, status: 'cancelled');

      final refund = await backend.repository.getRefundStatus(
        _idOf(registration),
        tokenA,
      );

      expect(refund.status, RefundStatus.none);
      expect(refund.hasRefund, isFalse);
      expect(refund.amount, isNull);
    });

    test('a status this app does not know is kept as it is, not thrown on', () {
      final refund = RefundStatus.fromJson({
        'registration_id': 7,
        'status': 'refund_on_hold',
        'amount': '10.00',
        'safe_message': null,
      });

      expect(refund.status, 'refund_on_hold');
      expect(refund.hasRefund, isTrue);
      expect(refund.amount, 10.0);
      expect(refund.safeMessage, isNull);
    });
  });

  group('ISSUE-005: refund status state', () {
    test('nothing is fetched until the view asks', () async {
      final h = _harnessWithRefund('refund_pending')..openView();
      await pumpEventQueue();

      expect(h.backend.requests, isEmpty);
      expect(h.state.refund, isNull);
      expect(h.state.isLoading, isFalse);
      expect(h.state.errorMessage, isNull);
    });

    test('Tests B, C: loading, then pending, then processed on the next '
        'check', () async {
      final h = _harnessWithRefund('refund_pending')..openView();

      final first = h.notifier.check();
      expect(h.state.isLoading, isTrue);
      await first;
      expect(h.state.isLoading, isFalse);
      expect(h.state.refund?.status, RefundStatus.pending);
      expect(h.state.errorMessage, isNull);

      h.backend.razorpayNowSays = 'refund_processed';
      await h.notifier.check();

      expect(h.state.refund?.status, RefundStatus.processed);
      expect(h.state.refund?.finalizedAt, isNotNull);
      expect(h.backend.refundStatusRequests, hasLength(2));
    });

    test('Test E: a refund that failed at the payment provider', () async {
      final h = _harnessWithRefund('refund_pending')..openView();
      h.backend.razorpayNowSays = 'refund_failed';

      await h.notifier.check();

      expect(h.state.refund?.status, RefundStatus.failed);
      expect(
        h.state.refund?.safeMessage,
        'Your registration is cancelled, but the refund could not be '
        'completed automatically. Our team will follow up.',
      );
    });

    test('Test G: showing a refund the app already has sends nothing', () async {
      final h = _harnessWithRefund('refund_pending')..openView();
      const fromCancel = RefundStatus(
        status: RefundStatus.pending,
        refundId: 'RFND-1',
        amount: 99,
      );

      h.notifier.show(fromCancel);
      await pumpEventQueue();

      expect(h.state.refund, same(fromCancel));
      expect(h.state.isLoading, isFalse);
      expect(h.backend.requests, isEmpty);
    });

    test('Test K: one GET per check, a second check while one is in flight '
        'is ignored, and nothing but GET is sent', () async {
      final backend = FakeRegistrationBackend()
        ..heldRefundStatus = Completer<void>();
      final h = _harnessWithRefund('refund_pending', backend: backend)
        ..openView();

      final inFlight = h.notifier.check();
      await h.notifier.check();
      await pumpEventQueue();
      expect(backend.refundStatusRequests, hasLength(1));
      backend.heldRefundStatus!.complete();
      await inFlight;

      backend.heldRefundStatus = null;
      for (var i = 0; i < 3; i++) {
        await h.notifier.check();
      }

      expect(backend.refundStatusRequests, hasLength(4));
      expect(backend.requests.where((r) => r.method != 'GET'), isEmpty);
      expect(backend.refundsCreated, 0);
    });

    test('the state is discarded when the view closes, so opening it again '
        'starts empty', () async {
      final h = _harnessWithRefund('refund_processed')..openView();
      await h.notifier.check();
      expect(h.state.refund, isNotNull);

      h.closeView();
      await pumpEventQueue();
      h.openView();

      expect(h.state.refund, isNull);
      expect(h.backend.refundStatusRequests, hasLength(1));
    });
  });

  group('ISSUE-005: errors', () {
    test('Test I: 404 for a registration that is not the caller\'s', () async {
      final backend = FakeRegistrationBackend();
      final theirs = backend.seedRegistration(
        tokenB,
        status: 'cancelled',
        refund: 'refund_processed',
      );
      final h = _Harness(backend, _idOf(theirs))
        ..auth.logIn(sessionA)
        ..openView();

      await h.notifier.check();

      expect(backend.refundStatusRequests.single.bearer, 'Bearer $tokenA');
      expect(h.state.refund, isNull);
      expect(h.state.errorMessage, _notFound);
    });

    test('Test I: no connection', () async {
      final backend = FakeRegistrationBackend()..refundStatusRequestsToDrop = 1;
      final h = _harnessWithRefund('refund_pending', backend: backend)
        ..openView();

      await h.notifier.check();

      expect(h.state.refund, isNull);
      expect(h.state.isLoading, isFalse);
      expect(h.state.errorMessage, _noConnection);
    });

    test('Test I: a 500, and anything else, gets the general message', () async {
      final backend = FakeRegistrationBackend()..refundStatusServerError = 500;
      final h = _harnessWithRefund('refund_pending', backend: backend)
        ..openView();

      await h.notifier.check();
      expect(h.state.errorMessage, _couldNotLoad);

      backend.refundStatusServerError = 503;
      await h.notifier.check();
      expect(h.state.errorMessage, _couldNotLoad);
    });

    test('a failed check keeps the last refund, and the next good one '
        'clears the error', () async {
      final h = _harnessWithRefund('refund_pending')..openView();
      await h.notifier.check();

      h.backend.refundStatusRequestsToDrop = 1;
      await h.notifier.check();
      expect(h.state.refund?.status, RefundStatus.pending);
      expect(h.state.errorMessage, _noConnection);

      await h.notifier.check();
      expect(h.state.refund?.status, RefundStatus.pending);
      expect(h.state.errorMessage, isNull);
    });

    test('no message shows exception text, a status code or a backend code', () {
      final request = RequestOptions(path: '/api/v1/registrations/1/refund');
      DioException http(int statusCode, Object? data) => DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response<Object?>(
          requestOptions: request,
          statusCode: statusCode,
          data: data,
        ),
      );
      final errors = <Object>[
        StateError('boom'),
        const FormatException('bad json'),
        for (final type in DioExceptionType.values)
          DioException(requestOptions: request, type: type, message: 'boom'),
        http(404, {'detail': 'registration_not_found'}),
        http(404, {'detail': 'Not Found'}),
        http(401, {'detail': 'invalid_or_expired_token'}),
        http(403, {'detail': 'alumni_only'}),
        http(422, {
          'detail': [
            {'msg': 'Input should be a valid integer'},
          ],
        }),
        http(500, 'Internal Server Error'),
        http(502, null),
      ];

      for (final error in errors) {
        final message = refundStatusErrorMessage(error);
        expect(message, isNot(contains(_technicalWording)));
        expect(message, endsWith('.'));
        expect([_notFound, _noConnection, _couldNotLoad], contains(message));
      }
    });
  });

  group('ISSUE-005: one user never gets another user\'s refund', () {
    test('Test J: after logout and login as user B, the state holds nothing '
        'of user A and nothing is asked for with A\'s token', () async {
      final backend = FakeRegistrationBackend(finalAmount: '777.00');
      final h = _harnessWithRefund('refund_pending', backend: backend)
        ..openView();
      await h.notifier.check();
      expect(h.state.refund?.amount, 777);
      final requestsAsA = backend.requests.length;
      final statesAsA = h.states.length;

      await h.switchTo(sessionB);
      await pumpEventQueue();

      expect(h.state.refund, isNull);
      expect(h.state.isLoading, isFalse);
      expect(h.state.errorMessage, isNull);
      expect(backend.requests, hasLength(requestsAsA));

      // The same registration id, now asked for as user B.
      await h.notifier.check();

      final afterSwitch = backend.requests.skip(requestsAsA).toList();
      expect(afterSwitch.single.bearer, 'Bearer $tokenB');
      expect(h.state.refund, isNull);
      expect(h.state.errorMessage, _notFound);
      // No state since the switch has held a refund, A's or anyone's.
      final sinceSwitch = h.states.skip(statesAsA).toList();
      expect(sinceSwitch, isNotEmpty);
      expect(sinceSwitch.where((s) => s.refund != null), isEmpty);
    });

    test('Test J: an answer for user A that arrives after the switch is '
        'dropped', () async {
      final backend = FakeRegistrationBackend()
        ..heldRefundStatus = Completer<void>();
      final h = _harnessWithRefund('refund_processed', backend: backend)
        ..openView();
      final inFlightForA = h.notifier.check();
      await pumpEventQueue();
      expect(backend.refundStatusRequests, hasLength(1));

      await h.switchTo(sessionB);
      backend.heldRefundStatus!.complete();
      await inFlightForA;
      await pumpEventQueue();

      expect(h.state.refund, isNull);
      expect(h.states.where((s) => s.refund != null), isEmpty);
      expect(backend.refundStatusRequests, hasLength(1));
    });

    test('signed out: nothing is sent', () async {
      final backend = FakeRegistrationBackend();
      final registration = backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_pending',
      );
      final h = _Harness(backend, _idOf(registration))
        ..auth.restore(null)
        ..openView();

      await h.notifier.check();

      expect(backend.requests, isEmpty);
      expect(h.state.refund, isNull);
    });
  });

  group('ISSUE-005: which registrations can have a refund', () {
    MyEventRegistration parse(String status, {String? latestOrderId}) {
      return MyEventRegistration.fromJson({
        'registration_id': 1,
        'event_id': eventX,
        'status': status,
        'registered_at': '2098-12-01T10:00:00Z',
        'latest_order_id': latestOrderId,
      });
    }

    test('latest_order_id is read from the registration', () {
      expect(parse('cancelled', latestOrderId: 'ORD-abc').latestOrderId, 'ORD-abc');
      expect(parse('cancelled').latestOrderId, isNull);
    });

    test('only a cancelled registration with a payment order may have one', () {
      expect(parse('cancelled', latestOrderId: 'ORD-abc').mayHaveRefund, isTrue);
      // Free: no order was ever made.
      expect(parse('cancelled').mayHaveRefund, isFalse);
      for (final status in const [
        'registered',
        'seat_held',
        'payment_pending',
        'payment_verification',
        'payment_failed',
      ]) {
        expect(parse(status, latestOrderId: 'ORD-abc').mayHaveRefund, isFalse);
      }
    });

    test('My Events rows carry latest_order_id through the repository', () async {
      final backend = FakeRegistrationBackend();
      backend.seedRegistration(tokenA, status: 'cancelled');
      final paid = backend.seedRegistration(
        tokenA,
        status: 'cancelled',
        refund: 'refund_pending',
      );

      final rows = await backend.repository.getMyRegistrations(tokenA);

      expect(rows.map((r) => r.latestOrderId), ['ORD-${_idOf(paid)}', null]);
      expect(rows.map((r) => r.mayHaveRefund), [true, false]);
      // Listing registrations does not ask about refunds.
      expect(backend.refundStatusRequests, isEmpty);
    });
  });
}
