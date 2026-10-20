import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../theme/app_palette.dart';
import '../../../../theme/app_text_styles.dart';
import '../../../../shared/widgets/filter_controls.dart';
import '../../../../shared/widgets/list_page.dart';
import '../../../../shared/widgets/quick_filter_pill.dart';
import '../../../../shared/widgets/segment_toggle.dart';
import '../../../../shared/widgets/state_message.dart';
import '../../../admin/domain/registration_filters.dart';
import '../../../admin/presentation/admin_widgets.dart';
import '../../../admin/presentation/event_admin_actions.dart';
import '../../../auth/domain/admin_access.dart';
import '../../../auth/services/auth_controller.dart';
import '../providers/created_events_provider.dart';
import '../providers/events_provider.dart';
import '../providers/my_events_provider.dart';
import '../widgets/event_card.dart';
import '../widgets/event_list_controls.dart';
import '../../domain/event.dart';
import '../../domain/my_event_registration.dart';
import '../../../../shared/format.dart';
import '../../../../shared/widgets/list_search_field.dart';
import '../widgets/unregister_flow.dart';

/// "Registered by me" filter. UI state only; shared with the phone filter
/// sheet, which is a separate route.
final _registeredOnlyProvider = StateProvider.autoDispose<bool>((ref) => false);

/// The type pills (Admin → Events has its own set, with drafts and
/// cancelled events). Upcoming is the default.
enum _Show {
  upcoming('Upcoming'),
  open('Open'),
  past('Past'),
  all('All');

  const _Show(this.label);
  final String label;

  bool matches(AppEvent e) => switch (this) {
        _Show.upcoming => !eventEnded(e),
        _Show.open => e.registrationStatus == 'open' && !eventEnded(e),
        _Show.past => eventEnded(e),
        _Show.all => true,
      };
}

class EventListScreen extends ConsumerStatefulWidget {
  const EventListScreen({super.key});

  @override
  ConsumerState<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends ConsumerState<EventListScreen> {
  /// Admin actions in place (website pattern): on cards of events you
  /// administer, the same ⋯ menu as Admin → Events.
  final Set<int> _busy = {};
  late final EventAdminActions _adminActions = EventAdminActions(
    context: context,
    ref: ref,
    onChanged: () async {}, // the shared refresh reloads this list
    isBusy: _busy.contains,
    setBusy: (id, busy) {
      if (!mounted) return;
      setState(() => busy ? _busy.add(id) : _busy.remove(id));
    },
  );

  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Cards / Table view (website ViewToggle) and table sort.
  String _view = 'cards';
  // Table view sort (column id, ascending): soonest first.
  (String, bool) _tableSort = ('date', true);

  // Same controls as Admin → Events: type pills, the date line and the
  // Date ↑/↓ order (soonest first by default).
  _Show _show = _Show.upcoming;
  DateTimeRange? _dates;
  bool _soonestFirst = true;
  String? _appliedUri;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      ref.read(eventsProvider.notifier).setSearchQuery(_searchController.text);
    });
    // Your registrations, for the "Registered by me" filter and own cards.
    Future.microtask(() {
      if (ref.read(authControllerProvider).isAuthenticated) {
        ref.read(myEventsProvider.notifier).fetchMyEvents();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // /home?mine=1 opens with "Registered by me" on. Applied once per URL,
    // so resizing (which also lands here) doesn't re-apply it.
    final uri = GoRouterState.of(context).uri;
    if (uri.toString() == _appliedUri) return;
    _appliedUri = uri.toString();
    if (uri.queryParameters['mine'] == '1') {
      Future.microtask(() {
        if (mounted) ref.read(_registeredOnlyProvider.notifier).state = true;
      });
    }
  }

  /// Your registrations by event id (empty when signed out).
  Map<int, MyEventRegistration> _registrationsByEvent() {
    if (!ref.watch(authControllerProvider).isAuthenticated) return const {};
    final byEvent = <int, MyEventRegistration>{};
    for (final r in ref.watch(myEventsProvider).registrations) {
      // An event can have several rows, such as one cancelled and then one
      // registered again. The active row is the one Unregister acts on.
      if (r.isActive || !byEvent.containsKey(r.eventId)) byEvent[r.eventId] = r;
    }
    return byEvent;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildMaterialLayout();
  }

  /// A rail section of on/off chips over "included" flags: [included] maps
  /// each option to whether its events are shown (all true = no filter).
  ///
  /// A chip is lit only when it narrows the list, so a fresh page shows none
  /// lit. Clicking one when none is lit shows only that option; clicking a
  /// lit one takes it off again (the last one off means all again).
  List<Widget> _includeChips(
    String label,
    Map<String, String> options,
    Map<String, bool> included,
    void Function(String key) toggle,
  ) {
    bool on(String key) => included[key] ?? true;
    final all = options.keys.every(on);
    void tap(String key) {
      final wanted = all
          ? {key}
          : {for (final k in options.keys) if (on(k) != (k == key)) k};
      // Nothing left means no filter: everything shown again.
      final target = wanted.isEmpty ? options.keys.toSet() : wanted;
      for (final k in options.keys) {
        if (on(k) != target.contains(k)) toggle(k);
      }
    }

    return [
      FilterLabel(label),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final MapEntry(:key, :value) in options.entries)
          FilterChipToggle(
            label: value,
            selected: !all && on(key),
            onChanged: (_) => tap(key),
          ),
      ]),
      const SizedBox(height: 20),
    ];
  }

  /// Active filters, for the rail badge (search and dates not counted).
  int _activeFilterCount(EventsState s, bool registeredOnly) => [
        _show != _Show.upcoming,
        registeredOnly,
        !((s.filterModes['physical'] ?? true) && (s.filterModes['virtual'] ?? true)),
        !((s.filterRegistrationStatus['open'] ?? true) &&
            (s.filterRegistrationStatus['closed'] ?? true)),
        !((s.filterPrice['free'] ?? true) && (s.filterPrice['paid'] ?? true)),
      ].where((active) => active).length;

  void _clearFilters() {
    ref.read(_registeredOnlyProvider.notifier).state = false;
    ref.read(eventsProvider.notifier).clearFilters();
    _searchController.clear();
    setState(() => _show = _Show.upcoming);
  }

  /// The Filters rail (a bottom sheet on phones): every filter, the pills
  /// included. Reads rather than watches: the page rebuilds the rail, and
  /// the sheet rebuilds itself on each tap.
  Widget _filterRail() {
    final state = ref.read(eventsProvider);
    final notifier = ref.read(eventsProvider.notifier);
    final signedIn = ref.read(authControllerProvider).isAuthenticated;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FilterLabel('Show'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in _Show.values)
              FilterChipToggle(
                label: s.label,
                selected: s == _show,
                onChanged: (_) => setState(() => _show = s),
              ),
          ]),
          const SizedBox(height: 20),
          // Your registrations (website "Author: My Stories"), signed in only.
          if (signedIn) ...[
            const FilterLabel('My registrations'),
            const SizedBox(height: 8),
            FilterChipToggle(
              label: 'Registered by me',
              selected: ref.read(_registeredOnlyProvider),
              onChanged: (on) => ref.read(_registeredOnlyProvider.notifier).state = on,
            ),
            const SizedBox(height: 20),
          ],
          // Mode, registration and price work like the website's chips:
          // none lit = all; lit = only those. The provider keeps "included"
          // flags (all included = no filter); _includeChips maps between the
          // two.
          ..._includeChips(
            'Event mode',
            const {'physical': 'Physical', 'virtual': 'Virtual'},
            state.filterModes,
            notifier.toggleFilterMode,
          ),
          ..._includeChips(
            'Registration',
            const {'open': 'Open', 'closed': 'Closed'},
            state.filterRegistrationStatus,
            notifier.toggleFilterRegistrationStatus,
          ),
          ..._includeChips(
            'Price',
            const {'free': 'Free', 'paid': 'Paid'},
            state.filterPrice,
            notifier.toggleFilterPrice,
          ),
        ],
      ),
    );
  }

  // ==========================================
  // LAYOUT
  // ==========================================
  Widget _buildMaterialLayout() {
    final state = ref.watch(eventsProvider);
    // Search and the Filters rail (mode, registration, price).
    final railed = ref.watch(filteredEventsProvider);
    // "Registered by me" (website "My Stories" filter): narrowed to events
    // with an active registration of yours.
    final registrations = _registrationsByEvent();
    final registeredOnly = ref.watch(_registeredOnlyProvider);
    // Events you created get the "mine" tint.
    final created =
        ref.watch(createdEventIdsProvider).valueOrNull ?? const <int>{};
    final signedIn = ref.watch(authControllerProvider).isAuthenticated;
    final access = ref.watch(authControllerProvider).session?.access ?? AdminAccess.none;
    final drafts = access.isAnyAdmin ? (ref.watch(myDraftCountProvider).valueOrNull ?? 0) : 0;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final table = _view == 'table' && !compact;

    // Everything but the type pills: their counts follow the rest.
    final narrowed = [
      for (final e in railed)
        if ((!registeredOnly || (registrations[e.eventId]?.isActive ?? false)) &&
            FilterDateRange.contains(_dates, e.startDatetime))
          e,
    ];
    final filteredEvents = orderEvents(
      narrowed.where(_show.matches),
      soonestFirst: _soonestFirst,
    );

    // The same rows as Admin → Events: search, Cards/Table, Filters; the
    // pills; the date line; the count and Create event.
    return Scaffold(
      key: _scaffoldKey,
      body: ListPage(
        title: 'Events',
        subtitle: 'Reunions, talks and meetups of the NITK Surathkal Alumni Association.',
        search: ListSearchField(
          controller: _searchController,
          hint: 'Search events…',
        ),
        // Cards / Table, like the website; phones get cards only.
        toggle: compact
            ? null
            : SegmentToggle<String>(
                options: const [
                  SegmentOption('cards', 'Cards', icon: Icons.grid_view),
                  SegmentOption('table', 'Table', icon: Icons.table_rows_outlined),
                ],
                selected: _view,
                onChanged: (view) => setState(() => _view = view),
              ),
        count: state.isLoading
            ? null
            : ResultCount(count: filteredEvents.length, one: 'event', many: 'events'),
        // Admins act here too: their drafts (kept off the public grid, as on
        // the website) and Create event.
        actions: [
          if (drafts > 0)
            TextButton.icon(
              onPressed: () => context.go('/admin/events?filter=draft'),
              icon: const Icon(Icons.edit_note_outlined, size: 18),
              label: Text(drafts == 1 ? '1 draft' : '$drafts drafts'),
            ),
          // Import from a Google Sheet: computers only (not in phoneActions).
          if (access.isEventCreator)
            OutlinedButton.icon(
              key: const ValueKey('events-import'),
              onPressed: _adminActions.importFromSheet,
              icon: const Icon(Icons.table_chart_outlined, size: 18),
              label: const Text('Import'),
            ),
          if (access.isEventCreator)
            FilledButton.icon(
              onPressed: _adminActions.create,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create event'),
            ),
        ],
        // Phones: the pills already count the events; drafts and Create
        // event are small squares in the search row.
        countOnPhone: false,
        phoneActions: [
          if (drafts > 0)
            ListIconAction(
              icon: Icons.edit_note_outlined,
              tooltip: drafts == 1 ? '1 draft' : '$drafts drafts',
              badge: drafts,
              onPressed: () => context.go('/admin/events?filter=draft'),
            ),
          if (access.isEventCreator)
            ListIconAction(
              icon: Icons.add,
              tooltip: 'Create event',
              onPressed: _adminActions.create,
              filled: true,
            ),
        ],
        quickFilters: [
          for (final s in _Show.values)
            QuickFilterPill(
              label: s.label,
              count: state.isLoading ? null : narrowed.where(s.matches).length,
              active: s == _show,
              onTap: () => setState(() => _show = s),
            ),
          if (signedIn)
            QuickFilterPill(
              label: 'Registered by me',
              active: registeredOnly,
              onTap: () =>
                  ref.read(_registeredOnlyProvider.notifier).state = !registeredOnly,
            ),
        ],
        belowPills: state.events.isEmpty
            ? null
            : EventDateLine(
                events: state.events,
                value: _dates,
                onChanged: (v) => setState(() => _dates = v),
                sortable: !table,
                soonestFirst: _soonestFirst,
                dateOrder: true,
                onDateOrder: () {},
                onFlip: () => setState(() => _soonestFirst = !_soonestFirst),
              ),
        filters: (context) => _filterRail(),
        onOpenFilters: () => showFilterSheet(
          context,
          builder: (_) => _filterRail(),
          onClear: _clearFilters,
        ),
        activeFilterCount: _activeFilterCount(state, registeredOnly),
        onClearFilters: _clearFilters,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final pad = ListPage.contentPadding(context, constraints.maxWidth);
            return state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : state.errorMessage != null
            ? StateMessage(
                icon: Icons.error_outline,
                title: 'Couldn\'t load events',
                body: state.errorMessage!,
                action: TextButton(
                  onPressed: () =>
                      ref.read(eventsProvider.notifier).fetchEvents(isRefresh: true),
                  child: const Text('Try again'),
                ),
              )
            : filteredEvents.isEmpty
            ? StateMessage(
                icon: Icons.event_note_outlined,
                title: 'No events found',
                body: _dates != null || _show != _Show.upcoming || registeredOnly
                    ? 'Try other dates or filters.'
                    : 'Check back later or try other filters.',
              )
            : table
            ? _eventTable(filteredEvents, registrations)
            // Website grid: columns of at least 300px, every card the same
            // height (no intrinsic sizing).
            : EventCardGrid(
                padding: pad,
                itemCount: filteredEvents.length,
                itemBuilder: (context, index) {
                  final event = filteredEvents[index];
                  final registration = registrations[event.eventId];
                  final registered = registration?.isActive ?? false;
                  return EventCard.forEvent(
                    event,
                    attendance: registered
                        ? EventAttendance.registered
                        : EventAttendance.none,
                    mine: created.contains(event.eventId),
                    onView: () => context.push('/events/${event.eventId}'),
                    adminActions: access.canAdminEvent(event.eventId)
                        ? _adminActions.actionsFor(event)
                        : const [],
                    onUnregister: registered && registration!.canCancel
                        ? () => confirmAndUnregister(
                            // The page's context, not the card's: with
                            // "Registered by me" on, the card goes away once
                            // cancelled, and the notice (View refund) needs
                            // something that stays.
                            this.context,
                            ref,
                            registration: registration,
                            eventTitle: event.title,
                          )
                        : null,
                    unregistering: registration != null &&
                        ref
                            .watch(myEventsProvider)
                            .isCancelling(registration.registrationId),
                  );
                },
              );
          },
        ),
      ),
    );
  }

  /// Table view (website ViewToggle "Table"): the shared table; every
  /// heading sorts and a row opens the event.
  Widget _eventTable(List<AppEvent> events, Map<int, MyEventRegistration> registrations) {
    final p = context.palette;
    String registration(AppEvent e) => (registrations[e.eventId]?.isActive ?? false)
        ? 'Registered'
        : e.registrationStatus == 'open'
        ? 'Open'
        : 'Closed';
    final columns = <GridColumn<AppEvent>>[
      GridColumn(id: 'title', label: 'Title', kind: ColumnKind.text, value: (e) => e.title),
      GridColumn(
        id: 'date',
        label: 'Date',
        kind: ColumnKind.date,
        value: (e) => e.startDatetime,
        text: (e) => formatDate(e.startDatetime),
      ),
      GridColumn(
        id: 'time',
        label: 'Time',
        kind: ColumnKind.text,
        value: (e) => e.startDatetime.hour * 60 + e.startDatetime.minute,
        text: (e) => formatTimeRange(e.startDatetime, e.endDatetime),
      ),
      GridColumn(
        id: 'mode',
        label: 'Mode',
        kind: ColumnKind.category,
        value: (e) => e.isVirtual ? 'Virtual' : 'Physical',
      ),
      GridColumn(
        id: 'location',
        label: 'Location',
        kind: ColumnKind.text,
        value: (e) => e.locationText ?? (e.isVirtual ? 'Online' : 'TBD'),
      ),
      GridColumn(
        id: 'registration',
        label: 'Registration',
        kind: ColumnKind.category,
        value: registration,
      ),
    ];
    final rows = applyGrid(events, columns, sortId: _tableSort.$1, ascending: _tableSort.$2);
    return AdminGridTable<AppEvent>(
      rows: rows,
      columns: columns,
      sortId: _tableSort.$1,
      ascending: _tableSort.$2,
      onSort: (id, kind) => setState(
        () => _tableSort = _tableSort.$1 == id ? (id, !_tableSort.$2) : (id, true),
      ),
      onRowTap: (e) => context.push('/events/${e.eventId}'),
      cell: (c, e) {
        if (c.id != 'registration') return null;
        final label = registration(e);
        return Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
            color: label == 'Registered'
                ? p.primary
                : label == 'Open'
                ? p.success
                : p.error,
          ),
        );
      },
    );
  }

  // ==========================================
  // HELPER DATE & TIME FORMATTERS
  // ==========================================
}
