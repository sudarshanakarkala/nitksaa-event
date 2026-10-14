import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../../../shared/widgets/list_page.dart';
import '../../../shared/widgets/state_message.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../domain/registration_filters.dart';

/// Column heading style of the admin tables.
TextStyle adminHeadStyle(AppPalette p) => AppTextStyles.labelSmall.copyWith(
      color: p.textMuted,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    );

/// Cell text style of the admin tables.
TextStyle adminCellStyle(AppPalette p) =>
    AppTextStyles.bodySmall.copyWith(fontSize: 13, color: p.textPrimary);

/// The one table of the app (`UI_PATTERNS.md` → Tables). It fills the page
/// body under the toolbar.
///
/// - **Wide screens** (600px and up): headings stay at the top while the
///   rows scroll, the first column (who / what) stays on the left while the
///   others scroll sideways, and only the rows on screen are drawn. Every
///   heading sorts; an arrow shows the sorted column and direction.
/// - **Phones**: the rows as cards, with a sort menu, in one scrolling page.
///
/// [above] (a summary, notes) sits above the table: fixed on wide screens,
/// scrolling with the cards on phones. [below] (paging) sits under it.
class AdminGridTable<T> extends StatefulWidget {
  const AdminGridTable({
    super.key,
    required this.rows,
    required this.columns,
    required this.sortId,
    required this.ascending,
    required this.onSort,
    this.cell,
    this.onRowTap,
    this.above = const [],
    this.below,
    this.empty,
    this.card,
    this.onRefresh,
    this.frozenColumns = 1,
  });

  final List<T> rows;
  final List<GridColumn<T>> columns;
  final String sortId;
  final bool ascending;

  /// A heading was tapped (or a sort chosen on a phone). The page decides
  /// the direction: the same column again usually reverses it.
  final void Function(String id, ColumnKind kind) onSort;

  /// Custom cell for a column, or null for plain text.
  final Widget? Function(GridColumn<T> column, T row)? cell;

  /// Tapping a row (e.g. to open its details). Null: rows aren't tappable.
  final void Function(T row)? onRowTap;

  final List<Widget> above;
  final Widget? below;

  /// Shown instead of the table when there are no rows.
  final Widget? empty;

  /// A phone card for a row. Null: a card listing the columns.
  final Widget Function(BuildContext context, T row)? card;

  /// Pull to refresh (phones).
  final Future<void> Function()? onRefresh;

  /// Columns that stay on the left while the rest scroll sideways.
  final int frozenColumns;

  /// Below this width the rows are shown as cards.
  static const double cardsBelow = 600;

  static const double _headHeight = 40;
  static const double _rowHeight = 52;
  static const double _cellPadding = 12;
  static const double _maxTextWidth = 240;

  @override
  State<AdminGridTable<T>> createState() => _AdminGridTableState<T>();
}

class _AdminGridTableState<T> extends State<AdminGridTable<T>> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  int? _hovered;

  // Column widths, measured over every row and kept until the rows
  // themselves (not their order) or the available width change, so sorting
  // never resizes the table.
  Object? _widthsKey;
  List<double> _cachedWidths = const [];

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  Widget? _custom(GridColumn<T> c, T row) => widget.cell?.call(c, row);

  Widget _plain(GridColumn<T> c, T row, AppPalette p) {
    final text = adminCellStyle(p);
    final value = c.text(row);
    if (value.isEmpty) return Text('—', style: text.copyWith(color: p.textMuted));
    final style = _isFirst(c)
        ? text.copyWith(fontWeight: FontWeight.w600)
        : (c.id == 'number' || c.id == 'event')
        ? text.copyWith(color: p.textSecondary)
        : text;
    return Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: style);
  }

  bool _isFirst(GridColumn<T> c) => c.id == 'name' || identical(c, widget.columns.first);

  /// Column widths from the text they hold (a sample of the rows), capped,
  /// then stretched to fill [available] when the table is narrower.
  List<double> _widths(AppPalette p, double available) {
    final key = Object.hash(
      available.round(),
      Object.hashAll(widget.columns.map((c) => c.id)),
      Object.hashAllUnordered(widget.rows),
    );
    if (key == _widthsKey) return _cachedWidths;
    _widthsKey = key;
    return _cachedWidths = _measure(p, available);
  }

  List<double> _measure(AppPalette p, double available) {
    final head = adminHeadStyle(p);
    final cell = adminCellStyle(p);
    double measure(String s, TextStyle style) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      return tp.width;
    }

    final widths = <double>[];
    final fixed = <bool>[];
    for (final c in widget.columns) {
      final headWidth = measure(c.label.toUpperCase(), head) + 20; // + sort arrow
      if (c.width != null) {
        widths.add(math.max(c.width!, headWidth) + 2 * AdminGridTable._cellPadding);
        fixed.add(true);
        continue;
      }
      var widest = headWidth;
      final style = _isFirst(c) ? cell.copyWith(fontWeight: FontWeight.w600) : cell;
      for (final row in widget.rows) {
        final w = measure(c.text(row), style);
        if (w > widest) widest = w;
        if (widest >= AdminGridTable._maxTextWidth) break;
      }
      widths.add(math.min(widest, AdminGridTable._maxTextWidth) + 2 * AdminGridTable._cellPadding + 2);
      fixed.add(false);
    }
    final total = widths.fold<double>(0, (a, b) => a + b);
    final stretchable = [
      for (var i = 0; i < widths.length; i++)
        if (!fixed[i]) widths[i],
    ].fold<double>(0, (a, b) => a + b);
    if (total < available && stretchable > 0) {
      final scale = (available - (total - stretchable)) / stretchable;
      for (var i = 0; i < widths.length; i++) {
        if (!fixed[i]) widths[i] *= scale;
      }
    }
    return widths;
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < AdminGridTable.cardsBelow;
    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = ListPage.contentPadding(context, constraints.maxWidth, top: 20, bottom: 16);
        if (widget.rows.isEmpty) {
          return ListView(
            padding: pad,
            children: [
              ...widget.above,
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: widget.empty ?? const StateMessage(body: 'Nothing matches.'),
              ),
              if (widget.below != null) widget.below!,
            ],
          );
        }
        return compact ? _cards(context, pad) : _table(context, pad);
      },
    );
  }

  // ── Phones ──────────────────────────────────────────────────────────────

  Widget _cards(BuildContext context, EdgeInsets pad) {
    final list = ListView(
      padding: pad,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        ...widget.above,
        _sortMenu(context),
        const SizedBox(height: 10),
        for (final row in widget.rows) ...[
          widget.card?.call(context, row) ?? _defaultCard(context, row),
          const SizedBox(height: 10),
        ],
        if (widget.below != null) widget.below!,
      ],
    );
    final refresh = widget.onRefresh;
    return refresh == null
        ? list
        : RefreshIndicator(onRefresh: refresh, color: context.palette.primary, child: list);
  }

  Widget _sortMenu(BuildContext context) {
    final p = context.palette;
    final current = widget.columns.where((c) => c.id == widget.sortId).firstOrNull;
    return Row(
      children: [
        Text('Sort by', style: AppTextStyles.bodySmall.copyWith(color: p.textMuted)),
        const SizedBox(width: 8),
        PopupMenuButton<GridColumn<T>>(
          tooltip: 'Sort',
          onSelected: (c) => widget.onSort(c.id, c.kind),
          itemBuilder: (context) => [
            for (final c in widget.columns)
              if (c.label.isNotEmpty)
                PopupMenuItem(value: c, child: Text(c.label)),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                current?.label ?? 'Choose',
                style: AppTextStyles.bodySmall.copyWith(color: p.primary, fontWeight: FontWeight.w600),
              ),
              Icon(Icons.arrow_drop_down, color: p.primary, size: 20),
            ],
          ),
        ),
        if (current != null)
          IconButton(
            tooltip: widget.ascending ? 'Ascending' : 'Descending',
            visualDensity: VisualDensity.compact,
            onPressed: () => widget.onSort(current.id, current.kind),
            icon: Icon(
              widget.ascending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
              color: p.primary,
            ),
          ),
      ],
    );
  }

  /// The first column as the title, the others as label and value lines.
  Widget _defaultCard(BuildContext context, T row) {
    final p = context.palette;
    final first = widget.columns.first;
    final label = adminHeadStyle(p);
    final tap = widget.onRowTap;
    final body = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _custom(first, row) ?? _plain(first, row, p),
          const SizedBox(height: 8),
          for (final c in widget.columns.skip(1))
            if (c.label.isNotEmpty || _custom(c, row) != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(width: 104, child: Text(c.label.toUpperCase(), style: label)),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _custom(c, row) ?? _plain(c, row, p),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
    if (tap == null) return body;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => tap(row),
      child: body,
    );
  }

  // ── Wide screens ────────────────────────────────────────────────────────

  Widget _table(BuildContext context, EdgeInsets pad) {
    final p = context.palette;
    // Opaque fills: the frozen column and the headings cover what scrolls
    // under them.
    final base = Color.alphaBlend(p.card, p.background);
    final headFill = Color.alphaBlend(p.surfaceSubtle, base);
    final hoverFill = Color.alphaBlend(p.surfaceHover, base);
    final divider = BorderSide(color: p.border, width: 0.6);
    final frozen = math.min(widget.frozenColumns, widget.columns.length - 1);
    final head = adminHeadStyle(p);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.above.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.above,
            ),
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              pad.left,
              widget.above.isEmpty ? pad.top : 0,
              pad.right,
              widget.below == null ? pad.bottom : 8,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: base,
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final widths = _widths(p, box.maxWidth - 2);
                    Widget headCell(int i) {
                      final c = widget.columns[i];
                      final sorted = c.id == widget.sortId;
                      return InkWell(
                        onTap: c.label.isEmpty ? null : () => widget.onSort(c.id, c.kind),
                        child: Container(
                          decoration: BoxDecoration(
                            color: headFill,
                            border: Border(
                              bottom: divider,
                              right: i == frozen - 1 ? divider : BorderSide.none,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: AdminGridTable._cellPadding),
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  c.label.toUpperCase(),
                                  overflow: TextOverflow.ellipsis,
                                  style: sorted ? head.copyWith(color: p.primary) : head,
                                ),
                              ),
                              if (sorted) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  widget.ascending ? Icons.arrow_upward : Icons.arrow_downward,
                                  size: 14,
                                  color: p.primary,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }

                    Widget rowCell(int r, int i) {
                      final c = widget.columns[i];
                      final row = widget.rows[r];
                      final tap = widget.onRowTap;
                      final fill = _hovered == r && tap != null ? hoverFill : base;
                      return MouseRegion(
                        cursor: tap == null ? MouseCursor.defer : SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _hovered = r),
                        onExit: (_) {
                          if (_hovered == r) setState(() => _hovered = null);
                        },
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: tap == null ? null : () => tap(row),
                          child: Container(
                            decoration: BoxDecoration(
                              color: fill,
                              border: Border(
                                bottom: r == widget.rows.length - 1 ? BorderSide.none : divider,
                                right: i == frozen - 1 ? divider : BorderSide.none,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: AdminGridTable._cellPadding),
                            alignment: Alignment.centerLeft,
                            child: _custom(c, row) ?? _plain(c, row, p),
                          ),
                        ),
                      );
                    }

                    final table = TableView.builder(
                      verticalDetails: ScrollableDetails.vertical(controller: _vertical),
                      horizontalDetails: ScrollableDetails.horizontal(controller: _horizontal),
                      columnCount: widget.columns.length,
                      rowCount: widget.rows.length + 1,
                      pinnedRowCount: 1,
                      pinnedColumnCount: frozen,
                      columnBuilder: (i) => TableSpan(extent: FixedTableSpanExtent(widths[i])),
                      rowBuilder: (r) => TableSpan(
                        extent: FixedTableSpanExtent(
                          r == 0 ? AdminGridTable._headHeight : AdminGridTable._rowHeight,
                        ),
                      ),
                      cellBuilder: (context, v) => TableViewCell(
                        child: v.row == 0 ? headCell(v.column) : rowCell(v.row - 1, v.column),
                      ),
                    );

                    // Visible scrollbars both ways; the table can also be
                    // dragged with the mouse (otherwise nothing says it scrolls).
                    final scrollable = ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: const {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                        },
                      ),
                      child: Scrollbar(
                        controller: _vertical,
                        thumbVisibility: true,
                        notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
                        child: Scrollbar(
                          controller: _horizontal,
                          thumbVisibility: true,
                          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                          child: table,
                        ),
                      ),
                    );
                    // Cues that the table scrolls sideways: a fade on the
                    // right while columns are hidden there, and a shadow
                    // beside the frozen column once scrolled.
                    final frozenWidth = widths.take(frozen).fold<double>(0, (a, b) => a + b);
                    return Stack(
                      children: [
                        // Size changes (first layout, a resize) don't move the
                        // scroll position, so redraw the cues on those too.
                        Positioned.fill(
                          child: NotificationListener<ScrollMetricsNotification>(
                            onNotification: (n) {
                              if (n.metrics.axis == Axis.horizontal) setState(() {});
                              return false;
                            },
                            child: scrollable,
                          ),
                        ),
                        ListenableBuilder(
                          listenable: _horizontal,
                          builder: (context, _) {
                            final has = _horizontal.hasClients && _horizontal.position.hasContentDimensions;
                            final after = has ? _horizontal.position.extentAfter : 0.0;
                            final before = has ? _horizontal.position.extentBefore : 0.0;
                            return Stack(
                              children: [
                                if (after > 1)
                                  Positioned(
                                    top: 0,
                                    bottom: 0,
                                    right: 0,
                                    width: 36,
                                    child: IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [base.withValues(alpha: 0), base],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (before > 1 && frozen > 0)
                                  Positioned(
                                    top: 0,
                                    bottom: 0,
                                    left: frozenWidth,
                                    width: 10,
                                    child: IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              p.overlay.withValues(alpha: 0.35),
                                              p.overlay.withValues(alpha: 0),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (widget.below != null)
          Padding(
            padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, pad.bottom),
            child: widget.below!,
          ),
      ],
    );
  }
}
