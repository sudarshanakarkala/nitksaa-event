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

/// Edit event → Google Sheet (B7).
///
/// Not linked: paste the sheet's link, then **Link and Refresh**. Linked:
/// the link, when it was last read, and **Refresh**. Each Refresh reads the
/// sheet and saves what it holds in one step, so it doesn't wait for the
/// form's Save. Unlinking is the group's Remove (see the form).
class EventSheetPanel extends ConsumerStatefulWidget {
  const EventSheetPanel({
    super.key,
    required this.eventId,
    required this.linkedUrl,
    required this.readAt,
    required this.confirmFirstLink,
    required this.onRefreshed,
  });

  final int eventId;

  /// The linked sheet, or null.
  final String? linkedUrl;
  final DateTime? readAt;

  /// Before the first link: asks whether the sheet may replace what was
  /// typed. False stops.
  final Future<bool> Function() confirmFirstLink;

  /// After a Refresh saved: the form reloads its lists.
  final Future<void> Function(SheetRefresh result) onRefreshed;

  @override
  ConsumerState<EventSheetPanel> createState() => _EventSheetPanelState();
}

class _EventSheetPanelState extends ConsumerState<EventSheetPanel> {
  final _link = TextEditingController();
  var _busy = false;
  SheetProblem? _problem;
  List<String> _warnings = const [];

  bool get _linked => widget.linkedUrl != null;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final token = ref.read(authControllerProvider).session?.accessToken;
    if (token == null) return;
    final url = _linked ? null : _link.text.trim();
    if (!_linked && (url == null || url.isEmpty)) {
      setState(() => _problem = const SheetProblem("Paste the sheet's link first."));
      return;
    }
    if (!_linked && !await widget.confirmFirstLink()) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final result = await ref.read(eventsRepositoryProvider).refreshEventSheet(widget.eventId, url, token);
      await widget.onRefreshed(result);
      if (!mounted) return;
      setState(() {
        _warnings = result.warnings;
        _link.clear();
      });
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
    final info = ref.watch(sheetInfoProvider).valueOrNull;
    return Column(
      key: const ValueKey('event-sheet-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_linked) ...[
          Row(
            children: [
              Icon(Icons.table_chart_outlined, size: 18, color: p.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => launchUrl(Uri.parse(widget.linkedUrl!), webOnlyWindowName: '_blank'),
                  child: Text(
                    'Open the sheet',
                    style: TextStyle(fontSize: 13, color: p.primary, decoration: TextDecoration.underline),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              'Speakers, the agenda and sponsors come from this sheet: change them there, then press Refresh.',
              if (widget.readAt != null) 'Last read ${sheetReadTime(widget.readAt!)}.',
            ].join(' '),
            style: TextStyle(fontSize: 12, color: p.textSecondary),
          ),
        ] else ...[
          Text(
            'Keep the speakers, agenda and sponsors in a Google Sheet; the app reads it when you press Refresh.',
            style: TextStyle(fontSize: 12, color: p.textSecondary),
          ),
          const SizedBox(height: 14),
          SheetSteps(
            info: info,
            linkField: TextField(
              key: const ValueKey('event-sheet-link'),
              controller: _link,
              enabled: !_busy,
              decoration: InputDecoration(
                hintText: 'https://docs.google.com/spreadsheets/d/…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onSubmitted: (_) => _refresh(),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('event-sheet-refresh'),
              onPressed: _busy ? null : _refresh,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
              label: Text(_busy ? 'Reading the sheet…' : _linked ? 'Refresh' : 'Link and Refresh'),
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
          for (final e in problem.errors)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $e', style: TextStyle(fontSize: 12, color: p.textPrimary)),
            ),
          if (problem.errors.isNotEmpty) ...[
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
        for (final w in warnings)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('• $w', style: TextStyle(fontSize: 12, color: p.textSecondary)),
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
