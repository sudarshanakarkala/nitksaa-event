import 'package:flutter/material.dart';

import '../../../shared/widgets/list_page.dart';

/// The one layout every admin tab uses (`ADMIN_LAYOUT_DESIGN.md` §3), on
/// [ListPage]. Each tab fills the slots it needs and leaves out the rest:
///
/// 1. [search] · [toggle] (Cards/Table) · Filters icon (when [filters] is set);
/// 2. [picker] (the event picker) · [pills], with counts;
/// 3. [count] · [action] on the right;
/// then the [body] (a table or cards).
///
/// - With no search box, the Filters icon sits at the end of row 2.
/// - Every tab lines up with the "Admin" title: the Filters rail slides over
///   the page rather than keeping a strip free on the left.
/// - [loading] shows a thin line under the toolbar, only while loading.
class AdminTabFrame extends StatelessWidget {
  const AdminTabFrame({
    super.key,
    required this.body,
    this.search,
    this.toggle,
    this.picker,
    this.pills = const [],
    this.count,
    this.action,
    this.filters,
    this.onOpenFilters,
    this.activeFilterCount = 0,
    this.onClearFilters,
    this.loading = false,
    this.bigActionOnPhone = false,
  });

  final Widget? search;
  final Widget? toggle;
  final Widget? picker;
  final List<Widget> pills;
  final Widget? count;

  /// At most one main action per tab: a FilledButton or OutlinedButton at
  /// the standard height, in sentence case ("Create event").
  final Widget? action;

  final WidgetBuilder? filters;
  final VoidCallback? onOpenFilters;
  final int activeFilterCount;
  final VoidCallback? onClearFilters;
  final bool loading;

  /// Phones: the action full width on its own line (Check-in's Scan).
  final bool bigActionOnPhone;

  final Widget body;

  /// Width of the event picker in row 2; null (full width) on phones.
  static double? pickerWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width < ListPage.panelBreakpoint ? null : 320;

  @override
  Widget build(BuildContext context) {
    return ListPage(
      reserveRail: false,
      search: search,
      toggle: toggle,
      picker: picker,
      quickFilters: pills,
      count: count,
      actions: [?action],
      wideActionOnPhone: bigActionOnPhone,
      filters: filters,
      onOpenFilters: onOpenFilters,
      activeFilterCount: activeFilterCount,
      onClearFilters: onClearFilters,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 2,
            child: loading ? const LinearProgressIndicator(minHeight: 2) : null,
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
