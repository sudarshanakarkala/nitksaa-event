import 'dart:async';

import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/nitika/data/nitika_api.dart';
import 'package:event_app/features/nitika/domain/nitika_models.dart';
import 'package:event_app/features/nitika/presentation/nitika_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/nitika_fakes.dart';

const home = NitikaPageContext(page: '/home');

void main() {
  late FakeAuthController auth;
  late ScriptedNitikaApi api;
  late ProviderContainer container;

  NitikaController controller() =>
      container.read(nitikaControllerProvider.notifier);
  NitikaState state() => container.read(nitikaControllerProvider);

  setUp(() {
    auth = FakeAuthController()..restore(sessionA);
    api = ScriptedNitikaApi();
    container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth),
        nitikaApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
  });

  test('send appends the user turn and the reply', () async {
    api.reply(const NitikaReply(answer: 'Two events.', requestId: 'r1'));
    final sent = await controller().send('  What is on?  ', home);

    expect(sent, isTrue);
    expect(api.calls.single.message, 'What is on?');
    expect(api.calls.single.token, sessionA.accessToken);
    expect(api.calls.single.history, isEmpty);
    expect(state().messages.map((m) => m.kind), [
      NitikaMessageKind.user,
      NitikaMessageKind.reply,
    ]);
    expect(state().messages.last.reply!.answer, 'Two events.');
    expect(state().sending, isFalse);
  });

  test('empty and over-long messages are not sent', () async {
    expect(await controller().send('   ', home), isFalse);
    expect(await controller().send('x' * 2001, home), isFalse);
    expect(await controller().send('x' * 2000, home), isTrue);
    expect(api.calls, hasLength(1));
  });

  test('history: the last 10 real turns, each cut to 4,000 chars', () async {
    api.reply(NitikaReply(answer: 'a' * 5000));
    await controller().send('first', home);
    for (var i = 2; i <= 7; i++) {
      await controller().send('message $i', home);
    }

    final history = api.calls.last.history;
    expect(history, hasLength(10));
    // 6 earlier exchanges = 12 turns; the oldest two are dropped.
    expect(history.first.role, ChatRole.user);
    expect(history.first.text, 'message 2');
    expect(history.last.role, ChatRole.assistant);
    expect(history.last.text, 'Answer 6');

    final third = api.calls[1].history;
    expect(third[1].text.length, 4000);
  });

  test('errors and table-only replies are not sent as history', () async {
    api.fail(httpError(502, 'model_failure'));
    await controller().send('one', home);
    api.reply(
      const NitikaReply(
        mode: 'sql',
        table: NitikaTable(columns: ['n'], rows: [[1]], rowCount: 1, truncated: false),
      ),
    );
    await controller().send('SELECT 1', home);
    await controller().send('three', home);

    expect(
      api.calls.last.history.map((t) => '${t.role.name}:${t.text}'),
      ['user:one', 'user:SELECT 1'],
    );
  });

  test('a second send while one is in flight is ignored', () async {
    final held = api.hold();
    final first = controller().send('one', home);
    expect(state().sending, isTrue);
    expect(await controller().send('two', home), isFalse);

    held.complete(const NitikaReply(answer: 'ok'));
    await first;
    expect(api.calls, hasLength(1));
    expect(state().messages, hasLength(2));
  });

  test('retry resends the same message and history', () async {
    await controller().send('earlier', home);
    api.fail(httpError(503, 'not_ready'));
    await controller().send('again?', const NitikaPageContext(page: '/events/3', eventId: 3));
    final error = state().messages.last;
    expect(error.kind, NitikaMessageKind.error);
    expect(error.canRetry, isTrue);

    await controller().retry(error.id);
    final retried = api.calls.last;
    expect(retried.message, 'again?');
    expect(retried.context.eventId, 3);
    expect(retried.history.map((t) => t.text), ['earlier', 'Answer 1']);
    // The error bubble is replaced by the reply; the user turn isn't repeated.
    expect(state().messages.map((m) => m.kind), [
      NitikaMessageKind.user,
      NitikaMessageKind.reply,
      NitikaMessageKind.user,
      NitikaMessageKind.reply,
    ]);
  });

  test('only network, 502, 503 and 504 errors can be retried', () async {
    for (final (error, retry) in [
      (const NitikaError(NitikaErrorKind.failed, code: 'network'), true),
      (httpError(502, 'model_failure'), true),
      (httpError(503, 'not_ready'), true),
      (httpError(504, 'timeout'), true),
      (httpError(403, 'scope_denied'), false),
      (httpError(400, 'invalid_request'), false),
      (httpError(401), false),
    ]) {
      api.fail(error);
      await controller().send('q', home);
      expect(state().messages.last.canRetry, retry, reason: '${error.kind}');
    }
  });

  test('404 and the budget block the composer, and clear keeps that', () async {
    api.fail(httpError(404));
    await controller().send('hello', home);
    expect(state().blockedBy?.kind, NitikaErrorKind.unavailable);
    expect(await controller().send('again', home), isFalse);

    controller().clear();
    expect(state().messages, isEmpty);
    expect(state().blockedBy, isNotNull);
    expect(api.calls, hasLength(1));
  });

  test('sign-out clears the conversation', () async {
    await controller().send('mine', home);
    expect(state().messages, isNotEmpty);

    await auth.signOut();
    expect(state().messages, isEmpty);
  });

  test('another user signing in clears the conversation', () async {
    await controller().send('mine', home);
    auth.logIn(sessionB);
    expect(state().messages, isEmpty);
  });

  test('a notification that changes nothing keeps the conversation', () async {
    await controller().send('mine', home);
    auth.notifyWithoutChange();
    expect(state().messages, hasLength(2));
  });

  test("a reply that arrives after sign-out isn't shown", () async {
    final held = api.hold();
    final pending = controller().send('mine', home);
    await auth.signOut();
    held.complete(const NitikaReply(answer: 'for the old user'));
    await pending;
    expect(state().messages, isEmpty);
  });

  test('the locale is sent', () async {
    await controller().send('hi', home, locale: 'hi-IN');
    expect(api.calls.single.locale, 'hi-IN');
  });

  test('an unexpected exception becomes a retryable error', () async {
    container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth),
        nitikaApiProvider.overrideWithValue(_ThrowingApi()),
      ],
    );
    addTearDown(container.dispose);
    await controller().send('hi', home);
    expect(state().messages.last.error!.kind, NitikaErrorKind.failed);
    expect(state().messages.last.canRetry, isTrue);
  });
}

class _ThrowingApi implements NitikaApi {
  @override
  Future<NitikaReply> chat({
    required String accessToken,
    required String message,
    required List<ChatTurn> history,
    required String locale,
    required NitikaPageContext context,
  }) => Future.error(StateError('boom'));
}
