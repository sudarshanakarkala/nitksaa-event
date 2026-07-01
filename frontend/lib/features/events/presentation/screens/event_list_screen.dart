import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';
import '../../../auth/services/auth_controller.dart';
import '../providers/events_provider.dart';
import '../../domain/event.dart';

class EventListScreen extends ConsumerStatefulWidget {
  const EventListScreen({super.key});

  @override
  ConsumerState<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends ConsumerState<EventListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      ref.read(eventsProvider.notifier).setSearchQuery(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    if (isIOS) {
      return _buildCupertinoLayout();
    } else {
      return _buildMaterialLayout();
    }
  }

  Future<void> _handleAuthAction() async {
    final auth = ref.read(authControllerProvider);
    if (auth.isAuthenticated) {
      await auth.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logged out successfully.')),
        );
      }
    } else {
      context.push(AppRoutes.login);
    }
  }

  void _showFilterBottomSheet() {
    final isWebScreen = kIsWeb || MediaQuery.of(context).size.width > 900;
    if (isWebScreen) {
      // Open the scaffold end drawer for a standards-compliant side filter panel
      _scaffoldKey.currentState?.openEndDrawer();
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => _buildFilterPanel(),
      );
    }
  }

  void _showFilterDialog() {
    // Left for backward compatibility; prefer using the end-drawer via
    // `_showFilterBottomSheet` on large screens. Fallback to dialog for
    // contexts where a drawer isn't available.
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SizedBox(
            width: 500,
            child: _buildFilterPanel(),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPanel([WidgetRef? panelRef]) {
    final rf = panelRef ?? ref;
    final state = rf.watch(eventsProvider);
    final hasActiveFilters = state.dateRangeStart != null ||
      state.dateRangeEnd != null ||
      !((state.filterModes?['physical'] ?? true) && (state.filterModes?['virtual'] ?? true)) ||
      !((state.filterRegistrationStatus?['open'] ?? true) && (state.filterRegistrationStatus?['closed'] ?? true)) ||
      state.searchQuery.isNotEmpty;
    final isInDrawer = kIsWeb || MediaQuery.of(context).size.width > 900;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (with clear & close actions)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Filters',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  if (hasActiveFilters)
                    TextButton.icon(
                      onPressed: () {
                        rf.read(eventsProvider.notifier).clearFilters();
                        _searchController.clear();
                        if (isInDrawer) {
                          // keep drawer open so user can see cleared state
                        } else {
                          Navigator.pop(context);
                        }
                      },
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('Clear All'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.orange,
                      ),
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
          const SizedBox(height: 20),

          // Date Range Section
          const Text(
            'Date Range',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
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

          // Event Mode Section (checkbox style)
          const Text(
            'Event Mode',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Physical'),
            value: state.filterModes?['physical'] ?? true,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (val) {
              if (val == null) return;
              final current = state.filterModes?['physical'] ?? true;
              if (val != current) {
                rf.read(eventsProvider.notifier).toggleFilterMode('physical');
              }
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Virtual'),
            value: state.filterModes?['virtual'] ?? true,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (val) {
              if (val == null) return;
              final current = state.filterModes?['virtual'] ?? true;
              if (val != current) {
                rf.read(eventsProvider.notifier).toggleFilterMode('virtual');
              }
            },
          ),
          const SizedBox(height: 20),

          // Registration Status Section (checkbox style)
          const Text(
            'Registration Status',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Open'),
            value: state.filterRegistrationStatus?['open'] ?? true,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (val) {
              if (val == null) return;
              final current = state.filterRegistrationStatus?['open'] ?? true;
              if (val != current) {
                rf.read(eventsProvider.notifier).toggleFilterRegistrationStatus('open');
              }
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Closed'),
            value: state.filterRegistrationStatus?['closed'] ?? true,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (val) {
              if (val == null) return;
              final current = state.filterRegistrationStatus?['closed'] ?? true;
              if (val != current) {
                rf.read(eventsProvider.notifier).toggleFilterRegistrationStatus('closed');
              }
            },
          ),
          const SizedBox(height: 24),

          // Action Buttons
          if (MediaQuery.of(context).size.width <= 900)
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC9952A),
                    ),
                    child: const Text(
                      'Apply',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          // Drawer-only clear button removed — top 'Clear All' handles clearing.
        ],
      ),
    );
  }

  Widget _buildFilterToggle({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFC9952A) : Colors.transparent,
          border: Border.all(
            color: isActive
                ? const Color(0xFFC9952A)
                : Theme.of(context).colorScheme.outlineVariant,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : null,
            fontSize: 13,
          ),
        ),
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
  // CUPERTINO LAYOUT (iOS)
  // ==========================================
  Widget _buildCupertinoLayout() {
    final state = ref.watch(eventsProvider);
    final filteredEvents = ref.watch(filteredEventsProvider);
    final auth = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
    final textPrimary = isDark ? Colors.white : Colors.black;
    final textSecondary = isDark
        ? const Color(0xFFEBEBF5)
        : const Color(0xFF3C3C43);
    final accentGold = const Color(0xFFC9952A);

    return CupertinoPageScaffold(
      backgroundColor: bg,
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          'NITKSAA Events',
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          child: Icon(
            auth.isAuthenticated
                ? CupertinoIcons.square_arrow_right
                : CupertinoIcons.person_crop_circle,
            color: accentGold,
            size: 22,
          ),
          onPressed: _handleAuthAction,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: CupertinoSearchTextField(
                controller: _searchController,
                placeholder: 'Search events…',
                style: TextStyle(color: textPrimary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoSegmentedControl<String>(
                      groupValue: state.period,
                      selectedColor: isDark ? accentGold : const Color(0xFF007AFF),
                      unselectedColor: cardBg,
                      borderColor: isDark
                          ? accentGold.withValues(alpha: 0.5)
                          : const Color(0x3C3C430C),
                      children: const {
                        'upcoming': Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'Upcoming',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        'past': Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'Past',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      },
                      onValueChanged: (value) {
                        ref.read(eventsProvider.notifier).setPeriod(value);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(CupertinoIcons.slider_horizontal_3, color: accentGold, size: 18),
                          const SizedBox(width: 6),
                          const Text('Filters'),
                        ],
                      ),
                      onPressed: () {
                        showCupertinoModalPopup(
                          context: context,
                          builder: (context) => _buildCupertinoFilterPanel(
                            state,
                            accentGold,
                            isDark,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: state.isLoading
                  ? const Center(child: CupertinoActivityIndicator(radius: 12))
                  : state.errorMessage != null
                  ? _buildCupertinoErrorState(state.errorMessage!)
                  : filteredEvents.isEmpty
                  ? _buildCupertinoEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      itemCount: filteredEvents.length,
                      itemBuilder: (context, index) {
                        return _buildCupertinoEventCard(
                          filteredEvents[index],
                          cardBg,
                          textPrimary,
                          textSecondary,
                          accentGold,
                          isDark,
                        );
                      },
                    ),
            ),
            _buildCupertinoBottomNav(accentGold, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildCupertinoEventCard(
    AppEvent event,
    Color cardBg,
    Color textPrimary,
    Color textSecondary,
    Color accentGold,
    bool isDark,
  ) {
    final regStatusColor = event.registrationStatus == 'open'
        ? (isDark ? const Color(0xFF30D158) : const Color(0xFF34C759))
        : (isDark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30));

    final typeColor = event.isVirtual
        ? (isDark ? const Color(0xFFBF5AF2) : const Color(0xFF5856D6))
        : (isDark ? const Color(0xFF90B5FF) : const Color(0xFF007AFF));

    final capacityText = event.capacity != null
        ? '${event.registeredCount} / ${event.capacity}'
        : '${event.registeredCount} Registered';
    final progress = event.capacity != null && event.capacity! > 0
        ? (event.registeredCount / event.capacity!).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: textSecondary.withValues(alpha: 0.1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (event.bannerUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                event.bannerUrl!,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (event.thumbnailUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                event.thumbnailUrl!,
                height: 60,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  event.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  event.isVirtual ? 'Virtual' : 'Physical',
                  style: TextStyle(
                    color: typeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (event.tagline != null && event.tagline!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              event.tagline!,
              style: TextStyle(
                fontSize: 12,
                color: textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Metadata grid
          _buildCupertinoMetaRow(
            CupertinoIcons.calendar,
            _formatDate(event.startDatetime),
            textSecondary,
          ),
          _buildCupertinoMetaRow(
            CupertinoIcons.clock,
            _formatTime(event.startDatetime, event.endDatetime),
            textSecondary,
          ),
          _buildCupertinoMetaRow(
            event.isVirtual ? CupertinoIcons.videocam : CupertinoIcons.location,
            event.locationText ??
                (event.isVirtual ? 'Virtual Link' : 'To Be Decided'),
            textSecondary,
          ),
          const SizedBox(height: 12),
          // Capacity bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Capacity',
                style: TextStyle(fontSize: 11, color: textSecondary),
              ),
              Text(
                capacityText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2.5),
            child: SizedBox(
              height: 5,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFE5E5EA),
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress > 0.8 ? Colors.orange : Colors.green,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: regStatusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  event.registrationStatus == 'open'
                      ? 'Registration open'
                      : 'Closed',
                  style: TextStyle(
                    color: regStatusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: isDark ? accentGold : const Color(0xFF007AFF),
                borderRadius: BorderRadius.circular(8),
                minimumSize: Size.zero,
                child: Text(
                  'View details',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.black : Colors.white,
                  ),
                ),
                onPressed: () {
                  context.push('/events/${event.eventId}');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCupertinoMetaRow(IconData icon, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFFC9952A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCupertinoBottomNav(Color accentGold, bool isDark) {
    final navBg = isDark ? const Color(0xFF161617) : const Color(0xFFF9F9F9);
    final inactiveColor = const Color(0xFF8E8E93);

    return Container(
      decoration: BoxDecoration(
        color: navBg,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        children: [
          _buildCupertinoNavItem(
            CupertinoIcons.calendar,
            'Events',
            true,
            accentGold,
            inactiveColor,
          ),
          _buildCupertinoNavItem(
            CupertinoIcons.bookmark,
            'My Events',
            false,
            accentGold,
            inactiveColor,
          ),
          _buildCupertinoNavItem(
            CupertinoIcons.shield,
            'Volunteer',
            false,
            accentGold,
            inactiveColor,
          ),
          _buildCupertinoNavItem(
            CupertinoIcons.person_circle,
            'Manage',
            false,
            accentGold,
            inactiveColor,
          ),
          _buildCupertinoNavItem(
            CupertinoIcons.ellipsis,
            'More',
            false,
            accentGold,
            inactiveColor,
          ),
        ],
      ),
    );
  }

  Widget _buildCupertinoNavItem(
    IconData icon,
    String label,
    bool active,
    Color activeColor,
    Color inactiveColor,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (label == 'Manage') {
            context.go(AppRoutes.manageEvents);
            return;
          }
          if (!active) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('$label tab coming soon.')));
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: active ? activeColor : inactiveColor),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: active ? activeColor : inactiveColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCupertinoErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 42,
              color: CupertinoColors.systemRed,
            ),
            const SizedBox(height: 12),
            Text(
              'Error Loading Events',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: CupertinoColors.systemGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCupertinoEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.calendar_badge_minus,
            size: 48,
            color: CupertinoColors.systemGrey,
          ),
          const SizedBox(height: 12),
          Text(
            'No Events Found',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Try searching for something else.',
            style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
          ),
        ],
      ),
    );
  }

  Widget _buildCupertinoFilterPanel(
    EventsState state,
    Color accentGold,
    bool isDark,
  ) {
    final hasActiveFilters = state.dateRangeStart != null ||
      state.dateRangeEnd != null ||
      !((state.filterModes['physical'] ?? true) && (state.filterModes['virtual'] ?? true)) ||
      !((state.filterRegistrationStatus['open'] ?? true) && (state.filterRegistrationStatus['closed'] ?? true)) ||
      state.searchQuery.isNotEmpty;

    return CupertinoActionSheetAction(
      onPressed: () {},
      child: Container(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Filters',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: const Icon(CupertinoIcons.xmark, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Clear All Button
                  if (hasActiveFilters)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: Row(
                          children: [
                            Icon(CupertinoIcons.clear_thick, size: 16, color: accentGold),
                            const SizedBox(width: 6),
                            const Text('Clear All Filters'),
                          ],
                        ),
                        onPressed: () {
                          ref.read(eventsProvider.notifier).clearFilters();
                          _searchController.clear();
                          Navigator.pop(context);
                        },
                      ),
                    ),

                  // Date Range Section
                  const Padding(
                    padding: EdgeInsets.only(top: 12.0, bottom: 8.0),
                    child: Text(
                      'Date Range',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: state.dateRangeStart ?? DateTime.now(),
                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              ref.read(eventsProvider.notifier).setDateRangeStart(picked);
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFD0D0D0)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              state.dateRangeStart == null
                                  ? 'From'
                                  : '${state.dateRangeStart!.day}/${state.dateRangeStart!.month}',
                              style: const TextStyle(fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: state.dateRangeEnd ?? DateTime.now(),
                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              ref.read(eventsProvider.notifier).setDateRangeEnd(picked);
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFD0D0D0)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              state.dateRangeEnd == null
                                  ? 'To'
                                  : '${state.dateRangeEnd!.day}/${state.dateRangeEnd!.month}',
                              style: const TextStyle(fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      if (state.dateRangeStart != null || state.dateRangeEnd != null)
                        CupertinoButton(
                          padding: const EdgeInsets.all(6),
                          child: const Icon(CupertinoIcons.xmark_circle_fill, size: 18),
                          onPressed: () {
                            ref.read(eventsProvider.notifier).setDateRangeStart(null);
                            ref.read(eventsProvider.notifier).setDateRangeEnd(null);
                          },
                        ),
                    ],
                  ),

                  // Event Mode Section
                  const Padding(
                    padding: EdgeInsets.only(top: 16.0, bottom: 8.0),
                    child: Text(
                      'Event Mode',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Physical'),
                          CupertinoSwitch(
                            value: state.filterModes['physical'] ?? true,
                            onChanged: (val) {
                              final current = state.filterModes['physical'] ?? true;
                              if (val != current) {
                                ref.read(eventsProvider.notifier).toggleFilterMode('physical');
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Virtual'),
                          CupertinoSwitch(
                            value: state.filterModes['virtual'] ?? true,
                            onChanged: (val) {
                              final current = state.filterModes['virtual'] ?? true;
                              if (val != current) {
                                ref.read(eventsProvider.notifier).toggleFilterMode('virtual');
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Registration Status Section
                  const Padding(
                    padding: EdgeInsets.only(top: 16.0, bottom: 8.0),
                    child: Text(
                      'Registration',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Open'),
                          CupertinoSwitch(
                            value: state.filterRegistrationStatus['open'] ?? true,
                            onChanged: (val) {
                              final current = state.filterRegistrationStatus['open'] ?? true;
                              if (val != current) {
                                ref.read(eventsProvider.notifier).toggleFilterRegistrationStatus('open');
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Closed'),
                          CupertinoSwitch(
                            value: state.filterRegistrationStatus['closed'] ?? true,
                            onChanged: (val) {
                              final current = state.filterRegistrationStatus['closed'] ?? true;
                              if (val != current) {
                                ref.read(eventsProvider.notifier).toggleFilterRegistrationStatus('closed');
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Done Button
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      color: accentGold,
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCupertinoFilterToggle({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFC9952A) : Colors.transparent,
          border: Border.all(
            color: isActive
                ? const Color(0xFFC9952A)
                : const Color(0xFFD0D0D0),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: isActive ? Colors.white : Colors.black,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // ==========================================
  // MATERIAL LAYOUT (WEB / ANDROID)
  // ==========================================
  Widget _buildMaterialLayout() {
    final state = ref.watch(eventsProvider);
    final filteredEvents = ref.watch(filteredEventsProvider);
    final auth = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    // Web styling rules
    final isWebScreen = kIsWeb || MediaQuery.of(context).size.width > 900;

    final sidebar = isWebScreen
        ? Container(
            width: 240,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0E1726) : const Color(0xFFF8F9FD),
              border: Border(
                right: BorderSide(
                  color: colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
            ),
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      color: Color(0xFFC9952A),
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'NITKSAA',
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? const Color(0xFFC9952A)
                            : colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                _buildSidebarItem(Icons.calendar_month, 'Events', true, isDark),
                _buildSidebarItem(
                  Icons.bookmark_border,
                  'My Events',
                  false,
                  isDark,
                ),
                _buildSidebarItem(
                  Icons.verified_user_outlined,
                  'Volunteer',
                  false,
                  isDark,
                ),
                _buildSidebarItem(
                  Icons.admin_panel_settings_outlined,
                  'Manage Events',
                  false,
                  isDark,
                ),
                _buildSidebarItem(Icons.more_horiz, 'More', false, isDark),
                const Spacer(),
                if (auth.isAuthenticated) ...[
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFFC9952A),
                        radius: 18,
                        child: Text(
                          (auth.session?.fullname ?? 'U')
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              auth.session?.fullname ?? 'Alumni User',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              auth.session?.userType ?? 'Member',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark
                          ? const Color(0xFFC9952A)
                          : const Color(0xFF0D1B3E),
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: Icon(
                      auth.isAuthenticated ? Icons.logout : Icons.login,
                    ),
                    label: Text(auth.isAuthenticated ? 'Log Out' : 'Log In'),
                    onPressed: _handleAuthAction,
                  ),
                ),
              ],
            ),
          )
        : null;

    final bodyContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Web / Mobile Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'NITKSAA Events',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (isWebScreen)
                Row(
                  children: [
                    SizedBox(
                      width: 250,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Search events…',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant.withOpacity(0.5),
                            ),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF1A2A3A).withOpacity(0.5)
                              : Colors.grey.withOpacity(0.1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Filters'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: colorScheme.outlineVariant,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _showFilterBottomSheet,
                    ),
                  ],
                )
              else if (!isWebScreen)
                IconButton(
                  icon: Icon(
                    auth.isAuthenticated
                        ? Icons.logout_outlined
                        : Icons.login_outlined,
                  ),
                  onPressed: _handleAuthAction,
                ),
            ],
          ),
        ),

        // Tabs Row (for web only below header)
        if (isWebScreen)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: TabBar(
              isScrollable: false,
              labelColor: isDark ? const Color(0xFFC9952A) : colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              indicatorColor: const Color(0xFFC9952A),
              indicatorWeight: 3,
              tabs: const [
                Tab(text: 'Upcoming'),
                Tab(text: 'Past'),
              ],
              onTap: (index) {
                ref
                    .read(eventsProvider.notifier)
                    .setPeriod(index == 0 ? 'upcoming' : 'past');
              },
            ),
          ),

        // Mobile Search + Tab Row
        if (!isWebScreen)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final searchWidget = SizedBox(
                  width: double.infinity,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search events…',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                );

                final filterTabs = TabBar(
                  isScrollable: true,
                  labelColor: isDark
                      ? const Color(0xFFC9952A)
                      : colorScheme.primary,
                  unselectedLabelColor: colorScheme.onSurfaceVariant,
                  indicatorColor: const Color(0xFFC9952A),
                  tabs: const [
                    Tab(text: 'Upcoming'),
                    Tab(text: 'Past'),
                  ],
                  onTap: (index) {
                    ref
                        .read(eventsProvider.notifier)
                        .setPeriod(index == 0 ? 'upcoming' : 'past');
                  },
                );

                return Column(
                  children: [
                    searchWidget,
                    const SizedBox(height: 8),
                    filterTabs,
                  ],
                );
              },
            ),
          ),

        const SizedBox(height: 16),

        // List Grid area
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : state.errorMessage != null
                ? _buildMaterialErrorState(state.errorMessage!)
                : filteredEvents.isEmpty
                ? _buildMaterialEmptyState()
                : GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isWebScreen ? 2 : 1,
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                      mainAxisExtent: 420,
                    ),
                    itemCount: filteredEvents.length,
                    itemBuilder: (context, index) {
                      return _buildMaterialEventCard(
                        filteredEvents[index],
                        isDark,
                        theme,
                      );
                    },
                  ),
          ),
        ),
      ],
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        key: _scaffoldKey,
        endDrawer: isWebScreen
            ? Drawer(
                child: Consumer(
                  builder: (context, drawerRef, _) => SafeArea(
                    child: Container(
                      width: 420,
                      padding: const EdgeInsets.all(20.0),
                      child: _buildFilterPanel(drawerRef),
                    ),
                  ),
                ),
              )
            : null,
        drawer: (!isWebScreen && auth.isAuthenticated)
            ? Drawer(
                child: ListView(
                  children: [
                    UserAccountsDrawerHeader(
                      decoration: const BoxDecoration(color: Color(0xFF0D1B3E)),
                      currentAccountPicture: CircleAvatar(
                        backgroundColor: const Color(0xFFC9952A),
                        child: Text(
                          (auth.session?.fullname ?? 'U')
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                          ),
                        ),
                      ),
                      accountName: Text(
                        auth.session?.fullname ?? 'Alumni User',
                      ),
                      accountEmail: Text(auth.session?.email ?? ''),
                    ),
                    ListTile(
                      leading: const Icon(Icons.calendar_month),
                      title: const Text('Events'),
                      selected: true,
                      onTap: () => Navigator.pop(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.bookmark_border),
                      title: const Text('My Events'),
                      onTap: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('My Events coming soon.'),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text('Volunteer'),
                      onTap: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Volunteer options coming soon.'),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: const Text('Manage Events'),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(AppRoutes.manageEvents);
                      },
                    ),
                  ],
                ),
              )
            : null,
        body: SafeArea(
          child: Row(
            children: [
              if (sidebar != null) sidebar,
              Expanded(child: bodyContent),
            ],
          ),
        ),
        bottomNavigationBar: (!isWebScreen && !auth.isAuthenticated)
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                color: isDark ? const Color(0xFF14171C) : Colors.white,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC9952A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _handleAuthAction,
                  child: const Text(
                    'Log In to Access Premium Features',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildSidebarItem(
    IconData icon,
    String label,
    bool active,
    bool isDark,
  ) {
    final activeBg = isDark ? const Color(0xFF1C2A40) : const Color(0xFFEEF3FA);
    final activeText = isDark ? Colors.white : const Color(0xFF0D1B3E);
    return Container(
      margin: const EdgeInsets.only(bottom: 6.0),
      decoration: BoxDecoration(
        color: active ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        visualDensity: VisualDensity.compact,
        leading: Icon(
          icon,
          color: active ? activeText : const Color(0xFF5A6A8A),
          size: 20,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: active ? activeText : const Color(0xFF5A6A8A),
            fontSize: 13,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        onTap: () {
          if (active) return;
          if (label == 'My Events') {
            context.go(AppRoutes.myEvents);
            return;
          }
          if (label == 'Manage Events') {
            context.go(AppRoutes.manageEvents);
            return;
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$label coming soon.')));
        },
      ),
    );
  }

  Widget _buildMaterialEventCard(AppEvent event, bool isDark, ThemeData theme) {
    final isPhysical = !event.isVirtual;
    final tagBg = isPhysical
        ? (isDark ? const Color(0xFF1E2E50) : const Color(0xFFDDE8FF))
        : (isDark ? const Color(0xFF1E1540) : const Color(0xFFEDE6FF));
    final tagText = isPhysical
        ? (isDark ? const Color(0xFF90B5FF) : const Color(0xFF1B3C8A))
        : (isDark ? const Color(0xFFB89AFF) : const Color(0xFF4A2DB0));

    final regBg = event.registrationStatus == 'open'
        ? (isDark ? const Color(0xFF0F2920) : const Color(0xFFD9F4E8))
        : (isDark ? const Color(0xFF2E1010) : const Color(0xFFFFE9E9));
    final regText = event.registrationStatus == 'open'
        ? (isDark ? const Color(0xFF6FDBA8) : const Color(0xFF1B5C3A))
        : (isDark ? const Color(0xFFFF9090) : const Color(0xFF8A1B1B));

    final capacityText = event.capacity != null
        ? '${event.registeredCount} / ${event.capacity}'
        : '${event.registeredCount} Registered';
    final progress = event.capacity != null && event.capacity! > 0
        ? (event.registeredCount / event.capacity!).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      color: isDark ? const Color(0xFF131E30) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (event.thumbnailUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  event.thumbnailUrl!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: tagBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isPhysical ? 'Physical' : 'Virtual',
                    style: TextStyle(
                      color: tagText,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (event.tagline != null && event.tagline!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                event.tagline!,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMaterialMetaRow(
                          Icons.calendar_today,
                          _formatDate(event.startDatetime),
                          theme,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMaterialMetaRow(
                          Icons.access_time,
                          _formatTime(event.startDatetime, event.endDatetime),
                          theme,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _buildMaterialMetaRow(
                    event.isVirtual ? Icons.videocam : Icons.location_pin,
                    event.locationText ??
                        (event.isVirtual ? 'Zoom Link' : 'TBD'),
                    theme,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Capacity',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
                Text(
                  capacityText,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: isDark
                    ? const Color(0xFF1C2A40)
                    : const Color(0xFFEEF3FA),
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress > 0.85 ? Colors.orange : Colors.green,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: regBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    event.registrationStatus == 'open'
                        ? 'Registration open'
                        : 'Closed',
                    style: TextStyle(
                      color: regText,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: isDark
                        ? const Color(0xFFC9952A)
                        : const Color(0xFF0D1B3E),
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    context.push('/events/${event.eventId}');
                  },
                  child: const Text(
                    'View details',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialMetaRow(IconData icon, String label, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFFC9952A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text(
              'Something went wrong',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'No Events Found',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            'Please check back later or try adjusting filters.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // HELPER DATE & TIME FORMATTERS
  // ==========================================
  String _formatDate(DateTime dt) {
    final months = [
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

  String _formatTime(DateTime start, DateTime? end) {
    String formatSingle(DateTime dt) {
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute $period';
    }

    if (end == null) {
      return formatSingle(start);
    }
    return '${formatSingle(start)} – ${formatSingle(end)}';
  }
}
