import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'page_header.dart';

/// List page frame matching the website's directory / stories / career
/// pages: a collapsible filter rail on the left (wide screens), a fixed
/// toolbar block (page header, search, toggle, count and actions) and the
/// scrolling [body] below it.
///
/// Below [railBreakpoint] there is no rail; a Filters button calls
/// [onOpenFilters] (typically a bottom sheet).
class ListPage extends StatefulWidget {
  const ListPage({
    super.key,
    required this.title,
    required this.body,
    this.eyebrow = 'NITKSAA Alumni Network',
    this.subtitle,
    this.search,
    this.toggle,
    this.count,
    this.actions = const [],
    this.filters,
    this.onOpenFilters,
    this.activeFilterCount = 0,
    this.onClearFilters,
    this.resultNote,
  });

  final String title;
  final String eyebrow;
  final String? subtitle;
  final Widget? search;
  final Widget? toggle;
  final Widget? count;
  final List<Widget> actions;

  /// Filter controls shown in the rail on wide screens.
  final WidgetBuilder? filters;

  /// Opens the filters on narrow screens.
  final VoidCallback? onOpenFilters;

  /// Number of active filters: badge on the rail title / filter button;
  /// when above zero, "Clear all" (rail) or a clear-filters icon (narrow).
  final int activeFilterCount;
  final VoidCallback? onClearFilters;

  /// Muted line at the bottom of the rail, e.g. "8 events".
  final String? resultNote;

  final Widget body;

  static const double railBreakpoint = 900;
  static const double railOpenFrom = 900;

  /// Horizontal page padding for content aligned with the toolbar.
  static double sidePadding(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600 ? 16 : 40;

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  bool? _railOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= ListPage.railBreakpoint;
    final compact = width < 600;
    final side = ListPage.sidePadding(context);
    // Open by default; the chevron collapses it.
    final railOpen = _railOpen ?? width >= ListPage.railOpenFrom;
    final hasFilters = widget.filters != null;

    final toolbar = Padding(
      padding: EdgeInsets.fromLTRB(side, compact ? 20 : 28, side, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            eyebrow: widget.eyebrow,
            title: widget.title,
            subtitle: compact ? null : widget.subtitle,
          ),
          const SizedBox(height: 20),
          // Phones: search on its own row, toggle and filter icons below.
          if (compact) ...[
            if (widget.search != null) widget.search!,
            const SizedBox(height: 10),
            Row(
              children: [
                if (widget.toggle != null) widget.toggle!,
                const Spacer(),
                ..._filterButtons(context, wide),
              ],
            ),
          ] else
            Row(
              children: [
                if (widget.search != null) Expanded(child: widget.search!),
                if (widget.toggle != null) ...[
                  const SizedBox(width: 12),
                  widget.toggle!,
                ],
                ..._filterButtons(context, wide),
              ],
            ),
          if (widget.count != null || widget.actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.count != null) widget.count!,
                const Spacer(),
                for (var i = 0; i < widget.actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  widget.actions[i],
                ],
              ],
            ),
          ],
        ],
      ),
    );

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.border)),
          ),
          child: toolbar,
        ),
        Expanded(child: widget.body),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide && hasFilters)
          _FilterRail(
            open: railOpen,
            onToggle: () => setState(() => _railOpen = !railOpen),
            activeCount: widget.activeFilterCount,
            onClear: widget.onClearFilters,
            resultNote: widget.resultNote,
            child: widget.filters!(context),
          ),
        Expanded(child: main),
      ],
    );
  }

  /// Narrow screens: funnel button (with active count) to open the filters,
  /// plus a clear-filters button while any are active.
  List<Widget> _filterButtons(BuildContext context, bool wide) {
    if (wide || widget.filters == null) return const [];
    final p = context.palette;
    final count = widget.activeFilterCount;
    Widget square(Widget child, VoidCallback? onPressed, String tooltip) =>
        Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 44,
            height: 44,
            child: OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
              child: child,
            ),
          ),
        );
    return [
      const SizedBox(width: 8),
      square(
        Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          backgroundColor: p.primary,
          textColor: p.onPrimary,
          child: Icon(
            count > 0 ? Icons.filter_alt : Icons.filter_alt_outlined,
            size: 20,
          ),
        ),
        widget.onOpenFilters,
        'Filters',
      ),
      if (count > 0 && widget.onClearFilters != null) ...[
        const SizedBox(width: 8),
        square(
          const Icon(Icons.filter_alt_off_outlined, size: 20),
          widget.onClearFilters,
          'Clear filters',
        ),
      ],
    ];
  }
}

/// Website left rail: 260px panel with a "Filters" title and a chevron that
/// collapses it to a 28px strip.
class _FilterRail extends StatelessWidget {
  const _FilterRail({
    required this.open,
    required this.onToggle,
    required this.child,
    this.activeCount = 0,
    this.onClear,
    this.resultNote,
  });

  final bool open;
  final VoidCallback onToggle;
  final Widget child;
  final int activeCount;
  final VoidCallback? onClear;
  final String? resultNote;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: open ? 260 : 28,
      decoration: BoxDecoration(
        color: p.card,
        border: Border(right: BorderSide(color: p.border)),
      ),
      clipBehavior: Clip.hardEdge,
      child: open
          ? OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 260,
              maxWidth: 260,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                    child: Row(
                      children: [
                        Text(
                          'Filters',
                          style: AppTextStyles.titleLarge.copyWith(
                            fontSize: 17,
                            color: p.textPrimary,
                          ),
                        ),
                        if (activeCount > 0) ...[
                          const SizedBox(width: 8),
                          // Website .filter-badge: gold pill with the count.
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(
                              color: p.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '$activeCount',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: p.onPrimary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (activeCount > 0 && onClear != null)
                          _ClearAllLink(onTap: onClear!),
                        IconButton(
                          tooltip: 'Hide filters',
                          iconSize: 18,
                          color: p.textMuted,
                          icon: const Icon(Icons.chevron_left),
                          onPressed: onToggle,
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: p.border, indent: 20, endIndent: 20),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: child,
                    ),
                  ),
                  if (resultNote != null) ...[
                    Divider(height: 1, color: p.border, indent: 20, endIndent: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        resultNote!,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
                      ),
                    ),
                  ],
                ],
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: IconButton(
                  tooltip: 'Show filters',
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  color: p.textMuted,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: onToggle,
                ),
              ),
            ),
    );
  }
}

/// Website `.btn-reset`: small faint text link that turns red on hover.
class _ClearAllLink extends StatefulWidget {
  const _ClearAllLink({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ClearAllLink> createState() => _ClearAllLinkState();
}

class _ClearAllLinkState extends State<_ClearAllLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            'Clear all',
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 12.5,
              color: _hover ? p.error : p.textSecondary.withValues(alpha: 0.75),
            ),
          ),
        ),
      ),
    );
  }
}
