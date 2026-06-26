import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';
import '../../../auth/services/auth_controller.dart';
import '../../domain/my_event_registration.dart';
import '../providers/my_events_provider.dart';

class MyEventsScreen extends ConsumerStatefulWidget {
  const MyEventsScreen({super.key});

  @override
  ConsumerState<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends ConsumerState<MyEventsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(myEventsProvider.notifier).fetchMyEvents());
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final state = ref.watch(myEventsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isWebScreen = kIsWeb || MediaQuery.of(context).size.width > 900;

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
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
            if (isWebScreen) _Sidebar(isDark: isDark, auth: auth),
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
                            fontFamily: 'Fraunces',
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
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
                    const SizedBox(height: 24),
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
                              : state.registrations.isEmpty
                                  ? const _EmptyState()
                                  : RefreshIndicator(
                                      onRefresh: () => ref
                                          .read(myEventsProvider.notifier)
                                          .fetchMyEvents(),
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          final columns =
                                              constraints.maxWidth > 980 ? 2 : 1;
                                          return GridView.builder(
                                            gridDelegate:
                                                SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: columns,
                                              crossAxisSpacing: 20,
                                              mainAxisSpacing: 20,
                                              mainAxisExtent: 260,
                                            ),
                                            itemCount: state.registrations.length,
                                            itemBuilder: (context, index) {
                                              final registration =
                                                  state.registrations[index];
                                              return _RegistrationCard(
                                                registration: registration,
                                                isDark: isDark,
                                                isCancelling:
                                                    state.cancellingEventId ==
                                                        registration.eventId,
                                                onView: () => context.push(
                                                  '/events/${registration.eventId}',
                                                ),
                                                onCancel: registration.canCancel
                                                    ? () => _confirmCancel(
                                                          registration,
                                                        )
                                                    : null,
                                              );
                                            },
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
      bottomNavigationBar: isWebScreen
          ? null
          : NavigationBar(
              selectedIndex: 1,
              onDestinationSelected: (index) {
                if (index == 0) context.go(AppRoutes.home);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.calendar_month),
                  label: 'Events',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bookmark),
                  label: 'My Events',
                ),
              ],
            ),
    );
  }

  Future<void> _confirmCancel(MyEventRegistration registration) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel registration?'),
        content: Text(
          'This will cancel your registration for ${registration.event?.title ?? 'this event'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Registration'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(myEventsProvider.notifier)
        .cancelRegistration(registration.eventId);
    if (!mounted) return;
    final error = ref.read(myEventsProvider).errorMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? 'Registration cancelled.'
              : 'Could not cancel registration.',
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.isDark, required this.auth});

  final bool isDark;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 240,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0E1726) : const Color(0xFFF8F9FD),
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calendar_today_outlined, color: Color(0xFFC9952A)),
              SizedBox(width: 8),
              Text(
                'NITKSAA',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFC9952A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _SidebarItem(
            icon: Icons.calendar_month,
            label: 'Events',
            active: false,
            onTap: () => context.go(AppRoutes.home),
          ),
          _SidebarItem(
            icon: Icons.bookmark,
            label: 'My Events',
            active: true,
            onTap: () {},
          ),
          const _SidebarItem(
            icon: Icons.verified_user_outlined,
            label: 'Volunteer',
            active: false,
          ),
          const _SidebarItem(icon: Icons.more_horiz, label: 'More', active: false),
          const Spacer(),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFC9952A),
                child: Text(
                  (auth.session?.fullname ?? 'U').substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  auth.session?.fullname ?? 'Alumni User',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBg = isDark ? const Color(0xFF1C2A40) : const Color(0xFFEEF3FA);
    final activeText = isDark ? Colors.white : const Color(0xFF0D1B3E);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: active ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        visualDensity: VisualDensity.compact,
        leading: Icon(
          icon,
          size: 20,
          color: active ? activeText : const Color(0xFF5A6A8A),
        ),
        title: Text(
          label,
          style: TextStyle(
            color: active ? activeText : const Color(0xFF5A6A8A),
            fontSize: 13,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _RegistrationCard extends StatelessWidget {
  const _RegistrationCard({
    required this.registration,
    required this.isDark,
    required this.isCancelling,
    required this.onView,
    required this.onCancel,
  });

  final MyEventRegistration registration;
  final bool isDark;
  final bool isCancelling;
  final VoidCallback onView;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = registration.event;
    final publicEvent = registration.publicEvent;
    final isVirtual = event?.isVirtual ?? publicEvent?.isVirtual ?? false;
    final eventTitle = event?.title ?? publicEvent?.title ?? 'Registered Event';
    final start = event?.startDatetime ?? publicEvent?.startDatetime;
    final end = event?.endDatetime ?? publicEvent?.endDatetime;
    final location = event?.locationText ??
        publicEvent?.locationText ??
        (isVirtual ? 'Online event' : 'Venue to be announced');
    final open = publicEvent?.registrationStatus == 'open';

    return Card(
      elevation: 0,
      color: isDark ? const Color(0xFF131E30) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    eventTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _Tag(
                  label: registration.isActive ? 'Registered' : 'Cancelled',
                  bg: registration.isActive
                      ? const Color(0xFFDDEEFF)
                      : const Color(0xFFFFE9E9),
                  fg: registration.isActive
                      ? const Color(0xFF1B5C9B)
                      : const Color(0xFF8A1B1B),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _MetaRow(
              icon: Icons.calendar_today,
              label: start == null ? 'Date pending' : _formatDate(start),
            ),
            _MetaRow(
              icon: Icons.access_time,
              label: start == null ? 'Time pending' : _formatTime(start, end),
            ),
            _MetaRow(
              icon: isVirtual ? Icons.videocam : Icons.location_pin,
              label: location,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Tag(
                  label: isVirtual ? 'Virtual' : 'Physical',
                  bg: isVirtual
                      ? const Color(0xFFEDE6FF)
                      : const Color(0xFFDDE8FF),
                  fg: isVirtual
                      ? const Color(0xFF4A2DB0)
                      : const Color(0xFF1B3C8A),
                ),
                _Tag(
                  label: open ? 'Registration open' : 'Registration closed',
                  bg: open ? const Color(0xFFD9F4E8) : const Color(0xFFFFE9E9),
                  fg: open ? const Color(0xFF1B5C3A) : const Color(0xFF8A1B1B),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('View Details'),
                  ),
                ),
                if (onCancel != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: isCancelling ? null : onCancel,
                      icon: isCancelling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Cancel'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  static String _formatTime(DateTime start, DateTime? end) {
    String one(DateTime dt) {
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    }

    return end == null ? one(start) : '${one(start)} - ${one(end)}';
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFFC9952A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
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
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_available_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No registered events yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
