import 'package:dio/dio.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_error_message.dart';
import '../../../core/logger/app_logger.dart';
import '../../../shared/widgets/filter_controls.dart';
import '../../../shared/widgets/list_page.dart';
import '../../../shared/widgets/quick_filter_pill.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/services/auth_controller.dart';
import '../../events/data/events_repository.dart';
import '../../events/domain/event.dart';
import '../data/registrations_api.dart';
import '../domain/registration_filters.dart';
import 'admin_widgets.dart';

/// Value of the event picker meaning "all events".
const int _allEvents = adminAllEvents;

/// How many events load at once in the all-events view.
const int _parallelLoads = 4;

/// Admin → Registrations: who registered, who cancelled and who checked in,
/// for one event or for every event you administer.
///
/// The picked event lives in the URL (`/admin/registrations?event=12`), so
/// links from the Events tab open it directly and Back works. Same frame as
/// the Events page: search, the Filters rail (event first), the list pills,
/// the count. Table headings sort; all filtering is in the rail.
class AdminRegistrationsTab extends ConsumerStatefulWidget {
  const AdminRegistrationsTab({super.key});

  @override
  ConsumerState<AdminRegistrationsTab> createState() => _AdminRegistrationsTabState();
}

class _AdminRegistrationsTabState extends ConsumerState<AdminRegistrationsTab> {
  final _search = TextEditingController();

  List<AppEvent> _events = const [];
  bool _eventsLoading = true;
  String? _eventsError;

  /// The event in the URL, or [_allEvents].
  int _selected = _allEvents;

  /// What [_data] was loaded for (an event id or [_allEvents]); null before
  /// the first load.
  int? _loadedFor;
  Map<int, EventRegistrationData> _data = const {};
  bool _loading = false;
  String? _error;

  /// Events in the all-events view that couldn't be loaded.
  int _failedEvents = 0;

  RegistrationView _view = RegistrationView.registered;

  /// Rail filters: column id → ticked values (none = all). A list only
  /// applies the ones for columns it has.
  final Map<String, Set<String>> _rail = {};

  /// Batch: a decade, or a From/To year range (website "Graduation era").
  int? _decade;
  int? _yearFrom;
  int? _yearTo;

  /// Branch: one, typed or picked (website searchable select).
  String? _branch;

  /// Sort, per list.
  final Map<RegistrationView, (String, bool)> _sorts = {
    RegistrationView.registered: ('registered', false),
    RegistrationView.cancelled: ('cancelled', false),
    RegistrationView.checkIns: ('checkedIn', false),
  };

  bool _exporting = false;

  String? get _token => ref.read(authControllerProvider).session?.accessToken;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    Future.microtask(_loadEvents);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final param = GoRouterState.of(context).uri.queryParameters['event'];
    final fromUrl = int.tryParse(param ?? '') ?? _allEvents;
    if (fromUrl != _selected) {
      _selected = fromUrl;
      // Another event: start from a clean search. Done after this pass,
      // since clearing the search field rebuilds the tab.
      Future.microtask(() {
        if (!mounted) return;
        setState(_resetFilters);
        if (!_eventsLoading) _loadData();
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  Future<void> _loadEvents() async {
    final token = _token;
    if (token == null) return;
    setState(() {
      _eventsLoading = true;
      _eventsError = null;
    });
    try {
      final events = await ref.read(eventsRepositoryProvider).getAllAdminEvents(token);
      if (!mounted) return;
      setState(() {
        // Newest first.
        _events = [...events]..sort((a, b) => b.startDatetime.compareTo(a.startDatetime));
        _eventsLoading = false;
      });
      await _loadData();
    } catch (error, stackTrace) {
      AppLogger.error('Admin registrations: events load failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _eventsLoading = false;
        _eventsError = apiErrorMessage(error, action: 'load your events');
      });
    }
  }

  List<AdminEventOption> get _eventOptions => [for (final e in _events) AdminEventOption.of(e)];

  AppEvent? _event(int id) {
    for (final e in _events) {
      if (e.eventId == id) return e;
    }
    return null;
  }

  /// Events worth asking about in the all-events view: drafts that nobody
  /// has registered for have nothing to show.
  List<AppEvent> get _withRegistrations =>
      _events.where((e) => e.status != 'draft' || e.registeredCount > 0).toList();

  Future<void> _loadData({bool force = false}) async {
    final token = _token;
    final target = _selected;
    if (token == null || (!force && target == _loadedFor && _error == null)) return;
    if (target != _allEvents && _event(target) == null) {
      // Not one of your events (or it no longer exists); nothing to load.
      setState(() {
        _loadedFor = target;
        _data = const {};
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _failedEvents = 0;
    });
    final api = ref.read(registrationsApiProvider);
    try {
      final loaded = <int, EventRegistrationData>{};
      var failed = 0;
      if (target == _allEvents) {
        final ids = _withRegistrations.map((e) => e.eventId).toList();
        for (var i = 0; i < ids.length; i += _parallelLoads) {
          final batch = ids.skip(i).take(_parallelLoads);
          final results = await Future.wait(
            batch.map((id) async {
              try {
                return await api.loadEvent(accessToken: token, eventId: id);
              } catch (error, stackTrace) {
                AppLogger.error('Admin registrations: event $id failed', error, stackTrace);
                return null;
              }
            }),
          );
          for (final r in results) {
            if (r == null) {
              failed++;
            } else {
              loaded[r.eventId] = r;
            }
          }
          if (!mounted || _selected != target) return;
        }
        if (ids.isNotEmpty && loaded.isEmpty) {
          throw StateError('every event failed to load');
        }
      } else {
        loaded[target] = await api.loadEvent(accessToken: token, eventId: target);
      }
      if (!mounted || _selected != target) return;
      setState(() {
        _data = loaded;
        _loadedFor = target;
        _loading = false;
        _failedEvents = failed;
      });
    } catch (error, stackTrace) {
      AppLogger.error('Admin registrations: load failed', error, stackTrace);
      if (!mounted || _selected != target) return;
      setState(() {
        _loading = false;
        _loadedFor = target;
        _data = const {};
        _error = _friendly(error, 'load registrations');
      });
    }
  }

  Future<void> _refresh() async {
    await ref.read(authControllerProvider.notifier).refreshSession();
    await _loadEvents();
    await _loadData(force: true);
  }

  String _friendly(Object error, String what) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final data = error.response?.data;
      final detail = data is Map ? data['detail'] : null;
      if (status == 403 || detail == 'event_admin_required') {
        return 'You\'re not an admin of this event.';
      }
      if (status == 404 || detail == 'event_not_found') {
        return 'This event no longer exists.';
      }
    }
    return apiErrorMessage(error, action: what);
  }

  void _pick(int eventId) {
    if (eventId == _selected) return;
    context.go(
      eventId == _allEvents
          ? '/admin/registrations'
          : '/admin/registrations?event=$eventId',
    );
  }

  void _resetFilters() {
    _search.clear();
    _rail.clear();
    _decade = null;
    _yearFrom = null;
    _yearTo = null;
    _branch = null;
  }

  bool get _batchActive => _decade != null || _yearFrom != null || _yearTo != null;

  Map<String, ColumnFilter> get _columnFilters => {
        for (final e in _rail.entries)
          if (e.value.isNotEmpty) e.key: ColumnFilter(values: e.value),
        if (_batchActive)
          'batch': _decade != null
              ? ColumnFilter(from: _decade, to: _decade! + 9)
              : ColumnFilter(from: _yearFrom, to: _yearTo),
        if (_branch != null) 'branch': ColumnFilter(values: {_branch!}),
      };

  int get _activeFilterCount =>
      _rail.values.where((v) => v.isNotEmpty).length +
      (_batchActive ? 1 : 0) +
      (_branch != null ? 1 : 0) +
      (_isAll ? 0 : 1);

  void _clearAll() {
    setState(_resetFilters);
    if (!_isAll) _pick(_allEvents);
  }

  // ── Columns ──────────────────────────────────────────────────────────────

  bool get _isAll => _selected == _allEvents;

  String _eventTitle(int id) => _event(id)?.title ?? 'Event $id';

  List<GridColumn<AdminRegistration>> _registrationColumns({required bool cancelled}) => [
        GridColumn(
          id: 'number',
          label: 'No.',
          kind: ColumnKind.text,
          value: (r) => r.registrationNumber,
        ),
        GridColumn(
          id: 'name',
          label: 'Name',
          kind: ColumnKind.text,
          value: (r) => r.displayName,
        ),
        if (_isAll)
          GridColumn(
            id: 'event',
            label: 'Event',
            kind: ColumnKind.category,
            value: (r) => _eventTitle(r.eventId),
          ),
        if (!cancelled) ...[
          GridColumn(
            id: 'batch',
            label: 'Batch',
            kind: ColumnKind.category,
            value: (r) => r.batchYear,
          ),
          GridColumn(
            id: 'branch',
            label: 'Branch',
            kind: ColumnKind.category,
            value: (r) => r.branch,
          ),
        ],
        GridColumn(
          id: 'email',
          label: 'Email',
          kind: ColumnKind.text,
          value: (r) => r.email,
        ),
        if (!cancelled) ...[
          GridColumn(
            id: 'phone',
            label: 'Phone',
            kind: ColumnKind.text,
            value: (r) => r.phone,
          ),
          GridColumn(
            id: 'emailStatus',
            label: 'Confirmation email',
            kind: ColumnKind.category,
            value: (r) => confirmationEmailLabel(r.confirmationEmailStatus),
          ),
        ],
        GridColumn(
          id: 'registered',
          label: 'Registered',
          kind: ColumnKind.date,
          value: (r) => r.registeredAt,
        ),
        if (cancelled)
          GridColumn(
            id: 'cancelled',
            label: 'Cancelled',
            kind: ColumnKind.date,
            value: (r) => r.cancelledAt,
          ),
      ];

  List<GridColumn<CheckInEntry>> get _checkInColumns => [
        GridColumn(
          id: 'name',
          label: 'Name',
          kind: ColumnKind.text,
          value: (c) => c.person?.displayName ?? 'Registration ${c.checkIn.registrationId}',
        ),
        GridColumn(
          id: 'number',
          label: 'No.',
          kind: ColumnKind.text,
          value: (c) => c.person?.registrationNumber,
        ),
        if (_isAll)
          GridColumn(
            id: 'event',
            label: 'Event',
            kind: ColumnKind.category,
            value: (c) => _eventTitle(c.checkIn.eventId),
          ),
        GridColumn(
          id: 'checkedIn',
          label: 'Checked in',
          kind: ColumnKind.date,
          value: (c) => c.checkIn.checkedInAt,
        ),
        GridColumn(
          id: 'for',
          label: 'Checked in for',
          kind: ColumnKind.category,
          value: (c) => c.checkIn.sessionId == null ? 'Event entry' : 'Session ${c.checkIn.sessionId}',
        ),
      ];

  // ── Rows ─────────────────────────────────────────────────────────────────

  Iterable<EventRegistrationData> get _loaded => _data.values;

  List<AdminRegistration> get _registered => [for (final d in _loaded) ...d.registered];

  List<AdminRegistration> get _cancelled => [for (final d in _loaded) ...d.cancelled];

  List<CheckInEntry> get _checkIns {
    final people = {
      for (final r in [..._registered, ..._cancelled]) r.registrationId: r,
    };
    return [
      for (final d in _loaded)
        for (final c in d.checkIns) CheckInEntry(c, people[c.registrationId]),
    ];
  }

  List<AdminRegistration> _registrationRows(RegistrationView view) {
    final cancelled = view == RegistrationView.cancelled;
    final sort = _sorts[view]!;
    return applyGrid(
      cancelled ? _cancelled : _registered,
      _registrationColumns(cancelled: cancelled),
      search: _search.text,
      filters: _columnFilters,
      sortId: sort.$1,
      ascending: sort.$2,
    );
  }

  List<CheckInEntry> get _checkInRows {
    final sort = _sorts[RegistrationView.checkIns]!;
    return applyGrid(
      _checkIns,
      _checkInColumns,
      search: _search.text,
      filters: _columnFilters,
      sortId: sort.$1,
      ascending: sort.$2,
    );
  }

  int _count(RegistrationView view) => view == RegistrationView.checkIns
      ? _checkInRows.length
      : _registrationRows(view).length;

  bool get _anyFilter =>
      _search.text.trim().isNotEmpty ||
      _rail.values.any((v) => v.isNotEmpty) ||
      _batchActive ||
      _branch != null;

  /// Tapping a heading: same column flips the order; a new column starts
  /// A–Z, or newest first for dates.
  void _sortBy(String id, ColumnKind kind) {
    setState(() {
      final current = _sorts[_view]!;
      _sorts[_view] = current.$1 == id
          ? (id, !current.$2)
          : (id, kind != ColumnKind.date);
    });
  }

  // ── Export ───────────────────────────────────────────────────────────────

  Future<void> _export() async {
    final token = _token;
    final id = _selected;
    if (token == null || id == _allEvents) return;
    setState(() => _exporting = true);
    try {
      final bytes = await ref
          .read(registrationsApiProvider)
          .exportCsv(accessToken: token, eventId: id);
      await FileSaver.instance.saveFile(
        name: _exportName(id),
        bytes: bytes,
        ext: 'csv',
        mimeType: MimeType.csv,
      );
      _snack('Downloaded the registrations for "${_eventTitle(id)}".');
    } catch (error, stackTrace) {
      AppLogger.error('Admin registrations: export failed', error, stackTrace);
      _snack(_friendly(error, 'download the CSV'), isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// e.g. `registrations-alumni-meet-2026`.
  String _exportName(int id) {
    final slug = _event(id)?.slug.trim() ?? '';
    return slug.isEmpty ? 'registrations-event-$id' : 'registrations-$slug';
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    final p = context.palette;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: p.textPrimary)),
          backgroundColor: p.tinted(isError ? p.error : p.success),
          duration: Duration(seconds: isError ? 7 : 3),
        ),
      );
  }

  // ── Layout ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < ListPage.panelBreakpoint;

    if (_eventsLoading && _events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_eventsError != null && _events.isEmpty) {
      return _Message(
        icon: Icons.error_outline,
        title: 'Couldn\'t load your events',
        body: _eventsError!,
        action: TextButton(onPressed: _loadEvents, child: const Text('Try again')),
      );
    }
    if (_events.isEmpty) {
      return const _Message(
        icon: Icons.event_note_outlined,
        title: 'No events yet',
        body: 'Registrations appear here once you\'re an admin of an event.',
      );
    }

    final shown = _count(_view);
    final (one, many) = switch (_view) {
      RegistrationView.registered => ('registration', 'registrations'),
      RegistrationView.cancelled => ('cancelled registration', 'cancelled registrations'),
      RegistrationView.checkIns => ('check-in', 'check-ins'),
    };

    // Same frame as the Events page: search and Filters; the list pills;
    // then the count and Export CSV.
    return ListPage(
      search: SizedBox(
        height: 44,
        child: TextField(
          controller: _search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 20),
            hintText: 'Search name, email, phone or number…',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ),
      // Quick filters: shortcuts to filters that are also in the rail.
      quickFilters: [
        SizedBox(
          width: compact ? 240 : 320,
          child: AdminEventPicker(
            options: _eventOptions,
            selected: _selected,
            onChanged: _pick,
            width: compact ? 240 : 320,
          ),
        ),
        const SizedBox(width: 6),
        for (final v in RegistrationView.values)
          QuickFilterPill(
            label: v.label,
            count: _count(v),
            active: v == _view,
            onTap: () => setState(() => _view = v),
          ),
        if (compact) _compactSortMenu(),
      ],
      count: _loadedFor == _selected && _error == null
          ? ResultCount(count: shown, one: one, many: many)
          : null,
      actions: [
        if (!_isAll)
          OutlinedButton.icon(
            onPressed: _exporting || _loading ? null : _export,
            icon: _exporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined, size: 18),
            label: const Text('Export CSV'),
          ),
      ],
      filters: (context) => _filterRail(),
      onOpenFilters: () => showFilterSheet(
        context,
        builder: (_) => _filterRail(),
        onClear: _clearAll,
      ),
      activeFilterCount: _activeFilterCount,
      onClearFilters: _clearAll,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body(compact)),
        ],
      ),
    );
  }

  /// The Filters rail: the event first, then the values of the current
  /// list's filterable columns.
  Widget _filterRail() {
    final sections = <Widget>[];
    void section<T>(String id, String label, List<T> rows, GridColumn<T> column) {
      final values = distinctValues(rows, column);
      if (values.isEmpty || (values.length == 1 && values.first.isEmpty)) return;
      sections.add(
        FilterChipSection(
          label: label,
          options: {for (final v in values) v: v.isEmpty ? '(blank)' : v},
          selected: _rail[id] ?? const {},
          onChanged: (v) => setState(() => _rail[id] = v),
        ),
      );
    }

    if (_view == RegistrationView.checkIns) {
      final columns = _checkInColumns;
      for (final c in columns.where((c) => c.kind == ColumnKind.category && c.id != 'event')) {
        section(c.id, c.label, _checkIns, c);
      }
    } else {
      final cancelled = _view == RegistrationView.cancelled;
      final rows = cancelled ? _cancelled : _registered;
      final columns = _registrationColumns(cancelled: cancelled);
      if (!cancelled) {
        sections.add(
          FilterYearRange(
            label: 'Graduation era',
            decades: decadesOf(rows.map((r) => r.batchYear)),
            decade: _decade,
            from: _yearFrom,
            to: _yearTo,
            onChanged: (decade, from, to) => setState(() {
              _decade = decade;
              _yearFrom = from;
              _yearTo = to;
            }),
          ),
        );
        final branches = rows.map((r) => r.branch).whereType<String>().toSet().toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        if (branches.isNotEmpty) {
          sections.add(
            FilterSearchSelect(
              label: 'Branch',
              allLabel: 'All branches',
              options: {for (final b in branches) b: b},
              value: _branch,
              onChanged: (v) => setState(() => _branch = v),
            ),
          );
        }
      }
      const handled = {'event', 'batch', 'branch'};
      for (final c in columns.where((c) => c.kind == ColumnKind.category && !handled.contains(c.id))) {
        section(c.id, c.label, rows, c);
      }
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FilterLabel('Event'),
          const SizedBox(height: 8),
          AdminEventPicker(options: _eventOptions, selected: _selected, onChanged: _pick),
          const SizedBox(height: 20),
          const FilterLabel('Show'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in RegistrationView.values)
                FilterChipToggle(
                  label: v.label,
                  selected: v == _view,
                  onChanged: (_) => setState(() => _view = v),
                ),
            ],
          ),
          const SizedBox(height: 20),
          ...sections,
        ],
      ),
    );
  }

  /// Phones show cards, not a table: sorting moves to a menu.
  Widget _compactSortMenu() {
    final p = context.palette;
    final columns = _view == RegistrationView.checkIns
        ? [for (final c in _checkInColumns) (c.id, c.label, c.kind)]
        : [
            for (final c in _registrationColumns(cancelled: _view == RegistrationView.cancelled))
              (c.id, c.label, c.kind),
          ];
    final current = _sorts[_view]!;
    return PopupMenuButton<(String, ColumnKind)>(
      tooltip: 'Sort',
      onSelected: (c) => _sortBy(c.$1, c.$2),
      itemBuilder: (_) => [
        for (final c in columns)
          CheckedPopupMenuItem<(String, ColumnKind)>(
            value: (c.$1, c.$3),
            checked: c.$1 == current.$1,
            child: Text(c.$2),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort, size: 18, color: p.textSecondary),
            const SizedBox(width: 4),
            Text('Sort', style: AppTextStyles.labelMedium.copyWith(color: p.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _body(bool compact) {
    final target = _selected;
    if (target != _allEvents && _event(target) == null && !_eventsLoading) {
      return _Message(
        icon: Icons.lock_outline,
        title: 'Not available',
        body: 'This event doesn\'t exist, or you\'re not one of its admins.',
        action: TextButton(
          onPressed: () => _pick(_allEvents),
          child: const Text('Show all events'),
        ),
      );
    }
    if (_loadedFor != target) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _Message(
        icon: Icons.error_outline,
        title: 'Couldn\'t load registrations',
        body: _error!,
        action: TextButton(
          onPressed: () => _loadData(force: true),
          child: const Text('Try again'),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = ListPage.contentPadding(context, constraints.maxWidth, top: 20);
        final children = <Widget>[
          _summary(),
          if (_failedEvents > 0) ...[
            const SizedBox(height: 12),
            _Note(
              text: _failedEvents == 1
                  ? 'One event couldn\'t be loaded, so its registrations are missing. Refresh to try again.'
                  : '$_failedEvents events couldn\'t be loaded, so their registrations are missing. Refresh to try again.',
              warning: true,
            ),
          ],
          const SizedBox(height: 20),
          ..._list(compact),
        ];
        return RefreshIndicator(
          onRefresh: _refresh,
          color: context.palette.primary,
          child: ListView(
            padding: padding,
            physics: const AlwaysScrollableScrollPhysics(),
            children: children,
          ),
        );
      },
    );
  }

  Widget _summary() {
    final registered = _registered.length;
    final cancelled = _cancelled.length;
    final checkedIn = _checkIns.map((c) => c.checkIn.registrationId).toSet().length;
    if (_isAll) {
      return _SummaryCard(
        title: 'All events',
        tiles: [
          _Tile('Events', '${_events.length}'),
          _Tile('Registered', '$registered'),
          _Tile('Cancelled', '$cancelled'),
          _Tile('Checked in', '$checkedIn'),
        ],
      );
    }
    final e = _event(_selected)!;
    final cap = e.capacity;
    return _SummaryCard(
      title: e.title,
      subtitle: 'Starts ${formatDateTime(e.startDatetime.toLocal())}',
      tiles: [
        _Tile('Capacity', cap == null ? 'No limit' : '$cap'),
        _Tile('Registered', '$registered'),
        _Tile(
          'Seats left',
          cap == null ? '—' : '${(cap - registered).clamp(0, cap)}',
          isError: cap != null && registered >= cap,
        ),
        _Tile('Cancelled', '$cancelled'),
        _Tile('Checked in', '$checkedIn'),
        _Tile(
          'Published',
          e.publishedAt == null ? 'Not yet' : formatDate(e.publishedAt!.toLocal()),
        ),
      ],
      capacityFraction: cap != null && cap > 0 ? registered / cap : null,
    );
  }

  List<Widget> _list(bool compact) {
    final sort = _sorts[_view]!;
    switch (_view) {
      case RegistrationView.registered:
      case RegistrationView.cancelled:
        final cancelled = _view == RegistrationView.cancelled;
        final rows = _registrationRows(_view);
        if (rows.isEmpty) return [_empty()];
        if (compact) {
          return [
            for (final r in rows) ...[
              _RegistrationTile(
                registration: r,
                eventTitle: _isAll ? _eventTitle(r.eventId) : null,
              ),
              const SizedBox(height: 10),
            ],
          ];
        }
        return [
          AdminGridTable<AdminRegistration>(
            rows: rows,
            columns: _registrationColumns(cancelled: cancelled),
            sortId: sort.$1,
            ascending: sort.$2,
            onSort: _sortBy,
            cell: _registrationCell,
          ),
        ];
      case RegistrationView.checkIns:
        final rows = _checkInRows;
        const note = [
          _Note(
            text: 'Check-ins scanned at the door. Rejected scans aren\'t recorded, so they don\'t appear here.',
          ),
          SizedBox(height: 12),
        ];
        if (rows.isEmpty) return [...note, _empty()];
        if (compact) {
          return [
            ...note,
            for (final c in rows) ...[
              _CheckInTile(entry: c, eventTitle: _isAll ? _eventTitle(c.checkIn.eventId) : null),
              const SizedBox(height: 10),
            ],
          ];
        }
        return [
          ...note,
          AdminGridTable<CheckInEntry>(
            rows: rows,
            columns: _checkInColumns,
            sortId: sort.$1,
            ascending: sort.$2,
            onSort: _sortBy,
          ),
        ];
    }
  }

  /// Cells that need more than plain text.
  Widget? _registrationCell(GridColumn<AdminRegistration> column, AdminRegistration r) {
    switch (column.id) {
      case 'emailStatus':
        return _EmailStatus(status: r.confirmationEmailStatus);
      case 'email':
      case 'phone':
        final text = column.text(r);
        return text.isEmpty ? null : SelectableText(text, style: adminCellStyle(context.palette));
      default:
        return null;
    }
  }

  Widget _empty() {
    final what = switch (_view) {
      RegistrationView.registered => 'No one has registered yet',
      RegistrationView.cancelled => 'No cancelled registrations',
      RegistrationView.checkIns => 'No one has checked in yet',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: _Message(
        icon: _anyFilter ? Icons.search_off : Icons.people_outline,
        title: _anyFilter ? 'No one matches' : what,
        body: _anyFilter ? 'Try a different search or clear the filters.' : '',
      ),
    );
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────

class _Tile {
  const _Tile(this.label, this.value, {this.isError = false});

  final String label;
  final String value;
  final bool isError;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.tiles,
    this.subtitle,
    this.capacityFraction,
  });

  final String title;
  final String? subtitle;
  final List<_Tile> tiles;
  final double? capacityFraction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fraction = capacityFraction?.clamp(0.0, 1.0).toDouble();
    final barTone = fraction == null
        ? p.success
        : fraction >= 1
        ? p.error
        : fraction >= 0.9
        ? p.warning
        : p.success;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.titleMedium.copyWith(color: p.textPrimary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 32,
            runSpacing: 14,
            children: [
              for (final t in tiles)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.label.toUpperCase(),
                      style: AppTextStyles.labelSmall.copyWith(
                        color: p.textMuted,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.value,
                      style: AppTextStyles.titleLarge.copyWith(
                        color: t.isError ? p.error : p.textPrimary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: p.surfaceHover,
                valueColor: AlwaysStoppedAnimation<Color>(barTone),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = warning ? p.warning : p.textMuted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(warning ? Icons.warning_amber_outlined : Icons.info_outline, size: 16, color: tone),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _EmailStatus extends StatelessWidget {
  const _EmailStatus({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = confirmationEmailLabel(status);
    if (label.isEmpty) return Text('—', style: adminCellStyle(p).copyWith(color: p.textMuted));
    final tone = switch (status) {
      'sent' => p.success,
      'failed' => p.error,
      'pending' || 'queued' => p.warning,
      _ => p.textMuted,
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

/// Phone layout: one card per registration.
class _RegistrationTile extends StatelessWidget {
  const _RegistrationTile({required this.registration, this.eventTitle});

  final AdminRegistration registration;
  final String? eventTitle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = registration;
    final secondary = AppTextStyles.bodySmall.copyWith(color: p.textSecondary);
    final batchBranch = [
      if (r.batchYear != null) 'Batch ${r.batchYear}',
      if (r.branch != null) r.branch!,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  r.displayName,
                  style: AppTextStyles.titleSmall.copyWith(color: p.textPrimary),
                ),
              ),
              if (!r.isCancelled) _EmailStatus(status: r.confirmationEmailStatus),
            ],
          ),
          if (r.registrationNumber != null)
            Text(r.registrationNumber!, style: secondary.copyWith(color: p.textMuted)),
          if (eventTitle != null) ...[
            const SizedBox(height: 4),
            Text(eventTitle!, style: secondary),
          ],
          if (batchBranch.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(batchBranch, style: secondary),
          ],
          if (r.email != null) ...[
            const SizedBox(height: 4),
            SelectableText(r.email!, style: secondary),
          ],
          if (r.phone != null) SelectableText(r.phone!, style: secondary),
          const SizedBox(height: 6),
          Text(
            r.isCancelled && r.cancelledAt != null
                ? 'Registered ${formatDate(r.registeredAt)} · Cancelled ${formatDate(r.cancelledAt!)}'
                : 'Registered ${formatDateTime(r.registeredAt)}',
            style: secondary.copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Phone layout: one card per check-in.
class _CheckInTile extends StatelessWidget {
  const _CheckInTile({required this.entry, this.eventTitle});

  final CheckInEntry entry;
  final String? eventTitle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = entry.checkIn;
    final muted = AppTextStyles.bodySmall.copyWith(color: p.textSecondary);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.person?.displayName ?? 'Registration ${c.registrationId}',
            style: AppTextStyles.titleSmall.copyWith(color: p.textPrimary),
          ),
          if (eventTitle != null) Text(eventTitle!, style: muted),
          Text(
            '${formatDateTime(c.checkedInAt)} · ${c.sessionId == null ? 'Event entry' : 'Session ${c.sessionId}'}',
            style: muted,
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
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
