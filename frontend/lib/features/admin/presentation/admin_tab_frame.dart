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
    this.belowPills,
    this.collapseOnPhone = true,
    this.countOnPhone = true,
    this.phoneAction,
  });

  /// Phones: the toolbar, the Admin title and tabs and the footer fold away
  /// while scrolling down the list ([ListPage.collapseOnPhone]). Off for
  /// Check-in.
  final bool collapseOnPhone;

  /// Phones: show [count] ([ListPage.countOnPhone]).
  final bool countOnPhone;

  /// Phones: a small square version of [action] in the search row
  /// ([ListIconAction]), in place of [action].
  final Widget? phoneAction;

  /// A full-width line under the pills, for a tab that needs one (Events:
  /// the date slider). Written down in ADMIN_LAYOUT_DESIGN.md §4.
  final Widget? belowPills;

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
      belowPills: belowPills,
      collapseOnPhone: collapseOnPhone,
      countOnPhone: countOnPhone,
      phoneActions: phoneAction == null ? null : [phoneAction!],
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
