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
import '../../../admin/presentation/event_admin_actions.dart';
import '../../../auth/domain/admin_access.dart';
import '../../../auth/services/auth_controller.dart';
import '../providers/created_events_provider.dart';
import '../providers/events_provider.dart';
import '../providers/my_events_provider.dart';
import '../widgets/event_card.dart';
import '../../domain/event.dart';
import '../../domain/my_event_registration.dart';
import '../../../../shared/format.dart';
import '../../../../shared/widgets/list_search_field.dart';
import '../widgets/unregister_flow.dart';

/// "Registered by me" filter. UI state only; shared with the phone filter
/// sheet, which is a separate route.
final _registeredOnlyProvider = StateProvider.autoDispose<bool>((ref) => false);

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
  int _sortColumn = 1; // Date
  bool _sortAsc = true;
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

  /// Phones: the filters in a bottom sheet. Wider screens use the Filters
  /// panel in ListPage, which slides over the cards.
  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => ProviderScope(
        child: Consumer(
          builder: (context, ref, _) => _buildFilterPanel(ref),
        ),
      ),
    );
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

  /// Active filters, for the rail badge (search is not counted).
  int _activeFilterCount(EventsState s) => [
        s.period == 'past',
        s.dateRangeStart != null || s.dateRangeEnd != null,
        s.timeline != null,
        !((s.filterModes['physical'] ?? true) && (s.filterModes['virtual'] ?? true)),
        !((s.filterRegistrationStatus['open'] ?? true) &&
            (s.filterRegistrationStatus['closed'] ?? true)),
        !((s.filterPrice['free'] ?? true) && (s.filterPrice['paid'] ?? true)),
      ].where((active) => active).length;

  Widget _buildFilterPanel([WidgetRef? panelRef, bool inRail = false]) {
    final rf = panelRef ?? ref;
    final state = rf.watch(eventsProvider);
    final hasActiveFilters = state.dateRangeStart != null ||
      state.dateRangeEnd != null ||
      !((state.filterModes['physical'] ?? true) && (state.filterModes['virtual'] ?? true)) ||
      !((state.filterRegistrationStatus['open'] ?? true) && (state.filterRegistrationStatus['closed'] ?? true)) ||
      !((state.filterPrice['free'] ?? true) && (state.filterPrice['paid'] ?? true)) ||
      state.searchQuery.isNotEmpty ||
      state.timeline != null;
    final isInDrawer = MediaQuery.of(context).size.width >= 900;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (with clear & close actions). In the rail, the rail
          // header has the title and "Clear all".
          if (!inRail)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Filters',
                style: TextStyle(fontFamily: AppTextStyles.serif, fontSize: 20, fontWeight: FontWeight.w600),
              ),
              Row(
                children: [
                  if (hasActiveFilters)
                    TextButton(
                      onPressed: () {
                        rf.read(eventsProvider.notifier).clearFilters();
                        rf.read(eventsProvider.notifier).setPeriod('upcoming');
                        rf.read(_registeredOnlyProvider.notifier).state = false;
                        _searchController.clear();
                        if (isInDrawer) {
                          // keep drawer open so user can see cleared state
                        } else {
                          Navigator.pop(context);
                        }
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: context.palette.textSecondary,
                      ),
                      child: const Text('Clear all'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      // Only close the panel; do not modify filters.
                      if (isInDrawer) {
                        Navigator.of(context).maybePop();
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: inRail ? 8 : 20),

          // When: upcoming or past (single choice; was the page tabs).
          const FilterLabel('When'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final period in const ['upcoming', 'past'])
              FilterChipToggle(
                label: period == 'upcoming' ? 'Upcoming' : 'Past',
                selected: state.period == period,
                onChanged: (_) => rf.read(eventsProvider.notifier).setPeriod(period),
              ),
          ]),
          const SizedBox(height: 20),

          // Your registrations (website "Author: My Stories"), signed in only.
          if (rf.watch(authControllerProvider).isAuthenticated) ...[
            const FilterLabel('My Registrations'),
            const SizedBox(height: 8),
            FilterChipToggle(
              label: 'Registered by me',
              selected: rf.watch(_registeredOnlyProvider),
              onChanged: (on) => rf.read(_registeredOnlyProvider.notifier).state = on,
            ),
            const SizedBox(height: 20),
          ],

          // Date Range Section
          const FilterLabel('Date Range'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDatePickerButton(
                  label: state.dateRangeStart == null
                      ? 'From Date'
                      : '${state.dateRangeStart!.day}/${state.dateRangeStart!.month}/${state.dateRangeStart!.year}',
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: state.dateRangeStart ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      rf.read(eventsProvider.notifier).setDateRangeStart(picked);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDatePickerButton(
                  label: state.dateRangeEnd == null
                      ? 'To Date'
                      : '${state.dateRangeEnd!.day}/${state.dateRangeEnd!.month}/${state.dateRangeEnd!.year}',
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: state.dateRangeEnd ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      rf.read(eventsProvider.notifier).setDateRangeEnd(picked);
                    }
                  },
                ),
              ),
              if (state.dateRangeStart != null || state.dateRangeEnd != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      rf.read(eventsProvider.notifier).setDateRangeStart(null);
                      rf.read(eventsProvider.notifier).setDateRangeEnd(null);
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Timeline Section (single-select dropdown)
          const FilterLabel('Timeline'),
          const SizedBox(height: 8),
          _buildTimelineDropdown(rf, state, isInDrawer),
          const SizedBox(height: 20),

          // Event mode, registration status and price work like the website's
          // chips: none lit = all; lit = only those. The provider keeps
          // "included" flags (all included = no filter); _includeChips maps
          // between the two.
          ..._includeChips(
            'Event Mode',
            const {'physical': 'Physical', 'virtual': 'Virtual'},
            state.filterModes,
            rf.read(eventsProvider.notifier).toggleFilterMode,
          ),
          ..._includeChips(
            'Registration Status',
            const {'open': 'Open', 'closed': 'Closed'},
            state.filterRegistrationStatus,
            rf.read(eventsProvider.notifier).toggleFilterRegistrationStatus,
          ),
          ..._includeChips(
            'Price',
            const {'free': 'Free', 'paid': 'Paid'},
            state.filterPrice,
            rf.read(eventsProvider.notifier).toggleFilterPrice,
          ),
          const SizedBox(height: 24),

          // Drawer-only clear button removed — top 'Clear All' handles clearing.
        ],
      ),
    );
  }

  Widget _buildDatePickerButton({required String label, required VoidCallback onTap}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  

  // ==========================================
  // LAYOUT
  // ==========================================
  Widget _buildMaterialLayout() {
    final state = ref.watch(eventsProvider);
    final allEvents = ref.watch(filteredEventsProvider);
    // "Registered by me" (website "My Stories" filter): the public list
    // narrowed to events with an active registration of yours.
    final registrations = _registrationsByEvent();
    final registeredOnly = ref.watch(_registeredOnlyProvider);
    // Events you created get the "mine" tint.
    final created =
        ref.watch(createdEventIdsProvider).valueOrNull ?? const <int>{};
    final filteredEvents = registeredOnly
        ? allEvents.where((e) => registrations[e.eventId]?.isActive ?? false).toList()
        : allEvents;
    final signedIn = ref.watch(authControllerProvider).isAuthenticated;
    final access = ref.watch(authControllerProvider).session?.access ?? AdminAccess.none;
    final drafts = access.isAnyAdmin ? (ref.watch(myDraftCountProvider).valueOrNull ?? 0) : 0;
    // Quick "when" pills: shortcuts to the same filters as the panel.
    final noDates = state.dateRangeStart == null && state.dateRangeEnd == null;
    void when({required String period, String? timeline}) {
      final n = ref.read(eventsProvider.notifier);
      n.setDateRangeStart(null);
      n.setDateRangeEnd(null);
      n.setTimeline(timeline);
      n.setPeriod(period);
    }

    // Toolbar (header, search, Filters, quick pills), then the card grid.
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
        toggle: MediaQuery.sizeOf(context).width < 600
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
          if (access.isEventCreator)
            FilledButton.icon(
              onPressed: _adminActions.create,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create event'),
            ),
        ],
        quickFilters: [
          QuickFilterPill(
            label: 'Upcoming',
            active: state.period == 'upcoming' && state.timeline == null && noDates,
            onTap: () => when(period: 'upcoming'),
          ),
          QuickFilterPill(
            label: 'This week',
            active: state.period == 'upcoming' && state.timeline == 'this_week' && noDates,
            onTap: () => when(period: 'upcoming', timeline: 'this_week'),
          ),
          QuickFilterPill(
            label: 'This month',
            active: state.period == 'upcoming' && state.timeline == 'this_month' && noDates,
            onTap: () => when(period: 'upcoming', timeline: 'this_month'),
          ),
          QuickFilterPill(
            label: 'Past',
            active: state.period == 'past' && state.timeline == null && noDates,
            onTap: () => when(period: 'past'),
          ),
          if (signedIn)
            QuickFilterPill(
              label: 'Registered by me',
              active: registeredOnly,
              onTap: () =>
                  ref.read(_registeredOnlyProvider.notifier).state = !registeredOnly,
            ),
        ],
        filters: (context) => _buildFilterPanel(ref, true),
        onOpenFilters: _showFilterBottomSheet,
        activeFilterCount: _activeFilterCount(state) + (registeredOnly ? 1 : 0),
        onClearFilters: () {
          ref.read(_registeredOnlyProvider.notifier).state = false;
          ref.read(eventsProvider.notifier).clearFilters();
          ref.read(eventsProvider.notifier).setPeriod('upcoming');
          _searchController.clear();
        },
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
            ? const StateMessage(
                icon: Icons.event_note_outlined,
                title: 'No events found',
                body: 'Check back later or try other filters.',
              )
            : _view == 'table' && MediaQuery.sizeOf(context).width >= 600
            ? _buildEventTable(filteredEvents, pad, registrations)
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

  /// Table view (website ViewToggle "Table"): sortable columns, a row
  /// opens the event.
  Widget _buildEventTable(
    List<AppEvent> events,
    EdgeInsets pad,
    Map<int, MyEventRegistration> registrations,
  ) {
    final p = context.palette;
    int compare(AppEvent a, AppEvent b) {
      switch (_sortColumn) {
        case 0:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case 3:
          return a.isVirtual.toString().compareTo(b.isVirtual.toString());
        case 5:
          return a.registrationStatus.compareTo(b.registrationStatus);
        default:
          return a.startDatetime.compareTo(b.startDatetime);
      }
    }

    final rows = [...events]
      ..sort((a, b) => _sortAsc ? compare(a, b) : compare(b, a));
    void onSort(int column, bool ascending) => setState(() {
          _sortColumn = column;
          _sortAsc = ascending;
        });
    final cellStyle = AppTextStyles.bodySmall.copyWith(color: p.textSecondary);

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // Left and right insets differ on wide screens (content lines up with
        // the logo); using the left one on both sides cut the table short.
        padding: EdgeInsets.fromLTRB(pad.left, 24, pad.right, 24),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth - pad.horizontal),
            child: Container(
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: DataTable(
                sortColumnIndex: _sortColumn,
                sortAscending: _sortAsc,
                showCheckboxColumn: false,
                headingRowColor: WidgetStateProperty.all(p.surfaceSubtle),
                headingTextStyle: AppTextStyles.labelMedium.copyWith(
                  color: p.primary.withValues(alpha: 0.8),
                ),
                dividerThickness: 1,
                columns: [
                  DataColumn(label: const Text('TITLE'), onSort: onSort),
                  DataColumn(label: const Text('DATE'), onSort: onSort),
                  const DataColumn(label: Text('TIME')),
                  DataColumn(label: const Text('MODE'), onSort: onSort),
                  const DataColumn(label: Text('LOCATION')),
                  DataColumn(label: const Text('REGISTRATION'), onSort: onSort),
                ],
                rows: [
                  for (final event in rows)
                    DataRow(
                      onSelectChanged: (_) => context.push('/events/${event.eventId}'),
                      cells: [
                        DataCell(Text(
                          event.title,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        )),
                        DataCell(Text(formatDate(event.startDatetime), style: cellStyle)),
                        DataCell(Text(
                          formatTimeRange(event.startDatetime, event.endDatetime),
                          style: cellStyle,
                        )),
                        DataCell(Text(event.isVirtual ? 'Virtual' : 'Physical', style: cellStyle)),
                        DataCell(Text(
                          event.locationText ?? (event.isVirtual ? 'Online' : 'TBD'),
                          style: cellStyle,
                          overflow: TextOverflow.ellipsis,
                        )),
                        DataCell(Text(
                          (registrations[event.eventId]?.isActive ?? false)
                              ? 'Registered'
                              : event.registrationStatus == 'open'
                              ? 'Open'
                              : 'Closed',
                          style: cellStyle.copyWith(
                            color: (registrations[event.eventId]?.isActive ?? false)
                                ? p.primary
                                : event.registrationStatus == 'open'
                                ? p.success
                                : p.error,
                            fontWeight: FontWeight.w600,
                          ),
                        )),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TIMELINE DROPDOWN HELPERS
  // ==========================================
  static const Map<String, String> _timelineOptions = {
    'this_week': 'This week',
    'next_week': 'Next week',
    'this_month': 'This month',
    'next_month': 'Next month',
    'next_3_months': 'Next 3 months',
  };

  Widget _buildTimelineDropdown(WidgetRef rf, EventsState state, bool isInDrawer) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: state.timeline,
          isExpanded: true,
          hint: const Text('Select timeline'),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'None',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ..._timelineOptions.entries.map((entry) {
              return DropdownMenuItem<String?>(
                value: entry.key,
                child: Text(entry.value),
              );
            }),
          ],
          onChanged: (value) {
            rf.read(eventsProvider.notifier).setTimeline(value);
          },
        ),
      ),
    );
  }

  // ==========================================
  // HELPER DATE & TIME FORMATTERS
  // ==========================================
}
