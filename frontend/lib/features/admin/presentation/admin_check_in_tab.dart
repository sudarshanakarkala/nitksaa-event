import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_error_message.dart';
import '../../../core/logger/app_logger.dart';
import '../../../shared/widgets/list_page.dart';
import '../../../shared/widgets/notice.dart';
import '../../../shared/widgets/quick_filter_pill.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/services/auth_controller.dart';
import '../../checkin/data/check_in_api.dart';
import '../../checkin/check_in_scanner_screen.dart';
import '../../events/data/events_repository.dart';
import '../../events/domain/event.dart';
import '../data/registrations_api.dart';
import '../domain/registration_filters.dart' show formatDate;

/// When an event ends (start + 4 hours if it has no end time).
DateTime _endOf(AppEvent e) =>
    (e.endDatetime ?? e.startDatetime.add(const Duration(hours: 4))).toLocal();

/// Events worth checking people in to: not a draft or cancelled, someone
/// registered, and on now, coming up, or ended in the last 7 days. On now and
/// coming up first (soonest first), then the recent ones (latest first).
List<AppEvent> checkInEvents(List<AppEvent> events, DateTime now) {
  final relevant = events
      .where((e) =>
          e.status != 'draft' &&
          e.status != 'cancelled' &&
          e.registeredCount > 0 &&
          _endOf(e).isAfter(now.subtract(const Duration(days: 7))))
      .toList();
  final current = relevant.where((e) => _endOf(e).isAfter(now)).toList()
    ..sort((a, b) => a.startDatetime.compareTo(b.startDatetime));
  final recent = relevant.where((e) => !_endOf(e).isAfter(now)).toList()
    ..sort((a, b) => _endOf(b).compareTo(_endOf(a)));
  return [...current, ...recent];
}

/// Which people the list shows.
enum _Show {
  notYet('Not checked in'),
  checkedIn('Checked in'),
  all('All');

  const _Show(this.label);
  final String label;
}

/// Admin → Check-in: the door list for one event. Search for someone,
/// check them in with one tap (e.g. they have no QR), undo a mistake, or
/// open the scanner to check in one QR after another.
///
/// The event lives in the URL (`/admin/checkin?event=12`). Without one, the
/// tab opens the event happening now or next.
class AdminCheckInTab extends ConsumerStatefulWidget {
  const AdminCheckInTab({super.key});

  @override
  ConsumerState<AdminCheckInTab> createState() => _AdminCheckInTabState();
}

class _AdminCheckInTabState extends ConsumerState<AdminCheckInTab> {
  final _search = TextEditingController();

  List<AppEvent> _events = const [];
  bool _eventsLoading = true;
  String? _eventsError;

  /// The event in the URL; null until picked.
  int? _selected;

  int? _loadedFor;
  List<AdminRegistration> _people = const [];

  /// Registration id → their check-in.
  Map<int, AdminCheckIn> _checkIns = const {};
  bool _loading = false;
  String? _error;

  _Show _show = _Show.notYet;

  /// Registrations with a check-in or undo on its way.
  final Set<int> _busy = {};

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
    final fromUrl = int.tryParse(GoRouterState.of(context).uri.queryParameters['event'] ?? '');
    if (fromUrl != null && fromUrl != _selected) {
      _selected = fromUrl;
      Future.microtask(() {
        if (!mounted) return;
        _search.clear();
        if (!_eventsLoading) _loadPeople();
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
      final all = await ref.read(eventsRepositoryProvider).getAllAdminEvents(token);
      if (!mounted) return;
      final events = all.where((e) => e.status != 'draft' && e.status != 'cancelled').toList()
        ..sort((a, b) => b.startDatetime.compareTo(a.startDatetime));
      setState(() {
        _events = events;
        _eventsLoading = false;
      });
      if (_selected == null) {
        final now = _eventNow(events);
        if (now != null) _pick(now.eventId);
        return;
      }
      await _loadPeople();
    } catch (error, stackTrace) {
      AppLogger.error('Admin check-in: events load failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _eventsLoading = false;
        _eventsError = apiErrorMessage(error, action: 'load your events');
      });
    }
  }

  /// Where the tab opens: the first event worth checking in, else the
  /// latest event anyone registered for, else the latest event.
  static AppEvent? _eventNow(List<AppEvent> events) {
    final list = checkInEvents(events, DateTime.now());
    if (list.isNotEmpty) return list.first;
    for (final e in events) {
      if (e.registeredCount > 0) return e;
    }
    return events.isEmpty ? null : events.first;
  }

  Future<void> _loadPeople() async {
    final token = _token;
    final eventId = _selected;
    if (token == null || eventId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(registrationsApiProvider).loadEvent(
            accessToken: token,
            eventId: eventId,
          );
      if (!mounted || eventId != _selected) return;
      setState(() {
        _loadedFor = eventId;
        _people = [...data.registered]
          ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
        _checkIns = {for (final c in data.checkIns) c.registrationId: c};
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error('Admin check-in: load failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(error, action: 'load the check-in list');
      });
    }
  }

  void _pick(int eventId) {
    if (eventId == _selected) return;
    context.go('/admin/checkin?event=$eventId');
  }

  AppEvent? get _event {
    for (final e in _events) {
      if (e.eventId == _selected) return e;
    }
    return null;
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _checkIn(AdminRegistration person) async {
    final token = _token;
    final eventId = _selected;
    if (token == null || eventId == null) return;
    setState(() => _busy.add(person.registrationId));
    try {
      final done = await ref.read(checkInApiProvider).checkInRegistration(
            eventId: eventId,
            registrationId: person.registrationId,
            accessToken: token,
          );
      if (!mounted) return;
      setState(() {
        _checkIns = {
          ..._checkIns,
          person.registrationId: AdminCheckIn(
            checkinId: done.checkinId,
            eventId: eventId,
            registrationId: person.registrationId,
            checkedInAt: done.checkedInAt ?? DateTime.now(),
            result: 'success',
          ),
        };
      });
      showNotice(context, '${person.displayName} checked in.', kind: NoticeKind.success);
    } catch (error) {
      if (!mounted) return;
      showNotice(context, apiErrorMessage(error, action: 'check in'), kind: NoticeKind.error);
      await _loadPeople(); // e.g. someone else checked them in meanwhile
    } finally {
      if (mounted) setState(() => _busy.remove(person.registrationId));
    }
  }

  Future<void> _undo(AdminRegistration person) async {
    final token = _token;
    final eventId = _selected;
    final checkIn = _checkIns[person.registrationId];
    if (token == null || eventId == null || checkIn == null) return;
    setState(() => _busy.add(person.registrationId));
    try {
      await ref.read(checkInApiProvider).undo(
            eventId: eventId,
            checkinId: checkIn.checkinId,
            accessToken: token,
          );
      if (!mounted) return;
      setState(() => _checkIns = {..._checkIns}..remove(person.registrationId));
      showNotice(context, 'Check-in undone for ${person.displayName}.', kind: NoticeKind.info);
    } catch (error) {
      if (!mounted) return;
      showNotice(context, apiErrorMessage(error, action: 'undo the check-in'), kind: NoticeKind.error);
      await _loadPeople();
    } finally {
      if (mounted) setState(() => _busy.remove(person.registrationId));
    }
  }

  Future<void> _openScanner() async {
    final event = _event;
    if (event == null) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CheckInScannerScreen(
          eventId: event.eventId,
          eventTitle: event.title,
          total: _people.length,
          checkedIn: _checkedInCount,
        ),
      ),
    );
    if (mounted) await _loadPeople();
  }

  // ── View ─────────────────────────────────────────────────────────────────

  int get _checkedInCount => _people.where((p) => _checkIns.containsKey(p.registrationId)).length;

  bool _matches(AdminRegistration p, String q) {
    if (q.isEmpty) return true;
    return [p.displayName, p.email, p.phone, p.registrationNumber]
        .whereType<String>()
        .any((v) => v.toLowerCase().contains(q));
  }

  List<AdminRegistration> get _shown {
    final q = _search.text.trim().toLowerCase();
    final rows = _people.where((p) {
      final checked = _checkIns.containsKey(p.registrationId);
      final inView = switch (_show) {
        _Show.notYet => !checked,
        _Show.checkedIn => checked,
        _Show.all => true,
      };
      return inView && _matches(p, q);
    }).toList();
    if (_show == _Show.checkedIn) {
      // Latest arrivals first.
      rows.sort((a, b) =>
          _checkIns[b.registrationId]!.checkedInAt.compareTo(_checkIns[a.registrationId]!.checkedInAt));
    }
    return rows;
  }

  int _countFor(_Show s) => switch (s) {
        _Show.notYet => _people.length - _checkedInCount,
        _Show.checkedIn => _checkedInCount,
        _Show.all => _people.length,
      };

  Future<void> _chooseEvent() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EventChooser(
        all: _events,
        suggested: checkInEvents(_events, DateTime.now()),
        selected: _selected,
      ),
    );
    if (picked != null) _pick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ready = _loadedFor != null && _loadedFor == _selected && _error == null;
    final event = _event;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final pad = ListPage.contentPadding(context, constraints.maxWidth, top: 16, bottom: 0);

        final eventCard = _EventCard(
          event: event,
          loading: _eventsLoading,
          checkedIn: ready ? _checkedInCount : null,
          total: ready ? _people.length : null,
          onTap: _eventsLoading || _events.isEmpty ? null : _chooseEvent,
        );
        final scan = SizedBox(
          height: 52,
          width: compact ? double.infinity : null,
          child: ElevatedButton.icon(
            onPressed: ready && _people.isNotEmpty ? _openScanner : null,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        );
        final pills = Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in _Show.values)
              QuickFilterPill(
                label: s.label,
                count: ready ? _countFor(s) : null,
                active: s == _show,
                onTap: () => setState(() => _show = s),
              ),
          ],
        );
        final search = TextField(
          controller: _search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 20),
            hintText: 'Find a person: name, email, phone or number',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: pad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (compact) ...[
                    eventCard,
                    const SizedBox(height: 12),
                    scan,
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: eventCard,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(width: 160, child: scan),
                      ],
                    ),
                  const SizedBox(height: 16),
                  pills,
                  const SizedBox(height: 10),
                  if (compact)
                    search
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: search,
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            if (_loading || _eventsLoading)
              const LinearProgressIndicator(minHeight: 2)
            else
              Divider(height: 2, thickness: 1, color: p.border),
            Expanded(child: _body()),
          ],
        );
      },
    );
  }

  Widget _body() {
    final p = context.palette;
    Widget message(String text, {VoidCallback? retry}) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary)),
                if (retry != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: retry, child: const Text('Try again')),
                ],
              ],
            ),
          ),
        );

    if (_eventsError != null) return message(_eventsError!, retry: _loadEvents);
    if (_error != null) return message(_error!, retry: _loadPeople);
    if (_eventsLoading || _loadedFor != _selected) return const SizedBox.shrink();
    if (_events.isEmpty) return message('No published events to check people in to.');
    if (_people.isEmpty) return message('Nobody is registered for this event yet.');

    final rows = _shown;
    if (rows.isEmpty) {
      return message(_search.text.trim().isNotEmpty
          ? 'Nobody matches "${_search.text.trim()}".'
          : _show == _Show.notYet
              ? 'Everyone is checked in.'
              : 'Nobody is checked in yet.');
    }

    return LayoutBuilder(
      builder: (context, constraints) => ListView.separated(
        padding: ListPage.contentPadding(context, constraints.maxWidth, top: 12),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final person = rows[i];
          return _PersonRow(
            person: person,
            checkIn: _checkIns[person.registrationId],
            busy: _busy.contains(person.registrationId),
            onCheckIn: () => _checkIn(person),
            onUndo: () => _undo(person),
          );
        },
      ),
    );
  }
}

/// One person on the door list.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.checkIn,
    required this.busy,
    required this.onCheckIn,
    required this.onUndo,
  });

  final AdminRegistration person;
  final AdminCheckIn? checkIn;
  final bool busy;
  final VoidCallback onCheckIn;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final details = [person.registrationNumber, person.email, person.phone]
        .whereType<String>()
        .join(' · ');
    final checked = checkIn;

    final Widget action;
    if (busy) {
      action = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (checked != null) {
      action = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 18, color: p.success),
          const SizedBox(width: 4),
          Text(
            _time(checked.checkedInAt),
            style: AppTextStyles.bodySmall.copyWith(color: p.success, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          TextButton(onPressed: onUndo, child: const Text('Undo')),
        ],
      );
    } else {
      action = ElevatedButton(onPressed: onCheckIn, child: const Text('Check in'));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: checked != null ? p.tinted(p.success, 0.06) : p.surfaceSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: checked != null ? p.success.withValues(alpha: 0.35) : p.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.displayName,
                  style: AppTextStyles.titleMedium.copyWith(color: p.textPrimary),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          action,
        ],
      ),
    );
  }

  static String _time(DateTime t) {
    final local = t.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
  }
}


/// The chosen event, as a card to tap to change it.
class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.loading,
    required this.checkedIn,
    required this.total,
    required this.onTap,
  });

  final AppEvent? event;
  final bool loading;
  final int? checkedIn;
  final int? total;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = event;
    final title = e?.title ?? (loading ? 'Loading your events…' : 'Choose an event');
    final when = e == null ? null : formatDate(e.startDatetime.toLocal());
    final counts = checkedIn == null ? null : '$checkedIn of $total checked in';

    return Material(
      color: p.surfaceSubtle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(Icons.event_outlined, color: p.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleMedium.copyWith(color: p.textPrimary),
                    ),
                    if (when != null || counts != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [when, counts].whereType<String>().join(' · '),
                        style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Text('Change', style: AppTextStyles.labelMedium.copyWith(color: p.primary)),
                Icon(Icons.expand_more, color: p.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet to pick the event: the events worth checking in to, and a
/// search across all of them.
class _EventChooser extends StatefulWidget {
  const _EventChooser({required this.all, required this.suggested, required this.selected});

  final List<AppEvent> all;
  final List<AppEvent> suggested;
  final int? selected;

  @override
  State<_EventChooser> createState() => _EventChooserState();
}

class _EventChooserState extends State<_EventChooser> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final q = _query.text.trim().toLowerCase();
    final searching = q.isNotEmpty;
    final rows = searching
        ? widget.all.where((e) => e.title.toLowerCase().contains(q)).toList()
        : widget.suggested;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Choose an event',
                  style: AppTextStyles.titleLarge.copyWith(fontSize: 17, color: p.textPrimary)),
              const SizedBox(height: 12),
              TextField(
                controller: _query,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Search all events',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                searching ? 'All events' : 'On now, coming up and last 7 days',
                style: AppTextStyles.labelMedium.copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(
                          searching
                              ? 'No event matches "${_query.text.trim()}".'
                              : 'No events with registrations right now. Search to find others.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => Divider(height: 1, color: p.border),
                        itemBuilder: (context, i) {
                          final e = rows[i];
                          final chosen = e.eventId == widget.selected;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            title: Text(e.title,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: p.textPrimary,
                                  fontWeight: chosen ? FontWeight.w600 : FontWeight.w500,
                                )),
                            subtitle: Text(
                              '${formatDate(e.startDatetime.toLocal())} · ${e.registeredCount} registered',
                              style: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
                            ),
                            trailing: chosen ? Icon(Icons.check, color: p.primary) : null,
                            onTap: () => Navigator.of(context).pop(e.eventId),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
