import 'package:flutter/material.dart';

import '../../../../theme/app_palette.dart';
import '../../domain/nitika_models.dart';

/// A table from NITiKa: SQL results, attendee lists, payment lookups.
///
/// Shows the first [previewRows] rows inline, scrolling sideways; **Expand**
/// opens every row full screen with a sticky header. The rows are only ever
/// shown on screen: never logged, cached or saved.
class AnswerTable extends StatelessWidget {
  const AnswerTable(this.table, {super.key});

  final NitikaTable table;

  static const previewRows = 20;
  static const truncatedNote =
      'First 200 rows. Use Manage Events or ask an admin SQL query for more.';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shown = table.rows.length > previewRows
        ? table.rows.sublist(0, previewRows)
        : table.rows;
    final muted = TextStyle(color: p.textMuted, fontSize: 12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: p.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _GridRow.width(table.columns.length),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _GridRow.header(table.columns, table.columns.length),
                    for (final row in shown) _GridRow(row, table.columns.length),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                table.rows.length > shown.length
                    ? 'Showing ${shown.length} of ${table.rows.length}'
                    : '${table.rows.length} '
                          '${table.rows.length == 1 ? 'row' : 'rows'}',
                style: muted,
              ),
            ),
            TextButton.icon(
              onPressed: () => _expand(context),
              icon: const Icon(Icons.open_in_full, size: 16),
              label: const Text('Expand'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        if (table.truncated) Text(truncatedNote, style: muted),
      ],
    );
  }

  void _expand(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(child: _FullTable(table)),
    );
  }
}

class _FullTable extends StatelessWidget {
  const _FullTable(this.table);

  final NitikaTable table;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text('${table.rows.length} rows'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _GridRow.width(table.columns.length),
                child: Column(
                  children: [
                    _GridRow.header(table.columns, table.columns.length),
                    Expanded(
                      child: ListView.builder(
                        itemCount: table.rows.length,
                        itemBuilder: (_, i) =>
                            _GridRow(table.rows[i], table.columns.length),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (table.truncated)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                AnswerTable.truncatedNote,
                style: TextStyle(color: p.textMuted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// One row of fixed-width cells, so the header and the body line up.
class _GridRow extends StatelessWidget {
  const _GridRow(this.cells, this.columns) : isHeader = false;

  const _GridRow.header(List<String> names, this.columns)
    : cells = names,
      isHeader = true;

  final List<Object?> cells;
  final int columns;
  final bool isHeader;

  static const cellWidth = 160.0;
  static double width(int columns) => cellWidth * (columns < 1 ? 1 : columns);

  /// `true`/`false` → ✓/–, null → blank.
  static String format(Object? value) => switch (value) {
    null => '',
    true => '✓',
    false => '–',
    _ => value.toString(),
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = TextStyle(
      color: p.textPrimary,
      fontSize: 13,
      fontWeight: isHeader ? FontWeight.w700 : FontWeight.w400,
    );
    return Container(
      decoration: BoxDecoration(
        color: isHeader ? p.surfaceSubtle : null,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < columns; i++)
            _cell(i < cells.length ? format(cells[i]) : '', style),
        ],
      ),
    );
  }

  Widget _cell(String text, TextStyle style) {
    final label = Text(
      text,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
    return SizedBox(
      width: cellWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        // Long cells are cut; the full value is in the tooltip.
        child: text.length > 18
            ? Tooltip(message: text, child: label)
            : label,
      ),
    );
  }
}
