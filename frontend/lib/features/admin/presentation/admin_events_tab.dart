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
import 'admin_widgets.dart';

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

  // Filters rail (the pills are the status shortcuts).
  Set<String> _modes = const {};
  Set<String> _registration = const {};
  Set<String> _price = const {};
  bool _mine = false;

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

  /// Upcoming first (soonest at the top), then past (most recent first).
  List<AppEvent> get _visible {
    final rows = _filtered.where((e) => _matches(e, _filter)).toList();
    final upcoming = rows.where((e) => !_ended(e)).toList()
      ..sort((a, b) => a.startDatetime.compareTo(b.startDatetime));
    final past = rows.where(_ended).toList()
      ..sort((a, b) => b.startDatetime.compareTo(a.startDatetime));
    return [...upcoming, ...past];
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

    // Same frame as the Events page: search, Cards/Table, Filters; the
    // status pills; then the count and Create Event.
    return ListPage(
      search: SizedBox(
        height: 44,
        child: TextField(
          controller: _search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 20),
            hintText: 'Search events…',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
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
      quickFilters: [
        for (final f in _Filter.values)
          QuickFilterPill(
            label: f.label,
            count: filtered.where((e) => _matches(e, f)).length,
            active: f == _filter,
            onTap: () => setState(() => _filter = f),
          ),
      ],
      count: _loading && _events.isEmpty
          ? null
          : ResultCount(count: visible.length, one: 'event', many: 'events'),
      actions: [
        if (canCreate)
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create Event'),
          ),
      ],
      filters: (context) => _filterRail(),
      onOpenFilters: () => showFilterSheet(
        context,
        builder: (_) => _filterRail(),
        onClear: _clearFilters,
      ),
      activeFilterCount: _activeFilterCount,
      onClearFilters: _clearFilters,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading && _events.isNotEmpty) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body(visible, compact)),
        ],
      ),
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
      return _Message(
        icon: Icons.error_outline,
        title: 'Couldn\'t load events',
        body: _error!,
        action: TextButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    if (visible.isEmpty) {
      final searching = _search.text.trim().isNotEmpty;
      return _Message(
        icon: searching ? Icons.search_off : Icons.event_note_outlined,
        title: searching ? 'No events match your search' : 'No ${_filter.label.toLowerCase()} events',
        body: _filter == _Filter.all && !searching && _activeFilterCount == 0
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
                padding: padding,
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
    required this.padding,
    required this.createdBy,
    required this.actionsFor,
    required this.busy,
  });

  final List<AppEvent> events;
  final EdgeInsets padding;
  final String? Function(AppEvent) createdBy;
  final List<EventCardAction> Function(AppEvent) actionsFor;
  final Set<int> busy;

  @override
  State<_EventsTable> createState() => _EventsTableState();
}

class _EventsTableState extends State<_EventsTable> {
  // Column index and direction. Starts as the list arrives (no arrow).
  int? _sortIndex;
  bool _ascending = true;

  // Sort keys, in column order (the last column, the ⋯ menu, doesn't sort).
  static final List<Comparable Function(AppEvent)> _keys = [
    (e) => e.title.toLowerCase(),
    (e) => e.startDatetime,
    (e) => e.status,
    (e) => e.isVirtual ? 1 : 0,
    (e) => e.registeredCount,
    (e) => (e.isFree ?? true) ? -1.0 : (e.ticketPrice ?? 0.0),
    (e) => (e.createdByName ?? '').toLowerCase(),
  ];

  List<AppEvent> get _sorted {
    final i = _sortIndex;
    if (i == null) return widget.events;
    final list = [...widget.events];
    list.sort((a, b) {
      final c = _keys[i](a).compareTo(_keys[i](b));
      return _ascending ? c : -c;
    });
    return list;
  }

  void _sortBy(int index, bool ascending) => setState(() {
        _sortIndex = index;
        _ascending = ascending;
      });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _date(DateTime d) {
    final hour = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final minute = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${_months[d.month - 1]} ${d.year}, $hour:$minute ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  static String _price(AppEvent e) {
    if (e.isFree ?? true) return 'Free';
    final amount = e.ticketPrice;
    if (amount == null) return 'Paid';
    final whole = amount == amount.roundToDouble();
    return '₹${amount.toStringAsFixed(whole ? 0 : 2)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final head = AppTextStyles.labelSmall.copyWith(
      color: p.textMuted,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    );
    final cell = AppTextStyles.bodySmall.copyWith(fontSize: 13, color: p.textPrimary);
    final events = _sorted;
    final padding = widget.padding;
    final createdBy = widget.createdBy;
    final actionsFor = widget.actionsFor;
    final busy = widget.busy;
    return ListView(
      padding: padding,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: p.card,
            border: Border.all(color: p.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LayoutBuilder(
              builder: (context, constraints) => AdminHScroll(
                minWidth: constraints.maxWidth,
                child: DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 52,
                    dataRowMaxHeight: 60,
                    horizontalMargin: 16,
                    columnSpacing: 24,
                    dividerThickness: 0.6,
                    headingRowColor: WidgetStatePropertyAll(p.surfaceSubtle),
                    sortColumnIndex: _sortIndex,
                    sortAscending: _ascending,
                    columns: [
                      DataColumn(label: Text('EVENT', style: head), onSort: _sortBy),
                      DataColumn(label: Text('STARTS', style: head), onSort: _sortBy),
                      DataColumn(label: Text('STATUS', style: head), onSort: _sortBy),
                      DataColumn(label: Text('MODE', style: head), onSort: _sortBy),
                      DataColumn(label: Text('CAPACITY', style: head), onSort: _sortBy),
                      DataColumn(label: Text('PRICE', style: head), onSort: _sortBy),
                      DataColumn(label: Text('CREATED BY', style: head), onSort: _sortBy),
                      const DataColumn(label: SizedBox.shrink()),
                    ],
                    rows: [
                      for (final e in events)
                        DataRow(
                          cells: [
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 260),
                                child: Text(
                                  e.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: cell.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              onTap: () => context.push('/events/${e.eventId}'),
                            ),
                            DataCell(Text(_date(e.startDatetime), style: cell)),
                            DataCell(_StatusBadge(status: e.status)),
                            DataCell(Text(e.isVirtual ? 'Virtual' : 'Physical', style: cell)),
                            DataCell(_CapacityCell(registered: e.registeredCount, capacity: e.capacity)),
                            DataCell(Text(_price(e), style: cell)),
                            DataCell(
                              Text(
                                (createdBy(e) ?? '—').replaceFirst('Created by ', ''),
                                style: cell.copyWith(color: p.textSecondary),
                              ),
                            ),
                            DataCell(
                              busy.contains(e.eventId)
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : _ActionsMenu(actions: actionsFor(e)),
                            ),
                          ],
                        ),
                    ],
                  ),
              ),
            ),
          ),
        ),
      ],
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (label, tone) = switch (status) {
      'draft' => ('Draft', p.warning),
      'published' => ('Published', p.success),
      'cancelled' => ('Cancelled', p.error),
      'completed' => ('Completed', p.textMuted),
      _ => (status, p.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: tone,
        ),
      ),
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

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: p.textMuted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMedium.copyWith(color: p.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
