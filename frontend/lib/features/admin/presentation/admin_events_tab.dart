import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_error_message.dart';
import '../../../core/logger/app_logger.dart';
import '../../../shared/widgets/quick_filter_pill.dart';
import '../../../shared/widgets/segment_toggle.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/domain/admin_access.dart';
import '../../auth/services/auth_controller.dart';
import '../../events/data/events_repository.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/providers/created_events_provider.dart';
import '../../events/presentation/providers/events_provider.dart';
import '../../events/presentation/screens/manage_events_screen.dart' show showEventFormDialog;
import '../../events/presentation/widgets/event_card.dart';
import 'admin_screen.dart' show AdminContainer;
import 'event_admins_dialog.dart';

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
      final isNew = GoRouterState.of(context).uri.queryParameters['new'] == '1';
      if (isNew && _access.isEventCreator) _create();
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

  /// After a change: reload here, and refresh the public list and "mine".
  Future<void> _afterChange() async {
    await _load();
    if (!mounted) return;
    ref.read(eventsProvider.notifier).fetchEvents(isRefresh: true);
    ref.invalidate(createdEventIdsProvider);
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

  /// Upcoming first (soonest at the top), then past (most recent first).
  List<AppEvent> get _visible {
    final rows = _searched.where((e) => _matches(e, _filter)).toList();
    final upcoming = rows.where((e) => !_ended(e)).toList()
      ..sort((a, b) => a.startDatetime.compareTo(b.startDatetime));
    final past = rows.where(_ended).toList()
      ..sort((a, b) => b.startDatetime.compareTo(a.startDatetime));
    return [...upcoming, ...past];
  }

  String? _createdBy(AppEvent e) {
    if (e.createdByUid != null && e.createdByUid == _myUid) return 'Created by you';
    final name = e.createdByName?.trim();
    return (name == null || name.isEmpty) ? null : 'Created by $name';
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _create() async {
    if (await showEventFormDialog(context)) await _afterChange();
  }

  Future<void> _edit(AppEvent e) async {
    if (await showEventFormDialog(context, event: e)) await _afterChange();
  }

  Future<bool> _confirm(
    String title,
    String body, {
    String confirm = 'Confirm',
    bool destructive = false,
  }) async {
    final p = context.palette;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: p.error, foregroundColor: p.onPrimary)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Runs [action] for [e] with the event marked busy, then reloads.
  Future<void> _run(
    AppEvent e,
    String what,
    Future<void> Function(String token) action, {
    required String done,
  }) async {
    final token = _token;
    if (token == null) return;
    setState(() => _busy.add(e.eventId));
    try {
      await action(token);
      _snack(done);
      await _afterChange();
    } catch (error, stackTrace) {
      AppLogger.error('Admin events: $what failed', error, stackTrace);
      _snack(_friendly(error, what), isError: true);
    } finally {
      if (mounted) setState(() => _busy.remove(e.eventId));
    }
  }

  /// Plain messages for the refusals people will actually meet.
  String _friendly(Object error, String what) {
    if (error is DioException) {
      final detail = error.response?.data is Map ? (error.response!.data as Map)['detail'] : null;
      switch (detail) {
        case 'event_not_draft':
          return 'Only drafts can be deleted. Cancel the event instead.';
        case 'event_has_registrations':
          return 'This event has registrations, so it can\'t be deleted. Cancel it instead.';
        case 'event_admin_required':
          return 'You\'re not an admin of this event.';
      }
    }
    return apiErrorMessage(error, action: what);
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

  Future<void> _publish(AppEvent e) => _run(
        e,
        'publish the event',
        (t) => ref.read(eventsRepositoryProvider).updateEventStatus(e.eventId, 'published', t),
        done: '"${e.title}" is published.',
      );

  Future<void> _unpublish(AppEvent e) async {
    final hasRegs = e.registeredCount > 0;
    if (!await _confirm(
      'Unpublish "${e.title}"?',
      hasRegs
          ? 'It goes back to draft and disappears from the Events page. '
              'Its ${e.registeredCount} registrations are kept.'
          : 'It goes back to draft and disappears from the Events page.',
      confirm: 'Unpublish',
    )) {
      return;
    }
    await _run(
      e,
      'unpublish the event',
      (t) => ref.read(eventsRepositoryProvider).updateEventStatus(e.eventId, 'draft', t),
      done: '"${e.title}" is back in draft.',
    );
  }

  /// Sets the closing time to now. Reversible: Reopen clears it.
  Future<void> _closeRegistration(AppEvent e) async {
    if (!await _confirm(
      'Close registration for "${e.title}"?',
      'No one else can register. You can reopen registration later.',
      confirm: 'Close registration',
    )) {
      return;
    }
    await _run(
      e,
      'close registration',
      (t) => ref.read(eventsRepositoryProvider).updateAdminEvent(
            e.eventId,
            {'registration_closes_at': DateTime.now().toUtc().toIso8601String()},
            t,
          ),
      done: 'Registration is closed for "${e.title}".',
    );
  }

  Future<void> _reopenRegistration(AppEvent e) => _run(
        e,
        'reopen registration',
        (t) => ref.read(eventsRepositoryProvider).updateAdminEvent(
              e.eventId,
              {'registration_closes_at': null},
              t,
            ),
        done: 'Registration is open again for "${e.title}".',
      );

  Future<void> _cancel(AppEvent e) async {
    if (!await _confirm(
      'Cancel "${e.title}"?',
      'The event is marked cancelled for everyone and can\'t be reopened. '
          '${e.registeredCount > 0 ? 'Its ${e.registeredCount} registrations are kept; refunds aren\'t sent automatically. ' : ''}'
          'To remove a draft entirely, delete it instead.',
      confirm: 'Cancel event',
      destructive: true,
    )) {
      return;
    }
    await _run(
      e,
      'cancel the event',
      (t) => ref.read(eventsRepositoryProvider).updateEventStatus(e.eventId, 'cancelled', t),
      done: '"${e.title}" is cancelled.',
    );
  }

  Future<void> _delete(AppEvent e) async {
    if (!await _confirm(
      'Delete "${e.title}"?',
      'The draft and everything in it (sessions, sponsors, partners) are '
          'removed for good.',
      confirm: 'Delete',
      destructive: true,
    )) {
      return;
    }
    await _run(
      e,
      'delete the event',
      (t) => ref.read(eventsRepositoryProvider).deleteAdminEvent(e.eventId, t),
      done: '"${e.title}" is deleted.',
    );
  }

  Future<void> _admins(AppEvent e) async {
    await showEventAdminsDialog(context, event: e);
    // Your own rights may have changed (e.g. you removed yourself).
    await ref.read(authControllerProvider.notifier).refreshSession();
    if (mounted) await _load();
  }

  /// What can be done to [e], by status (design step 5).
  List<EventCardAction> _actionsFor(AppEvent e) {
    if (_busy.contains(e.eventId)) return const [];
    final draft = e.status == 'draft';
    final published = e.status == 'published';
    final live = draft || published;
    final ended = _ended(e);
    final regs = '/admin/events/${e.eventId}/registrations';
    return [
      if (live)
        EventCardAction(label: 'Edit', icon: Icons.edit_outlined, onSelected: () => _edit(e)),
      if (!draft || e.registeredCount > 0)
        EventCardAction(
          label: 'Registrations',
          icon: Icons.people_outline,
          onSelected: () => context.push(regs),
        ),
      if (draft)
        EventCardAction(label: 'Publish', icon: Icons.publish_outlined, onSelected: () => _publish(e)),
      if (published && !ended && e.registrationStatus != 'closed')
        EventCardAction(
          label: 'Close registration',
          icon: Icons.lock_outline,
          onSelected: () => _closeRegistration(e),
        ),
      if (published && !ended && e.registrationStatus == 'closed')
        EventCardAction(
          label: 'Reopen registration',
          icon: Icons.lock_open_outlined,
          onSelected: () => _reopenRegistration(e),
        ),
      if (published)
        EventCardAction(
          label: 'Unpublish',
          icon: Icons.unpublished_outlined,
          onSelected: () => _unpublish(e),
        ),
      EventCardAction(
        label: 'Admins',
        icon: Icons.admin_panel_settings_outlined,
        onSelected: () => _admins(e),
      ),
      if (live)
        EventCardAction(
          label: 'Cancel event',
          icon: Icons.event_busy_outlined,
          destructive: true,
          onSelected: () => _cancel(e),
        ),
      if (draft)
        EventCardAction(
          label: 'Delete',
          icon: Icons.delete_outline,
          destructive: true,
          onSelected: () => _delete(e),
        ),
    ];
  }

  // ── Layout ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;
    final visible = _visible;
    final searched = _searched;

    final search = TextField(
      controller: _search,
      decoration: InputDecoration(
        hintText: 'Search events…',
        prefixIcon: const Icon(Icons.search, size: 20),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
    final toggle = SegmentToggle<_View>(
      options: const [
        SegmentOption(_View.cards, 'Cards', icon: Icons.grid_view_outlined),
        SegmentOption(_View.table, 'Table', icon: Icons.table_rows_outlined),
      ],
      selected: compact ? _View.cards : _view,
      onChanged: (v) => setState(() => _view = v),
    );
    final create = ref.watch(authControllerProvider).session?.access.isEventCreator ?? false
        ? FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create Event'),
          )
        : null;

    // Toolbar: fixed above the scrolling results, like the website's
    // topbar (search, view toggle, action; then the filter pills).
    final toolbar = DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
      child: AdminContainer(
        child: Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                search,
                const SizedBox(height: 10),
                if (create != null) Align(alignment: Alignment.centerLeft, child: create),
              ] else
                Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 12),
                    toggle,
                    if (create != null) ...[const SizedBox(width: 12), create],
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final f in _Filter.values) ...[
                      QuickFilterPill(
                        label: f.label,
                        count: searched.where((e) => _matches(e, f)).length,
                        active: f == _filter,
                        onTap: () => setState(() => _filter = f),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toolbar,
        if (_loading && _events.isNotEmpty) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _body(visible, compact)),
      ],
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
        body: _filter == _Filter.all && !searching
            ? (_access.isEventCreator
                ? 'Create an event to get started.'
                : 'You\'re not an admin of any events yet.')
            : 'Try another filter.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = AdminContainer.scrollPadding(context, constraints.maxWidth);
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
/// cards. Scrolls sideways on narrower screens.
class _EventsTable extends StatelessWidget {
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
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 52,
                    dataRowMaxHeight: 60,
                    horizontalMargin: 16,
                    columnSpacing: 24,
                    dividerThickness: 0.6,
                    headingRowColor: WidgetStatePropertyAll(p.surfaceSubtle),
                    columns: [
                      DataColumn(label: Text('EVENT', style: head)),
                      DataColumn(label: Text('STARTS', style: head)),
                      DataColumn(label: Text('STATUS', style: head)),
                      DataColumn(label: Text('MODE', style: head)),
                      DataColumn(label: Text('CAPACITY', style: head)),
                      DataColumn(label: Text('PRICE', style: head)),
                      DataColumn(label: Text('CREATED BY', style: head)),
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
