import 'dart:async';

import 'package:event_app/features/auth/domain/auth_session.dart';
import 'package:event_app/features/nitika/data/nitika_api.dart';
import 'package:event_app/features/nitika/domain/nitika_models.dart';

export '../../events/support/auth_isolation_fakes.dart'
    show FakeAuthController, sessionA, sessionB;

const adminSession = AuthSession(
  accessToken: 'token-admin',
  firebaseUid: 'uid-admin',
  userType: 'admin',
  email: 'admin@example.com',
  fullname: 'Ada Admin',
);

typedef ChatCall = ({
  String token,
  String message,
  List<ChatTurn> history,
  String locale,
  NitikaPageContext context,
});

/// No network: answers with whatever the test queued, in order. A queued
/// [NitikaError] is thrown; a queued [Completer] holds the reply until the
/// test completes it.
class ScriptedNitikaApi implements NitikaApi {
  final calls = <ChatCall>[];
  final _queue = <Object>[];

  void reply(NitikaReply reply) => _queue.add(reply);
  void fail(NitikaError error) => _queue.add(error);
  Completer<NitikaReply> hold() {
    final c = Completer<NitikaReply>();
    _queue.add(c);
    return c;
  }

  @override
  Future<NitikaReply> chat({
    required String accessToken,
    required String message,
    required List<ChatTurn> history,
    required String locale,
    required NitikaPageContext context,
  }) async {
    calls.add((
      token: accessToken,
      message: message,
      history: List.of(history),
      locale: locale,
      context: context,
    ));
    final next = _queue.isEmpty
        ? NitikaReply(answer: 'Answer ${calls.length}')
        : _queue.removeAt(0);
    return switch (next) {
      NitikaError e => throw e,
      Completer<NitikaReply> c => c.future,
      NitikaReply r => r,
      _ => throw StateError('bad script entry'),
    };
  }
}

NitikaError httpError(int status, [String? code, String? message]) =>
    NitikaError.fromResponse(status, {
      'error': {
        'code': ?code,
        'message': ?message,
        'request_id': 'req-$status',
      },
    });
