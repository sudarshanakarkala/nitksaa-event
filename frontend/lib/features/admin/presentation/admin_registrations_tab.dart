import 'package:dio/dio.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_error_message.dart';
import '../../../core/logger/app_logger.dart';
import '../../../shared/widgets/quick_filter_pill.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/services/auth_controller.dart';
import '../../events/data/events_repository.dart';
import '../../events/domain/event.dart';
import '../data/registrations_api.dart';
import '../domain/registration_filters.dart';
import 'admin_screen.dart' show AdminContainer;

/// Value of the event picker meaning "all my events".
const int _allEvents = -1;

/// How many events load at once in the all-events view.
const int _parallelLoads = 4;

/// Admin → Registrations: who registered, who cancelled and who checked in,
/// for one event or for every event you administer.
///
/// The picked event lives in the URL (`/admin/registrations?event=12`), so
/// links from the Events tab open it directly and Back works.
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
  int? _batch;
  String? _branch;
  RegistrationSort _sort = RegistrationSort.registeredAt;
  bool _ascending = false;
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
        _events = _ordered(events);
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

  static bool _ended(AppEvent e) =>
      (e.endDatetime ?? e.startDatetime).isBefore(DateTime.now());

  /// Upcoming first (soonest at the top), then past (most recent first).
  static List<AppEvent> _ordered(List<AppEvent> events) {
    final upcoming = events.where((e) => !_ended(e)).toList()
      ..sort((a, b) => a.startDatetime.compareTo(b.startDatetime));
    final past = events.where(_ended).toList()
      ..sort((a, b) => b.startDatetime.compareTo(a.startDatetime));
    return [...upcoming, ...past];
  }

  AppEvent? _event(int id) {
    for (final e in _events) {
      if (e.eventId == id) return e;
    }
    return null;
  }

  /// With a single event there's nothing to choose: show it.
  int get _effective =>
      _selected == _allEvents && _events.length == 1 ? _events.first.eventId : _selected;

  /// Events worth asking about in the all-events view: drafts that nobody
  /// has registered for have nothing to show.
  List<AppEvent> get _withRegistrations =>
      _events.where((e) => e.status != 'draft' || e.registeredCount > 0).toList();

  Future<void> _loadData({bool force = false}) async {
    final token = _token;
    final target = _effective;
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
          if (!mounted || _effective != target) return;
        }
        if (ids.isNotEmpty && loaded.isEmpty) {
          throw StateError('every event failed to load');
        }
      } else {
        loaded[target] = await api.loadEvent(accessToken: token, eventId: target);
      }
      if (!mounted || _effective != target) return;
      setState(() {
        _data = loaded;
        _loadedFor = target;
        _loading = false;
        _failedEvents = failed;
      });
    } catch (error, stackTrace) {
      AppLogger.error('Admin registrations: load failed', error, stackTrace);
      if (!mounted || _effective != target) return;
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
    _batch = null;
    _branch = null;
  }

  // ── What's shown ─────────────────────────────────────────────────────────

  bool get _isAll => _effective == _allEvents;

  Iterable<EventRegistrationData> get _loaded => _data.values;

  List<AdminRegistration> get _registered =>
      [for (final d in _loaded) ...d.registered];

  List<AdminRegistration> get _cancelled =>
      [for (final d in _loaded) ...d.cancelled];

  List<AdminCheckIn> get _checkIns =>
      [for (final d in _loaded) ...d.checkIns]
        ..sort((a, b) => b.checkedInAt.compareTo(a.checkedInAt));

  /// Every registration by id, so check-ins can show who it was.
  Map<int, AdminRegistration> get _byId => {
        for (final r in [..._registered, ..._cancelled]) r.registrationId: r,
      };

  RegistrationFilters get _filters => RegistrationFilters(
        query: _search.text,
        batchYear: _view == RegistrationView.registered ? _batch : null,
        branch: _view == RegistrationView.registered ? _branch : null,
      );

  List<AdminRegistration> _rowsFor(RegistrationView view) {
    final source = view == RegistrationView.cancelled ? _cancelled : _registered;
    final filtered = _filters.apply(source);
    var sort = _sort;
    if (view != RegistrationView.cancelled && sort == RegistrationSort.cancelledAt) {
      sort = RegistrationSort.registeredAt;
    }
    if (view == RegistrationView.cancelled && sort == RegistrationSort.batch) {
      sort = RegistrationSort.cancelledAt;
    }
    return sortRegistrations(filtered, sort, ascending: _ascending);
  }

  List<AdminCheckIn> get _visibleCheckIns {
    final byId = _byId;
    final text = RegistrationFilters(query: _search.text);
    return _checkIns.where((c) {
      final r = byId[c.registrationId];
      return r == null ? text.isEmpty : text.matchesText(r);
    }).toList();
  }

  int _count(RegistrationView view) {
    final text = RegistrationFilters(query: _search.text);
    switch (view) {
      case RegistrationView.registered:
        return _filters.apply(_registered).length;
      case RegistrationView.cancelled:
        return text.apply(_cancelled).length;
      case RegistrationView.checkIns:
        return _visibleCheckIns.length;
    }
  }

  String _eventTitle(int id) => _event(id)?.title ?? 'Event $id';

  void _sortBy(RegistrationSort by) {
    setState(() {
      if (_sort == by) {
        _ascending = !_ascending;
      } else {
        _sort = by;
        // Names A–Z first; dates and batches newest first.
        _ascending = by == RegistrationSort.name;
      }
    });
  }

  // ── Export ───────────────────────────────────────────────────────────────

  Future<void> _export() async {
    final token = _token;
    final id = _effective;
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
    final compact = MediaQuery.sizeOf(context).width < 600;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(compact),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _body(compact)),
      ],
    );
  }

  Widget _toolbar(bool compact) {
    final p = context.palette;
    final picker = _EventPicker(
      events: _events,
      selected: _effective,
      showAll: _events.length > 1,
      onChanged: _pick,
    );
    final search = TextField(
      controller: _search,
      decoration: InputDecoration(
        hintText: 'Search name, email, phone or number…',
        prefixIcon: const Icon(Icons.search, size: 20),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
    final export = _isAll
        ? null
        : OutlinedButton.icon(
            onPressed: _exporting || _loading ? null : _export,
            icon: _exporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined, size: 18),
            label: const Text('Export CSV'),
          );
    final refresh = IconButton(
      tooltip: 'Refresh',
      onPressed: _loading ? null : _refresh,
      icon: const Icon(Icons.refresh),
    );

    final registered = _view == RegistrationView.registered;
    final years = batchYearsIn(_registered);
    final branches = branchesIn(_registered);
    final filters = [
      if (registered && years.isNotEmpty)
        _SmallDropdown<int>(
          hint: 'All batches',
          value: _batch,
          items: {for (final y in years) y: '$y'},
          onChanged: (v) => setState(() => _batch = v),
        ),
      if (registered && branches.isNotEmpty)
        _SmallDropdown<String>(
          hint: 'All branches',
          value: _branch,
          items: {for (final b in branches) b: b},
          onChanged: (v) => setState(() => _branch = v),
        ),
      if (_batch != null || _branch != null || _search.text.isNotEmpty)
        TextButton(
          onPressed: () => setState(_resetFilters),
          child: const Text('Clear'),
        ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
      child: AdminContainer(
        child: Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                Row(children: [Expanded(child: picker), refresh]),
                const SizedBox(height: 10),
                search,
                if (export != null) ...[
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerLeft, child: export),
                ],
              ] else
                Row(
                  children: [
                    SizedBox(width: 340, child: picker),
                    const SizedBox(width: 12),
                    Expanded(child: search),
                    if (export != null) ...[const SizedBox(width: 12), export],
                    const SizedBox(width: 4),
                    refresh,
                  ],
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final v in RegistrationView.values)
                    QuickFilterPill(
                      label: v.label,
                      count: _count(v),
                      active: v == _view,
                      onTap: () => setState(() => _view = v),
                    ),
                  if (filters.isNotEmpty) const SizedBox(width: 10),
                  ...filters,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(bool compact) {
    final target = _effective;
    if (target != _allEvents && _event(target) == null && !_eventsLoading) {
      return _Message(
        icon: Icons.lock_outline,
        title: 'Not available',
        body: 'This event doesn\'t exist, or you\'re not one of its admins.',
        action: TextButton(
          onPressed: () => _pick(_allEvents),
          child: Text(_events.length > 1 ? 'Show all my events' : 'Show my event'),
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
        final padding = AdminContainer.scrollPadding(context, constraints.maxWidth, top: 20);
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
    final checkedIn = _checkIns.map((c) => c.registrationId).toSet().length;
    if (_isAll) {
      return _SummaryCard(
        title: 'All my events',
        tiles: [
          _Tile('Events', '${_events.length}'),
          _Tile('Registered', '$registered'),
          _Tile('Cancelled', '$cancelled'),
          _Tile('Checked in', '$checkedIn'),
        ],
      );
    }
    final e = _event(_effective)!;
    final cap = e.capacity;
    return _SummaryCard(
      title: e.title,
      subtitle: 'Starts ${_formatDateTime(e.startDatetime)}',
      tiles: [
        _Tile('Capacity', cap == null ? 'No limit' : '$cap'),
        _Tile('Registered', '$registered'),
        _Tile(
          'Seats left',
          cap == null ? '—' : '${(cap - registered).clamp(0, cap)}',
          tone: cap != null && registered >= cap ? _Tone.error : null,
        ),
        _Tile('Cancelled', '$cancelled'),
        _Tile('Checked in', '$checkedIn'),
        _Tile(
          'Published',
          e.publishedAt == null ? 'Not yet' : _formatDate(e.publishedAt!.toLocal()),
        ),
      ],
      capacityFraction: cap != null && cap > 0 ? registered / cap : null,
    );
  }

  List<Widget> _list(bool compact) {
    switch (_view) {
      case RegistrationView.registered:
      case RegistrationView.cancelled:
        final rows = _rowsFor(_view);
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
          _RegistrationsTable(
            rows: rows,
            cancelledView: _view == RegistrationView.cancelled,
            eventTitle: _isAll ? _eventTitle : null,
            sort: _sort,
            ascending: _ascending,
            onSort: _sortBy,
          ),
        ];
      case RegistrationView.checkIns:
        final rows = _visibleCheckIns;
        final byId = _byId;
        return [
          const _Note(
            text: 'Check-ins scanned at the door. Rejected scans aren\'t recorded, so they don\'t appear here.',
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            _empty()
          else
            _CheckInsTable(
              rows: rows,
              people: byId,
              eventTitle: _isAll ? _eventTitle : null,
              compact: compact,
            ),
        ];
    }
  }

  Widget _empty() {
    final filtering = !_filters.isEmpty;
    final what = switch (_view) {
      RegistrationView.registered => 'No one has registered yet',
      RegistrationView.cancelled => 'No cancelled registrations',
      RegistrationView.checkIns => 'No one has checked in yet',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: _Message(
        icon: filtering ? Icons.search_off : Icons.people_outline,
        title: filtering ? 'No one matches' : what,
        body: filtering ? 'Try a different search or clear the filters.' : '',
      ),
    );
  }
}

// ── Formatting ───────────────────────────────────────────────────────────

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String _formatDateTime(DateTime d) {
  final hour = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
  final minute = d.minute.toString().padLeft(2, '0');
  return '${_formatDate(d)}, $hour:$minute ${d.hour >= 12 ? 'PM' : 'AM'}';
}

// ── Widgets ──────────────────────────────────────────────────────────────

class _EventPicker extends StatelessWidget {
  const _EventPicker({
    required this.events,
    required this.selected,
    required this.showAll,
    required this.onChanged,
  });

  final List<AppEvent> events;
  final int selected;
  final bool showAll;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final known = selected == _allEvents || events.any((e) => e.eventId == selected);
    return DropdownButtonFormField<int>(
      // Rebuild when the URL changes the selection.
      key: ValueKey(selected),
      initialValue: known ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.event_outlined, size: 20),
        hintText: 'Pick an event',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
      items: [
        if (showAll)
          const DropdownMenuItem<int>(
            value: _allEvents,
            child: Text('All my events', overflow: TextOverflow.ellipsis),
          ),
        for (final e in events)
          DropdownMenuItem<int>(
            value: e.eventId,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: e.title),
                  TextSpan(
                    text: '  ·  ${_formatDate(e.startDatetime.toLocal())}',
                    style: TextStyle(color: p.textMuted),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _SmallDropdown<T> extends StatelessWidget {
  const _SmallDropdown({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String hint;
  final T? value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: value == null ? p.surfaceSubtle : p.primary.withValues(alpha: 0.06),
        border: Border.all(
          color: value == null ? p.border : p.primary.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(100),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: items.containsKey(value) ? value : null,
          isDense: true,
          hint: Text(hint, style: AppTextStyles.labelMedium.copyWith(color: p.textSecondary)),
          style: AppTextStyles.labelMedium.copyWith(color: p.textPrimary),
          items: [
            DropdownMenuItem<T?>(value: null, child: Text(hint)),
            for (final entry in items.entries)
              DropdownMenuItem<T?>(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

enum _Tone { error }

class _Tile {
  const _Tile(this.label, this.value, {this.tone});

  final String label;
  final String value;
  final _Tone? tone;
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
                        color: t.tone == _Tone.error ? p.error : p.textPrimary,
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

/// Bordered card holding a sideways-scrolling [DataTable], like the
/// Events tab's table.
class _TableFrame extends StatelessWidget {
  const _TableFrame({required this.table});

  final DataTable table;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: table,
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _headStyle(AppPalette p) => AppTextStyles.labelSmall.copyWith(
      color: p.textMuted,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    );

TextStyle _cellStyle(AppPalette p) =>
    AppTextStyles.bodySmall.copyWith(fontSize: 13, color: p.textPrimary);

DataTable _dataTable(
  AppPalette p, {
  required List<DataColumn> columns,
  required List<DataRow> rows,
  int? sortColumnIndex,
  bool sortAscending = true,
}) {
  return DataTable(
    headingRowHeight: 40,
    dataRowMinHeight: 48,
    dataRowMaxHeight: 56,
    horizontalMargin: 16,
    columnSpacing: 24,
    dividerThickness: 0.6,
    headingRowColor: WidgetStatePropertyAll(p.surfaceSubtle),
    sortColumnIndex: sortColumnIndex,
    sortAscending: sortAscending,
    columns: columns,
    rows: rows,
  );
}

class _RegistrationsTable extends StatelessWidget {
  const _RegistrationsTable({
    required this.rows,
    required this.cancelledView,
    required this.eventTitle,
    required this.sort,
    required this.ascending,
    required this.onSort,
  });

  final List<AdminRegistration> rows;
  final bool cancelledView;

  /// Set in the all-events view, which adds an Event column.
  final String Function(int eventId)? eventTitle;
  final RegistrationSort sort;
  final bool ascending;
  final ValueChanged<RegistrationSort> onSort;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final head = _headStyle(p);
    final cell = _cellStyle(p);
    final muted = cell.copyWith(color: p.textSecondary);

    // Column order, with the sort each column uses (null: not sortable).
    final columns = <(String, RegistrationSort?)>[
      ('NO.', null),
      ('NAME', RegistrationSort.name),
      if (eventTitle != null) ('EVENT', null),
      if (!cancelledView) ...[
        ('BATCH', RegistrationSort.batch),
        ('BRANCH', null),
      ],
      ('EMAIL', null),
      if (!cancelledView) ...[
        ('PHONE', null),
        ('CONFIRMATION EMAIL', null),
      ],
      ('REGISTERED', RegistrationSort.registeredAt),
      if (cancelledView) ('CANCELLED', RegistrationSort.cancelledAt),
    ];
    final sortIndex = columns.indexWhere((c) => c.$2 == sort);

    return _TableFrame(
      table: _dataTable(
        p,
        sortColumnIndex: sortIndex < 0 ? null : sortIndex,
        sortAscending: ascending,
        columns: [
          for (final c in columns)
            DataColumn(
              label: Text(c.$1, style: head),
              onSort: c.$2 == null ? null : (_, _) => onSort(c.$2!),
            ),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              cells: [
                DataCell(Text(r.registrationNumber ?? '—', style: muted)),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      r.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: cell.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (eventTitle != null)
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        eventTitle!(r.eventId),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                  ),
                if (!cancelledView) ...[
                  DataCell(Text(r.batchYear?.toString() ?? '—', style: cell)),
                  DataCell(Text(r.branch ?? '—', style: cell)),
                ],
                DataCell(SelectableText(r.email ?? '—', style: cell)),
                if (!cancelledView) ...[
                  DataCell(SelectableText(r.phone ?? '—', style: cell)),
                  DataCell(_EmailStatus(status: r.confirmationEmailStatus)),
                ],
                DataCell(Text(_formatDateTime(r.registeredAt), style: cell)),
                if (cancelledView)
                  DataCell(
                    Text(
                      r.cancelledAt == null ? '—' : _formatDateTime(r.cancelledAt!),
                      style: cell,
                    ),
                  ),
              ],
            ),
        ],
      ),
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
    final tone = switch (status) {
      'sent' => p.success,
      'failed' => p.error,
      'pending' || 'queued' => p.warning,
      _ => p.textMuted,
    };
    if (label == '—') return Text(label, style: _cellStyle(p).copyWith(color: p.textMuted));
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
                ? 'Registered ${_formatDate(r.registeredAt)} · Cancelled ${_formatDate(r.cancelledAt!)}'
                : 'Registered ${_formatDateTime(r.registeredAt)}',
            style: secondary.copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }
}

class _CheckInsTable extends StatelessWidget {
  const _CheckInsTable({
    required this.rows,
    required this.people,
    required this.eventTitle,
    required this.compact,
  });

  final List<AdminCheckIn> rows;
  final Map<int, AdminRegistration> people;
  final String Function(int eventId)? eventTitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cell = _cellStyle(p);
    final muted = cell.copyWith(color: p.textSecondary);

    String who(AdminCheckIn c) =>
        people[c.registrationId]?.displayName ?? 'Registration ${c.registrationId}';
    String? number(AdminCheckIn c) => people[c.registrationId]?.registrationNumber;
    String scope(AdminCheckIn c) =>
        c.sessionId == null ? 'Event entry' : 'Session ${c.sessionId}';

    if (compact) {
      return Column(
        children: [
          for (final c in rows) ...[
            Container(
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
                  Text(who(c), style: AppTextStyles.titleSmall.copyWith(color: p.textPrimary)),
                  if (eventTitle != null) Text(eventTitle!(c.eventId), style: muted),
                  Text(
                    '${_formatDateTime(c.checkedInAt)} · ${scope(c)}',
                    style: muted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      );
    }

    final head = _headStyle(p);
    return _TableFrame(
      table: _dataTable(
        p,
        columns: [
          DataColumn(label: Text('NAME', style: head)),
          DataColumn(label: Text('NO.', style: head)),
          if (eventTitle != null) DataColumn(label: Text('EVENT', style: head)),
          DataColumn(label: Text('CHECKED IN', style: head)),
          DataColumn(label: Text('FOR', style: head)),
        ],
        rows: [
          for (final c in rows)
            DataRow(
              cells: [
                DataCell(Text(who(c), style: cell.copyWith(fontWeight: FontWeight.w600))),
                DataCell(Text(number(c) ?? '—', style: muted)),
                if (eventTitle != null)
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        eventTitle!(c.eventId),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                  ),
                DataCell(Text(_formatDateTime(c.checkedInAt), style: cell)),
                DataCell(Text(scope(c), style: muted)),
              ],
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
