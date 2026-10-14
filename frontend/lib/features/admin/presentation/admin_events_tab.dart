import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_error_message.dart';
import '../../../core/logger/app_logger.dart';
import '../../../shared/widgets/filter_controls.dart';
import '../../../shared/widgets/list_page.dart';
import '../../../shared/widgets/quick_filter_pill.dart';
import '../../../shared/widgets/segment_toggle.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/domain/admin_access.dart';
import '../../auth/services/auth_controller.dart';
import '../../events/data/events_repository.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/widgets/event_card.dart';
import 'event_admin_actions.dart';
import '../domain/registration_filters.dart';
import 'admin_tab_frame.dart';
import 'admin_widgets.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/state_message.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/list_search_field.dart';

/// Status filters, website pill style.
enum _Filter {
  all('All'),
  draft('Draft'),
  published('Published'),
  open('Registration open'),
  cancelled('Cancelled'),
  past('Past');

  const _Filter(this.label);
  final String label;
}

enum _View { cards, table }

/// Card order (the table sorts by its headings).
enum _Order {
  date('Date'),
  mostFull('Most full'),
  leastFull('Least full');

  const _Order(this.label);
  final String label;
}

/// Share of seats taken; null with no capacity set (sorted last).
double? _fillOf(AppEvent e) {
  final capacity = e.capacity;
  return capacity == null || capacity <= 0 ? null : e.registeredCount / capacity;
}

/// Admin → Events: every event you administer (all of them for an overall
/// admin), any status, past and upcoming, as cards or a table, with the
/// status filters and the per-event actions.
class AdminEventsTab extends ConsumerStatefulWidget {
  const AdminEventsTab({super.key});

  @override
  ConsumerState<AdminEventsTab> createState() => _AdminEventsTabState();
}

class _AdminEventsTabState extends ConsumerState<AdminEventsTab> {
  final _search = TextEditingController();
  List<AppEvent> _events = const [];
  bool _loading = true;
  String? _error;
  _Filter _filter = _Filter.all;
  _View _view = _View.cards;
  _Order _order = _Order.date;

  // Filters rail (the pills are the status shortcuts).
  Set<String> _modes = const {};
  Set<String> _registration = const {};
  Set<String> _price = const {};
  bool _mine = false;

  /// Events starting in this range; null for any date.
  DateTimeRange? _dates;

  /// Events with an action in flight; their actions are disabled.
  final Set<int> _busy = {};

  String? get _token => ref.read(authControllerProvider).session?.accessToken;
  AdminAccess get _access =>
      ref.read(authControllerProvider).session?.access ?? AdminAccess.none;
  String? get _myUid => ref.read(authControllerProvider).session?.firebaseUid;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    Future.microtask(_load);
    // "Create Event" links elsewhere arrive as /admin/events?new=1.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final query = GoRouterState.of(context).uri.queryParameters;
      // e.g. the Events page's "2 drafts" link: /admin/events?filter=draft
      for (final f in _Filter.values) {
        if (f.name == query['filter']) setState(() => _filter = f);
      }
      if (query['new'] == '1' && _access.isEventCreator) _create();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final token = _token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final events = await ref.read(eventsRepositoryProvider).getAllAdminEvents(token);
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error('Admin events: load failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(error, action: 'load events');
      });
    }
  }

  static bool _ended(AppEvent e) =>
      (e.endDatetime ?? e.startDatetime).isBefore(DateTime.now());

  bool _matches(AppEvent e, _Filter f) {
    switch (f) {
      case _Filter.all:
        return true;
      case _Filter.draft:
        return e.status == 'draft';
      case _Filter.published:
        return e.status == 'published';
      case _Filter.open:
        return e.status == 'published' && e.registrationStatus == 'open' && !_ended(e);
      case _Filter.cancelled:
        return e.status == 'cancelled';
      case _Filter.past:
        return _ended(e);
    }
  }

  List<AppEvent> get _searched {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _events;
    return _events.where((e) {
      return e.title.toLowerCase().contains(q) ||
          (e.tagline ?? '').toLowerCase().contains(q) ||
          (e.locationText ?? '').toLowerCase().contains(q);
    }).toList();
  }

  /// The rail's filters (mode, registration, price, created by me).
  bool _railMatches(AppEvent e) {
    if (_modes.isNotEmpty && !_modes.contains(e.isVirtual ? 'online' : 'in_person')) {
      return false;
    }
    if (_registration.isNotEmpty) {
      final open = e.status == 'published' && e.registrationStatus == 'open' && !_ended(e);
      if (!_registration.contains(open ? 'open' : 'closed')) return false;
    }
    if (_price.isNotEmpty && !_price.contains(e.isPaid ? 'paid' : 'free')) return false;
    if (_mine && (e.createdByUid == null || e.createdByUid != _myUid)) return false;
    final dates = _dates;
    if (dates != null) {
      final start = e.startDatetime.toLocal();
      final to = DateTime(dates.end.year, dates.end.month, dates.end.day + 1);
      if (start.isBefore(dates.start) || !start.isBefore(to)) return false;
    }
    return true;
  }

  int get _activeFilterCount => [
        _filter != _Filter.all,
        _modes.isNotEmpty,
        _registration.isNotEmpty,
        _price.isNotEmpty,
        _mine,
      ].where((on) => on).length;

  void _clearFilters() {
    setState(() {
      _modes = const {};
      _registration = const {};
      _price = const {};
      _mine = false;
      _filter = _Filter.all;
      _search.clear();
    });
  }

  /// Search and rail filters; the pills apply on top.
  List<AppEvent> get _filtered => _searched.where(_railMatches).toList();

  /// By date: upcoming first (soonest at the top), then past (most recent
  /// first). By fullness: share of seats taken, no capacity last; ties by
  /// that date order.
  List<AppEvent> get _visible {
    final rows = _filtered.where((e) => _matches(e, _filter)).toList();
    final upcoming = rows.where((e) => !_ended(e)).toList()
      ..sort((a, b) => a.startDatetime.compareTo(b.startDatetime));
    final past = rows.where(_ended).toList()
      ..sort((a, b) => b.startDatetime.compareTo(a.startDatetime));
    final byDate = [...upcoming, ...past];
    if (_order == _Order.date) return byDate;
    final indexed = [for (var i = 0; i < byDate.length; i++) (i, byDate[i])];
    indexed.sort((a, b) {
      final r = compareCells(_fillOf(a.$2), _fillOf(b.$2), ascending: _order == _Order.leastFull);
      return r != 0 ? r : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  String? _createdBy(AppEvent e) => e.createdByLabel(_myUid);

  // ── Actions (shared with the Events page) ─────────────────────────────

  late final EventAdminActions _actions = EventAdminActions(
    context: context,
    ref: ref,
    onChanged: _load,
    isBusy: _busy.contains,
    setBusy: (id, busy) {
      if (!mounted) return;
      setState(() => busy ? _busy.add(id) : _busy.remove(id));
    },
  );

  Future<void> _create() => _actions.create();

  List<EventCardAction> _actionsFor(AppEvent e) => _actions.actionsFor(e);

  // ── Layout ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < ListPage.panelBreakpoint;
    final visible = _visible;
    final filtered = _filtered;
    final canCreate = ref.watch(authControllerProvider).session?.access.isEventCreator ?? false;

    // The admin tab frame: search, Cards/Table, Filters; the status pills;
    // then the count and Create event.
    return AdminTabFrame(
      search: ListSearchField(
        controller: _search,
        hint: 'Search events…',
      ),
      toggle: compact
          ? null
          : SegmentToggle<_View>(
              options: const [
                SegmentOption(_View.cards, 'Cards', icon: Icons.grid_view),
                SegmentOption(_View.table, 'Table', icon: Icons.table_rows_outlined),
              ],
              selected: _view,
              onChanged: (v) => setState(() => _view = v),
            ),
      pills: [
        for (final f in _Filter.values)
          QuickFilterPill(
            label: f.label,
            count: filtered.where((e) => _matches(e, f)).length,
            active: f == _filter,
            onTap: () => setState(() => _filter = f),
          ),
        // Quick filters by type, then capacity (the date is on the line
        // below). The table sorts by its headings; phones use the menu on
        // the count line, as the pill row scrolls sideways there.
        if (!compact && _view == _View.cards) ...[
          const _PillDivider(),
          const _PillLabel('Sort'),
          for (final o in _Order.values)
            QuickFilterPill(
              label: o.label,
              active: o == _order,
              onTap: () => setState(() => _order = o),
            ),
        ],
      ],
      count: _loading && _events.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ResultCount(count: visible.length, one: 'event', many: 'events'),
                // Phones: the sort pills would be off-screen in the row.
                if (compact) ...[
                  const SizedBox(width: 16),
                  _OrderMenu(order: _order, onChanged: (o) => setState(() => _order = o)),
                ],
              ],
            ),
      action: canCreate
          ? FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create event'),
            )
          : null,
      belowPills: _events.isEmpty ? null : _dateFilter(),
      filters: (context) => _filterRail(),
      onOpenFilters: () => showFilterSheet(
        context,
        builder: (_) => _filterRail(),
        onClear: _clearFilters,
      ),
      activeFilterCount: _activeFilterCount,
      onClearFilters: _clearFilters,
      loading: _loading && _events.isNotEmpty,
      body: _body(visible, compact),
    );
  }

  /// Starting between two dates, on the page under the pills: presets, then
  /// the slider over the events' own dates. Sort by works within it.
  Widget _dateFilter() {
    final today = DateUtils.dateOnly(DateTime.now());
    final starts = [for (final e in _events) DateUtils.dateOnly(e.startDatetime.toLocal())]..sort();
    DateTime min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
    DateTime max(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
    final presets = <(String, DateTimeRange)>[
      ('Next 30 days', DateTimeRange(start: today, end: today.add(const Duration(days: 30)))),
      ('Next 90 days', DateTimeRange(start: today, end: today.add(const Duration(days: 90)))),
      ('This year', DateTimeRange(start: DateTime(today.year), end: DateTime(today.year, 12, 31))),
    ];
    return FilterDateRange(
      inline: true,
      label: 'Starts',
      first: min(starts.first, today),
      last: max(starts.last, today.add(const Duration(days: 90))),
      value: _dates,
      presets: presets,
      onChanged: (v) => setState(() => _dates = v),
    );
  }

  Widget _filterRail() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The status pills, so the rail has every filter.
          const FilterLabel('Status'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in _Filter.values)
                FilterChipToggle(
                  label: f.label,
                  selected: f == _filter,
                  onChanged: (_) => setState(() => _filter = f),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilterChipSection(
            label: 'Event mode',
            options: const {'in_person': 'In person', 'online': 'Online'},
            selected: _modes,
            onChanged: (v) => setState(() => _modes = v),
          ),
          FilterChipSection(
            label: 'Registration',
            options: const {'open': 'Open', 'closed': 'Closed'},
            selected: _registration,
            onChanged: (v) => setState(() => _registration = v),
          ),
          FilterChipSection(
            label: 'Price',
            options: const {'free': 'Free', 'paid': 'Paid'},
            selected: _price,
            onChanged: (v) => setState(() => _price = v),
          ),
          const FilterLabel('Created by'),
          const SizedBox(height: 8),
          FilterChipToggle(
            label: 'Created by me',
            selected: _mine,
            onChanged: (on) => setState(() => _mine = on),
          ),
        ],
      ),
    );
  }

  Widget _body(List<AppEvent> visible, bool compact) {
    final p = context.palette;
    if (_loading && _events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _events.isEmpty) {
      return StateMessage(
        icon: Icons.error_outline,
        title: 'Couldn\'t load events',
        body: _error!,
        action: TextButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    if (visible.isEmpty) {
      final searching = _search.text.trim().isNotEmpty;
      return StateMessage(
        icon: searching ? Icons.search_off : Icons.event_note_outlined,
        title: searching ? 'No events match your search' : 'No ${_filter.label.toLowerCase()} events',
        body: _filter == _Filter.all && !searching && _activeFilterCount == 0 && _dates == null
            ? (_access.isEventCreator
                ? 'Create an event to get started.'
                : 'You\'re not an admin of any events yet.')
            : 'Try another filter.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = ListPage.contentPadding(context, constraints.maxWidth);
        final table = !compact && _view == _View.table;
        final content = table
            ? _EventsTable(
                events: visible,
                createdBy: _createdBy,
                actionsFor: _actionsFor,
                busy: _busy,
              )
            : EventCardGrid(
                admin: true,
                padding: padding,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final e = visible[index];
                  return EventCard.forEvent(
                    e,
                    showAdmin: true,
                    mine: e.createdByUid != null && e.createdByUid == _myUid,
                    footerNote: _busy.contains(e.eventId) ? 'Working…' : _createdBy(e),
                    onView: () => context.push('/events/${e.eventId}'),
                    adminActions: _actionsFor(e),
                  );
                },
              );
        return RefreshIndicator(
          onRefresh: _load,
          color: p.primary,
          child: content,
        );
      },
    );
  }
}

/// Table view: one row per event; the ⋯ menu has the same actions as the
/// cards. Every heading sorts (click again to reverse), like the other admin
/// tables. Scrolls sideways on narrower screens.
class _EventsTable extends StatefulWidget {
  const _EventsTable({
    required this.events,
    required this.createdBy,
    required this.actionsFor,
    required this.busy,
  });

  final List<AppEvent> events;
  final String? Function(AppEvent) createdBy;
  final List<EventCardAction> Function(AppEvent) actionsFor;
  final Set<int> busy;

  @override
  State<_EventsTable> createState() => _EventsTableState();
}

class _EventsTableState extends State<_EventsTable> {
  // Starts sorted on a visible column (UI_PATTERNS → Tables): newest first.
  (String, bool) _sort = ('starts', false);

  static String _price(AppEvent e) {
    if (e.isFree ?? true) return 'Free';
    final amount = e.ticketPrice;
    if (amount == null) return 'Paid';
    return formatMoney(amount);
  }

  List<GridColumn<AppEvent>> get _columns => [
        GridColumn(id: 'title', label: 'Event', kind: ColumnKind.text, value: (e) => e.title),
        GridColumn(
          id: 'starts',
          label: 'Starts',
          kind: ColumnKind.date,
          value: (e) => e.startDatetime,
        ),
        GridColumn(
          id: 'status',
          label: 'Status',
          kind: ColumnKind.category,
          value: (e) => e.status,
          width: 96,
        ),
        GridColumn(
          id: 'mode',
          label: 'Mode',
          kind: ColumnKind.category,
          value: (e) => e.isVirtual ? 'Virtual' : 'Physical',
        ),
        GridColumn(
          id: 'capacity',
          label: 'Capacity',
          kind: ColumnKind.number,
          // Sorts by share of seats taken; no capacity goes last.
          value: _fillOf,
          text: (e) => e.capacity == null ? '${e.registeredCount}' : '${e.registeredCount} / ${e.capacity}',
          width: 120,
        ),
        GridColumn(
          id: 'price',
          label: 'Price',
          kind: ColumnKind.number,
          value: (e) => (e.isFree ?? true) ? -1.0 : (e.ticketPrice ?? 0.0),
          text: _price,
        ),
        GridColumn(
          id: 'createdBy',
          label: 'Created by',
          kind: ColumnKind.text,
          value: (e) => (widget.createdBy(e) ?? '').replaceFirst('Created by ', ''),
        ),
        // The ⋯ menu; doesn't sort.
        GridColumn(id: 'actions', label: '', kind: ColumnKind.text, value: (_) => null, width: 32),
      ];

  @override
  Widget build(BuildContext context) {
    final columns = _columns;
    final rows = applyGrid(widget.events, columns, sortId: _sort.$1, ascending: _sort.$2);
    return AdminGridTable<AppEvent>(
      rows: rows,
      columns: columns,
      sortId: _sort.$1,
      ascending: _sort.$2,
      onSort: (id, kind) => setState(
        () => _sort = _sort.$1 == id ? (id, !_sort.$2) : (id, kind != ColumnKind.date),
      ),
      onRowTap: (e) => context.push('/events/${e.eventId}'),
      cell: (c, e) => switch (c.id) {
        'status' => StatusBadge.event(context, e.status),
        'capacity' => _CapacityCell(registered: e.registeredCount, capacity: e.capacity),
        'actions' => widget.busy.contains(e.eventId)
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : _ActionsMenu(actions: widget.actionsFor(e)),
        _ => null,
      },
    );
  }
}

class _ActionsMenu extends StatelessWidget {
  const _ActionsMenu({required this.actions});

  final List<EventCardAction> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PopupMenuButton<int>(
      tooltip: 'Actions',
      icon: Icon(Icons.more_horiz, color: p.textSecondary),
      onSelected: (i) => actions[i].onSelected(),
      itemBuilder: (_) => [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Row(
              children: [
                Icon(
                  actions[i].icon,
                  size: 18,
                  color: actions[i].destructive ? p.error : p.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  actions[i].label,
                  style: TextStyle(color: actions[i].destructive ? p.error : p.textPrimary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CapacityCell extends StatelessWidget {
  const _CapacityCell({required this.registered, required this.capacity});

  final int registered;
  final int? capacity;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cap = capacity;
    final fraction = cap != null && cap > 0 ? (registered / cap).clamp(0.0, 1.0) : 0.0;
    final tone = fraction >= 1
        ? p.error
        : fraction >= 0.9
        ? p.warning
        : p.success;
    return SizedBox(
      width: 120,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cap == null ? '$registered' : '$registered / $cap',
            style: AppTextStyles.labelSmall.copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 4,
              backgroundColor: p.surfaceHover,
              valueColor: AlwaysStoppedAnimation<Color>(tone),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Sort by Date ▾" on the count line, the same look as the phone tables.
class _OrderMenu extends StatelessWidget {
  const _OrderMenu({required this.order, required this.onChanged});

  final _Order order;
  final ValueChanged<_Order> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Sort by', style: AppTextStyles.bodySmall.copyWith(color: p.textMuted)),
        const SizedBox(width: 6),
        PopupMenuButton<_Order>(
          tooltip: 'Sort',
          onSelected: onChanged,
          itemBuilder: (_) => [
            for (final o in _Order.values)
              PopupMenuItem(
                value: o,
                child: Text(
                  o.label,
                  style: TextStyle(
                    color: o == order ? p.primary : null,
                    fontWeight: o == order ? FontWeight.w600 : null,
                  ),
                ),
              ),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                order.label,
                style: AppTextStyles.bodySmall.copyWith(color: p.primary, fontWeight: FontWeight.w600),
              ),
              Icon(Icons.arrow_drop_down, color: p.primary, size: 20),
            ],
          ),
        ),
      ],
    );
  }
}

/// Thin upright line between the type pills and the sort pills.
class _PillDivider extends StatelessWidget {
  const _PillDivider();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(height: 22, child: VerticalDivider(width: 1, color: context.palette.border)),
      );
}

class _PillLabel extends StatelessWidget {
  const _PillLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(color: context.palette.textMuted),
      );
}
