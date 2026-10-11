
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';
import '../../../../theme/app_palette.dart';
import '../../../../theme/app_text_styles.dart';
import '../../../auth/services/auth_controller.dart';
import '../../domain/my_event_registration.dart';
import '../providers/my_events_provider.dart';
import '../widgets/event_card.dart';
import '../widgets/refund_status_dialog.dart';

class MyEventsScreen extends ConsumerStatefulWidget {
  const MyEventsScreen({super.key});

  @override
  ConsumerState<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends ConsumerState<MyEventsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {}); // Trigger rebuild when search text changes
    });
    Future.microtask(() => ref.read(myEventsProvider.notifier).fetchMyEvents());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final state = ref.watch(myEventsProvider);
    final theme = Theme.of(context);
    final isWebScreen = MediaQuery.of(context).size.width >= 900;

    // Get search query and filter registrations
    final searchQuery = _searchController.text.toLowerCase();
    final filteredRegistrations = searchQuery.isEmpty
        ? state.registrations
        : state.registrations.where((r) {
            final title = (r.event?.title ?? r.publicEvent?.title ?? '').toLowerCase();
            final tagline = (r.publicEvent?.tagline ?? '').toLowerCase();
            final location = (r.event?.locationText ?? r.publicEvent?.locationText ?? '').toLowerCase();
            return title.contains(searchQuery) || tagline.contains(searchQuery) || location.contains(searchQuery);
          }).toList();

    if (!auth.isAuthenticated) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bookmark_border, size: 56),
                    const SizedBox(height: 16),
                    const Text(
                      'Log in to view My Events',
                      style: TextStyle(fontFamily: AppTextStyles.serif, fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your registered events and join details appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => context.push(AppRoutes.login),
                      child: const Text('Log In'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isWebScreen ? 32 : 20,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'My Events',
                          style: TextStyle(
                            fontFamily: AppTextStyles.serif,
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Refresh',
                          onPressed: state.isLoading
                              ? null
                              : () => ref
                                  .read(myEventsProvider.notifier)
                                  .fetchMyEvents(),
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${state.registrations.where((r) => r.isActive).length} active registrations',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    // Search box
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search my events...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: state.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : state.errorMessage != null
                              ? _ErrorState(
                                  message: state.errorMessage!,
                                  onRetry: () => ref
                                      .read(myEventsProvider.notifier)
                                      .fetchMyEvents(),
                                )
                              : filteredRegistrations.isEmpty
                                  ? searchQuery.isNotEmpty
                                      ? const _SearchEmptyState()
                                      : const _EmptyState()
                                  : RefreshIndicator(
                                      onRefresh: () => ref
                                          .read(myEventsProvider.notifier)
                                          .fetchMyEvents(),
                                      child: EventCardGrid(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        itemCount: filteredRegistrations.length,
                                        itemBuilder: (context, index) {
                                          final registration =
                                              filteredRegistrations[index];
                                          return _registrationCard(
                                            registration,
                                            isCancelling: state.isCancelling(
                                              registration.registrationId,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The shared event card for one of your registrations.
  Widget _registrationCard(
    MyEventRegistration registration, {
    required bool isCancelling,
  }) {
    final summary = registration.event;
    final event = registration.publicEvent;
    final active = registration.isActive;
    final when = active ? registration.registeredAt : registration.cancelledAt;
    return EventCard(
      title: summary?.title ?? event?.title ?? 'Registered event',
      tagline: event?.tagline,
      start: summary?.startDatetime ?? event?.startDatetime,
      end: summary?.endDatetime ?? event?.endDatetime,
      isVirtual: summary?.isVirtual ?? event?.isVirtual ?? false,
      location: summary?.locationText ?? event?.locationText,
      imageUrl: event?.thumbnailUrl ?? event?.bannerUrl,
      isFree: event?.isFree,
      price: event?.ticketPrice,
      registrationStatus: event?.registrationStatus,
      registrationClosesAt: event?.registrationClosesAt,
      attendance:
          active ? EventAttendance.registered : EventAttendance.cancelled,
      footerNote: when == null
          ? null
          : '${active ? 'Registered' : 'Cancelled'} ${_shortDate(when)}',
      onView: () => context.push('/events/${registration.eventId}'),
      onUnregister:
          registration.canCancel ? () => _confirmCancel(registration) : null,
      unregistering: isCancelling,
      onViewRefund: registration.mayHaveRefund
          ? () => showRefundStatus(
                context,
                ref,
                registrationId: registration.registrationId,
              )
          : null,
    );
  }

  static String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  Future<void> _confirmCancel(MyEventRegistration registration) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unregister?'),
        content: Text(
          'This will unregister you from ${registration.event?.title ?? 'this event'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unregister'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final outcome = await ref
        .read(myEventsProvider.notifier)
        .cancelRegistration(registration.registrationId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.message),
        // A snackbar with an action stays up until it is pressed unless told
        // otherwise. This one closes after the usual four seconds.
        persist: false,
        action: viewRefundAction(
          context,
          ref,
          outcome: outcome,
          registrationId: registration.registrationId,
        ),
      ),
    );
  }
}


class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: context.palette.error),
          const SizedBox(height: 12),
          const Text('Could not load registrations'),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 64, color: context.palette.textMuted),
          const SizedBox(height: 16),
          const Text(
            'No events match your search',
            style: TextStyle(fontFamily: AppTextStyles.serif, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            style: TextStyle(color: context.palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_available_outlined, size: 64, color: context.palette.textMuted),
          const SizedBox(height: 16),
          const Text(
            'No registered events yet',
            style: TextStyle(fontFamily: AppTextStyles.serif, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('Browse events'),
          ),
        ],
      ),
    );
  }
}
