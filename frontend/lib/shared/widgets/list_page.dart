import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'page_header.dart';
import 'site_header.dart';

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
  static const double panelWidth = 300;

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
    final side = sidePadding(context);
    final extra = ((width - SiteHeader.maxContentWidth) / 2).clamp(0.0, double.infinity);
    return EdgeInsets.fromLTRB(side + extra, top, side + extra, bottom);
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
    final side = ListPage.sidePadding(context);
    final hasFilters = widget.filters != null;
    // The panel only exists on wider screens.
    final panelOpen = _panelOpen && !compact && hasFilters;

    final filterButton = hasFilters
        ? _FiltersButton(
            count: widget.activeFilterCount,
            open: panelOpen,
            onPressed: _openFilters,
          )
        : null;

    final toolbar = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: SiteHeader.maxContentWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, compact ? 20 : 28, side, 14),
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
                  if (filterButton != null) ...[const SizedBox(width: 12), filterButton],
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
                      if (widget.activeFilterCount > 0 && widget.onClearFilters != null) ...[
                        const SizedBox(width: 8),
                        _ClearAllLink(onTap: widget.onClearFilters!),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
          child: toolbar,
        ),
        Expanded(
          // The panel slides over the results; they never move.
          child: Stack(
            children: [
              Positioned.fill(child: widget.body),
              if (hasFilters && !compact) ...[
                // Light scrim while open; a tap closes the panel.
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
                  left: panelOpen ? 0 : -(ListPage.panelWidth + 12),
                  width: ListPage.panelWidth,
                  child: _FilterPanel(
                    activeCount: widget.activeFilterCount,
                    onClear: widget.onClearFilters,
                    onClose: () => setState(() => _panelOpen = false),
                    child: widget.filters!(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "Filters" button with the active count, like the website's filter badge.
class _FiltersButton extends StatelessWidget {
  const _FiltersButton({required this.count, required this.open, required this.onPressed});

  final int count;
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final active = open || count > 0;
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          foregroundColor: active ? p.primary : p.textSecondary,
          side: BorderSide(color: active ? p.primary.withValues(alpha: 0.5) : p.border),
          backgroundColor: open ? p.primary.withValues(alpha: 0.06) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        icon: Icon(count > 0 ? Icons.filter_alt : Icons.filter_alt_outlined, size: 18),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Filters'),
            if (count > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: p.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
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
  });

  final Widget child;
  final VoidCallback onClose;
  final int activeCount;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.card,
      elevation: 8,
      shadowColor: p.overlay,
      shape: Border(right: BorderSide(color: p.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
            child: Row(
              children: [
                Text(
                  'Filters',
                  style: AppTextStyles.titleLarge.copyWith(fontSize: 17, color: p.textPrimary),
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
                const Spacer(),
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
