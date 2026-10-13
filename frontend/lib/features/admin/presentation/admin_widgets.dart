import 'package:flutter/material.dart';

import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../events/domain/event.dart';
import '../domain/registration_filters.dart';

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
  });

  /// Fixed width (in the pill row); null fills the space (in the rail).
  final double? width;

  /// Newest first.
  final List<AdminEventOption> options;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final known = selected == adminAllEvents || options.any((e) => e.id == selected);
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
        const DropdownMenuEntry<int>(value: adminAllEvents, label: 'All events'),
        for (final e in options) DropdownMenuEntry<int>(value: e.id, label: e.label),
      ],
      onSelected: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

TextStyle adminHeadStyle(AppPalette p) => AppTextStyles.labelSmall.copyWith(
      color: p.textMuted,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    );

TextStyle adminCellStyle(AppPalette p) =>
    AppTextStyles.bodySmall.copyWith(fontSize: 13, color: p.textPrimary);

/// A table whose every heading sorts (tap it; again to reverse), in a
/// bordered card that scrolls sideways when it's wider than the page.
class AdminGridTable<T> extends StatelessWidget {
  const AdminGridTable({
    super.key,
    required this.rows,
    required this.columns,
    required this.sortId,
    required this.ascending,
    required this.onSort,
    this.cell,
    this.onRowTap,
  });

  final List<T> rows;
  final List<GridColumn<T>> columns;
  final String sortId;
  final bool ascending;
  final void Function(String id, ColumnKind kind) onSort;

  /// Custom cell for a column, or null for plain text.
  final Widget? Function(GridColumn<T> column, T row)? cell;

  /// Tapping a row (e.g. to open its details). Null: rows aren't tappable.
  final void Function(T row)? onRowTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final head = adminHeadStyle(p);
    final text = adminCellStyle(p);
    final sortIndex = columns.indexWhere((c) => c.id == sortId);

    Widget plain(GridColumn<T> c, T row) {
      final value = c.text(row);
      if (value.isEmpty) return Text('—', style: text.copyWith(color: p.textMuted));
      final style = c.id == 'name'
          ? text.copyWith(fontWeight: FontWeight.w600)
          : (c.id == 'number' || c.id == 'event')
          ? text.copyWith(color: p.textSecondary)
          : text;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: style),
      );
    }

    final table = DataTable(
      headingRowHeight: 40,
      dataRowMinHeight: 48,
      dataRowMaxHeight: 56,
      horizontalMargin: 16,
      columnSpacing: 24,
      dividerThickness: 0.6,
      headingRowColor: WidgetStatePropertyAll(p.surfaceSubtle),
      sortColumnIndex: sortIndex < 0 ? null : sortIndex,
      showCheckboxColumn: false,
      sortAscending: ascending,
      columns: [
        for (final c in columns)
          DataColumn(
            onSort: (_, _) => onSort(c.id, c.kind),
            label: Text(c.label.toUpperCase(), style: head),
          ),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            onSelectChanged: onRowTap == null ? null : (_) => onRowTap!(row),
            cells: [
              for (final c in columns) DataCell(cell?.call(c, row) ?? plain(c, row)),
            ],
          ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: table,
            ),
          ),
        ),
      ),
    );
  }
}

