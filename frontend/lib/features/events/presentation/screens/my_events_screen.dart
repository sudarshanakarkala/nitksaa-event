import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../routes/app_routes.dart';
import '../../../../shared/widgets/filter_controls.dart';
import '../../../../shared/widgets/list_page.dart';
import '../../../../shared/widgets/quick_filter_pill.dart';
import '../../../../shared/widgets/state_message.dart';
import '../../../auth/services/auth_controller.dart';
import '../../domain/my_events_view.dart';
import '../providers/created_events_provider.dart';
import '../providers/my_events_provider.dart';
import '../widgets/event_card.dart';
import '../widgets/refund_status_dialog.dart';
import '../../../../shared/format.dart';
import '../../../../shared/widgets/list_search_field.dart';
import '../widgets/entry_pass_qr.dart' show showEntryPasses;
import '../widgets/unregister_flow.dart';

/// Your registrations, one card per event, in the Events page's layout
/// (`ListPage`): search, Filters rail, quick-filter pills and a count line.
/// Cancelled registrations stay here, so their refunds can be looked up.
class MyEventsScreen extends ConsumerStatefulWidget {
  const MyEventsScreen({super.key});

  @override
  ConsumerState<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends ConsumerState<MyEventsScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// Rail filters; none selected = all.
  Set<String> _when = {};
  Set<String> _status = {};

  static const _whenOptions = {'upcoming': 'Upcoming', 'past': 'Past'};
  // "Active", not "Registered": that word is the card's badge.
  static const _statusOptions = {'registered': 'Active', 'cancelled': 'Cancelled'};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    Future.microtask(() {
      if (ref.read(authControllerProvider).isAuthenticated) {
        ref.read(myEventsProvider.notifier).fetchMyEvents();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _set(VoidCallback change) => setState(change);

  void _clearAll() => setState(() {
        _when = {};
        _status = {};
        _searchController.clear();
      });

  /// Quick pill: exactly these filters, nothing else.
  void _quick({Set<String> when = const {}, Set<String> status = const {}}) =>
      setState(() {
        _when = {...when};
        _status = {...status};
      });

  bool _isQuick({Set<String> when = const {}, Set<String> status = const {}}) =>
      _setEquals(_when, when) && _setEquals(_status, status);

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  /// [all] narrowed by the search and the filters ([when] and [status]
  /// in place of the current ones, for the pills' counts).
  List<MyEventEntry> _visible(
    List<MyEventEntry> all, {
    Set<String>? when,
    Set<String>? status,
  }) {
    final wantWhen = when ?? _when;
    final wantStatus = status ?? _status;
    final now = DateTime.now();
    final query = _searchController.text.trim().toLowerCase();
    return all.where((e) {
      if (wantWhen.isNotEmpty && !wantWhen.contains(e.isUpcoming(now) ? 'upcoming' : 'past')) {
        return false;
      }
      if (wantStatus.isNotEmpty &&
          // Unfinished payments aren't cancelled: they count as Active.
          !wantStatus.contains(e.registration.isCancelled ? 'cancelled' : 'registered')) {
        return false;
      }
      if (query.isEmpty) return true;
      final r = e.registration;
      final text = [
        e.title,
        r.publicEvent?.tagline ?? '',
        r.event?.locationText ?? r.publicEvent?.locationText ?? '',
      ].join(' ').toLowerCase();
      return text.contains(query);
    }).toList();
  }

  /// The quick pills, with their counts (as on Events): on phones on the
  /// page, on wider screens at the top of the Filters rail.
  List<Widget> _pills(List<MyEventEntry> entries) {
    Widget pill(String label, {Set<String> when = const {}, Set<String> status = const {}}) =>
        QuickFilterPill(
          label: label,
          count: _visible(entries, when: when, status: status).length,
          active: _isQuick(when: when, status: status),
          onTap: () => _quick(when: when, status: status),
        );
    return [
      pill('All'),
      pill('Upcoming', when: {'upcoming'}),
      pill('Past', when: {'past'}),
      pill('Cancelled', status: {'cancelled'}),
    ];
  }

  /// [pills] (computers and tablets): the quick pills first, as on every
  /// list page's rail.
  Widget _filterRail({List<Widget>? pills}) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          if (pills != null) ...[
            const FilterLabel('Show'),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: pills),
            const SizedBox(height: 20),
          ],
          FilterChipSection(
            label: 'When',
            options: _whenOptions,
            selected: _when,
            onChanged: (v) => _set(() => _when = v),
          ),
          FilterChipSection(
            label: 'Status',
            options: _statusOptions,
            selected: _status,
            onChanged: (v) => _set(() => _status = v),
          ),
        ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    if (!auth.isAuthenticated) return const _SignedOut();

    final state = ref.watch(myEventsProvider);
    // Events you created get the "mine" tint.
    final created =
        ref.watch(createdEventIdsProvider).valueOrNull ?? const <int>{};
    final entries = myEventEntries(state.registrations);
    final visible = _visible(entries);
    final activeCount = entries.where((e) => !e.registration.isCancelled).length;

    return Scaffold(
      body: ListPage(
        title: 'My Events',
        subtitle: 'Events you have registered for, and the ones you cancelled '
            'with their refunds.',
        search: ListSearchField(
          controller: _searchController,
          hint: 'Search my events…',
        ),
        // Computers and tablets: every filter in the rail; phones: the pills
        // on the page and the sheet.
        filtersInRail: true,
        quickFilters: _pills(entries),
        count: state.isLoading
            ? null
            : ResultCount(
                count: visible.length,
                one: 'event',
                many: 'events',
                extra: '$activeCount registered',
              ),
        filters: (context) => _filterRail(pills: _pills(entries)),
        onOpenFilters: () =>
            showFilterSheet(context, builder: (_) => _filterRail(), onClear: _clearAll),
        activeFilterCount: _when.length + _status.length,
        onClearFilters: _clearAll,
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (state.isLoading && state.registrations.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.errorMessage != null) {
              return StateMessage(
                icon: Icons.error_outline,
                title: 'Could not load your registrations',
                body: state.errorMessage!,
                action: TextButton(
                  onPressed: () => ref.read(myEventsProvider.notifier).fetchMyEvents(),
                  child: const Text('Try again'),
                ),
              );
            }
            if (entries.isEmpty) {
              return StateMessage(
                icon: Icons.event_available_outlined,
                title: 'No registrations yet',
                action: TextButton(
                  onPressed: () => context.go(AppRoutes.home),
                  child: const Text('Browse events'),
                ),
              );
            }
            if (visible.isEmpty) {
              return StateMessage(
                icon: Icons.search_off,
                title: 'No events match',
                body: 'Try another search or filter.',
                action: TextButton(onPressed: _clearAll, child: const Text('Clear filters')),
              );
            }
            return EventCardGrid(
              padding: ListPage.contentPadding(context, constraints.maxWidth),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final entry = visible[index];
                return _registrationCard(
                  entry,
                  isCancelling: state.isCancelling(entry.registration.registrationId),
                  created: created,
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// The shared event card for one event you registered for.
  Widget _registrationCard(
    MyEventEntry entry, {
    required bool isCancelling,
    required Set<int> created,
  }) {
    final registration = entry.registration;
    final summary = registration.event;
    final event = registration.publicEvent;
    final active = registration.isActive;
    final when =
        registration.isCancelled ? registration.cancelledAt : registration.registeredAt;
    final joinUrl = registration.joinUrl?.trim() ?? '';
    final canJoin = active && joinUrl.isNotEmpty && entry.isUpcoming(DateTime.now());
    final refundFrom = entry.refundFrom;
    return EventCard(
      title: entry.title,
      tagline: event?.tagline,
      start: entry.start,
      end: summary?.endDatetime ?? event?.endDatetime,
      isVirtual: summary?.isVirtual ?? event?.isVirtual ?? false,
      location: summary?.locationText ?? event?.locationText,
      imageUrl: event?.thumbnailUrl ?? event?.bannerUrl,
      isFree: event?.isFree,
      price: event?.ticketPrice,
      registrationStatus: event?.registrationStatus,
      registrationClosesAt: event?.registrationClosesAt,
      attendance: active
          ? EventAttendance.registered
          : registration.isPaymentDue
              ? EventAttendance.paymentDue
              : registration.isConfirmingPayment
                  ? EventAttendance.confirmingPayment
                  : EventAttendance.cancelled,
      // A payment to finish is finished on the event page.
      viewLabel: registration.isPaymentDue ? 'Complete payment' : 'View Details',
      mine: created.contains(registration.eventId),
      footerNote: when == null
          ? null
          : '${active ? 'Registered' : registration.isCancelled ? 'Cancelled' : 'Started'} ${formatShortDate(when)}'
              '${active && registration.activeGuests.isNotEmpty ? ' · +${registration.activeGuests.length} ${registration.activeGuests.length == 1 ? 'guest' : 'guests'}' : ''}',
      onView: () => context.push('/events/${registration.eventId}'),
      onUnregister:
          registration.canCancel ? () => confirmAndUnregister(
                context,
                ref,
                registration: registration,
                eventTitle: registration.event?.title ?? 'this event',
              ) : null,
      unregistering: isCancelling,
      onJoin: canJoin
          ? () => launchUrl(Uri.parse(joinUrl), mode: LaunchMode.externalApplication)
          : null,
      // At the door: everyone's QR in this registration.
      onShowBadge: registration.entryPasses.isEmpty
          ? null
          : () => showEntryPasses(
                context,
                eventId: registration.eventId,
                eventTitle: entry.title,
                passes: registration.entryPasses,
              ),
      onViewRefund: refundFrom == null
          ? null
          : () => showRefundStatus(
                context,
                ref,
                registrationId: refundFrom.registrationId,
              ),
    );
  }

}

class _SignedOut extends StatelessWidget {
  const _SignedOut();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StateMessage(
        icon: Icons.bookmark_border,
        title: 'Sign in to see My Events',
        body: 'Your registrations, join links and refunds appear here.',
        action: FilledButton(
          onPressed: () => context.push(AppRoutes.login),
          child: const Text('Sign in'),
        ),
      ),
    );
  }
}
