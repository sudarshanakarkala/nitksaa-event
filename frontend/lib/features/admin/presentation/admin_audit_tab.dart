import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error_message.dart';
import '../../../core/logger/app_logger.dart';
import '../../../shared/widgets/filter_controls.dart';
import '../../../shared/widgets/quick_filter_pill.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/services/auth_controller.dart';
import '../../events/data/events_repository.dart';
import '../data/audit_api.dart';
import '../domain/registration_filters.dart';
import 'admin_tab_frame.dart';
import 'admin_widgets.dart';
import '../../../shared/widgets/state_message.dart';
import '../../../shared/widgets/list_search_field.dart';

const _categories = {
  'events': 'Events',
  'registrations': 'Registrations',
  'payments': 'Payments',
  'roles': 'Roles',
};

const _whoLabels = {'admin': 'Admins', 'attendee': 'Attendees', 'system': 'System'};

/// Admin → Audit: who did what, newest first (website Audit tab, step 10b).
///
/// Overall admins see every entry; event admins only their events'. The
/// server filters and pages (50 a page); headings sort the page shown, as
/// on the website. Clicking a row opens its recorded details.
class AdminAuditTab extends ConsumerStatefulWidget {
  const AdminAuditTab({super.key});

  @override
  ConsumerState<AdminAuditTab> createState() => _AdminAuditTabState();
}

class _AdminAuditTabState extends ConsumerState<AdminAuditTab> {
  final _search = TextEditingController();
  Timer? _debounce;

  List<AuditEntry> _rows = const [];
  List<AdminEventOption> _events = const [];
  int _total = 0;
  int _page = 1;
  int _pages = 1;
  bool _loading = true;
  String? _error;

  String? _category;
  String? _who;
  /// When the entries happened (the server's `from` and `to`); null = any.
  DateTimeRange? _dates;
  int _event = adminAllEvents;
  (String, bool) _sort = ('when', false);

  String? get _token => ref.read(authControllerProvider).session?.accessToken;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () => _load(page: 1));
    });
    Future.microtask(() async {
      await _loadEvents();
      await _load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    final token = _token;
    if (token == null) return;
    try {
      final events = await ref.read(eventsRepositoryProvider).getAllAdminEvents(token);
      if (!mounted) return;
      setState(() {
        _events = [for (final e in events) AdminEventOption.of(e)]
          ..sort((a, b) => (b.start ?? DateTime(1970)).compareTo(a.start ?? DateTime(1970)));
      });
    } catch (error) {
      AppLogger.warning('Audit: event list not loaded: $error');
    }
  }

  /// The date line: the server filters, so a drag waits until it settles.
  void _setDates(DateTimeRange? v) {
    setState(() => _dates = v);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load(page: 1));
  }

  Widget _dateLine() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return FilterDateRange(
      inline: true,
      lookBack: true,
      label: 'When',
      first: today.subtract(const Duration(days: 365)),
      last: today,
      value: _dates,
      presets: FilterDateRange.lookBackPresets(now),
      onChanged: _setDates,
    );
  }

  Future<void> _load({int? page}) async {
    final token = _token;
    if (token == null) return;
    final wanted = page ?? _page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.read(auditApiProvider).list(
            token,
            page: wanted,
            category: _category,
            who: _who,
            eventId: _event == adminAllEvents ? null : _event,
            from: _dates?.start,
            to: _dates?.end,
            q: _search.text,
          );
      if (!mounted) return;
      setState(() {
        _rows = result.rows;
        _total = result.total;
        _page = result.page;
        _pages = result.pages;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error('Audit: load failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(error, action: 'load the audit log');
      });
    }
  }

  void _set(VoidCallback change) {
    setState(change);
    _load(page: 1);
  }

  int get _activeFilterCount =>
      [_category != null, _who != null, _event != adminAllEvents].where((on) => on).length;

  void _clearAll() {
    _debounce?.cancel();
    _search.clear();
    _set(() {
      _category = null;
      _who = null;
      _event = adminAllEvents;
    });
  }

  List<GridColumn<AuditEntry>> get _columns => [
        GridColumn(id: 'when', label: 'When', kind: ColumnKind.date, value: (e) => e.at),
        GridColumn(id: 'what', label: 'What', kind: ColumnKind.text, value: (e) => e.label),
        GridColumn(id: 'who', label: 'Who', kind: ColumnKind.text, value: (e) => e.actor),
        GridColumn(id: 'event', label: 'Event', kind: ColumnKind.text, value: (e) => e.eventTitle),
        GridColumn(
          id: 'ref',
          label: 'Registration / order',
          kind: ColumnKind.text,
          value: (e) => e.orderNumber ?? e.registrationNumber,
        ),
      ];

  List<AuditEntry> get _sorted => applyGrid(_rows, _columns, sortId: _sort.$1, ascending: _sort.$2);

  @override
  Widget build(BuildContext context) {
    return AdminTabFrame(
      search: ListSearchField(
        controller: _search,
        hint: 'Search name, event, number, email or Razorpay id…',
      ),
      picker: AdminEventPicker(
        options: _events,
        selected: _event,
        onChanged: (id) => _set(() => _event = id),
        width: AdminTabFrame.pickerWidth(context),
      ),
      pills: [
        QuickFilterPill(label: 'All', active: _category == null, onTap: () => _set(() => _category = null)),
        for (final c in _categories.entries)
          QuickFilterPill(label: c.value, active: _category == c.key, onTap: () => _set(() => _category = c.key)),
      ],
      count: _loading && _rows.isEmpty ? null : ResultCount(count: _total, one: 'entry', many: 'entries'),
      filters: (context) => _filterRail(),
      onOpenFilters: () => showFilterSheet(context, builder: (_) => _filterRail(), onClear: _clearAll),
      activeFilterCount: _activeFilterCount,
      onClearFilters: _clearAll,
      belowPills: _dateLine(),
      loading: _loading && _rows.isNotEmpty,
      body: _body(),
    );
  }

  /// Single-choice chips; picking the chosen one again clears it.
  Widget _chips(String label, Map<String, String> options, String? selected, void Function(String?) onChanged) =>
      FilterChipSection(
        label: label,
        options: options,
        selected: {?selected},
        onChanged: (picked) {
          final added = picked.difference({?selected});
          onChanged(added.isEmpty ? null : added.first);
        },
      );

  Widget _filterRail() => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FilterLabel('Event'),
            const SizedBox(height: 8),
            AdminEventPicker(options: _events, selected: _event, onChanged: (id) => _set(() => _event = id)),
            const SizedBox(height: 20),
            _chips('Category', _categories, _category, (v) => _set(() => _category = v)),
            _chips('Who', _whoLabels, _who, (v) => _set(() => _who = v)),
          ],
        ),
      );

  Widget _body() {
    final p = context.palette;
    if (_loading && _rows.isEmpty && _error == null) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return StateMessage(
        icon: Icons.error_outline,
        title: 'Couldn\'t load the audit log',
        body: _error!,
        action: TextButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    return AdminGridTable<AuditEntry>(
      rows: _sorted,
      columns: _columns,
      sortId: _sort.$1,
      ascending: _sort.$2,
      onSort: (id, kind) => setState(
        () => _sort = _sort.$1 == id ? (id, !_sort.$2) : (id, kind != ColumnKind.date),
      ),
      onRowTap: (e) => showAuditEntry(context, e),
      empty: const StateMessage(body: 'No entries match.'),
      onRefresh: () => _load(page: _page),
      below: _pages > 1
          ? Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _page > 1 && !_loading ? () => _load(page: _page - 1) : null,
                  child: const Text('Newer'),
                ),
                Text('Page $_page of $_pages', style: AppTextStyles.bodySmall.copyWith(color: p.textMuted)),
                TextButton(
                  onPressed: _page < _pages && !_loading ? () => _load(page: _page + 1) : null,
                  child: const Text('Older'),
                ),
              ],
            )
          : null,
    );
  }
}

/// One entry's details window: what, when, who, and its recorded details.
Future<void> showAuditEntry(BuildContext context, AuditEntry e) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(e.label),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: AdminDetailRows(
              rows: [
                ('When', formatDateTime(e.at), false),
                ('Who', e.who == 'system' ? 'System' : '${e.actor} (${e.who == 'attendee' ? 'attendee' : 'admin'})', false),
                ('Event', e.eventTitle, false),
                ('Registration', e.registrationNumber, true),
                ('Order #', e.orderNumber, true),
                for (final d in e.details) (d.label, d.value, d.copy),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );

/// An order's history, oldest first, for the order details window.
class AuditTimeline extends StatelessWidget {
  const AuditTimeline({super.key, required this.entries});

  final List<AuditEntry> entries;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in entries)
          InkWell(
            onTap: () => showAuditEntry(context, e),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(formatDateTime(e.at), style: AppTextStyles.bodySmall.copyWith(color: p.textMuted)),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: e.label,
                        style: AppTextStyles.bodyMedium.copyWith(color: p.textPrimary),
                        children: [
                          TextSpan(
                            text: '  ·  ${e.actor}',
                            style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
