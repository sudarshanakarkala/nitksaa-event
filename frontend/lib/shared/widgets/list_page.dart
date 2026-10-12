import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'page_header.dart';
import 'page_insets.dart';

/// List page frame (Events): a fixed toolbar (page header, search, view
/// toggle, Filters button, quick-filter pills, count and actions) and the
/// scrolling [body] below it, in the site header's 1520px container.
///
/// Improves on the website's left rail: the common filters are one-click
/// [quickFilters] pills, and the rest open in a Filters panel that slides
/// over the results instead of squeezing them, so the cards never move when
/// it opens or closes. Phones get the panel as a bottom sheet
/// ([onOpenFilters]).
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
    this.quickFilters = const [],
    this.filters,
    this.onOpenFilters,
    this.activeFilterCount = 0,
    this.onClearFilters,
  });

  final String title;
  final String eyebrow;
  final String? subtitle;
  final Widget? search;
  final Widget? toggle;
  final Widget? count;
  final List<Widget> actions;

  /// One-click shortcuts (QuickFilterPill) to the same filters the panel has.
  final List<Widget> quickFilters;

  /// All filters, shown in the Filters panel.
  final WidgetBuilder? filters;

  /// Opens the filters on phones (typically a bottom sheet).
  final VoidCallback? onOpenFilters;

  /// Active filters: badge on the Filters button; above zero, "Clear all".
  final int activeFilterCount;
  final VoidCallback? onClearFilters;

  final Widget body;

  /// Below this width the panel opens as [onOpenFilters] (a bottom sheet).
  static const double panelBreakpoint = 600;

  /// From this width the Filters rail has its own space on the left, always
  /// kept free, so opening it covers nothing and moves nothing.
  static const double railFrom = 900;
  static const double railWidth = 260;

  /// Gap between the rail and the content.
  static const double railGap = 32;

  /// Horizontal page padding for content aligned with the toolbar.
  static double sidePadding(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600 ? 16 : 40;

  /// Padding for a full-width scroll view (scrollbar at the window edge)
  /// whose content stays inside the 1520px container, lined up with the
  /// toolbar and the site header.
  static EdgeInsets contentPadding(
    BuildContext context,
    double width, {
    double top = 24,
    double bottom = 24,
  }) {
    final reserved = context.dependOnInheritedWidgetOfExactType<_ReservedLeft>()?.width ?? 0;
    final h = PageInsets.horizontal(context, width, minLeft: reserved);
    return EdgeInsets.fromLTRB(h.left, top, h.right, bottom);
  }

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  bool _panelOpen = false;

  void _openFilters() {
    final width = MediaQuery.sizeOf(context).width;
    if (width < ListPage.panelBreakpoint) {
      widget.onOpenFilters?.call();
    } else {
      setState(() => _panelOpen = !_panelOpen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;
    final hasFilters = widget.filters != null;
    // The panel only exists on wider screens.
    final panelOpen = _panelOpen && !compact && hasFilters;

    final filterButtons = hasFilters
        ? _FilterIconButtons(
            count: widget.activeFilterCount,
            open: panelOpen,
            onOpen: _openFilters,
            onClear: widget.onClearFilters,
          )
        : null;

    final reserve = hasFilters && width >= ListPage.railFrom;
    final reservedLeft = reserve ? ListPage.railWidth + ListPage.railGap : 0.0;

    final toolbar = LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: PageInsets.horizontal(context, constraints.maxWidth, minLeft: reservedLeft),
        child: Padding(
        padding: EdgeInsets.only(top: compact ? 20 : 28, bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              eyebrow: widget.eyebrow,
              title: widget.title,
              subtitle: compact ? null : widget.subtitle,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (widget.search != null) Expanded(child: widget.search!),
                if (widget.toggle != null && !compact) ...[
                  const SizedBox(width: 12),
                  widget.toggle!,
                ],
                if (filterButtons != null) ...[const SizedBox(width: 8), filterButtons],
              ],
            ),
            if (widget.quickFilters.isNotEmpty) ...[
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < widget.quickFilters.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      widget.quickFilters[i],
                    ],
                  ],
                ),
              ),
            ],
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
      ),
    ),
    );

    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
          child: toolbar,
        ),
        Expanded(
          child: _ReservedLeft(width: reservedLeft, child: widget.body),
        ),
      ],
    );

    if (!hasFilters || compact) return page;

    // Desktop: the rail has its own strip on the left (kept free even when
    // closed), so the open panel covers nothing. Tablets: no room for that,
    // so the panel overlays the edge of the cards with a light scrim.
    // Either way the page never moves.
    final overlay = !reserve;
    const panelWidth = ListPage.railWidth;

    return Stack(
      children: [
        Positioned.fill(child: page),
        if (overlay)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !panelOpen,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: panelOpen ? 1 : 0,
                child: GestureDetector(
                  onTap: () => setState(() => _panelOpen = false),
                  child: ColoredBox(color: p.overlay.withValues(alpha: 0.25)),
                ),
              ),
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          top: 0,
          bottom: 0,
          left: panelOpen ? 0 : -(panelWidth + 12),
          width: panelWidth,
          child: _FilterPanel(
            activeCount: widget.activeFilterCount,
            onClear: widget.onClearFilters,
            onClose: () => setState(() => _panelOpen = false),
            elevated: overlay,
            child: widget.filters!(context),
          ),
        ),
      ],
    );
  }
}

/// How much room on the left the page keeps for the Filters rail, for
/// [ListPage.contentPadding].
class _ReservedLeft extends InheritedWidget {
  const _ReservedLeft({required this.width, required super.child});

  final double width;

  @override
  bool updateShouldNotify(_ReservedLeft old) => old.width != width;
}


/// Filter controls as icons, as on phones: a funnel (with the active count;
/// gold while the panel is open) and, while any filter is on, a clear-
/// filters icon.
class _FilterIconButtons extends StatelessWidget {
  const _FilterIconButtons({
    required this.count,
    required this.open,
    required this.onOpen,
    this.onClear,
  });

  final int count;
  final bool open;
  final VoidCallback onOpen;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget square({
      required String tooltip,
      required VoidCallback onPressed,
      required Widget child,
      bool active = false,
    }) =>
        Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 44,
            height: 44,
            child: OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: active ? p.primary : p.textSecondary,
                backgroundColor: active ? p.primary.withValues(alpha: 0.06) : null,
                side: BorderSide(color: active ? p.primary.withValues(alpha: 0.5) : p.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: child,
            ),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        square(
          tooltip: open ? 'Hide filters' : 'Filters',
          onPressed: onOpen,
          active: open || count > 0,
          child: Badge(
            isLabelVisible: count > 0,
            label: Text('$count'),
            backgroundColor: p.primary,
            textColor: p.onPrimary,
            child: Icon(count > 0 ? Icons.filter_alt : Icons.filter_alt_outlined, size: 20),
          ),
        ),
        if (count > 0 && onClear != null) ...[
          const SizedBox(width: 8),
          square(
            tooltip: 'Clear filters',
            onPressed: onClear!,
            child: const Icon(Icons.filter_alt_off_outlined, size: 20),
          ),
        ],
      ],
    );
  }
}

/// The Filters panel: website rail look (card fill, "Filters" title, count
/// badge, Clear all), sliding over the left of the results.
class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.child,
    required this.onClose,
    this.activeCount = 0,
    this.onClear,
    this.elevated = true,
  });

  final Widget child;
  final VoidCallback onClose;

  /// Shadow when it overlays the cards; flat in its own rail.
  final bool elevated;
  final int activeCount;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.card,
      elevation: elevated ? 8 : 0,
      shadowColor: p.overlay,
      shape: Border(right: BorderSide(color: p.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
            // The title side gives way first, so the row never overflows.
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Filters',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleLarge.copyWith(fontSize: 17, color: p.textPrimary),
                        ),
                      ),
                      if (activeCount > 0) ...[
                        const SizedBox(width: 8),
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
                    ],
                  ),
                ),
                if (activeCount > 0 && onClear != null) _ClearAllLink(onTap: onClear!),
                IconButton(
                  tooltip: 'Close filters',
                  iconSize: 18,
                  color: p.textMuted,
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
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
        ],
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
