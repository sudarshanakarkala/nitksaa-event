import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/logger/app_logger.dart';
import '../../../../theme/app_palette.dart';
import '../../../../shared/widgets/notice.dart';
import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/event_sheet.dart';

/// The email to share with and the template links, loaded once per app run.
final sheetInfoProvider = FutureProvider<SheetInfo>((ref) async {
  final token = ref.watch(authControllerProvider).session?.accessToken;
  if (token == null) throw const SheetProblem('Sign in again to use a Google Sheet.');
  return ref.read(eventsRepositoryProvider).getSheetInfo(token);
});

/// An imported event's sheet, at the top of its Edit event: which sheet,
/// when it was last read, **Open**, **Refresh** and **Unlink**.
///
/// Refresh reads the sheet. If its Event tab would change the event (title,
/// dates, price…), the changes are listed first and saved only when agreed;
/// speakers, the agenda and sponsors just refresh.
class EventSheetPanel extends ConsumerStatefulWidget {
  const EventSheetPanel({
    super.key,
    required this.eventId,
    required this.linkedUrl,
    required this.readAt,
    required this.onRefreshed,
    required this.onUnlink,
  });

  final int eventId;
  final String linkedUrl;
  final DateTime? readAt;

  /// After a Refresh saved: the form reloads what it shows.
  final Future<void> Function(SheetRefresh result) onRefreshed;

  /// Unlink (asks first; one way).
  final Future<void> Function() onUnlink;

  @override
  ConsumerState<EventSheetPanel> createState() => _EventSheetPanelState();
}

class _EventSheetPanelState extends ConsumerState<EventSheetPanel> {
  var _busy = false;
  SheetProblem? _problem;
  List<String> _warnings = const [];

  Future<void> _refresh() async {
    final token = ref.read(authControllerProvider).session?.accessToken;
    if (token == null) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    final repo = ref.read(eventsRepositoryProvider);
    try {
      var result = await repo.refreshEventSheet(widget.eventId, null, token);
      if (result.needsConfirm) {
        if (!mounted) return;
        // Not "reading" while it waits for an answer.
        setState(() => _busy = false);
        final ok = await confirmSheetChanges(context, result.changes);
        if (!ok || !mounted) return;
        setState(() => _busy = true);
        result = await repo.refreshEventSheet(widget.eventId, null, token, confirm: true);
      }
      await widget.onRefreshed(result);
      if (!mounted) return;
      setState(() => _warnings = result.warnings);
      showNotice(context, 'Read from your sheet: ${result.summary.describe()}.', kind: NoticeKind.success);
    } catch (error, stackTrace) {
      AppLogger.error('Event sheet: refresh failed', error, stackTrace);
      if (mounted) setState(() => _problem = SheetProblem.from(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      key: const ValueKey('event-sheet-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One card: what's linked and when it was read, with its actions.
        Container(
          key: const ValueKey('event-sheet-linked'),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            border: Border.all(color: p.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.table_chart_outlined, size: 22, color: p.primary),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Imported from a Google Sheet',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.textPrimary)),
                      const SizedBox(height: 2),
                      Text(
                        widget.readAt == null ? 'Not read yet' : 'Last read ${sheetReadTime(widget.readAt!)}',
                        style: TextStyle(fontSize: 12, color: p.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('event-sheet-open'),
                    onPressed: () => launchUrl(Uri.parse(widget.linkedUrl), webOnlyWindowName: '_blank'),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    key: const ValueKey('event-sheet-refresh'),
                    onPressed: _busy ? null : _refresh,
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(_busy ? 'Reading the sheet…' : 'Refresh'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text(
              'Everything about this event comes from the sheet. Change it there, then press Refresh.',
              style: TextStyle(fontSize: 12, color: p.textSecondary),
            ),
            TextButton(
              key: const ValueKey('event-sheet-unlink'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: _busy ? null : widget.onUnlink,
              child: const Text('Unlink and edit here instead'),
            ),
          ],
        ),
        if (_problem != null) ...[
          const SizedBox(height: 12),
          SheetProblemBox(problem: _problem!),
        ],
        if (_warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          SheetWarnings(warnings: _warnings),
        ],
      ],
    );
  }
}

/// Before a Refresh changes the event: the changes, then Apply or Cancel.
Future<bool> confirmSheetChanges(BuildContext context, List<SheetChange> changes) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final p = context.palette;
      return AlertDialog(
        title: const Text('Apply the changes from your sheet?'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              key: const ValueKey('sheet-changes'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in changes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.field, style: TextStyle(fontSize: 12, color: p.textSecondary)),
                        const SizedBox(height: 2),
                        Text.rich(TextSpan(children: [
                          TextSpan(text: c.from, style: TextStyle(color: p.textMuted, decoration: TextDecoration.lineThrough)),
                          const TextSpan(text: '  →  '),
                          TextSpan(text: c.to, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600)),
                        ])),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('sheet-changes-apply'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      );
    },
  );
  return ok == true;
}

/// The three steps to a linked sheet, in the order they're done:
/// 1 make a copy of a template, 2 share it with the app, 3 paste its link
/// ([linkField]).
class SheetSteps extends StatelessWidget {
  const SheetSteps({super.key, required this.info, required this.linkField});

  final SheetInfo? info;
  final Widget linkField;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final email = info?.shareWith ?? '';
    final templates = info?.templates ?? const [];
    final hint = TextStyle(fontSize: 12, color: p.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SheetStep(
          number: 1,
          title: 'Make a copy of a template',
          children: [
            Text('Or use a sheet you already made from one.', style: hint),
            if (templates.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in templates)
                    OutlinedButton.icon(
                      key: ValueKey('sheet-template-${t.name}'),
                      onPressed: () => launchUrl(Uri.parse(t.url), webOnlyWindowName: '_blank'),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(t.name),
                    ),
                ],
              ),
            ],
          ],
        ),
        _SheetStep(
          number: 2,
          title: 'Share it with the app, as Viewer',
          children: [
            Container(
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      email.isEmpty ? '…' : email,
                      key: const ValueKey('event-sheet-share-with'),
                      style: TextStyle(fontSize: 13, color: p.textPrimary),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: email.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: email));
                            if (context.mounted) showNotice(context, 'Email copied', kind: NoticeKind.success);
                          },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text('In the sheet: Share → paste this email → Viewer. Untick "Notify people".', style: hint),
          ],
        ),
        _SheetStep(
          number: 3,
          title: "Paste the sheet's link",
          last: true,
          children: [linkField],
        ),
      ],
    );
  }
}

/// One numbered step: a circle with the number, a title, what to do.
class _SheetStep extends StatelessWidget {
  const _SheetStep({required this.number, required this.title, required this.children, this.last = false});

  final int number;
  final String title;
  final List<Widget> children;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: p.primary.withValues(alpha: 0.15),
            child: Text('$number', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.textPrimary)),
                ),
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The sheet's problems, each naming its tab and row. Nothing changed.
class SheetProblemBox extends StatelessWidget {
  const SheetProblemBox({super.key, required this.problem});

  final SheetProblem problem;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const ValueKey('event-sheet-problem'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.error.withValues(alpha: 0.08),
        border: Border.all(color: p.error.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(problem.message, style: TextStyle(fontSize: 13, color: p.textPrimary, fontWeight: FontWeight.w600)),
          if (problem.errors.isNotEmpty) ...[
            const SizedBox(height: 4),
            _ShortList(lines: problem.errors, color: p.textPrimary),
            const SizedBox(height: 6),
            Text('Nothing was changed. Fix these in the sheet, then try again.',
                style: TextStyle(fontSize: 12, color: p.textSecondary)),
          ],
        ],
      ),
    );
  }
}

/// What was read but worth a look (saved anyway).
class SheetWarnings extends StatelessWidget {
  const SheetWarnings({super.key, required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      key: const ValueKey('event-sheet-warnings'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Saved. Worth a look:', style: TextStyle(fontSize: 12, color: p.textSecondary)),
        _ShortList(lines: warnings, color: p.textSecondary),
      ],
    );
  }
}

/// A bulleted list that shows the first few lines, then "Show all N".
class _ShortList extends StatefulWidget {
  const _ShortList({required this.lines, required this.color});

  final List<String> lines;
  final Color color;

  /// Lines shown before "Show all".
  static const shown = 5;

  @override
  State<_ShortList> createState() => _ShortListState();
}

class _ShortListState extends State<_ShortList> {
  var _all = false;

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    final long = lines.length > _ShortList.shown;
    final visible = _all || !long ? lines : lines.take(_ShortList.shown);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in visible)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('• $line', style: TextStyle(fontSize: 12, color: widget.color)),
          ),
        if (long)
          TextButton(
            key: const ValueKey('sheet-list-more'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            onPressed: () => setState(() => _all = !_all),
            child: Text(_all ? 'Show fewer' : 'Show all ${lines.length}'),
          ),
      ],
    );
  }
}

/// Events → Import: paste a sheet's link; returns what it read (or null).
Future<SheetPreview?> showImportSheetDialog(BuildContext context) {
  return showDialog<SheetPreview>(context: context, builder: (_) => const _ImportSheetDialog());
}

class _ImportSheetDialog extends ConsumerStatefulWidget {
  const _ImportSheetDialog();

  @override
  ConsumerState<_ImportSheetDialog> createState() => _ImportSheetDialogState();
}

class _ImportSheetDialogState extends ConsumerState<_ImportSheetDialog> {
  final _link = TextEditingController();
  var _busy = false;
  SheetProblem? _problem;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final token = ref.read(authControllerProvider).session?.accessToken;
    final url = _link.text.trim();
    if (token == null) return;
    if (url.isEmpty) {
      setState(() => _problem = const SheetProblem("Paste the sheet's link first."));
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final preview = await ref.read(eventsRepositoryProvider).previewSheet(url, token);
      if (mounted) Navigator.pop(context, preview);
    } catch (error, stackTrace) {
      AppLogger.error('Event sheet: import preview failed', error, stackTrace);
      if (mounted) setState(() => _problem = SheetProblem.from(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final info = ref.watch(sheetInfoProvider).valueOrNull;
    return AlertDialog(
      title: const Text('Import an event from a Google Sheet'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "The sheet's Event tab fills in the new event, and its speakers, agenda "
                'and sponsors come with it.',
                style: TextStyle(fontSize: 13, color: p.textSecondary),
              ),
              const SizedBox(height: 18),
              SheetSteps(
                info: info,
                linkField: TextField(
                  key: const ValueKey('import-sheet-link'),
                  controller: _link,
                  enabled: !_busy,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'https://docs.google.com/spreadsheets/d/…',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onSubmitted: (_) => _read(),
                ),
              ),
              if (_problem != null) ...[
                const SizedBox(height: 12),
                SheetProblemBox(problem: _problem!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('import-sheet-read'),
          onPressed: _busy ? null : _read,
          child: Text(_busy ? 'Reading…' : 'Read the sheet'),
        ),
      ],
    );
  }
}
