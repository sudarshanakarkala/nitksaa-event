import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../theme/app_palette.dart';
import '../../auth/services/auth_controller.dart';
import '../domain/nitika_models.dart';
import 'nitika_controller.dart';
import 'widgets/answer_links.dart';
import 'widgets/answer_table.dart';
import 'widgets/answer_text.dart';

/// The shell's assistant, or null: only with the build switch on and a
/// signed-in user. The router passes [nitikaEnabled] as [enabled].
Widget? nitikaAssistant({
  required bool enabled,
  required bool signedIn,
  required String location,
}) => enabled && signedIn ? NitikaPanel(location: location) : null;

/// NITiKa chat, in the shell's right rail (from 1,200 px) or in the slide-in
/// panel / sheet the chat button opens.
class NitikaPanel extends ConsumerStatefulWidget {
  const NitikaPanel({super.key, required this.location});

  /// The current route path, sent as page context.
  final String location;

  @override
  ConsumerState<NitikaPanel> createState() => _NitikaPanelState();
}

class _NitikaPanelState extends ConsumerState<NitikaPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final _focus = FocusNode(onKeyEvent: _onKey);

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Enter sends; Shift+Enter makes a new line.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final enter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!enter || HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) _send(_input.text);
    return KeyEventResult.handled;
  }

  String get _locale {
    final locale = Localizations.maybeLocaleOf(context);
    // The app doesn't set its own locales, so English means en-IN.
    if (locale == null || locale.languageCode == 'en') return 'en-IN';
    return locale.toLanguageTag();
  }

  Future<void> _send(String text) async {
    final controller = ref.read(nitikaControllerProvider.notifier);
    final state = ref.read(nitikaControllerProvider);
    if (text.trim().isEmpty || state.sending || state.blockedBy != null) {
      return;
    }
    _input.clear();
    await controller.send(
      text,
      NitikaPageContext.fromLocation(widget.location),
      locale: _locale,
    );
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nitikaControllerProvider);
    ref.listen(nitikaControllerProvider, (prev, next) {
      if (prev?.messages.length != next.messages.length ||
          prev?.sending != next.sending) {
        _scrollToEnd();
      }
    });
    final p = context.palette;
    final inRail =
        MediaQuery.sizeOf(context).width >= AppShell.assistantRailFrom;

    return Material(
      color: p.card,
      child: Padding(
        // In the sheet or slide-in panel, keep the composer above the
        // keyboard. In the rail the scaffold already does.
        padding: EdgeInsets.only(
          bottom: inRail ? 0 : MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              inRail: inRail,
              canClear: !state.isEmpty,
              onClear: ref.read(nitikaControllerProvider.notifier).clear,
            ),
            Divider(height: 1, color: p.border),
            Expanded(
              child: state.isEmpty && !state.sending
                  ? _Starters(location: widget.location, onPick: _send)
                  : _Messages(state: state, scroll: _scroll),
            ),
            if (state.blockedBy != null)
              _BlockedNotice(error: state.blockedBy!),
            _Composer(
              input: _input,
              focus: _focus,
              enabled: state.blockedBy == null,
              sending: state.sending,
              onSend: () => _send(_input.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.inRail,
    required this.canClear,
    required this.onClear,
  });

  final bool inRail;
  final bool canClear;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      // In the rail the shell puts its hide button in the top-right corner.
      padding: EdgeInsets.fromLTRB(16, 10, inRail ? 52 : 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Website: gold chat icon before the title.
                    Icon(Icons.chat_bubble_outline, size: 16, color: p.primary),
                    const SizedBox(width: 6),
                    Text(
                      'NITiKa',
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Text(
                  "Conversations aren't saved.",
                  style: TextStyle(color: p.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Clear conversation',
            iconSize: 20,
            color: p.textMuted,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: canClear ? onClear : null,
          ),
          if (!inRail)
            IconButton(
              tooltip: 'Close assistant',
              iconSize: 20,
              color: p.textMuted,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
        ],
      ),
    );
  }
}

class _Starters extends ConsumerWidget {
  const _Starters({required this.location, required this.onPick});

  final String location;
  final ValueChanged<String> onPick;

  static const eventPageStarter = 'Is registration open for this event?';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final session = ref.watch(authControllerProvider).session;
    // The session has no finer admin role yet; every admin gets the admin
    // starter and the backend enforces scope.
    final isAdmin = session?.userType.toLowerCase() == 'admin';
    final onEventPage =
        NitikaPageContext.fromLocation(location).eventId != null;
    final starters = [
      if (onEventPage) eventPageStarter,
      "What's coming up?",
      'What have I registered for?',
      'How do refunds work?',
      if (isAdmin) 'Registrations per event?',
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Ask about events, your registrations or refunds.',
          style: TextStyle(color: p.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in starters)
              ActionChip(
                label: Text(s),
                tooltip: 'Ask: $s',
                backgroundColor: p.surfaceSubtle,
                side: BorderSide(color: p.border),
                labelStyle: TextStyle(color: p.textPrimary, fontSize: 13),
                onPressed: () => onPick(s),
              ),
          ],
        ),
      ],
    );
  }
}

class _Messages extends StatelessWidget {
  const _Messages({required this.state, required this.scroll});

  final NitikaState state;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final messages = state.messages;
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.all(12),
      itemCount: messages.length + (state.sending ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == messages.length) return const _Typing();
        final m = messages[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: switch (m.kind) {
            NitikaMessageKind.user => _UserBubble(m.text!),
            NitikaMessageKind.reply => _ReplyBubble(m.reply!),
            NitikaMessageKind.error => _ErrorBubble(m),
          },
        );
      },
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: p.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            text,
            style: TextStyle(color: p.onPrimary, fontSize: 14),
          ),
        ),
      ),
    );
  }
}

class _NitikaBubble extends StatelessWidget {
  const _NitikaBubble({required this.child, this.borderColor});

  final Widget child;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.surfaceSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor ?? p.border),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: p.textPrimary, fontSize: 14, height: 1.4),
          child: child,
        ),
      ),
    );
  }
}

class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble(this.reply);

  final NitikaReply reply;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = DefaultTextStyle.of(context).style.copyWith(
      color: p.textPrimary,
      fontSize: 14,
      height: 1.4,
    );
    final parts = <Widget>[
      if (reply.isSql)
        Text(
          'SQL result',
          style: TextStyle(
            color: p.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      if (reply.answer != null) AnswerText(reply.answer!, style: style),
      if (reply.table != null) AnswerTable(reply.table!),
      if (reply.links.isNotEmpty) AnswerLinks(reply.links),
    ];
    return _NitikaBubble(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < parts.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: parts[i],
            ),
        ],
      ),
    );
  }
}

/// What the panel says for each error (plan §6).
String nitikaErrorText(BuildContext context, NitikaError error) {
  return switch (error.kind) {
    NitikaErrorKind.sessionExpired =>
      'Your session has expired. Please sign in again.',
    NitikaErrorKind.scopeDenied =>
      (error.message?.trim().isNotEmpty ?? false)
          ? error.message!
          : "You don't have access to that.",
    NitikaErrorKind.unavailable => "NITiKa isn't available right now.",
    NitikaErrorKind.rateLimited =>
      'NITiKa is taking a quick breather. Please try again '
          '${_retryTime(context, error.retryAt)}. '
          'Your event details are always in My Events.',
    NitikaErrorKind.budgetReached =>
      'NITiKa is taking a break and will be back on '
          '${_firstOfNextMonth(DateTime.now())}. '
          'Your event details are always in My Events.',
    NitikaErrorKind.failed =>
      "NITiKa couldn't answer just now. Please try again in a moment.",
    NitikaErrorKind.timeout =>
      'NITiKa took too long to answer. Please try again.',
    NitikaErrorKind.invalid => "That message couldn't be sent.",
  };
}

String _retryTime(BuildContext context, DateTime? at) {
  if (at == null) return 'in a little while';
  final time = MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(at));
  return 'from $time';
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

String _firstOfNextMonth(DateTime now) {
  final next = DateTime(now.year, now.month + 1);
  return '1 ${_months[next.month - 1]}';
}

class _ErrorBubble extends ConsumerWidget {
  const _ErrorBubble(this.message);

  final NitikaMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final error = message.error!;
    final requestId = error.requestId;

    return GestureDetector(
      // Support asks for the request ID; a long press copies it.
      onLongPress: requestId == null
          ? null
          : () async {
              await Clipboard.setData(ClipboardData(text: requestId));
              if (!context.mounted) return;
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text('Request ID copied')),
              );
            },
      child: _NitikaBubble(
        borderColor: p.error,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(nitikaErrorText(context, error)),
            if (message.canRetry)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => ref
                      .read(nitikaControllerProvider.notifier)
                      .retry(message.id),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ),
            if (error.kind == NitikaErrorKind.sessionExpired)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _signInAgain(context, ref),
                  child: const Text('Sign in'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The app's own sign-in flow: sign out (which also clears this
  /// conversation), then the login screen.
  Future<void> _signInAgain(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    final inRail =
        MediaQuery.sizeOf(context).width >= AppShell.assistantRailFrom;
    if (!inRail) navigator.maybePop();
    await ref.read(authControllerProvider).signOut();
    router.go(AppRoutes.login);
  }
}

/// Shown under the conversation while NITiKa can't take messages.
class _BlockedNotice extends StatelessWidget {
  const _BlockedNotice({required this.error});

  final NitikaError error;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: p.tinted(p.warning, 0.12),
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            nitikaErrorText(context, error),
            style: TextStyle(color: p.textPrimary, fontSize: 13),
          ),
          if (error.kind == NitikaErrorKind.budgetReached) ...[
            const SizedBox(height: 8),
            const AnswerLinks([
              NitikaLink(label: 'Events', path: AppRoutes.home),
              NitikaLink(label: 'My Events', path: AppRoutes.myEvents),
              NitikaLink(label: 'Refund policy', path: AppRoutes.refund),
            ]),
          ],
        ],
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: 'NITiKa is typing',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: p.primary),
            ),
            const SizedBox(width: 8),
            Text(
              'NITiKa is thinking…',
              style: TextStyle(color: p.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.focus,
    required this.enabled,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController input;
  final FocusNode focus;
  final bool enabled;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: width),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: input,
              focusNode: focus,
              enabled: enabled,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              inputFormatters: [
                LengthLimitingTextInputFormatter(
                  NitikaController.maxMessageLength,
                ),
              ],
              style: TextStyle(color: p.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: enabled ? 'Ask NITiKa…' : 'NITiKa is unavailable',
                hintStyle: TextStyle(color: p.textMuted),
                filled: true,
                fillColor: p.surfaceSubtle,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: border(p.border),
                enabledBorder: border(p.border),
                disabledBorder: border(p.border),
                // Visible focus ring.
                focusedBorder: border(p.primary, 2),
              ),
            ),
          ),
          const SizedBox(width: 4),
          ValueListenableBuilder(
            valueListenable: input,
            builder: (context, value, _) {
              final canSend =
                  enabled && !sending && value.text.trim().isNotEmpty;
              return IconButton(
                tooltip: 'Send',
                color: p.primary,
                disabledColor: p.textMuted,
                icon: const Icon(Icons.send),
                onPressed: canSend ? onSend : null,
              );
            },
          ),
        ],
      ),
    );
  }
}
