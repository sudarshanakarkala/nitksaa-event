
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../../../../routes/app_routes.dart';
import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/event.dart';
import '../../presentation/providers/events_provider.dart';
import '../../../../shared/widgets/app_sidebar.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';

class ManageEventsScreen extends ConsumerStatefulWidget {
  const ManageEventsScreen({super.key});

  @override
  ConsumerState<ManageEventsScreen> createState() => _ManageEventsScreenState();
}

class _ManageEventsScreenState extends ConsumerState<ManageEventsScreen> with TickerProviderStateMixin {
  var _events = <AppEvent>[];
  var _isLoading = false;
  String? _errorMessage;
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  bool get _isAdmin {
    final userType = ref.read(authControllerProvider).session?.userType;
    return userType?.toLowerCase() == 'admin';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      setState(() {}); // Trigger rebuild when search text changes
    });
    Future.microtask(_fetchEvents);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<AppEvent> get _filteredEvents {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) return _events;
    return _events.where((e) {
      final title = e.title.toLowerCase();
      final description = e.description?.toLowerCase() ?? '';
      final tagline = e.tagline?.toLowerCase() ?? '';
      final location = e.locationText?.toLowerCase() ?? '';
      return title.contains(query) || description.contains(query) || tagline.contains(query) || location.contains(query);
    }).toList();
  }

  List<AppEvent> get _publishedEvents => _filteredEvents
      .where((e) => e.status.toLowerCase() == 'published' && _isUpcoming(e))
      .toList();
  
  List<AppEvent> get _draftEvents => _filteredEvents
      .where((e) => e.status.toLowerCase() == 'draft' && _isUpcoming(e))
      .toList();

  bool _isUpcoming(AppEvent event) {
    return event.startDatetime.isAfter(DateTime.now());
  }

  Future<void> _fetchEvents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final auth = ref.read(authControllerProvider);
      final accessToken = auth.session?.accessToken;
      
      if (accessToken == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Not authenticated';
        });
        return;
      }
      
      final data = await ref.read(eventsRepositoryProvider).getAdminEvents(
            page: 1,
            perPage: 100,
            period: 'upcoming',
            accessToken: accessToken,
          );
      final rawEvents = data['events'] as List<dynamic>? ?? [];
      setState(() {
        _events = rawEvents
            .map((json) => AppEvent.fromJson(json as Map<String, dynamic>))
            .toList();
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _publishEvent(AppEvent event) async {
    try {
      final auth = ref.read(authControllerProvider);
      final repo = ref.read(eventsRepositoryProvider);
      
      if (!mounted) return;
      
      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Publishing event...'),
          duration: Duration(seconds: 1),
        ),
      );
      
      // Call API to update event status to published using dedicated status endpoint
      await repo.updateEventStatus(
        event.eventId,
        'published',
        auth.session!.accessToken,
      );
      
      // Refresh events to show updated status
      await _fetchEvents();
      
      // Also refresh the public events list so EventListScreen shows updated data
      if (mounted) {
        ref.read(eventsProvider.notifier).fetchEvents(isRefresh: true);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${event.title} published successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error publishing event: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _unpublishEvent(AppEvent event) async {
    try {
      final auth = ref.read(authControllerProvider);
      final repo = ref.read(eventsRepositoryProvider);
      
      if (!mounted) return;
      
      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unpublishing event...'),
          duration: Duration(seconds: 1),
        ),
      );
      
      // Call API to update event status to draft
      await repo.updateEventStatus(
        event.eventId,
        'draft',
        auth.session!.accessToken,
      );
      
      // Refresh events to show updated status
      await _fetchEvents();
      
      // Also refresh the public events list so EventListScreen shows updated data
      if (mounted) {
        ref.read(eventsProvider.notifier).fetchEvents(isRefresh: true);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${event.title} unpublished successfully'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error unpublishing event: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteEvent(AppEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text('Are you sure you want to delete "${event.title}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      final auth = ref.read(authControllerProvider);
      final repo = ref.read(eventsRepositoryProvider);
      
      if (!mounted) return;
      
      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deleting event...'),
          duration: Duration(seconds: 1),
        ),
      );
      
      // Call API to delete event
      await repo.deleteAdminEvent(
        event.eventId,
        auth.session!.accessToken,
      );
      
      // Refresh events to show updated status
      await _fetchEvents();
      
      // Also refresh the public events list so EventListScreen shows updated data
      if (mounted) {
        ref.read(eventsProvider.notifier).fetchEvents(isRefresh: true);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${event.title} deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting event: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isWebScreen = MediaQuery.of(context).size.width >= 900;
    final isAdmin = auth.session?.userType.toLowerCase() == 'admin';

    if (!auth.isAuthenticated || !isAdmin) {
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
                    const Icon(Icons.admin_panel_settings_outlined, size: 56),
                    const SizedBox(height: 16),
                    const Text(
                      'Admin access required',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Manage Events is available only for admin users.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => context.go(AppRoutes.home),
                      child: const Text('Back to Events'),
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
            if (isWebScreen) const AppSidebar(),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isWebScreen ? 32 : 20,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 12,
                      children: [
                        const Text(
                          'Manage Events',
                          style: TextStyle(
                            fontFamily: 'Fraunces',
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            IconButton.filledTonal(
                              tooltip: 'Refresh',
                              onPressed: _isLoading ? null : _fetchEvents,
                              icon: const Icon(Icons.refresh),
                            ),
                            FilledButton.icon(
                              onPressed: () => _showEventForm(),
                              icon: const Icon(Icons.add),
                              label: const Text('Create Event'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Search box
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search events...',
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
                    // Tab Bar
                    TabBar(
                      controller: _tabController,
                      labelColor: isDark ? const Color(0xFFC9952A) : const Color(0xFF0D1B3E),
                      unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                      indicatorColor: const Color(0xFFC9952A),
                      indicatorWeight: 3,
                      tabs: [
                        Tab(
                          text: 'Published (${_publishedEvents.length})',
                        ),
                        Tab(
                          text: 'Draft (${_draftEvents.length})',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // Published Tab
                          _buildEventsList(_publishedEvents, isDark, theme, isPublished: true),
                          // Draft Tab
                          _buildEventsList(_draftEvents, isDark, theme, isPublished: false),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }

  Future<void> _showEventForm({AppEvent? event}) async {
    if (!_isAdmin) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _EventFormDialog(event: event),
    );
    if (saved == true) {
      await _fetchEvents();
      // Also refresh the public events list so EventListScreen shows updated data
      if (mounted) {
        ref.read(eventsProvider.notifier).fetchEvents(isRefresh: true);
      }
    }
  }

  Widget _buildEventsList(List<AppEvent> events, bool isDark, ThemeData theme, {required bool isPublished}) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _ErrorState(
        message: _errorMessage!,
        onRetry: _fetchEvents,
      );
    }

    if (events.isEmpty) {
      // Check if this is a search result or actual empty state
      final isSearchEmpty = _searchController.text.isNotEmpty;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearchEmpty ? Icons.search_off : (isPublished ? Icons.check_circle_outline : Icons.drafts_outlined),
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              isSearchEmpty 
                  ? 'No events match your search' 
                  : (isPublished ? 'No published events' : 'No draft events'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              isSearchEmpty
                  ? 'Try a different search term'
                  : (isPublished
                      ? 'Publish draft events to see them here.'
                      : 'Create new events or move from published to draft.'),
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchEvents,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 980 ? 2 : 1;
          return GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              mainAxisExtent: columns == 1 ? 360 : 330,
            ),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              return _ManageEventCard(
                event: event,
                isDark: isDark,
                theme: theme,
                isPublished: isPublished,
                onView: () => context.push('/events/${event.eventId}'),
                onEdit: () => _showEventForm(event: event),
                onPublish: isPublished ? null : () => _publishEvent(event),
                onUnpublish: isPublished ? () => _unpublishEvent(event) : null,
                onDelete: () => _deleteEvent(event),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Timezone options for event creation ────────────────────────────────────
List<String> _getAvailableTimezones() {
  return tz.timeZoneDatabase.locations.keys.toList()..sort();
}

// Common timezones for the simple dropdown
List<String> _getCommonTimezones() {
  return [
    'Asia/Kolkata',
    'UTC',
    'Asia/Dubai',
    'Europe/London',
    'America/New_York',
    'America/Los_Angeles',
    'Asia/Singapore',
    'Australia/Sydney',
    'Asia/Tokyo',
    'Europe/Paris',
    'Europe/Berlin',
    'Asia/Shanghai',
    'Asia/Hong_Kong',
    'Asia/Bangkok',
    'Asia/Jakarta',
    'Europe/Moscow',
    'America/Chicago',
    'America/Denver',
    'Pacific/Auckland',
  ];
}

// Fallback timezone offsets for common zones
const Map<String, String> TZ_OFFSETS = {
  'Asia/Kolkata': '+05:30',
  'UTC': '+00:00',
  'Asia/Dubai': '+04:00',
  'Europe/London': '+00:00',
  'America/New_York': '-05:00',
  'America/Los_Angeles': '-08:00',
  'Asia/Singapore': '+08:00',
  'Australia/Sydney': '+10:00',
};

String _getTimezoneOffset(String timezone) {
  // Use fallback offsets map for most common zones
  return TZ_OFFSETS[timezone] ?? '+05:30';
}

class _EventFormDialog extends ConsumerStatefulWidget {
  const _EventFormDialog({this.event});

  final AppEvent? event;

  @override
  ConsumerState<_EventFormDialog> createState() => _EventFormDialogState();
}

class _EventFormDialogState extends ConsumerState<_EventFormDialog> {
  final _formKey = GlobalKey<FormState>();
  
  // Basic info
  late final TextEditingController _title;
  late final TextEditingController _tagline;
  late final TextEditingController _description;
  
  // Datetime
  late final TextEditingController _startDate;
  late final TextEditingController _endDate;
  late final TextEditingController _startTime;
  late final TextEditingController _endTime;
  late final TextEditingController _timezone;
  bool _isFullDay = false;
  
  // Location/Virtual
  bool _isVirtual = false;
  late final TextEditingController _location;
  late final TextEditingController _locationMapsUrl;
  late final TextEditingController _virtualUrl;
  
  // Registration
  late final TextEditingController _registrationOpensAt;
  late final TextEditingController _registrationClosesAt;
  
  // Images
  late final TextEditingController _thumbnailUrl;
  late final TextEditingController _bannerUrl;
  
  // Capacity & Pricing
  late final TextEditingController _capacity;
  bool _isFree = true;
  late final TextEditingController _ticketPrice;
  
  // Speakers & Sessions
  late List<Map<String, String>> _speakers;
  late List<Map<String, String>> _sessions;
  
  // Sponsors
  late List<Map<String, String>> _sponsors;
  
  // Fees
  late List<Map<String, String>> _fees;

  // Registration fees — overall quantity limits (attached to the event)
  late final TextEditingController _regMinQuantity;
  late final TextEditingController _regMaxQuantity;
  
  var _isSaving = false;
  var _currentStep = 0;
  
  // Location search state
  final _locationSearchController = TextEditingController();
  var _locationSuggestions = <Map<String, String>>[];
  var _isSearchingLocation = false;
  var _locationSelected = false;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    
    _title = TextEditingController(text: event?.title ?? '');
    _tagline = TextEditingController(text: event?.tagline ?? '');
    _description = TextEditingController(text: event?.description ?? '');
    
    final startDt = event?.startDatetime ?? DateTime.now();
    final endDt = event?.endDatetime ?? DateTime.now().add(const Duration(hours: 2));
    
    _startDate = TextEditingController(text: _formatDateOnly(startDt));
    _endDate = TextEditingController(text: _formatDateOnly(endDt));
    _startTime = TextEditingController(text: _formatTimeFromDateTime(startDt));
    _endTime = TextEditingController(text: _formatTimeFromDateTime(endDt));
    _timezone = TextEditingController(text: event?.timezone ?? 'Asia/Kolkata');
    _isFullDay = false;
    
    _isVirtual = event?.isVirtual ?? false;
    _location = TextEditingController(text: event?.locationText ?? '');
    _locationMapsUrl = TextEditingController(text: event?.locationMapsUrl ?? '');
    _locationSearchController.text = event?.locationText ?? '';
    _locationSelected = event?.locationText != null && event!.locationText!.isNotEmpty;
    _virtualUrl = TextEditingController(text: event?.virtualUrl ?? '');
    
    _registrationOpensAt = TextEditingController(text: event?.registrationOpensAt != null 
      ? _formatDateTimeOnly(event!.registrationOpensAt!) 
      : '');
    _registrationClosesAt = TextEditingController(text: event?.registrationClosesAt != null 
      ? _formatDateTimeOnly(event!.registrationClosesAt!) 
      : '');
    
    _thumbnailUrl = TextEditingController(text: event?.thumbnailUrl ?? '');
    _bannerUrl = TextEditingController(text: event?.bannerUrl ?? '');
    
    _capacity = TextEditingController(text: event?.capacity?.toString() ?? '');
    _isFree = event?.isFree ?? true;
    _ticketPrice = TextEditingController(text: event?.ticketPrice?.toString() ?? '');
    
    // Initialize speakers (convert EventPerson to Map)
    _speakers = event?.speakers.map((sp) => {
      'fullname': sp.fullname,
      'title': sp.title ?? '',
      'organisation': sp.organisation ?? '',
    }).toList() ?? [];
    
    // Initialize sponsors (convert EventSponsor to Map)
    _sponsors = event?.sponsors.map((sp) => {
      'name': sp.name,
      'sponsor_type': sp.sponsorType,
      'logo_url': sp.logoUrl ?? '',
      'website_url': sp.websiteUrl ?? '',
    }).toList() ?? [];
    
    // Initialize fees
    _fees = [];
    
    // Initialize registration fee quantity limits (event level)
    _regMinQuantity = TextEditingController(
      text: event?.registrationMinQuantity?.toString() ?? '',
    );
    _regMaxQuantity = TextEditingController(
      text: event?.registrationMaxQuantity?.toString() ?? '',
    );
    
    // Initialize sessions (convert EventSession to Map)
    _sessions = event?.sessions.map((sess) {
      final speakerNames = _speakers.map((s) => s['fullname']!).toList();
      final matchingSpeaker = speakerNames.firstWhere(
        (name) => name.toLowerCase() == (sess.speakerName?.toLowerCase() ?? ''),
        orElse: () => '',
      );
      return {
        'title': sess.title,
        'speaker': matchingSpeaker,
        'start_time': _formatDateTimeOnly(sess.startDatetime),
        'end_time': sess.endDatetime != null ? _formatDateTimeOnly(sess.endDatetime!) : '',
      };
    }).toList() ?? [];
    
    // Add listeners for syncing dates and times
    _startDate.addListener(_syncDates);
    _startTime.addListener(_syncTimes);
    
    // Add listeners to step 1 required fields to trigger rebuild for Next button state
    _title.addListener(_onFieldChanged);
    _description.addListener(_onFieldChanged);
    _startDate.addListener(_onFieldChanged);
    _endDate.addListener(_onFieldChanged);
    _timezone.addListener(_onFieldChanged);
    _location.addListener(_onFieldChanged);
    _virtualUrl.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    // Trigger rebuild so _isStep1Complete is re-evaluated
    setState(() {});
  }

  void _syncDates() {
    _endDate.text = _startDate.text;
  }

  void _syncTimes() {
    final startTime = _parseTime(_startTime.text);
    if (startTime != null) {
      var totalMinutes = startTime.hour * 60 + startTime.minute + 180; // +3 hours
      var endHours = (totalMinutes ~/ 60) % 24;
      var endMinutes = totalMinutes % 60;
      _endTime.text = _formatTimeOfDay(TimeOfDay(hour: endHours, minute: endMinutes));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _tagline.dispose();
    _description.dispose();
    _startDate.removeListener(_syncDates);
    _startTime.removeListener(_syncTimes);
    _startDate.dispose();
    _endDate.dispose();
    _startTime.dispose();
    _endTime.dispose();
    _timezone.dispose();
    _location.dispose();
    _locationMapsUrl.dispose();
    _locationSearchController.dispose();
    _virtualUrl.dispose();
    _registrationOpensAt.dispose();
    _registrationClosesAt.dispose();
    _thumbnailUrl.dispose();
    _bannerUrl.dispose();
    _capacity.dispose();
    _ticketPrice.dispose();
    _regMinQuantity.dispose();
    _regMaxQuantity.dispose();
    super.dispose();
  }

  bool get _isStep1Complete {
    final titleFilled = _title.text.trim().isNotEmpty;
    final descFilled = _description.text.trim().isNotEmpty;
    final startDateFilled = _startDate.text.trim().isNotEmpty;
    final endDateFilled = _endDate.text.trim().isNotEmpty;
    final timezoneFilled = _timezone.text.trim().isNotEmpty;
    final locationFilled = _isVirtual
        ? _virtualUrl.text.trim().isNotEmpty
        : _location.text.trim().isNotEmpty;
    return titleFilled && descFilled && startDateFilled && endDateFilled && timezoneFilled && locationFilled;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.event != null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Dialog(
      child: SizedBox(
        width: MediaQuery.of(context).size.width > 800 ? 700 : null,
        height: MediaQuery.of(context).size.height * 0.9,
        child: Scaffold(
          appBar: AppBar(
            title: Text(isEditing ? 'Edit Event' : 'Create Event'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context, false),
            ),
          ),
          body: Form(
            key: _formKey,
            child: Column(
              children: [
                // Step indicator
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Row(
                    children: [
                      Flexible(
                        flex: 2,
                        child: _buildStepIndicator(0, 'General', 'Event details, date, location'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Divider(
                          color: _currentStep > 0 ? const Color(0xFFC9952A) : Colors.grey.shade300,
                          thickness: 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 3,
                        child: _buildStepIndicator(1, 'People & Agenda', 'Sponsors, speakers and sessions'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Divider(
                          color: _currentStep > 1 ? const Color(0xFFC9952A) : Colors.grey.shade300,
                          thickness: 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 2,
                        child: _buildStepIndicator(2, 'Fees', 'Registration fee tiers'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Step content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _currentStep == 0
                        ? _buildStep1()
                        : _currentStep == 1
                            ? _buildStep2()
                            : _buildStep3(),
                  ),
                ),
                // Bottom actions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      if (_currentStep > 0)
                        TextButton.icon(
                          onPressed: () => setState(() => _currentStep--),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back'),
                        )
                      else
                        const SizedBox.shrink(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: _isSaving ? null : () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          if (_currentStep == 0)
                            FilledButton.icon(
                              onPressed: _isStep1Complete ? () => setState(() => _currentStep = 1) : null,
                              icon: const Icon(Icons.arrow_forward),
                              label: const Text('Next'),
                            )
                          else if (_currentStep == 1)
                            FilledButton.icon(
                              onPressed: () => setState(() => _currentStep = 2),
                              icon: const Icon(Icons.arrow_forward),
                              label: const Text('Next'),
                            )
                          else
                            FilledButton(
                              onPressed: _isSaving ? null : _save,
                              child: Text(_isSaving ? 'Saving...' : 'Save Event'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int step, String title, String subtitle) {
    final isActive = _currentStep == step;
    final isCompleted = _currentStep > step;
    final color = isCompleted || isActive ? const Color(0xFFC9952A) : Colors.grey;
    final isNarrow = MediaQuery.of(context).size.width < 600;
    final canNavigate = step == 0 || _isStep1Complete;
    return GestureDetector(
      onTap: canNavigate ? () => setState(() => _currentStep = step) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted ? const Color(0xFFC9952A) : (isActive ? const Color(0xFFC9952A).withOpacity(0.15) : Colors.transparent),
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : Text('${step + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? const Color(0xFFC9952A) : Colors.grey, fontSize: 14)),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isActive || isCompleted ? const Color(0xFFC9952A) : Colors.grey),
                ),
                if (!isNarrow)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Event Details Section ──
        _buildSectionHeader('Event Details'),
        const SizedBox(height: 16),
        _buildTextField(_title, 'Event Title', hint: 'e.g., NITK Alumni Meetup', required: true),
        const SizedBox(height: 12),
        _buildTextField(_tagline, 'Tagline', hint: 'Brief one-line summary', maxLines: 1),
        const SizedBox(height: 12),
        _buildTextField(_description, 'Description', hint: 'Detailed event description', maxLines: 4, required: true),
        
        const SizedBox(height: 28),
        // ── Date & Time Section ──
        _buildSectionHeader('Date & Time'),
        const SizedBox(height: 16),
        
        // Timezone selector
        _buildTimezoneDropdown(),
        const SizedBox(height: 12),
        
        // Full day toggle
        _buildToggleField('Full Day Event', _isFullDay, (val) {
          setState(() => _isFullDay = val);
        }),
        const SizedBox(height: 12),
        
        // Date/time fields
        if (_isFullDay)
          Column(
            children: [
              _buildDateField(_startDate, 'Event Date', required: true),
              const SizedBox(height: 12),
            ],
          )
        else
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildDateField(_startDate, 'Start Date', required: true),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTimeField(_startTime, 'Start Time', required: true),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildDateField(_endDate, 'End Date', required: true),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTimeField(_endTime, 'End Time', required: true),
                  ),
                ],
              ),
            ],
          ),
        
        const SizedBox(height: 28),
        // ── Location Section ──
        _buildSectionHeader('Location'),
        const SizedBox(height: 16),
        
        _buildToggleField('Virtual Event', _isVirtual, (val) {
          setState(() => _isVirtual = val);
        }),
        const SizedBox(height: 12),
        
        if (_isVirtual)
          _buildTextField(_virtualUrl, 'Meeting URL', hint: 'e.g., https://zoom.us/j/...', required: true)
        else
          _buildLocationPicker(),
        
        const SizedBox(height: 28),
        // ── Registration Section ──
        _buildSectionHeader('Registration'),
        const SizedBox(height: 16),
        
        Row(
          children: [
            Expanded(
              child: _buildDateTimeField(
                _registrationOpensAt, 
                'Registration Opens', 
                hint: 'YYYY-MM-DD HH:mm',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDateTimeField(
                _registrationClosesAt, 
                'Registration Closes', 
                hint: 'YYYY-MM-DD HH:mm',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildTextField(_capacity, 'Capacity', hint: 'Leave empty for unlimited', keyboardType: TextInputType.number),
        
        const SizedBox(height: 28),
        // ── Images Section ──
        _buildSectionHeader('Images'),
        const SizedBox(height: 16),
        
        _buildTextField(_thumbnailUrl, 'Thumbnail URL', hint: 'Square image URL for event cards'),
        const SizedBox(height: 12),
        _buildTextField(_bannerUrl, 'Banner URL', hint: 'Wide image URL for event header'),
        
        const SizedBox(height: 28),
        // ── Pricing Section ──
        _buildSectionHeader('Pricing'),
        const SizedBox(height: 16),
        
        _buildToggleField('Free Event', _isFree, (val) {
          setState(() => _isFree = val);
        }),
        const SizedBox(height: 12),
        
        if (!_isFree)
          _buildTextField(
            _ticketPrice, 
            'Ticket Price', 
            hint: 'e.g., 499.99',
            keyboardType: TextInputType.number,
            required: true,
          ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Sponsors Section ──
        _buildSectionHeader('Sponsors'),
        const SizedBox(height: 16),
        _buildSponsorsSection(),
        
        const SizedBox(height: 28),
        // ── Speakers Section ──
        _buildSectionHeader('Speakers'),
        const SizedBox(height: 16),
        _buildSpeakersSection(),
        
        const SizedBox(height: 28),
        // ── Sessions Section ──
        _buildSectionHeader('Sessions'),
        const SizedBox(height: 16),
        _buildSessionsSection(),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Registration Fees Section (main form — attached to event) ──
        _buildSectionHeader('Registration Fees'),
        const SizedBox(height: 16),
        Text(
          'Quantity limits below apply to the event registration as a whole.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildTextField(
                _regMinQuantity,
                'Min Count Per Registration',
                hint: 'e.g., 1',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                _regMaxQuantity,
                'Max Count Per Registration',
                hint: 'e.g., 5',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        // ── Fee Tiers Section ──
        _buildSectionHeader('Fee Tiers'),
        const SizedBox(height: 16),
        _buildFeesSection(),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    String? hint,
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final displayLabel = required ? '$label *' : label;
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: displayLabel,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      maxLines: maxLines,
      minLines: maxLines == 1 ? 1 : null,
      keyboardType: keyboardType,
      validator: required
          ? (value) => value == null || value.trim().isEmpty ? '$label is required' : null
          : null,
    );
  }

  Widget _buildDateField(TextEditingController controller, String label, {bool required = false}) {
    final displayLabel = required ? '$label *' : label;
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: displayLabel,
        hintText: 'YYYY-MM-DD',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        suffixIcon: GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _parseDate(controller.text) ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2040),
            );
            if (picked != null) {
              controller.text = _formatDateOnly(picked);
            }
          },
          child: const Icon(Icons.calendar_today),
        ),
      ),
      keyboardType: TextInputType.datetime,
      validator: required
          ? (value) => value == null || value.trim().isEmpty ? '$label is required' : null
          : null,
    );
  }

  Widget _buildTimeField(TextEditingController controller, String label, {bool required = false}) {
    final displayLabel = required ? '$label *' : label;
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: displayLabel,
        hintText: 'HH:mm',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        suffixIcon: GestureDetector(
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: _parseTime(controller.text) ?? TimeOfDay.now(),
            );
            if (picked != null) {
              controller.text = _formatTimeOfDay(picked);
            }
          },
          child: const Icon(Icons.access_time),
        ),
      ),
      keyboardType: TextInputType.datetime,
      validator: required
          ? (value) => value == null || value.trim().isEmpty ? '$label is required' : null
          : null,
    );
  }

  Widget _buildDateTimeField(TextEditingController controller, String label, {String? hint}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        suffixIcon: GestureDetector(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2040),
            );
            if (date == null) return;

            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
            );
            if (time == null) return;

            final dateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
            controller.text = _formatDateTimeOnly(dateTime);
          },
          child: const Icon(Icons.schedule),
        ),
      ),
      keyboardType: TextInputType.datetime,
    );
  }

  Widget _buildTimezoneDropdown() {
    final zones = _getCommonTimezones();
    final currentValue = _timezone.text.isEmpty ? zones.first : _timezone.text;
    
    return DropdownButtonFormField<String>(
      value: zones.contains(currentValue) ? currentValue : zones.first,
      isDense: true,
      menuMaxHeight: 300,
      decoration: InputDecoration(
        labelText: 'Timezone *',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: zones.map((zone) => DropdownMenuItem(
        value: zone,
        child: Text(zone, style: const TextStyle(fontSize: 13)),
      )).toList(),
      onChanged: (value) {
        if (value != null) {
          _timezone.text = value;
        }
      },
      dropdownColor: Theme.of(context).cardColor,
    );
  }

  Widget _buildSpeakersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // List of speakers
        if (_speakers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No speakers added yet',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          )
        else
          ...List.generate(_speakers.length, (index) {
            final speaker = _speakers[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            speaker['fullname'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${speaker['title'] ?? ''}, ${speaker['organisation'] ?? ''}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _showSpeakerDialog(index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () {
                            setState(() => _speakers.removeAt(index));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => _showSpeakerDialog(null),
          icon: const Icon(Icons.add),
          label: const Text('Add Speaker'),
        ),
      ],
    );
  }
// ── Fee type options ────────────────────────────────────────────────────
  static const List<String> _feeTypeOptions = [
    'PARTICIPATION',
    'ACCOMMODATION',
    'CONTRIBUTIONS',
    'FOOD_PASS',
    'MERCHANDISE',
    'OTHER',
  ];

  String _feeTypeLabel(String type) {
    return type
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  String _formatFeeAmount(String amount) {
    final parsed = double.tryParse(amount);
    if (parsed == null) return amount.isEmpty ? '—' : amount;
    if (parsed == parsed.roundToDouble()) {
      return '₹${parsed.toInt()}';
    }
    return '₹${parsed.toStringAsFixed(2)}';
  }

  double get _feesTotal {
    var total = 0.0;
    for (final fee in _fees) {
      total += double.tryParse((fee['fee_amount'] ?? '').trim()) ?? 0.0;
    }
    return total;
  }

  Widget _buildFeeTableHeaderCell(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildFeeTableCell(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildFeesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fee table
        if (_fees.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No fees added yet',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 460,
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2.2),
                      1: FlexColumnWidth(1.4),
                      2: FlexColumnWidth(1.6),
                      3: IntrinsicColumnWidth(),
                    },
                    border: TableBorder(
                      horizontalInside: BorderSide(color: Colors.grey.shade200, width: 1),
                    ),
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          color: const Color(0xFFC9952A).withValues(alpha: 0.08),
                        ),
                        children: [
                          _buildFeeTableHeaderCell('Fee Name'),
                          _buildFeeTableHeaderCell('Fee Type'),
                          _buildFeeTableHeaderCell('Amount'),
                          const Padding(padding: EdgeInsets.all(8)),
                        ],
                      ),
                      ...List.generate(_fees.length, (index) {
                        final fee = _fees[index];
                        return TableRow(
                          children: [
                            _buildFeeTableCell(fee['fee_name'] ?? '', bold: true),
                            _buildFeeTableCell(_feeTypeLabel(fee['fee_type'] ?? '')),
                            _buildFeeTableCell(_formatFeeAmount(fee['fee_amount'] ?? '')),
                            Padding(
                              padding: EdgeInsets.zero,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _showFeeDialog(index),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      setState(() => _fees.removeAt(index));
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }),
                      // ── Total row ──
                      TableRow(
                        decoration: BoxDecoration(
                          color: const Color(0xFFC9952A).withValues(alpha: 0.12),
                        ),
                        children: [
                          _buildFeeTableCell('Total', bold: true),
                          _buildFeeTableCell(''),
                          _buildFeeTableCell(
                            _formatFeeAmount(_feesTotal.toString()),
                            bold: true,
                          ),
                          const Padding(padding: EdgeInsets.all(8)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => _showFeeDialog(null),
          icon: const Icon(Icons.add),
          label: const Text('Add Fee'),
        ),
      ],
    );
  }

  Widget _buildSessionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // List of sessions
        if (_sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No sessions added yet',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          )
        else
          ...List.generate(_sessions.length, (index) {
            final session = _sessions[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session['title'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Speaker: ${session['speaker'] ?? 'Not assigned'}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${session['start_time'] ?? ''} - ${session['end_time'] ?? ''}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _showSessionDialog(index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () {
                            setState(() => _sessions.removeAt(index));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _speakers.isEmpty 
            ? null 
            : () => _showSessionDialog(null),
          icon: const Icon(Icons.add),
          label: const Text('Add Session'),
        ),
        if (_speakers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Add speakers before creating sessions',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade600),
            ),
          ),
      ],
    );
  }

  Widget _buildSponsorsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_sponsors.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No sponsors added yet',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          )
        else
          ...List.generate(_sponsors.length, (index) {
            final sponsor = _sponsors[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Up/Down buttons
                    Column(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          onPressed: index > 0 ? () {
                            setState(() {
                              final temp = _sponsors[index];
                              _sponsors[index] = _sponsors[index - 1];
                              _sponsors[index - 1] = temp;
                            });
                          } : null,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 16),
                          padding: EdgeInsets.zero,
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 16),
                          onPressed: index < _sponsors.length - 1 ? () {
                            setState(() {
                              final temp = _sponsors[index];
                              _sponsors[index] = _sponsors[index + 1];
                              _sponsors[index + 1] = temp;
                            });
                          } : null,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 16),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    // Sponsor info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sponsor['name'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _sponsorTypeLabel(sponsor['sponsor_type'] ?? ''),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          if ((sponsor['logo_url'] ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Logo: ${sponsor['logo_url']}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Edit/Delete buttons
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _showSponsorDialog(index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () {
                            setState(() => _sponsors.removeAt(index));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => _showSponsorDialog(null),
          icon: const Icon(Icons.add),
          label: const Text('Add Sponsor'),
        ),
      ],
    );
  }

  String _sponsorTypeLabel(String type) {
    switch (type) {
      case 'TITLE_SPONSOR': return 'Title Sponsor';
      case 'GOLD_SPONSOR': return 'Gold Sponsor';
      case 'SILVER_SPONSOR': return 'Silver Sponsor';
      case 'BRONZE_SPONSOR': return 'Bronze Sponsor';
      case 'ASSOCIATE_SPONSOR': return 'Associate Sponsor';
      default: return type.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}').join(' ');
    }
  }

  void _showSponsorDialog(int? editIndex) {
    final nameCtrl = TextEditingController(
      text: editIndex != null ? _sponsors[editIndex]['name'] ?? '' : '',
    );
    final logoUrlCtrl = TextEditingController(
      text: editIndex != null ? _sponsors[editIndex]['logo_url'] ?? '' : '',
    );
    final websiteUrlCtrl = TextEditingController(
      text: editIndex != null ? _sponsors[editIndex]['website_url'] ?? '' : '',
    );
    var selectedType = editIndex != null ? _sponsors[editIndex]['sponsor_type'] ?? 'TITLE_SPONSOR' : 'TITLE_SPONSOR';

    final sponsorTypes = [
      'TITLE_SPONSOR',
      'GOLD_SPONSOR',
      'SILVER_SPONSOR',
      'BRONZE_SPONSOR',
      'ASSOCIATE_SPONSOR',
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final canSave = nameCtrl.text.trim().isNotEmpty;
          return AlertDialog(
            title: Text(editIndex == null ? 'Add Sponsor' : 'Edit Sponsor'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Sponsor Name *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: InputDecoration(
                      labelText: 'Sponsor Type *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: sponsorTypes.map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(_sponsorTypeLabel(type)),
                    )).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedType = value ?? 'TITLE_SPONSOR');
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: logoUrlCtrl,
                    decoration: InputDecoration(
                      labelText: 'Logo URL',
                      hintText: 'https://example.com/logo.png',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: websiteUrlCtrl,
                    decoration: InputDecoration(
                      labelText: 'Website URL',
                      hintText: 'https://example.com',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: canSave ? () {
                  setState(() {
                    final sponsor = {
                      'name': nameCtrl.text.trim(),
                      'sponsor_type': selectedType,
                      'logo_url': logoUrlCtrl.text.trim(),
                      'website_url': websiteUrlCtrl.text.trim(),
                    };
                    if (editIndex == null) {
                      _sponsors.add(sponsor);
                    } else {
                      _sponsors[editIndex] = sponsor;
                    }
                  });
                  Navigator.pop(context);
                } : null,
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSpeakerDialog(int? editIndex) {
    final fullnameCtrl = TextEditingController(
      text: editIndex != null ? _speakers[editIndex]['fullname'] ?? '' : '',
    );
    final titleCtrl = TextEditingController(
      text: editIndex != null ? _speakers[editIndex]['title'] ?? '' : '',
    );
    final organisationCtrl = TextEditingController(
      text: editIndex != null ? _speakers[editIndex]['organisation'] ?? '' : '',
    );
    final photoUrlCtrl = TextEditingController(
      text: editIndex != null ? _speakers[editIndex]['photo_url'] ?? '' : '',
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final canSave = fullnameCtrl.text.trim().isNotEmpty && 
              organisationCtrl.text.trim().isNotEmpty;
          return AlertDialog(
            title: Text(editIndex == null ? 'Add Speaker' : 'Edit Speaker'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: fullnameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Full Name *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: 'Title',
                      hintText: 'e.g., Chief Technology Officer',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: organisationCtrl,
                    decoration: InputDecoration(
                      labelText: 'Organization *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: photoUrlCtrl,
                    decoration: InputDecoration(
                      labelText: 'Profile Picture URL',
                      hintText: 'https://example.com/photo.jpg',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: canSave ? () {
                  setState(() {
                    final speaker = {
                      'fullname': fullnameCtrl.text.trim(),
                      'title': titleCtrl.text.trim(),
                      'organisation': organisationCtrl.text.trim(),
                      'photo_url': photoUrlCtrl.text.trim(),
                    };
                    if (editIndex == null) {
                      _speakers.add(speaker);
                    } else {
                      _speakers[editIndex] = speaker;
                    }
                  });
                  Navigator.pop(context);
                } : null,
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
void _showFeeDialog(int? editIndex) {
    final nameCtrl = TextEditingController(
      text: editIndex != null ? _fees[editIndex]['fee_name'] ?? '' : '',
    );
    final amountCtrl = TextEditingController(
      text: editIndex != null ? _fees[editIndex]['fee_amount'] ?? '' : '',
    );
    var selectedType = editIndex != null ? _fees[editIndex]['fee_type'] ?? 'PARTICIPATION' : 'PARTICIPATION';
    var attemptedSave = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final name = nameCtrl.text.trim();
          final amountText = amountCtrl.text.trim();

          final amountValue = double.tryParse(amountText);

          final nameError = name.isEmpty ? 'Fee name is required' : null;
          final amountError = amountText.isEmpty
              ? 'Fee amount is required'
              : amountValue == null
                  ? 'Enter a valid amount'
                  : amountValue < 0
                      ? 'Amount must be 0 or more'
                      : null;

          final canSave = nameError == null &&
              amountError == null;

          String? errorText(String? error) => attemptedSave ? error : null;

          return AlertDialog(
            title: Text(editIndex == null ? 'Add Fee' : 'Edit Fee'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Fee Name *',
                      hintText: 'e.g., Early Bird',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      errorText: errorText(nameError),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    isDense: true,
                    decoration: InputDecoration(
                      labelText: 'Fee Type *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: _feeTypeOptions.map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(_feeTypeLabel(type)),
                    )).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedType = value ?? 'PARTICIPATION');
                    },
                    dropdownColor: Theme.of(context).cardColor,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    decoration: InputDecoration(
                      labelText: 'Fee Amount (₹) *',
                      hintText: 'e.g., 499',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      errorText: errorText(amountError),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: canSave ? () {
                  setState(() {
                    final fee = {
                      'fee_name': nameCtrl.text.trim(),
                      'fee_type': selectedType,
                      'fee_amount': amountCtrl.text.trim(),
                    };
                    if (editIndex == null) {
                      _fees.add(fee);
                    } else {
                      _fees[editIndex] = fee;
                    }
                  });
                  Navigator.pop(context);
                } : () {
                  attemptedSave = true;
                  setDialogState(() {});
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSessionDialog(int? editIndex) {
    final titleCtrl = TextEditingController(
      text: editIndex != null ? _sessions[editIndex]['title'] ?? '' : '',
    );
    final startTimeCtrl = TextEditingController(
      text: editIndex != null ? _sessions[editIndex]['start_time'] ?? '' : _getDefaultStartTime(),
    );
    final endTimeCtrl = TextEditingController(
      text: editIndex != null ? _sessions[editIndex]['end_time'] ?? '' : _getDefaultEndTime(startTimeCtrl.text),
    );
    var selectedSpeaker = editIndex != null ? _sessions[editIndex]['speaker'] ?? '' : '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final canSave = titleCtrl.text.trim().isNotEmpty && 
              selectedSpeaker.isNotEmpty && 
              startTimeCtrl.text.trim().isNotEmpty && 
              endTimeCtrl.text.trim().isNotEmpty;
          
          return AlertDialog(
            title: Text(editIndex == null ? 'Add Session' : 'Edit Session'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: 'Session Title *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedSpeaker.isEmpty ? null : selectedSpeaker,
                    decoration: InputDecoration(
                      labelText: 'Speaker *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: _speakers
                        .map((s) => DropdownMenuItem(
                          value: s['fullname'],
                          child: Text(s['fullname'] ?? ''),
                        ))
                        .toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedSpeaker = value ?? '');
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: startTimeCtrl,
                    decoration: InputDecoration(
                      labelText: 'Start Time *',
                      hintText: 'YYYY-MM-DD HH:mm',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onTap: () async {
                      final dateTime = await _showDateTimePickerDialog(startTimeCtrl.text);
                      if (dateTime != null) {
                        startTimeCtrl.text = dateTime;
                        // Auto-calculate end time (+60 min)
                        final newEndTime = _getDefaultEndTime(dateTime);
                        endTimeCtrl.text = newEndTime;
                        setDialogState(() {});
                      }
                    },
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: endTimeCtrl,
                    decoration: InputDecoration(
                      labelText: 'End Time *',
                      hintText: 'YYYY-MM-DD HH:mm',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onTap: () async {
                      final dateTime = await _showDateTimePickerDialog(endTimeCtrl.text);
                      if (dateTime != null) {
                        endTimeCtrl.text = dateTime;
                        setDialogState(() {});
                      }
                    },
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: canSave ? () {
                  // Validate for time clashes
                  final clashError = _validateSessionClash(
                    editIndex,
                    startTimeCtrl.text.trim(),
                    endTimeCtrl.text.trim(),
                  );
                  if (clashError != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(clashError)),
                    );
                    return;
                  }

                  setState(() {
                    final session = {
                      'title': titleCtrl.text.trim(),
                      'speaker': selectedSpeaker,
                      'start_time': startTimeCtrl.text.trim(),
                      'end_time': endTimeCtrl.text.trim(),
                    };
                    if (editIndex == null) {
                      _sessions.add(session);
                    } else {
                      _sessions[editIndex] = session;
                    }
                  });
                  Navigator.pop(context);
                } : null,
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getDefaultStartTime() {
    // If there are existing sessions, use the end time of the last one
    if (_sessions.isNotEmpty) {
      final lastSession = _sessions.last;
      final lastEndTime = lastSession['end_time'] ?? '';
      if (lastEndTime.isNotEmpty) {
        try {
          final parsed = DateTime.parse(lastEndTime);
          return _formatDateTimeOnly(parsed);
        } catch (e) {
          // Fall through to default
        }
      }
    }
    // Default to current time
    return _formatDateTimeOnly(DateTime.now());
  }

  String _getDefaultEndTime(String startTime) {
    if (startTime.isEmpty) return _formatDateTimeOnly(DateTime.now().add(const Duration(hours: 1)));
    try {
      final parsed = DateTime.parse(startTime);
      return _formatDateTimeOnly(parsed.add(const Duration(minutes: 60)));
    } catch (e) {
      return _formatDateTimeOnly(DateTime.now().add(const Duration(hours: 1)));
    }
  }

  String? _validateSessionClash(int? editIndex, String startTime, String endTime) {
    try {
      final start = DateTime.parse(startTime);
      final end = DateTime.parse(endTime);
      
      if (!end.isAfter(start)) {
        return 'End time must be after start time';
      }

      // Check for clashes with other sessions
      for (int i = 0; i < _sessions.length; i++) {
        if (i == editIndex) continue; // Skip the session being edited
        
        final otherStart = DateTime.parse(_sessions[i]['start_time'] ?? '');
        final otherEnd = DateTime.parse(_sessions[i]['end_time'] ?? '');
        
        // Check if times overlap: (start < otherEnd) && (end > otherStart)
        if (start.isBefore(otherEnd) && end.isAfter(otherStart)) {
          return 'Session timing clashes with "${_sessions[i]['title']}"';
        }
      }
      return null;
    } catch (e) {
      return null; // Let other validation handle parsing errors
    }
  }

  Future<String?> _showDateTimePickerDialog(String currentValue) async {
    DateTime? dateTime;
    try {
      dateTime = DateTime.parse(currentValue);
    } catch (e) {
      dateTime = DateTime.now();
    }

    final date = await showDatePicker(
      context: context,
      initialDate: dateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );

    if (date == null) return null;

    if (!mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(dateTime),
    );

    if (time == null) return null;

    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    return _formatDateTimeOnly(combined);
  }

  Widget _buildLocationPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Location search field
        TextFormField(
          controller: _locationSearchController,
          decoration: InputDecoration(
            labelText: 'Search Location *',
            hintText: 'Type a place name or address...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _locationSelected
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.green),
                    tooltip: 'Clear selection',
                    onPressed: () {
                      setState(() {
                        _locationSearchController.clear();
                        _location.text = '';
                        _locationMapsUrl.text = '';
                        _locationSuggestions = [];
                        _locationSelected = false;
                      });
                    },
                  )
                : null,
          ),
          onChanged: (value) {
            setState(() {
              _locationSelected = false;
              _location.text = '';
              _locationMapsUrl.text = '';
            });
            _debouncedLocationSearch(value);
          },
          validator: (value) {
            if (!_locationSelected && (value == null || value.trim().isEmpty)) {
              return 'Location is required';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        // Manual use button - always at the top when text is entered and no location selected
        if (!_locationSelected && _locationSearchController.text.trim().length >= 3 && !_isSearchingLocation)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    final text = _locationSearchController.text.trim();
                    _location.text = text;
                    _locationMapsUrl.text = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(text)}';
                    _locationSuggestions = [];
                    _locationSelected = true;
                  });
                },
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(
                  _locationSuggestions.isNotEmpty
                      ? 'Use typed text as location'
                      : 'Use as location',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        // Suggestions list
        if (_isSearchingLocation)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (_locationSuggestions.isNotEmpty && !_locationSelected)
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _locationSuggestions.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                final suggestion = _locationSuggestions[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place, size: 18, color: Color(0xFFC9952A)),
                  title: Text(
                    suggestion['name'] ?? '',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    suggestion['address'] ?? '',
                    style: const TextStyle(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _selectLocation(suggestion),
                );
              },
            ),
          ),
        // Selected location display
        if (_locationSelected)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFC9952A).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFC9952A).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFFC9952A), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _location.text,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      if (_locationMapsUrl.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: GestureDetector(
                            onTap: () async {
                              final uri = Uri.tryParse(_locationMapsUrl.text);
                              if (uri != null && await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            child: Text(
                              'Open in Google Maps',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Timer? _debounceTimer;
  void _debouncedLocationSearch(String query) {
    _debounceTimer?.cancel();
    if (query.trim().length < 3) {
      setState(() {
        _locationSuggestions = [];
        _isSearchingLocation = false;
      });
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 500), () => _searchPlaces(query.trim()));
  }

  Future<void> _searchPlaces(String query) async {
    setState(() => _isSearchingLocation = true);
    try {
      // Use OpenStreetMap Nominatim API (free, no API key required)
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json'
        '&addressdetails=1'
        '&limit=5'
        '&countrycodes=in',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'NITKSAAEventApp/1.0'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        setState(() {
          _locationSuggestions = data.map((r) {
            final rMap = r as Map<String, dynamic>;
            final lat = rMap['lat'] as String?;
            final lng = rMap['lon'] as String?;
            final displayName = rMap['display_name'] as String? ?? '';
            final addressParts = displayName.split(',');
            // Extract a short name (first part) and full address
            final name = addressParts.isNotEmpty ? addressParts[0].trim() : displayName;
            final address = addressParts.length > 1
                ? addressParts.sublist(1).join(',').trim()
                : displayName;
            final mapsUrl = (lat != null && lng != null)
                ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lng'
                : '';
            return {
              'name': name,
              'address': address,
              'maps_url': mapsUrl,
            };
          }).toList();
          _isSearchingLocation = false;
        });
      } else {
        setState(() {
          _locationSuggestions = [];
          _isSearchingLocation = false;
        });
      }
    } catch (e) {
      setState(() {
        _locationSuggestions = [];
        _isSearchingLocation = false;
      });
    }
  }

  void _selectLocation(Map<String, String> suggestion) {
    setState(() {
      _location.text = suggestion['name'] ?? suggestion['address'] ?? '';
      _locationMapsUrl.text = suggestion['maps_url'] ?? '';
      _locationSearchController.text = suggestion['name'] ?? suggestion['address'] ?? '';
      _locationSuggestions = [];
      _locationSelected = true;
    });
  }

  Widget _buildToggleField(String label, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        Switch(
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Parse and validate dates
    final startDate = _parseDate(_startDate.text);
    final endDate = _parseDate(_endDate.text);

    if (startDate == null || endDate == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter valid dates')),
        );
      }
      return;
    }

    DateTime? startDateTime;
    DateTime? endDateTime;

    if (_isFullDay) {
      startDateTime = startDate;
      endDateTime = endDate.add(const Duration(days: 1));
    } else {
      final startTime = _parseTime(_startTime.text);
      final endTime = _parseTime(_endTime.text);

      if (startTime == null || endTime == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter valid times')),
          );
        }
        return;
      }

      startDateTime = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
        startTime.hour,
        startTime.minute,
      );

      endDateTime = DateTime(
        endDate.year,
        endDate.month,
        endDate.day,
        endTime.hour,
        endTime.minute,
      );
    }

    if (!endDateTime.isAfter(startDateTime)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End time must be after start time')),
        );
      }
      return;
    }

    // Validate registration opens/closes
    if (_registrationOpensAt.text.trim().isNotEmpty && _registrationClosesAt.text.trim().isNotEmpty) {
      try {
        final regOpen = DateTime.parse(_registrationOpensAt.text.trim());
        final regClose = DateTime.parse(_registrationClosesAt.text.trim());
        if (regClose.isBefore(regOpen)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Registration closes must be on or after registration opens')),
            );
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid registration date format')),
          );
        }
        return;
      }
    }

    // Validate all sessions fall within event timeframe
    if (_sessions.isNotEmpty) {
      for (final session in _sessions) {
        final sessionStartStr = session['start_time'] ?? '';
        final sessionEndStr = session['end_time'] ?? '';
        if (sessionStartStr.isEmpty || sessionEndStr.isEmpty) continue;

        try {
          final sessionStart = DateTime.parse(sessionStartStr);
          final sessionEnd = DateTime.parse(sessionEndStr);

          if (!sessionEnd.isAfter(sessionStart)) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Session "${session['title']}" end time must be after start time')),
              );
            }
            return;
          }

          if (sessionStart.isBefore(startDateTime) || sessionEnd.isAfter(endDateTime)) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Session "${session['title']}" must be within event timeframe '
                    '(${_formatDateTimeOnly(startDateTime)} - ${_formatDateTimeOnly(endDateTime)})',
                  ),
                ),
              );
            }
            return;
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid session date/time format')),
            );
          }
          return;
        }
      }
    }

    if (_isVirtual && _virtualUrl.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter meeting URL for virtual events')),
        );
      }
      return;
    }

    if (!_isFree && _ticketPrice.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter ticket price for paid events')),
        );
      }
      return;
    }

    // Validate registration fee quantity limits (event level)
    final regMinQtyText = _regMinQuantity.text.trim();
    final regMaxQtyText = _regMaxQuantity.text.trim();
    final regMinQty = regMinQtyText.isEmpty ? null : int.tryParse(regMinQtyText);
    final regMaxQty = regMaxQtyText.isEmpty ? null : int.tryParse(regMaxQtyText);

    if (regMinQtyText.isNotEmpty && regMinQty == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Min count must be a whole number')),
        );
      }
      return;
    }
    if (regMinQty != null && regMinQty < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Min count must be 0 or more')),
        );
      }
      return;
    }
    if (regMaxQtyText.isNotEmpty && regMaxQty == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Max count must be a whole number')),
        );
      }
      return;
    }
    if (regMaxQty != null && regMaxQty < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Max count must be 0 or more')),
        );
      }
      return;
    }
    if (regMinQty != null && regMaxQty != null && regMaxQty < regMinQty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Max count cannot be less than min count')),
        );
      }
      return;
    }

    setState(() => _isSaving = true);

    try {
      final auth = ref.read(authControllerProvider);
      final offset = _getTimezoneOffset(_timezone.text);

      final data = <String, dynamic>{
        'title': _title.text.trim(),
        'tagline': _tagline.text.trim().isEmpty ? null : _tagline.text.trim(),
        'description': _description.text.trim(),
        'start_datetime': '${_formatDateOnly(startDateTime)}T${_formatTimeFromDateTime(startDateTime)}:00$offset',
        'end_datetime': '${_formatDateOnly(endDateTime)}T${_formatTimeFromDateTime(endDateTime)}:00$offset',
        'timezone': _timezone.text,
        'is_virtual': _isVirtual,
        'location_text': _isVirtual ? null : _location.text.trim().isEmpty ? null : _location.text.trim(),
        'location_maps_url': _isVirtual ? null : _locationMapsUrl.text.trim().isEmpty ? null : _locationMapsUrl.text.trim(),
        'virtual_url': _isVirtual ? _virtualUrl.text.trim() : null,
        'is_full_day': _isFullDay,
        'capacity': _capacity.text.trim().isEmpty ? null : int.tryParse(_capacity.text.trim()),
        'is_free': _isFree,
        'ticket_price': _isFree ? null : double.tryParse(_ticketPrice.text.trim()),
        'registration_min_quantity': regMinQty,
        'registration_max_quantity': regMaxQty,
        'thumbnail_url': _thumbnailUrl.text.trim().isEmpty ? null : _thumbnailUrl.text.trim(),
        'banner_url': _bannerUrl.text.trim().isEmpty ? null : _bannerUrl.text.trim(),
        if (_registrationOpensAt.text.trim().isNotEmpty)
          'registration_opens_at': '${_registrationOpensAt.text.trim()}:00$offset',
        if (_registrationClosesAt.text.trim().isNotEmpty)
          'registration_closes_at': '${_registrationClosesAt.text.trim()}:00$offset',
        // Add sponsors data
        'sponsors': _sponsors.asMap().entries.map((entry) => {
          'name': entry.value['name'],
          'sponsor_type': entry.value['sponsor_type'],
          'logo_url': entry.value['logo_url']?.isEmpty == true ? null : entry.value['logo_url'],
          'website_url': entry.value['website_url']?.isEmpty == true ? null : entry.value['website_url'],
          'display_order': entry.key,
        }).toList(),
        // Add speakers data
        'speakers': _speakers.map((speaker) => {
          'fullname': speaker['fullname'],
          'title': speaker['title'],
          'organisation': speaker['organisation'],
          'role': 'SPEAKER',
        }).toList(),
        // Add sessions data
        'sessions': _sessions.map((session) => {
          'title': session['title'],
          'speaker_name': session['speaker'],
          'start_datetime': '${session['start_time']}:00$offset',
          'end_datetime': '${session['end_time']}:00$offset',
        }).toList(),
        // Add fees data
        'fees': _fees.map((fee) => {
          'fee_name': fee['fee_name'],
          'fee_type': fee['fee_type'],
          'fee_amount': double.tryParse((fee['fee_amount'] ?? '').trim()) ?? 0,
        }).toList(),
      };

      final repo = ref.read(eventsRepositoryProvider);
      if (widget.event == null) {
        await repo.createAdminEvent(data, auth.session!.accessToken);
      } else {
        await repo.updateAdminEvent(widget.event!.eventId, data, auth.session!.accessToken);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving event: $error')),
      );
    }
  }

  // ── Helper formatters ──
  static String _formatDateOnly(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  static String _formatTimeFromDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
  }

  static String _formatTimeOfDay(TimeOfDay time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}';
  }

  static String _formatDateTimeOnly(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  static DateTime? _parseDate(String value) {
    if (value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (e) {
      return null;
    }
  }

  static TimeOfDay? _parseTime(String value) {
    if (value.isEmpty) return null;
    try {
      final parts = value.split(':');
      if (parts.length != 2) return null;
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      return null;
    }
  }
}

class _ManageEventCard extends StatelessWidget {
  const _ManageEventCard({
    required this.event,
    required this.isDark,
    required this.theme,
    required this.isPublished,
    required this.onView,
    required this.onEdit,
    this.onPublish,
    this.onUnpublish,
    this.onDelete,
  });

  final AppEvent event;
  final bool isDark;
  final ThemeData theme;
  final bool isPublished;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback? onPublish;
  final VoidCallback? onUnpublish;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isPublished
                        ? const Color(0xFFD9F4E8)
                        : const Color(0xFFFFE9E9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isPublished ? 'Published' : 'Draft',
                    style: TextStyle(
                      color: isPublished
                          ? const Color(0xFF1B5C3A)
                          : const Color(0xFF8A1B1B),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              event.description ?? 'No description provided.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const Spacer(),
            _MetaRow(icon: Icons.event, label: _formatDateTime(event.startDatetime)),
            const SizedBox(height: 6),
            _MetaRow(
              icon: event.isVirtual ? Icons.videocam_outlined : Icons.place_outlined,
              label: event.locationText ?? (event.isVirtual ? 'Virtual event' : 'Location pending'),
            ),
            const SizedBox(height: 16),
            // Action buttons
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (isPublished) ...[
                  OutlinedButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('View', style: TextStyle(fontSize: 12)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/admin/events/${event.eventId}/registrations'),
                    icon: const Icon(Icons.people_outline, size: 16),
                    label: const Text('Registrations', style: TextStyle(fontSize: 12)),
                  ),
                  FilledButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit', style: TextStyle(fontSize: 12)),
                  ),
                  if (onUnpublish != null)
                    OutlinedButton.icon(
                      onPressed: onUnpublish,
                      icon: const Icon(Icons.unpublished_outlined, size: 16),
                      label: const Text('Unpublish', style: TextStyle(fontSize: 12)),
                    ),
                  if (onDelete != null)
                    OutlinedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      label: const Text('Delete', style: TextStyle(fontSize: 12, color: Colors.red)),
                    ),
                ] else ...[
                  if (onPublish != null)
                    FilledButton.icon(
                      onPressed: onPublish,
                      icon: const Icon(Icons.publish_outlined, size: 16),
                      label: const Text('Publish', style: TextStyle(fontSize: 12)),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit', style: TextStyle(fontSize: 12)),
                  ),
                  if (onDelete != null)
                    OutlinedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      label: const Text('Delete', style: TextStyle(fontSize: 12, color: Colors.red)),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime value) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.day} ${months[value.month - 1]} ${value.year}, $hour:$minute $period';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFD9F4E8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.replaceAll('_', ' '),
        style: const TextStyle(
          color: Color(0xFF1B5C3A),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFFC9952A)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
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
            active: false,
            onTap: () => context.go(AppRoutes.myEvents),
          ),
          const _SidebarItem(
            icon: Icons.admin_panel_settings,
            label: 'Manage Events',
            active: true,
          ),
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
                  auth.session?.fullname ?? 'Admin User',
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
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_busy, size: 48),
          SizedBox(height: 12),
          Text('No upcoming events to manage.'),
        ],
      ),
    );
  }
}
