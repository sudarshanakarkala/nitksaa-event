// Tests for ISSUE-004 below the screens: the cancel request, its idempotency
// key, the refund status it returns, and the message each outcome maps to.
//
// MyEventsNotifier and EventsRepository are the real classes, on a real Dio
// client whose transport is the fake backend. The buttons themselves are
// covered by cancellation_screens_test.dart.

import 'package:dio/dio.dart';
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/domain/refund_status.dart';
import 'package:event_app/features/events/presentation/providers/cancellation_outcome.dart';
import 'package:event_app/features/events/presentation/providers/my_events_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_isolation_fakes.dart';
import 'support/registration_backend_fake.dart';

const _cancelled = 'Your registration has been cancelled.';
const _cancelledAndRefunding =
    'Your registration has been cancelled. Your refund has been initiated.';
const _contactSupport =
    "We couldn't cancel this registration automatically. Please contact "
    'support.';
const _noConnection =
    'Unable to connect to the server. Check your internet connection and try '
    'again.';
const _generic = 'Could not cancel your registration. Please try again.';

/// What must never be shown to an attendee.
final _technicalWording = RegExp(
  r'exception|dio|status code|\b[45]\d\d\b|_',
  caseSensitive: false,
);

/// My Events for a signed-in attendee, loaded once.
Future<ProviderContainer> _openMyEvents(
  FakeRegistrationBackend backend, {
  bool signedIn = true,
}) async {
  final auth = FakeAuthController();
  signedIn ? auth.logIn(sessionA) : auth.restore(null);
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => auth),
      eventsRepositoryProvider.overrideWithValue(backend.repository),
    ],
  );
  addTearDown(container.dispose);
  container.listen(myEventsProvider, (_, _) {});
  await container.read(myEventsProvider.notifier).fetchMyEvents();
  return container;
}

int _idOf(Map<String, dynamic> registration) =>
    registration['registration_id'] as int;

String _keyOf(RecordedRequest request) =>
    request.json['idempotency_key'] as String;

void main() {
  group('ISSUE-004: idempotency key', () {
    test('Test F: a retry after a network failure repeats the key, and a '
        'later action gets a new one', () async {
      final backend = FakeRegistrationBackend(isFree: true)
        ..cancelRequestsToDrop = 1;
      final first = backend.seedRegistration(tokenA, status: 'registered');
      final container = await _openMyEvents(backend);
      final notifier = container.read(myEventsProvider.notifier);

      final failed = await notifier.cancelRegistration(_idOf(first));
      expect(failed.cancelled, isFalse);
      expect(failed.message, _noConnection);
      expect(first['status'], 'registered');

      final retried = await notifier.cancelRegistration(_idOf(first));
      expect(retried.cancelled, isTrue);
      expect(first['status'], 'cancelled');

      // The attendee registers again and, later, cancels that one too.
      final second = backend.seedRegistration(tokenA, status: 'registered');
      await notifier.fetchMyEvents();
      final again = await notifier.cancelRegistration(_idOf(second));
      expect(again.cancelled, isTrue);

      final keys = backend.cancelRequests.map(_keyOf).toList();
      expect(keys, hasLength(3));
      expect(keys[1], keys[0]);
      expect(keys[2], isNot(keys[0]));
      for (final key in keys) {
        expect(key.length, inInclusiveRange(8, 128));
      }
    });

    test('Test F: when the response is lost after the backend refunded, the '
        'retry gets the same refund and not a second one', () async {
      final backend = FakeRegistrationBackend()..loseNextCancelResponse = true;
      final registration = backend.seedRegistration(
        tokenA,
        status: 'registered',
        paid: true,
      );
      final container = await _openMyEvents(backend);
      final notifier = container.read(myEventsProvider.notifier);

      final lost = await notifier.cancelRegistration(_idOf(registration));
      expect(lost.cancelled, isFalse);
      expect(lost.message, _noConnection);
      // The backend did cancel; the app could not know.
      expect(registration['status'], 'cancelled');
      expect(backend.refundsCreated, 1);

      final retried = await notifier.cancelRegistration(_idOf(registration));

      expect(retried.cancelled, isTrue);
      expect(retried.refund?.refundId, 'RFND-${_idOf(registration)}');
      expect(backend.refundsCreated, 1);
      final keys = backend.cancelRequests.map(_keyOf).toList();
      expect(keys, hasLength(2));
      expect(keys.first, keys.last);
      expect(
        backend.refunds[_idOf(registration)]!['idempotency_key'],
        keys.first,
      );
    });

    test('a 5xx keeps the key, because the backend may have cancelled', () async {
      final backend = FakeRegistrationBackend()..cancelServerError = 500;
      final registration = backend.seedRegistration(
        tokenA,
        status: 'registered',
        paid: true,
      );
      final container = await _openMyEvents(backend);
      final notifier = container.read(myEventsProvider.notifier);

      final failed = await notifier.cancelRegistration(_idOf(registration));
      expect(failed.message, _generic);
      backend.cancelServerError = null;
      await notifier.cancelRegistration(_idOf(registration));

      final keys = backend.cancelRequests.map(_keyOf).toList();
      expect(keys.first, keys.last);
    });

    test('a refusal ends the action: trying again later is a new one', () async {
      final backend = FakeRegistrationBackend();
      final registration = backend.seedRegistration(
        tokenA,
        status: 'registered',
      );
      final container = await _openMyEvents(backend);
      final notifier = container.read(myEventsProvider.notifier);
      registration['status'] = 'payment_verification';

      final refused = await notifier.cancelRegistration(_idOf(registration));
      expect(refused.cancelled, isFalse);
      registration['status'] = 'registered';
      // The key is a timestamp to the millisecond.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final cancelled = await notifier.cancelRegistration(_idOf(registration));
      expect(cancelled.cancelled, isTrue);

      final keys = backend.cancelRequests.map(_keyOf).toList();
      expect(keys.last, isNot(keys.first));
    });
  });

  group('ISSUE-004: state while cancelling', () {
    test('only the registration being cancelled is marked, and the mark is '
        'gone when the request ends', () async {
      final backend = FakeRegistrationBackend(isFree: true);
      final old = backend.seedRegistration(tokenA, status: 'cancelled');
      final current = backend.seedRegistration(tokenA, status: 'registered');
      final container = await _openMyEvents(backend);
      final notifier = container.read(myEventsProvider.notifier);

      final pending = notifier.cancelRegistration(_idOf(current));

      final during = container.read(myEventsProvider);
      expect(during.isCancelling(_idOf(current)), isTrue);
      // Same event, different registration.
      expect(during.isCancelling(_idOf(old)), isFalse);

      await pending;
      final after = container.read(myEventsProvider);
      expect(after.cancellingRegistrationIds, isEmpty);
      expect(after.registrations.where((r) => r.isActive), isEmpty);
    });

    test('Tests H, J: a failed cancel leaves the list and its error state '
        'as they were', () async {
      final backend = FakeRegistrationBackend()..cancelRequestsToDrop = 1;
      final registration = backend.seedRegistration(
        tokenA,
        status: 'registered',
      );
      final container = await _openMyEvents(backend);
      final notifier = container.read(myEventsProvider.notifier);
      final before = container.read(myEventsProvider);

      await notifier.cancelRegistration(_idOf(registration));

      final after = container.read(myEventsProvider);
      expect(after.errorMessage, isNull);
      expect(after.isLoading, isFalse);
      expect(after.registrations, same(before.registrations));
      expect(after.registrations.single.isActive, isTrue);
      expect(after.cancellingRegistrationIds, isEmpty);
    });

    test('signed out: nothing is sent', () async {
      final backend = FakeRegistrationBackend(isFree: true);
      final registration = backend.seedRegistration(
        tokenA,
        status: 'registered',
      );
      final container = await _openMyEvents(backend, signedIn: false);

      final outcome = await container
          .read(myEventsProvider.notifier)
          .cancelRegistration(_idOf(registration));

      expect(outcome.cancelled, isFalse);
      expect(outcome.message, _generic);
      expect(backend.cancelRequests, isEmpty);
    });
  });

  group('ISSUE-004: what the attendee is told', () {
    /// Cancels a registration with [status] on [backend] and returns the
    /// outcome.
    Future<CancellationOutcome> cancel(
      FakeRegistrationBackend backend, {
      String status = 'registered',
      bool paid = false,
    }) async {
      final registration = backend.seedRegistration(
        tokenA,
        status: 'registered',
        paid: paid,
      );
      final container = await _openMyEvents(backend);
      registration['status'] = status;
      return container
          .read(myEventsProvider.notifier)
          .cancelRegistration(_idOf(registration));
    }

    test('Test D: free registration, refund status none', () async {
      final outcome = await cancel(FakeRegistrationBackend(isFree: true));

      expect(outcome.cancelled, isTrue);
      expect(outcome.refund?.status, RefundStatus.none);
      expect(outcome.refund?.refundId, isNull);
      expect(outcome.message, _cancelled);
    });

    test('Test E: paid registration, refund pending', () async {
      final backend = FakeRegistrationBackend(finalAmount: '123.45');
      final outcome = await cancel(backend, paid: true);

      expect(outcome.cancelled, isTrue);
      expect(outcome.message, _cancelledAndRefunding);
      final refund = outcome.refund!;
      expect(refund.status, RefundStatus.pending);
      expect(refund.refundId, startsWith('RFND-'));
      expect(refund.amount, 123.45);
      expect(refund.currency, 'INR');
      expect(refund.requestedAt, isNotNull);
      expect(refund.finalizedAt, isNull);
      expect(refund.paymentMode, 'test');
      expect(refund.realMoney, isFalse);
    });

    test('Test E: paid registration, refund already processed', () async {
      final backend = FakeRegistrationBackend()
        ..refundStatusOnCancel = 'refund_processed';
      final outcome = await cancel(backend, paid: true);

      expect(outcome.cancelled, isTrue);
      expect(outcome.refund?.status, RefundStatus.processed);
      expect(outcome.refund?.finalizedAt, isNotNull);
      expect(outcome.message, _cancelledAndRefunding);
    });

    test("refund failed: cancelled, with the backend's own message", () async {
      final backend = FakeRegistrationBackend()
        ..refundStatusOnCancel = 'refund_failed';
      final outcome = await cancel(backend, paid: true);

      expect(outcome.cancelled, isTrue);
      expect(outcome.refund?.status, RefundStatus.failed);
      expect(
        outcome.message,
        'Your registration is cancelled, but the refund could not be '
        'completed automatically. Our team will follow up.',
      );
    });

    test('Test G: already cancelled is a success', () async {
      final outcome = await cancel(
        FakeRegistrationBackend(isFree: true),
        status: 'cancelled',
      );

      expect(outcome.cancelled, isTrue);
      expect(outcome.message, _cancelled);
    });

    for (final status in const [
      'seat_held',
      'payment_pending',
      'payment_verification',
      'payment_failed',
    ]) {
      test('Test H: $status is refused as not cancellable', () async {
        final outcome = await cancel(FakeRegistrationBackend(), status: status);

        expect(outcome.cancelled, isFalse);
        expect(outcome.refund, isNull);
        expect(
          outcome.message,
          "This registration can't be cancelled while payment is in progress.",
        );
      });
    }

    test("Test I: another user's registration is not found", () async {
      final backend = FakeRegistrationBackend(isFree: true);
      final theirs = backend.seedRegistration(tokenB, status: 'registered');
      final container = await _openMyEvents(backend);

      final outcome = await container
          .read(myEventsProvider.notifier)
          .cancelRegistration(_idOf(theirs));

      expect(backend.cancelRequests.single.bearer, 'Bearer $tokenA');
      expect(outcome.cancelled, isFalse);
      expect(
        outcome.message,
        "We couldn't find this registration. Please refresh and try again.",
      );
      expect(theirs['status'], 'registered');
    });

    for (final detail in const [
      'no_captured_payment',
      'refund_not_supported',
      'refund_mode_mismatch',
    ]) {
      test('409 $detail asks the attendee to contact support', () async {
        final backend = FakeRegistrationBackend()..paidCancelRefusal = detail;
        final outcome = await cancel(backend, paid: true);

        expect(outcome.cancelled, isFalse);
        expect(outcome.message, _contactSupport);
        expect(backend.refundsCreated, 0);
      });
    }

    test('Test J: no connection', () async {
      final backend = FakeRegistrationBackend()..cancelRequestsToDrop = 1;
      final outcome = await cancel(backend);

      expect(outcome.cancelled, isFalse);
      expect(outcome.message, _noConnection);
    });

    test('anything else gets the general message', () async {
      final serverError = await cancel(
        FakeRegistrationBackend()..cancelServerError = 503,
      );
      expect(serverError.cancelled, isFalse);
      expect(serverError.message, _generic);

      final unknownCode = await cancel(
        FakeRegistrationBackend()..paidCancelRefusal = 'some_new_code',
        paid: true,
      );
      expect(unknownCode.message, _generic);
    });

    test('no outcome shows exception text, a status code or a backend code', () {
      final request = RequestOptions(path: '/api/v1/registrations/1/cancel');
      DioException http(int statusCode, Object? data) => DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response<Object?>(
          requestOptions: request,
          statusCode: statusCode,
          data: data,
        ),
      );
      final errors = <Object?>[
        null,
        StateError('boom'),
        const FormatException('bad json'),
        for (final type in DioExceptionType.values)
          DioException(requestOptions: request, type: type, message: 'boom'),
        for (final detail in const [
          'registration_not_cancellable',
          'registration_not_found',
          'no_captured_payment',
          'refund_not_supported',
          'refund_mode_mismatch',
          'invalid_or_expired_token',
        ])
          http(409, {'detail': detail}),
        http(401, {'detail': 'invalid_token'}),
        http(405, {'detail': 'Method Not Allowed'}),
        http(422, {
          'detail': [
            {'msg': 'String should have at least 8 characters'},
          ],
        }),
        http(500, 'Internal Server Error'),
        http(502, null),
      ];

      for (final error in errors) {
        final outcome = CancellationOutcome.failed(error);
        expect(outcome.cancelled, isFalse);
        expect(outcome.message, isNot(contains(_technicalWording)));
        expect(outcome.message, endsWith('.'));
      }
    });
  });

  group('ISSUE-004: RefundStatus', () {
    test('reads every field of RefundStatusResponse', () {
      final refund = RefundStatus.fromJson({
        'refund_id': 'RFND-abc',
        'registration_id': 42,
        'status': 'refund_processed',
        'amount': '1.00',
        'currency': 'INR',
        'requested_at': '2026-10-03T10:00:00Z',
        'finalized_at': '2026-10-03T10:00:05Z',
        'safe_message': 'Done.',
        'payment_mode': 'live',
        'real_money': true,
      });

      expect(refund.refundId, 'RFND-abc');
      expect(refund.registrationId, 42);
      expect(refund.status, RefundStatus.processed);
      expect(refund.amount, 1.0);
      expect(refund.currency, 'INR');
      expect(refund.requestedAt, DateTime.utc(2026, 10, 3, 10).toLocal());
      expect(refund.finalizedAt, DateTime.utc(2026, 10, 3, 10, 0, 5).toLocal());
      expect(refund.safeMessage, 'Done.');
      expect(refund.paymentMode, 'live');
      expect(refund.realMoney, isTrue);
    });

    test('accepts the nulls of a free cancellation, and a numeric amount', () {
      final none = RefundStatus.fromJson({
        'refund_id': null,
        'registration_id': 42,
        'status': 'none',
        'amount': null,
        'currency': null,
        'requested_at': null,
        'finalized_at': null,
        'safe_message': 'Your registration is cancelled.',
        'payment_mode': null,
        'real_money': false,
      });
      expect(none.status, RefundStatus.none);
      expect(none.refundId, isNull);
      expect(none.amount, isNull);
      expect(none.requestedAt, isNull);
      expect(none.paymentMode, isNull);
      expect(none.realMoney, isFalse);

      expect(RefundStatus.fromJson({'amount': 499.5}).amount, 499.5);
    });

    test('does not throw on an empty or malformed body', () {
      final empty = RefundStatus.fromJson({});
      expect(empty.status, RefundStatus.none);
      expect(empty.registrationId, isNull);
      expect(empty.realMoney, isFalse);

      final odd = RefundStatus.fromJson({
        'registration_id': 'forty-two',
        'amount': 'free',
        'requested_at': 'yesterday',
        'real_money': 'no',
      });
      expect(odd.registrationId, isNull);
      expect(odd.amount, isNull);
      expect(odd.requestedAt, isNull);
      expect(odd.realMoney, isFalse);
    });
  });
}
