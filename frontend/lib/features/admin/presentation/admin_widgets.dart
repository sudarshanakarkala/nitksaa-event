import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/notice.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../events/domain/event.dart';
import '../domain/registration_filters.dart';

export 'grid_table.dart';

/// Shared pieces of the admin list tabs (Registrations, Payments).

/// Event picker value meaning "all events".
const int adminAllEvents = -1;

/// One choice in [AdminEventPicker].
class AdminEventOption {
  const AdminEventOption(this.id, this.title, [this.start]);

  AdminEventOption.of(AppEvent e) : this(e.eventId, e.title, e.startDatetime);

  final int id;
  final String title;
  final DateTime? start;

  String get label => start == null ? title : '$title · ${formatDate(start!.toLocal())}';
}

/// Event picker you can type into: the list narrows to matching events.
class AdminEventPicker extends StatelessWidget {
  const AdminEventPicker({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.width,
    this.includeAll = true,
  });

  /// Fixed width (in the pill row); null fills the space (in the rail).
  final double? width;

  /// Offer "All events" (off where only one event makes sense: Check-in).
  final bool includeAll;

  /// Newest first.
  final List<AdminEventOption> options;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final known = (includeAll && selected == adminAllEvents) || options.any((e) => e.id == selected);
    return DropdownMenu<int>(
      // Rebuild when the URL changes the selection.
      key: ValueKey(selected),
      initialSelection: known ? selected : null,
      expandedInsets: width == null ? EdgeInsets.zero : null,
      width: width,
      enableFilter: true,
      requestFocusOnTap: true,
      menuHeight: 380,
      leadingIcon: const Icon(Icons.event_outlined, size: 20),
      hintText: 'Type to find an event',
      dropdownMenuEntries: [
        if (includeAll) const DropdownMenuEntry<int>(value: adminAllEvents, label: 'All events'),
        for (final e in options) DropdownMenuEntry<int>(value: e.id, label: e.label),
      ],
      onSelected: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// "Label  value  [copy]" lines for a details window (UI_PATTERNS: details
/// window for long records). Empty values are left out.
class AdminDetailRows extends StatelessWidget {
  const AdminDetailRows({super.key, required this.rows, this.labelWidth = 110});

  /// (label, value, copy button).
  final List<(String, String?, bool)> rows;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (label, value, copy) in rows)
          if (value != null && value.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Text(label, style: AppTextStyles.bodySmall.copyWith(color: p.textMuted)),
                  ),
                  Expanded(
                    child: Text(value, style: AppTextStyles.bodyMedium.copyWith(color: p.textPrimary)),
                  ),
                  if (copy)
                    IconButton(
                      tooltip: 'Copy $label',
                      icon: const Icon(Icons.copy, size: 16),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 20),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: value));
                        if (context.mounted) showNotice(context, '$label copied', kind: NoticeKind.success);
                      },
                    ),
                ],
              ),
            ),
      ],
    );
  }
}
