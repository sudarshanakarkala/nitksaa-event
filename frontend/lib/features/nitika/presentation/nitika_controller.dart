import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/services/auth_controller.dart';
import '../data/nitika_api.dart';
import '../domain/nitika_models.dart';

enum NitikaMessageKind { user, reply, error }

/// One bubble in the panel.
class NitikaMessage {
  const NitikaMessage.user(this.id, String this.text)
    : kind = NitikaMessageKind.user,
      reply = null,
      error = null,
      _retry = null;

  const NitikaMessage.reply(this.id, NitikaReply this.reply)
    : kind = NitikaMessageKind.reply,
      text = null,
      error = null,
      _retry = null;

  const NitikaMessage._error(this.id, NitikaError this.error, this._retry)
    : kind = NitikaMessageKind.error,
      text = null,
      reply = null;

  final int id;
  final NitikaMessageKind kind;
  final String? text;
  final NitikaReply? reply;
  final NitikaError? error;

  /// The request a Retry resends.
  final _Request? _retry;

  bool get canRetry => _retry != null;
}

class _Request {
  const _Request(this.message, this.history, this.context, this.locale);

  final String message;
  final List<ChatTurn> history;
  final NitikaPageContext context;
  final String locale;
}

class NitikaState {
  const NitikaState({
    this.messages = const [],
    this.sending = false,
    this.blockedBy,
  });

  final List<NitikaMessage> messages;
  final bool sending;

  /// Set when NITiKa can't take messages for now (not configured, or the
  /// monthly budget is spent). The composer stays disabled until reload.
  final NitikaError? blockedBy;

  bool get isEmpty => messages.isEmpty;

  NitikaState copyWith({
    List<NitikaMessage>? messages,
    bool? sending,
    NitikaError? blockedBy,
  }) => NitikaState(
    messages: messages ?? this.messages,
    sending: sending ?? this.sending,
    blockedBy: blockedBy ?? this.blockedBy,
  );
}

/// The conversation, in memory only. Cleared on sign-out and when another
/// user signs in; gone on refresh.
class NitikaController extends StateNotifier<NitikaState> {
  NitikaController(this._api, this._auth) : super(const NitikaState()) {
    _userId = _signedInUser;
    _auth.addListener(_onAuthChanged);
  }

  static const maxMessageLength = 2000;
  static const historyTurns = 10;
  static const maxTurnLength = 4000;

  final NitikaApi _api;
  final AuthController _auth;

  String? _userId;
  int _nextId = 0;

  /// Bumped by [clear], so a reply to a cleared conversation is dropped.
  int _generation = 0;

  String? get _signedInUser =>
      _auth.isAuthenticated ? _auth.session?.firebaseUid : null;

  void _onAuthChanged() {
    final user = _signedInUser;
    if (user == _userId) return;
    _userId = user;
    clear();
  }

  /// Sends [text]. Returns false, sending nothing, if it's empty or too
  /// long, or while another message is on its way.
  Future<bool> send(
    String text,
    NitikaPageContext context, {
    String locale = 'en-IN',
  }) async {
    final message = text.trim();
    if (message.isEmpty || message.length > maxMessageLength) return false;
    if (state.sending || state.blockedBy != null) return false;

    final history = _history();
    state = state.copyWith(
      messages: [...state.messages, NitikaMessage.user(_nextId++, message)],
    );
    await _run(_Request(message, history, context, locale));
    return true;
  }

  /// Resends the message behind the error bubble [messageId].
  Future<void> retry(int messageId) async {
    if (state.sending || state.blockedBy != null) return;
    final index = state.messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;
    final request = state.messages[index]._retry;
    if (request == null) return;
    state = state.copyWith(
      messages: [...state.messages]..removeAt(index),
    );
    await _run(request);
  }

  void clear() {
    _generation++;
    state = NitikaState(blockedBy: state.blockedBy);
  }

  Future<void> _run(_Request request) async {
    final generation = _generation;
    final token = _auth.session?.accessToken ?? '';
    state = state.copyWith(sending: true);

    NitikaMessage result;
    NitikaError? blockedBy;
    try {
      final reply = await _api.chat(
        accessToken: token,
        message: request.message,
        history: request.history,
        locale: request.locale,
        context: request.context,
      );
      result = NitikaMessage.reply(_nextId++, reply);
    } on NitikaError catch (e) {
      result = NitikaMessage._error(_nextId++, e, e.canRetry ? request : null);
      if (e.kind == NitikaErrorKind.unavailable ||
          e.kind == NitikaErrorKind.budgetReached) {
        blockedBy = e;
      }
    } catch (_) {
      const e = NitikaError(NitikaErrorKind.failed);
      result = NitikaMessage._error(_nextId++, e, request);
    }

    if (!mounted || generation != _generation) return;
    state = state.copyWith(
      messages: [...state.messages, result],
      sending: false,
      blockedBy: blockedBy,
    );
  }

  /// The last [historyTurns] real turns: the user's messages and NITiKa's
  /// answers. Error bubbles and table-only replies aren't sent.
  List<ChatTurn> _history() {
    final turns = <ChatTurn>[];
    for (final m in state.messages) {
      final ChatTurn turn;
      if (m.kind == NitikaMessageKind.user) {
        turn = ChatTurn(role: ChatRole.user, text: m.text!);
      } else if (m.kind == NitikaMessageKind.reply && m.reply!.answer != null) {
        turn = ChatTurn(role: ChatRole.assistant, text: m.reply!.answer!);
      } else {
        continue;
      }
      turns.add(
        turn.text.length > maxTurnLength
            ? ChatTurn(role: turn.role, text: turn.text.substring(0, maxTurnLength))
            : turn,
      );
    }
    return turns.length > historyTurns
        ? turns.sublist(turns.length - historyTurns)
        : turns;
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}

final nitikaControllerProvider =
    StateNotifierProvider<NitikaController, NitikaState>((ref) {
      return NitikaController(
        ref.watch(nitikaApiProvider),
        ref.read(authControllerProvider),
      );
    });
