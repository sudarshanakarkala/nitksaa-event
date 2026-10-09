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

  final Widget body;

  static const double railBreakpoint = 900;
  static const double railOpenFrom = 1200;

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
    // Open by default on large screens, collapsed on small laptops.
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
          Row(
            children: [
              if (widget.search != null) Expanded(child: widget.search!),
              if (widget.toggle != null) ...[
                const SizedBox(width: 12),
                widget.toggle!,
              ],
              if (!wide && hasFilters) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 44,
                  child: compact
                      ? OutlinedButton(
                          onPressed: widget.onOpenFilters,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: const Size(44, 44),
                          ),
                          child: const Icon(Icons.tune, size: 18),
                        )
                      : OutlinedButton.icon(
                          onPressed: widget.onOpenFilters,
                          icon: const Icon(Icons.tune, size: 18),
                          label: const Text('Filters'),
                        ),
                ),
              ],
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
            child: widget.filters!(context),
          ),
        Expanded(child: main),
      ],
    );
  }
}

/// Website left rail: 260px panel with a "Filters" title and a chevron that
/// collapses it to a 28px strip.
class _FilterRail extends StatelessWidget {
  const _FilterRail({
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final bool open;
  final VoidCallback onToggle;
  final Widget child;

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
                            fontSize: 18,
                            color: p.textPrimary,
                          ),
                        ),
                        const Spacer(),
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
