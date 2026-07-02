import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../../routes/app_routes.dart';
import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/event.dart';

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

  bool get _isAdmin {
    final userType = ref.read(authControllerProvider).session?.userType;
    return userType?.toLowerCase() == 'admin';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(_fetchEvents);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isUpcoming(AppEvent event) {
    return event.startDatetime.isAfter(DateTime.now());
  }

  List<AppEvent> get _publishedEvents => _events
      .where((e) => e.status.toLowerCase() == 'published' && _isUpcoming(e))
      .toList();
  
  List<AppEvent> get _draftEvents => _events
      .where((e) => e.status.toLowerCase() == 'draft' && _isUpcoming(e))
      .toList();

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

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isWebScreen = kIsWeb || MediaQuery.of(context).size.width > 900;
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
                          'Manage Events',
                          style: TextStyle(
                            fontFamily: 'Fraunces',
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
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
      bottomNavigationBar: isWebScreen
          ? null
          : NavigationBar(
              selectedIndex: 2,
              onDestinationSelected: (index) {
                if (index == 0) context.go(AppRoutes.home);
                if (index == 1) context.go(AppRoutes.myEvents);
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
                NavigationDestination(
                  icon: Icon(Icons.admin_panel_settings),
                  label: 'Manage',
                ),
              ],
            ),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPublished ? Icons.check_circle_outline : Icons.drafts_outlined,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              isPublished ? 'No published events' : 'No draft events',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              isPublished
                  ? 'Publish draft events to see them here.'
                  : 'Create new events or move from published to draft.',
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
              mainAxisExtent: 300,
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
  
  var _isSaving = false;

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
    _virtualUrl = TextEditingController(text: '');
    
    _registrationOpensAt = TextEditingController(text: event?.registrationOpensAt != null 
      ? _formatDateTimeOnly(event!.registrationOpensAt!) 
      : '');
    _registrationClosesAt = TextEditingController(text: event?.registrationClosesAt != null 
      ? _formatDateTimeOnly(event!.registrationClosesAt!) 
      : '');
    
    _thumbnailUrl = TextEditingController(text: event?.thumbnailUrl ?? '');
    _bannerUrl = TextEditingController(text: event?.bannerUrl ?? '');
    
    _capacity = TextEditingController(text: event?.capacity?.toString() ?? '');
    _isFree = true;
    _ticketPrice = TextEditingController(text: '');
    
    // Add listeners for syncing dates and times
    _startDate.addListener(_syncDates);
    _startTime.addListener(_syncTimes);
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
    _virtualUrl.dispose();
    _registrationOpensAt.dispose();
    _registrationClosesAt.dispose();
    _thumbnailUrl.dispose();
    _bannerUrl.dispose();
    _capacity.dispose();
    _ticketPrice.dispose();
    super.dispose();
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
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
                    _buildTextField(_location, 'Location', hint: 'e.g., NITK Surathkal Campus', required: true),
                  
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
                  
                  const SizedBox(height: 32),
                  // ── Actions ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isSaving ? null : () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _isSaving ? null : _save,
                        child: Text(_isSaving ? 'Saving...' : 'Save Event'),
                      ),
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
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
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
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
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
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
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
    return TextFormField(
      controller: _timezone,
      decoration: InputDecoration(
        labelText: 'Timezone',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        suffixIcon: GestureDetector(
          onTap: _showTimezoneSelector,
          child: const Icon(Icons.arrow_drop_down),
        ),
      ),
    );
  }

  Future<void> _showTimezoneSelector() async {
    final zones = _getAvailableTimezones();
    String searchText = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Select Timezone'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search timezone...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (value) {
                    setState(() => searchText = value);
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: zones
                        .where((z) => z.toLowerCase().contains(searchText.toLowerCase()))
                        .map((zone) => ListTile(
                          title: Text(zone),
                          selected: zone == _timezone.text,
                          onTap: () {
                            _timezone.text = zone;
                            Navigator.pop(context);
                          },
                        ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
        'virtual_url': _isVirtual ? _virtualUrl.text.trim() : null,
        'is_full_day': _isFullDay,
        'capacity': _capacity.text.trim().isEmpty ? null : int.tryParse(_capacity.text.trim()),
        'is_free': _isFree,
        'ticket_price': _isFree ? null : double.tryParse(_ticketPrice.text.trim()),
        'thumbnail_url': _thumbnailUrl.text.trim().isEmpty ? null : _thumbnailUrl.text.trim(),
        'banner_url': _bannerUrl.text.trim().isEmpty ? null : _bannerUrl.text.trim(),
        if (_registrationOpensAt.text.trim().isNotEmpty)
          'registration_opens_at': '${_registrationOpensAt.text.trim()}:00$offset',
        if (_registrationClosesAt.text.trim().isNotEmpty)
          'registration_closes_at': '${_registrationClosesAt.text.trim()}:00$offset',
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
  });

  final AppEvent event;
  final bool isDark;
  final ThemeData theme;
  final bool isPublished;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback? onPublish;

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
            Row(
              children: [
                if (!isPublished && onPublish != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPublish,
                      icon: const Icon(Icons.publish_outlined),
                      label: const Text('Publish'),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onView,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('View'),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
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
