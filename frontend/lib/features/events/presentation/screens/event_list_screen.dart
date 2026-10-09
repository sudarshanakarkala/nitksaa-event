import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';
import '../../../../theme/app_palette.dart';
import '../../../../theme/app_text_styles.dart';
import '../../../../shared/widgets/list_page.dart';
import '../../../../shared/widgets/segment_toggle.dart';
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

  // Cards / Table view (website ViewToggle) and table sort.
  String _view = 'cards';
  int _sortColumn = 1; // Date
  bool _sortAsc = true;

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
    final isWebScreen = MediaQuery.of(context).size.width >= 900;
    if (isWebScreen) {
      // Open the scaffold end drawer for a standards-compliant side filter panel
      _scaffoldKey.currentState?.openEndDrawer();
    } else {
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

  /// Filter section label, website `.filter-label`: small uppercase, 70% gold.
  Widget _filterLabel(String text) => Text(
        text.toUpperCase(),
        style: AppTextStyles.eyebrow.copyWith(
          fontSize: 11.5,
          letterSpacing: 0.9,
          color: context.palette.primary.withValues(alpha: 0.7),
        ),
      );

  /// Website `.chip` toggle: faint pill, gold-tinted when on. Calls
  /// [onChanged] with the new value, like the checkbox it replaces.
  Widget _filterChip(String label, bool value, ValueChanged<bool?> onChanged) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: value ? p.primary.withValues(alpha: 0.14) : p.surfaceSubtle,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: p.primary.withValues(alpha: value ? 0.5 : 0.14),
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            fontSize: 12.8,
            height: 1.2,
            color: value ? p.primary : p.textSecondary,
            fontWeight: value ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  /// Active filters, for the rail badge (search is not counted).
  int _activeFilterCount(EventsState s) => [
        s.period == 'past',
        s.dateRangeStart != null || s.dateRangeEnd != null,
        s.timeline != null,
        !((s.filterModes['physical'] ?? true) && (s.filterModes['virtual'] ?? true)),
        !((s.filterRegistrationStatus['open'] ?? true) &&
            (s.filterRegistrationStatus['closed'] ?? true)),
      ].where((active) => active).length;

  Widget _buildFilterPanel([WidgetRef? panelRef, bool inRail = false]) {
    final rf = panelRef ?? ref;
    final state = rf.watch(eventsProvider);
    final hasActiveFilters = state.dateRangeStart != null ||
      state.dateRangeEnd != null ||
      !((state.filterModes?['physical'] ?? true) && (state.filterModes?['virtual'] ?? true)) ||
      !((state.filterRegistrationStatus?['open'] ?? true) && (state.filterRegistrationStatus?['closed'] ?? true)) ||
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
          _filterLabel('When'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final period in const ['upcoming', 'past'])
              _filterChip(
                period == 'upcoming' ? 'Upcoming' : 'Past',
                state.period == period,
                (_) => rf.read(eventsProvider.notifier).setPeriod(period),
              ),
          ]),
          const SizedBox(height: 20),

          // Date Range Section
          _filterLabel('Date Range'),
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
          _filterLabel('Timeline'),
          const SizedBox(height: 8),
          _buildTimelineDropdown(rf, state, isInDrawer),
          const SizedBox(height: 20),

          // Event Mode Section (website chips)
          _filterLabel('Event Mode'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
          _filterChip(
            'Physical',
            state.filterModes?['physical'] ?? true,
            (val) {
              if (val == null) return;
              final current = state.filterModes?['physical'] ?? true;
              if (val != current) {
                rf.read(eventsProvider.notifier).toggleFilterMode('physical');
              }
            },
          ),
          _filterChip(
            'Virtual',
            state.filterModes?['virtual'] ?? true,
            (val) {
              if (val == null) return;
              final current = state.filterModes?['virtual'] ?? true;
              if (val != current) {
                rf.read(eventsProvider.notifier).toggleFilterMode('virtual');
              }
            },
          ),
          ]),
          const SizedBox(height: 20),

          // Registration Status Section (website chips)
          _filterLabel('Registration Status'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
          _filterChip(
            'Open',
            state.filterRegistrationStatus?['open'] ?? true,
            (val) {
              if (val == null) return;
              final current = state.filterRegistrationStatus?['open'] ?? true;
              if (val != current) {
                rf.read(eventsProvider.notifier).toggleFilterRegistrationStatus('open');
              }
            },
          ),
          _filterChip(
            'Closed',
            state.filterRegistrationStatus?['closed'] ?? true,
            (val) {
              if (val == null) return;
              final current = state.filterRegistrationStatus?['closed'] ?? true;
              if (val != current) {
                rf.read(eventsProvider.notifier).toggleFilterRegistrationStatus('closed');
              }
            },
          ),
          ]),
          const SizedBox(height: 24),

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
          color: isActive ? context.palette.primary : Colors.transparent,
          border: Border.all(
            color: isActive
                ? context.palette.primary
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
            color: isActive ? context.palette.onPrimary : null,
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

    final bg = context.palette.background;
    final cardBg = context.palette.card;
    final textPrimary = context.palette.textPrimary;
    final textSecondary = context.palette.textSecondary;
    final accentGold = context.palette.primary;

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
                      selectedColor: accentGold,
                      unselectedColor: cardBg,
                      borderColor: context.palette.border,
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
                        final isAdmin = auth.session?.userType.toLowerCase() == 'admin';
                        return _buildCupertinoEventCard(
                          filteredEvents[index],
                          cardBg,
                          textPrimary,
                          textSecondary,
                          accentGold,
                          isDark,
                          isAdmin: isAdmin,
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
    {required bool isAdmin}
  ) {
    final regStatusColor = event.registrationStatus == 'open'
        ? context.palette.success
        : context.palette.error;

    final typeColor = event.isVirtual
        ? context.palette.info
        : context.palette.primary;

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
        border: Border.all(color: context.palette.border),
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
                  border: Border.all(color: typeColor.withValues(alpha: 0.3)),
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
          if (isAdmin) ...[
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
                  backgroundColor: context.palette.surfaceHover,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress > 0.8 ? context.palette.warning : context.palette.success,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: regStatusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: regStatusColor.withValues(alpha: 0.3)),
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
                color: accentGold,
                borderRadius: BorderRadius.circular(8),
                minimumSize: Size.zero,
                child: Text(
                  'View details',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.palette.onPrimary,
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
          Icon(icon, size: 14, color: context.palette.primary),
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
    final navBg = context.palette.background;
    final inactiveColor = context.palette.textMuted;

    return Container(
      decoration: BoxDecoration(
        color: navBg,
        border: Border(
          top: BorderSide(
            color: context.palette.border,
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
            CupertinoIcons.person_circle,
            'Manage',
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
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 42,
              color: context.palette.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Error Loading Events',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCupertinoEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.calendar_badge_minus,
            size: 48,
            color: context.palette.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            'No Events Found',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Try searching for something else.',
            style: TextStyle(fontSize: 13, color: context.palette.textMuted),
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
      state.searchQuery.isNotEmpty ||
      state.timeline != null;

    return CupertinoActionSheetAction(
      onPressed: () {},
      child: Container(
        color: context.palette.surface,
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
                        style: TextStyle(fontFamily: AppTextStyles.serif, fontSize: 18, fontWeight: FontWeight.w600),
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

                  // Timeline Section
                  const Padding(
                    padding: EdgeInsets.only(top: 12.0, bottom: 8.0),
                    child: Text(
                      'Timeline',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  _buildCupertinoTimelineDropdown(state, accentGold, isDark),
                  const SizedBox(height: 12),

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
                              border: Border.all(color: context.palette.border),
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
                              border: Border.all(color: context.palette.border),
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
          color: isActive ? context.palette.primary : Colors.transparent,
          border: Border.all(
            color: isActive
                ? context.palette.primary
                : context.palette.border,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: isActive ? context.palette.onPrimary : context.palette.textPrimary,
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
    final p = context.palette;
    final side = ListPage.sidePadding(context);

    // Website page frame: filter rail, toolbar, then the card grid.
    return Scaffold(
      key: _scaffoldKey,
      body: ListPage(
        title: 'Events',
        subtitle: 'Reunions, talks and meetups of the NITK Surathkal Alumni Association.',
        search: SizedBox(
          height: 44,
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Search events…',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
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
            : Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${filteredEvents.length}',
                      style: TextStyle(color: p.primary, fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: filteredEvents.length == 1 ? ' event' : ' events'),
                  ],
                ),
                style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary),
              ),
        filters: (context) => _buildFilterPanel(ref, true),
        onOpenFilters: _showFilterBottomSheet,
        activeFilterCount: _activeFilterCount(state),
        onClearFilters: () {
          ref.read(eventsProvider.notifier).clearFilters();
          ref.read(eventsProvider.notifier).setPeriod('upcoming');
          _searchController.clear();
        },
        resultNote: state.isLoading
            ? null
            : '${filteredEvents.length} ${filteredEvents.length == 1 ? 'event' : 'events'}',
        body: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : state.errorMessage != null
            ? _buildMaterialErrorState(state.errorMessage!)
            : filteredEvents.isEmpty
            ? _buildMaterialEmptyState()
            : _view == 'table' && MediaQuery.sizeOf(context).width >= 600
            ? _buildEventTable(filteredEvents, side)
            : LayoutBuilder(
                builder: (context, constraints) {
                  // As many ~320px columns as fit, up to four (website grid).
                  const spacing = 20.0;
                  final usable = constraints.maxWidth - side * 2;
                  final columns =
                      ((usable + spacing) / (320 + spacing)).floor().clamp(1, 4);
                  // Rows of cards, each row as tall as its tallest card, so
                  // cards size to their content (website grid) instead of a
                  // fixed 420px cell.
                  final rows = (filteredEvents.length / columns).ceil();
                  final isAdmin = auth.session?.userType.toLowerCase() == 'admin';
                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(side, 24, side, 24),
                    itemCount: rows,
                    separatorBuilder: (_, _) => const SizedBox(height: spacing),
                    itemBuilder: (context, row) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var col = 0; col < columns; col++) ...[
                              if (col > 0) const SizedBox(width: spacing),
                              Expanded(
                                child: row * columns + col < filteredEvents.length
                                    ? _buildMaterialEventCard(
                                        filteredEvents[row * columns + col],
                                        isDark,
                                        theme,
                                        isAdmin: isAdmin,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
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
  Widget _buildEventTable(List<AppEvent> events, double side) {
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
        padding: EdgeInsets.fromLTRB(side, 24, side, 24),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth - side * 2),
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
                        DataCell(Text(_formatDate(event.startDatetime), style: cellStyle)),
                        DataCell(Text(
                          _formatTime(event.startDatetime, event.endDatetime),
                          style: cellStyle,
                        )),
                        DataCell(Text(event.isVirtual ? 'Virtual' : 'Physical', style: cellStyle)),
                        DataCell(Text(
                          event.locationText ?? (event.isVirtual ? 'Online' : 'TBD'),
                          style: cellStyle,
                          overflow: TextOverflow.ellipsis,
                        )),
                        DataCell(Text(
                          event.registrationStatus == 'open' ? 'Open' : 'Closed',
                          style: cellStyle.copyWith(
                            color: event.registrationStatus == 'open' ? p.success : p.error,
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

  Widget _buildMaterialEventCard(AppEvent event, bool isDark, ThemeData theme, {required bool isAdmin}) {
    final isPhysical = !event.isVirtual;
    final tagBg = isPhysical
        ? context.palette.primary.withValues(alpha: 0.14)
        : context.palette.info.withValues(alpha: 0.14);
    final tagText = isPhysical
        ? context.palette.primary
        : context.palette.info;

    final regBg = event.registrationStatus == 'open'
        ? context.palette.success.withValues(alpha: 0.14)
        : context.palette.error.withValues(alpha: 0.14);
    final regText = event.registrationStatus == 'open'
        ? context.palette.success
        : context.palette.error;

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
          color: context.palette.border,
        ),
      ),
      color: context.palette.card,
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
                    border: Border.all(color: tagText.withValues(alpha: 0.3)),
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
            // Details at their natural height; the Spacer below keeps the
            // footer aligned across a row of cards (rows size to the tallest).
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
            const Spacer(),
            if (isAdmin) ...[
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
                  backgroundColor: context.palette.surfaceHover,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress > 0.85 ? context.palette.warning : context.palette.success,
                  ),
                ),
              ),
            ],
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
                    border: Border.all(color: regText.withValues(alpha: 0.3)),
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
                    backgroundColor: context.palette.primary,
                    foregroundColor: context.palette.onPrimary,
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
          Icon(icon, size: 16, color: context.palette.primary),
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
            Icon(Icons.error_outline, size: 48, color: context.palette.error),
            const SizedBox(height: 12),
            const Text(
              'Something went wrong',
              style: TextStyle(fontFamily: AppTextStyles.serif, fontWeight: FontWeight.w600, fontSize: 18),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today_outlined, size: 64, color: context.palette.textMuted),
          const SizedBox(height: 16),
          Text(
            'No Events Found',
            style: TextStyle(fontFamily: AppTextStyles.serif, fontWeight: FontWeight.w600, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            'Please check back later or try adjusting filters.',
            style: TextStyle(color: context.palette.textMuted),
          ),
        ],
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

  Widget _buildCupertinoTimelineDropdown(
    EventsState state,
    Color accentGold,
    bool isDark,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: context.palette.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: state.timeline,
          isExpanded: true,
          dropdownColor: context.palette.surface,
          hint: Text(
            'Select timeline',
            style: TextStyle(
              color: context.palette.textSecondary,
            ),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'None',
                style: TextStyle(
                  color: context.palette.textSecondary,
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
            ref.read(eventsProvider.notifier).setTimeline(value);
          },
        ),
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
