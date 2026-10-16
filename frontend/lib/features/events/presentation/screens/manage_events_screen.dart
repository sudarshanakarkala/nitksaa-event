
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/api_error_message.dart';
import '../../../../core/logger/app_logger.dart';
import '../../../../routes/app_routes.dart';
import '../../../../theme/app_palette.dart';
import '../../../../theme/app_text_styles.dart';
import '../../../auth/domain/admin_access.dart';
import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/event.dart';
import '../../domain/event_publish_requirements.dart';
import '../../presentation/providers/events_provider.dart';
import '../widgets/event_card.dart';
import '../../domain/event_time_zone.dart';
import '../../../../shared/widgets/notice.dart';

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

  AdminAccess get _access =>
      ref.read(authControllerProvider).session?.access ?? AdminAccess.none;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      setState(() {}); // Trigger rebuild when search text changes
    });
    Future.microtask(_fetchEvents);
    // "Create Event" on the Events page links here with ?new=1: open the
    // new-event form once the page is up (people who can create events).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final isNew = GoRouterState.of(context).uri.queryParameters['new'] == '1';
      if (isNew && _access.isEventCreator) _showEventForm();
    });
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
    } catch (error, stackTrace) {
      AppLogger.error('Failed to load admin events', error, stackTrace);
      setState(() {
        _isLoading = false;
        _errorMessage = apiErrorMessage(error, action: 'load events');
      });
    }
  }

  Future<void> _publishEvent(AppEvent event) async {
    try {
      final auth = ref.read(authControllerProvider);
      final repo = ref.read(eventsRepositoryProvider);
      
      if (!mounted) return;
      
      // Show loading
      showNotice(context, 'Publishing event...', kind: NoticeKind.info);
      
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
        showNotice(context, '${event.title} published successfully', kind: NoticeKind.success);
      }
    } catch (error, stackTrace) {
      AppLogger.error('Failed to publish event ${event.eventId}', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        showNotice(context, apiErrorMessage(error, action: 'publish the event'), kind: NoticeKind.error);
      }
    }
  }

  Future<void> _unpublishEvent(AppEvent event) async {
    try {
      final auth = ref.read(authControllerProvider);
      final repo = ref.read(eventsRepositoryProvider);
      
      if (!mounted) return;
      
      // Show loading
      showNotice(context, 'Unpublishing event...', kind: NoticeKind.info);
      
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
        showNotice(context, '${event.title} unpublished successfully', kind: NoticeKind.success);
      }
    } catch (error, stackTrace) {
      AppLogger.error('Failed to unpublish event ${event.eventId}', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        showNotice(context, apiErrorMessage(error, action: 'unpublish the event'), kind: NoticeKind.error);
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
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
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
      showNotice(context, 'Deleting event...', kind: NoticeKind.info);
      
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
        showNotice(context, '${event.title} deleted successfully', kind: NoticeKind.success);
      }
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete event ${event.eventId}', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        showNotice(context, apiErrorMessage(error, action: 'delete the event'), kind: NoticeKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isWebScreen = MediaQuery.of(context).size.width >= 900;
    final access = auth.session?.access ?? AdminAccess.none;

    if (!auth.isAuthenticated || !access.isAnyAdmin) {
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
                      style: TextStyle(fontFamily: AppTextStyles.serif, fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Managing events is available only to admins.',
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
                            fontFamily: AppTextStyles.serif,
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
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
                            if (access.isEventCreator)
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
                      labelColor: context.palette.primary,
                      unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                      indicatorColor: context.palette.primary,
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
    );
  }

  Future<void> _showEventForm({AppEvent? event}) async {
    // Creating needs "can create events"; editing needs admin of that event.
    final allowed = event == null
        ? _access.isEventCreator
        : _access.canAdminEvent(event.eventId);
    if (!allowed) return;
    final saved = await showEventFormDialog(context, event: event);
    if (saved) {
      await _fetchEvents();
      // Also refresh the public events list so EventListScreen shows updated data
      if (mounted) {
        ref.read(eventsProvider.notifier).fetchEvents(isRefresh: true);
      }
    }
  }

  String? _createdBy(AppEvent event) =>
      event.createdByLabel(ref.read(authControllerProvider).session?.firebaseUid);

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
              color: context.palette.textMuted,
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
              style: TextStyle(color: context.palette.textMuted),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchEvents,
      child: EventCardGrid(
        admin: true,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: events.length,
        itemBuilder: (context, index) {
          final event = events[index];
          final registrationsPath = '/admin/registrations?event=${event.eventId}';
          return EventCard.forEvent(
            event,
            showAdmin: true,
            mine: event.createdByUid != null &&
                event.createdByUid ==
                    ref.read(authControllerProvider).session?.firebaseUid,
            onView: () => context.push('/events/${event.eventId}'),
            // The capacity bar already shows the count; the footer says
            // who created the event.
            footerNote: _createdBy(event),
            adminActions: [
              EventCardAction(
                label: 'Edit',
                icon: Icons.edit_outlined,
                onSelected: () => _showEventForm(event: event),
              ),
              if (isPublished)
                EventCardAction(
                  label: 'Registrations',
                  icon: Icons.people_outline,
                  onSelected: () => context.push(registrationsPath),
                ),
              if (isPublished)
                EventCardAction(
                  label: 'Unpublish',
                  icon: Icons.unpublished_outlined,
                  onSelected: () => _unpublishEvent(event),
                )
              else
                EventCardAction(
                  label: 'Publish',
                  icon: Icons.publish_outlined,
                  onSelected: () => _publishEvent(event),
                ),
              EventCardAction(
                label: 'Delete',
                icon: Icons.delete_outline,
                destructive: true,
                onSelected: () => _deleteEvent(event),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Timezone options for event creation ────────────────────────────────────

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

/// Opens the create/edit event form. Returns true when the event was saved.
Future<bool> showEventFormDialog(BuildContext context, {AppEvent? event}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _EventFormDialog(event: event),
  );
  return saved == true;
}

/// Sponsors and partners share one list UI in the form; this says which.
class _OrgKind {
  const _OrgKind({
    required this.noun,
    required this.apiPath,
    required this.typeKey,
    required this.idKey,
    required this.types,
  });

  final String noun;
  final String apiPath;
  final String typeKey;
  final String idKey;
  final List<String> types;
}

const _sponsorKind = _OrgKind(
  noun: 'Sponsor',
  apiPath: 'sponsors',
  typeKey: 'sponsor_type',
  idKey: 'sponsor_id',
  types: [
    'TITLE_SPONSOR',
    'GOLD_SPONSOR',
    'SILVER_SPONSOR',
    'BRONZE_SPONSOR',
    'ASSOCIATE_SPONSOR',
  ],
);

const _partnerKind = _OrgKind(
  noun: 'Partner',
  apiPath: 'partners',
  typeKey: 'partner_type',
  idKey: 'partner_id',
  types: [
    'COMMUNITY_PARTNER',
    'KNOWLEDGE_PARTNER',
    'MEDIA_PARTNER',
    'VENUE_PARTNER',
    'TECHNOLOGY_PARTNER',
    'ECOSYSTEM_PARTNER',
    'HIRING_PARTNER',
  ],
);

/// The optional parts of an event, added with "+" on the edit form only when
/// the event needs them (EVENT_FORM_REDESIGN.md). A group is shown when it
/// holds data or was just added; removing it clears its data on save.
enum _Group {
  images('Images'),
  registrationDates('Registration dates'),
  guests('Guests'),
  speakers('Speakers'),
  agenda('Agenda'),
  sponsors('Sponsors & partners');

  const _Group(this.label);
  final String label;
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

  /// Guests one registrant may bring (0 = none, up to 4).
  int _maxGuests = 0;
  bool _isFree = true;
  late final TextEditingController _ticketPrice;
  
  // Speakers & Sessions
  late List<Map<String, String>> _speakers;
  late List<Map<String, String>> _sessions;
  
  // Sponsors and partners. Each entry keeps its server id (when it has
  // one) under the kind's idKey, so saving can update, add and remove.
  late List<Map<String, String>> _sponsors;
  List<Map<String, String>> _partners = [];

  /// Ids as loaded, to know which were removed. Null until loaded (new
  /// events have none); if loading failed, saving leaves them untouched.
  Set<String>? _loadedSponsorIds;
  Set<String>? _loadedPartnerIds;
  bool _orgsLoading = false;
  bool _orgsLoadFailed = false;
  
  // Fee tiers: they break down the ticket price, which is their total.
  late List<Map<String, String>> _fees;

  // Speakers, sessions and fee tiers load from (and save to) their own
  // endpoint when editing. If loading failed, saving leaves them alone.
  bool _detailsLoading = false;
  bool _detailsLoadFailed = false;
  
  var _isSaving = false;

  /// Groups added with "+" in this sitting (see [_Group]).
  final _addedGroups = <_Group>{};

  /// The timezone picker shows once asked for, or for an event not in IST.
  var _showTimezone = false;

  /// The form as last saved or opened, to tell whether closing loses
  /// anything. Null until speakers, sponsors and the rest have loaded.
  String? _baseline;
  
  // Location search state
  final _locationSearchController = TextEditingController();

  /// The location field, so its "required" error can clear once a place is
  /// chosen (it is only checked again on Save otherwise).
  final _locationFieldKey = GlobalKey<FormFieldState<String>>();

  void _recheckLocationField() {
    final field = _locationFieldKey.currentState;
    if (field != null && field.hasError) field.validate();
  }
  var _locationSuggestions = <Map<String, String>>[];
  var _isSearchingLocation = false;
  var _locationSelected = false;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    
    _title = TextEditingController(text: event?.title ?? '');
    _description = TextEditingController(text: event?.description ?? '');
    
    // Times are shown and typed in the event's own timezone, wherever the
    // person editing is.
    final zone = event?.timezone ?? 'Asia/Kolkata';
    DateTime inZone(DateTime d) => EventTimeZone.wallTime(d, zone) ?? d;
    final startDt =
        event != null ? inZone(event.startDatetime) : DateTime.now();
    var endDt = event?.endDatetime != null
        ? inZone(event!.endDatetime!)
        : startDt.add(const Duration(hours: 2));
    // A full-day event is saved ending at midnight after its last day.
    if ((event?.isFullDay ?? false) && endDt.isAfter(startDt)) {
      endDt = endDt.subtract(const Duration(days: 1));
    }
    
    _startDate = TextEditingController(text: _formatDateOnly(startDt));
    _endDate = TextEditingController(text: _formatDateOnly(endDt));
    _startTime = TextEditingController(text: _formatTimeFromDateTime(startDt));
    _endTime = TextEditingController(text: _formatTimeFromDateTime(endDt));
    _timezone = TextEditingController(text: event?.timezone ?? 'Asia/Kolkata');
    _showTimezone = _timezone.text != 'Asia/Kolkata';
    _isFullDay = event?.isFullDay ?? false;
    
    _isVirtual = event?.isVirtual ?? false;
    _location = TextEditingController(text: event?.locationText ?? '');
    _locationMapsUrl = TextEditingController(text: event?.locationMapsUrl ?? '');
    _locationSearchController.text = event?.locationText ?? '';
    _locationSelected = event?.locationText != null && event!.locationText!.isNotEmpty;
    _virtualUrl = TextEditingController(text: event?.virtualUrl ?? '');
    
    _registrationOpensAt = TextEditingController(text: event?.registrationOpensAt != null 
      ? _formatDateTimeOnly(inZone(event!.registrationOpensAt!)) 
      : '');
    // Closing when the event starts is the default (saved when the field is
    // empty), so that time shows as an empty field.
    final closes = event?.registrationClosesAt;
    final closesAtStart = event != null &&
        closes != null &&
        closes.difference(event.startDatetime).inMinutes.abs() < 1;
    _registrationClosesAt = TextEditingController(text: closes != null && !closesAtStart
      ? _formatDateTimeOnly(inZone(closes))
      : '');
    
    _thumbnailUrl = TextEditingController(text: event?.thumbnailUrl ?? '');
    _bannerUrl = TextEditingController(text: event?.bannerUrl ?? '');
    
    _capacity = TextEditingController(text: event?.capacity?.toString() ?? '');
    _maxGuests = (event?.maxGuests ?? 0).clamp(0, 4);
    _isFree = event?.isFree ?? true;
    _ticketPrice = TextEditingController(text: event?.ticketPrice?.toString() ?? '');
    
    // Initialize speakers (convert EventPerson to Map)
    _speakers = event?.speakers.map((sp) => {
      'fullname': sp.fullname,
      'title': sp.title ?? '',
      'organisation': sp.organisation ?? '',
    }).toList() ?? [];
    
    // Sponsors and partners come from their own endpoints when editing.
    _sponsors = [];
    if (event != null) {
      _orgsLoading = true;
      _detailsLoading = true;
      Future.microtask(() => _loadOrgs(event.eventId));
      Future.microtask(() => _loadDetails(event.eventId));
    } else {
      _loadedSponsorIds = {};
      _loadedPartnerIds = {};
    }
    
    // Initialize fees
    _fees = [];
    
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
        'start_time': _formatDateTimeOnly(inZone(sess.startDatetime)),
        'end_time': sess.endDatetime != null ? _formatDateTimeOnly(inZone(sess.endDatetime!)) : '',
      };
    }).toList() ?? [];
    
    // Any change rebuilds, so groups and the unsaved-changes check stay current.
    for (final c in _textFields) {
      c.addListener(_onFieldChanged);
    }
    _setBaselineWhenLoaded();
  }

  List<TextEditingController> get _textFields => [
        _title, _description, _startDate, _endDate, _startTime, _endTime,
        _timezone, _location, _locationMapsUrl, _virtualUrl,
        _registrationOpensAt, _registrationClosesAt, _thumbnailUrl, _bannerUrl,
        _capacity,
      ];

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  /// Everything the form would save, as one string.
  String _signature() => jsonEncode([
        for (final c in _textFields) c.text,
        _isFullDay, _isVirtual, _maxGuests, _isFree,
        _speakers, _sessions, _fees, _sponsors, _partners,
      ]);

  /// Takes the "nothing changed yet" snapshot once everything has loaded.
  void _setBaselineWhenLoaded() {
    if (_baseline != null || _detailsLoading || _orgsLoading) return;
    _baseline = _signature();
  }

  bool get _hasUnsavedChanges => _baseline != null && _signature() != _baseline;

  /// Cancel, ✕, Esc or a click outside: asks first if anything would be lost.
  Future<void> _close() async {
    if (_hasUnsavedChanges) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard your changes?'),
          content: const Text('You have changes that aren\'t saved yet.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              key: const ValueKey('event-form-discard'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context, false);
  }

  bool _hasData(_Group group) => switch (group) {
        _Group.images =>
          _thumbnailUrl.text.trim().isNotEmpty || _bannerUrl.text.trim().isNotEmpty,
        _Group.registrationDates => _registrationOpensAt.text.trim().isNotEmpty ||
            _registrationClosesAt.text.trim().isNotEmpty,
        _Group.guests => _maxGuests > 0,
        _Group.speakers => _speakers.isNotEmpty,
        _Group.agenda => _sessions.isNotEmpty,
        _Group.sponsors => _sponsors.isNotEmpty || _partners.isNotEmpty,
      };

  bool _shows(_Group group) => _addedGroups.contains(group) || _hasData(group);

  /// Removes a group; if it holds data, asks first. The data goes on save.
  Future<void> _removeGroup(_Group group) async {
    if (_hasData(group)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remove ${group.label.toLowerCase()}?'),
          content: Text(switch (group) {
            _Group.images => 'The thumbnail and banner will be removed when you save.',
            _Group.registrationDates => 'Registration will go back to opening on '
                'publish and closing at the start, when you save.',
            _Group.guests => 'People won\'t be able to bring guests once you save.',
            _Group.speakers => 'All speakers will be removed from this event when you save.',
            _Group.agenda => 'All sessions will be removed from this event when you save.',
            _Group.sponsors =>
              'All sponsors and partners will be removed from this event when you save.',
          }),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('event-group-remove-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _addedGroups.remove(group);
      switch (group) {
        case _Group.images:
          _thumbnailUrl.clear();
          _bannerUrl.clear();
        case _Group.registrationDates:
          _registrationOpensAt.clear();
          _registrationClosesAt.clear();
        case _Group.guests:
          _maxGuests = 0;
        case _Group.speakers:
          _speakers.clear();
          // Sessions name their speaker; there are none now.
          for (final session in _sessions) {
            session['speaker'] = '';
          }
        case _Group.agenda:
          _sessions.clear();
        case _Group.sponsors:
          _sponsors.clear();
          _partners.clear();
      }
    });
  }

  /// One moment from a date field and a time field.
  DateTime? _fieldsToDateTime(TextEditingController date, TextEditingController time) {
    final d = _parseDate(date.text);
    if (d == null) return null;
    final t = _parseTime(time.text) ?? const TimeOfDay(hour: 0, minute: 0);
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  /// Moving the start moves the end with it, so the event keeps its length.
  /// [apply] changes the start fields.
  void _moveStart(void Function() apply) {
    final oldStart = _fieldsToDateTime(_startDate, _startTime);
    final oldEnd = _fieldsToDateTime(_endDate, _endTime);
    apply();
    final newStart = _fieldsToDateTime(_startDate, _startTime);
    if (oldStart == null || newStart == null) return;
    final length = (oldEnd != null && !oldEnd.isBefore(oldStart))
        ? oldEnd.difference(oldStart)
        : const Duration(hours: 3);
    final newEnd = newStart.add(length);
    _endDate.text = _formatDateOnly(newEnd);
    _endTime.text = _formatTimeFromDateTime(newEnd);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
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
    super.dispose();
  }

  /// Labels of the fields still missing to save, e.g. ['Capacity']: the
  /// publish rule (`_validate_for_publish` in
  /// backend/app/services/events_service.py, see
  /// event_publish_requirements.dart).
  List<String> _missingRequiredFields() => missingPublishFields(
        title: _title.text,
        startDate: _startDate.text,
        endDate: _endDate.text,
        timezone: _timezone.text,
        capacity: _capacity.text,
        isVirtual: _isVirtual,
        location: _location.text,
        virtualUrl: _virtualUrl.text,
      );

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.event != null;
    final theme = Theme.of(context);

    return PopScope(
      // Esc, back and a click outside come here first when changes would
      // be lost.
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_isSaving) _close();
      },
      child: Dialog(
        child: SizedBox(
          width: MediaQuery.of(context).size.width > 800 ? 700 : null,
          height: MediaQuery.of(context).size.height * 0.9,
          child: Scaffold(
            appBar: AppBar(
              title: Text(isEditing ? 'Edit event' : 'Create event'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close',
                onPressed: _isSaving ? null : _close,
              ),
            ),
            body: Form(
              key: _formKey,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildEssentials(),
                          const SizedBox(height: 32),
                          if (isEditing)
                            _buildGroups()
                          else
                            Text(
                              'After saving, open Edit event to add images, '
                              'guests, speakers, an agenda, sponsors and more.',
                              style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Bottom actions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      border: Border(top: BorderSide(color: context.palette.border)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _isSaving ? null : _close,
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const ValueKey('event-form-save'),
                          onPressed: _isSaving ? null : _save,
                          child: Text(_isSaving
                              ? 'Saving...'
                              : isEditing
                                  ? 'Save'
                                  : 'Save draft'),
                        ),
                      ],
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

  /// What every event needs: what, when, where, how many, and the price.
  Widget _buildEssentials() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTextField(_title, 'Event Title', hint: 'e.g., NITK Alumni Meetup', required: true),
        const SizedBox(height: 12),
        _buildTextField(
          _description,
          'Description (optional)',
          hint: 'What the event is about, who it is for',
          maxLines: 4,
        ),

        const SizedBox(height: 28),
        _buildSectionHeader('When'),
        const SizedBox(height: 12),
        _buildToggleField('Full Day Event', _isFullDay, (val) {
          setState(() => _isFullDay = val);
        }),
        const SizedBox(height: 12),
        // Full day: dates only (an event can run several days).
        if (_isFullDay)
          Row(
            children: [
              Expanded(child: _buildDateField(_startDate, 'Start Date', required: true)),
              const SizedBox(width: 12),
              Expanded(child: _buildDateField(_endDate, 'End Date', required: true)),
            ],
          )
        else
          Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildDateField(_startDate, 'Start Date', required: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTimeField(_startTime, 'Start Time', required: true)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildDateField(_endDate, 'End Date', required: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTimeField(_endTime, 'End Time', required: true)),
                ],
              ),
            ],
          ),
        const SizedBox(height: 8),
        if (_showTimezone)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _buildTimezoneDropdown(),
          )
        else
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Times are in ${_timezone.text}.',
                style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
              ),
              TextButton(
                key: const ValueKey('event-timezone-change'),
                onPressed: () => setState(() => _showTimezone = true),
                child: const Text('Change'),
              ),
            ],
          ),

        const SizedBox(height: 28),
        _buildSectionHeader('Where'),
        const SizedBox(height: 12),
        _buildToggleField('Online event', _isVirtual, (val) {
          setState(() => _isVirtual = val);
        }),
        const SizedBox(height: 12),
        if (_isVirtual)
          _buildTextField(_virtualUrl, 'Meeting URL', hint: 'e.g., https://zoom.us/j/...', required: true)
        else
          _buildLocationPicker(),

        const SizedBox(height: 28),
        _buildSectionHeader('Seats and price'),
        const SizedBox(height: 12),
        _buildTextField(
          _capacity,
          'Capacity',
          hint: 'Maximum number of attendees',
          required: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: validateCapacity,
        ),
        const SizedBox(height: 12),
        _buildToggleField('Free Event', _isFree, (val) {
          setState(() => _isFree = val);
        }),
        if (!_isFree) ...[
          const SizedBox(height: 12),
          Text(
            'List what attendees pay. A single price is one line (for example '
            'Registration ₹599). The total is the ticket price checkout charges.',
            style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
          ),
          const SizedBox(height: 16),
          _buildFeesSection(),
        ],
      ],
    );
  }

  /// The optional groups this event has, then "+" for the rest.
  Widget _buildGroups() {
    final shown = _Group.values.where(_shows).toList();
    final hidden = _Group.values.where((g) => !_shows(g)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in shown) ...[
          _buildGroup(group),
          const SizedBox(height: 28),
        ],
        if (hidden.isNotEmpty) ...[
          Text(
            'Add more only if this event needs it:',
            style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final group in hidden)
                OutlinedButton.icon(
                  key: ValueKey('event-add-${group.name}'),
                  onPressed: () => setState(() => _addedGroups.add(group)),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(group.label),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildGroup(_Group group) {
    return Column(
      key: ValueKey('event-group-${group.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildSectionHeader(group.label)),
            TextButton(
              key: ValueKey('event-remove-${group.name}'),
              onPressed: () => _removeGroup(group),
              child: const Text('Remove'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        switch (group) {
          _Group.images => Column(
              children: [
                _buildTextField(_thumbnailUrl, 'Thumbnail URL', hint: 'Square image URL for event cards'),
                const SizedBox(height: 12),
                _buildTextField(_bannerUrl, 'Banner URL', hint: 'Wide image URL for event header'),
              ],
            ),
          _Group.registrationDates => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildDateTimeField(
                        _registrationOpensAt,
                        'Registration Opens',
                        hint: 'When published',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDateTimeField(
                        _registrationClosesAt,
                        'Registration Closes',
                        hint: 'When the event starts',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Leave a date empty for the usual: opens when the event is '
                  'published, closes when it starts.',
                  style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
                ),
              ],
            ),
          _Group.guests => DropdownButtonFormField<int>(
              key: const ValueKey('event-max-guests'),
              initialValue: _maxGuests,
              decoration: const InputDecoration(
                labelText: 'Guests per registration',
                helperText: 'How many guests each person may bring. Guests take seats too.',
              ),
              items: [
                for (var n = 0; n <= 4; n++)
                  DropdownMenuItem(
                    value: n,
                    child: Text(n == 0 ? 'None' : '$n'),
                  ),
              ],
              onChanged: (value) => setState(() => _maxGuests = value ?? 0),
            ),
          _Group.speakers => _buildSpeakersSection(),
          _Group.agenda => _buildSessionsSection(),
          _Group.sponsors => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sponsors', style: TextStyle(fontSize: 13, color: context.palette.textSecondary)),
                const SizedBox(height: 8),
                _buildSponsorsSection(),
                const SizedBox(height: 20),
                Text('Partners', style: TextStyle(fontSize: 13, color: context.palette.textSecondary)),
                const SizedBox(height: 8),
                _buildPartnersSection(),
              ],
            ),
        },
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
    List<TextInputFormatter>? inputFormatters,
    FormFieldValidator<String>? validator,
  }) {
    final displayLabel = required ? '$label *' : label;
    return TextFormField(
      controller: controller,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: displayLabel,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      maxLines: maxLines,
      minLines: maxLines == 1 ? 1 : null,
      keyboardType: keyboardType,
      validator: validator ??
          (required
              ? (value) => value == null || value.trim().isEmpty ? '$label is required' : null
              : null),
    );
  }

  // Date and time fields are read-only: a click anywhere opens the picker,
  // and nothing changes unless something is picked. Past dates are allowed
  // (an old draft can be moved to a new date).

  /// True while a picker is open, so extra clicks don't stack more pickers.
  bool _picking = false;

  Future<T?> _onePicker<T>(Future<T?> Function() open) async {
    if (_picking) return null;
    _picking = true;
    try {
      return await open();
    } finally {
      _picking = false;
    }
  }

  Widget _buildDateField(TextEditingController controller, String label, {bool required = false}) {
    final displayLabel = required ? '$label *' : label;
    Future<void> pick() async {
      final picked = await _onePicker(() => showDatePicker(
        context: context,
        initialDate: _parseDate(controller.text) ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      ));
      if (picked == null) return;
      void apply() => controller.text = _formatDateOnly(picked);
      identical(controller, _startDate) ? _moveStart(apply) : apply();
    }

    return _PickerField(
      controller: controller,
      label: displayLabel,
      icon: Icons.calendar_today,
      onPick: pick,
      validator: required
          ? (value) => value == null || value.trim().isEmpty ? '$label is required' : null
          : null,
    );
  }

  Widget _buildTimeField(TextEditingController controller, String label, {bool required = false}) {
    final displayLabel = required ? '$label *' : label;
    Future<void> pick() async {
      final picked = await _onePicker(() => showTimePicker(
        context: context,
        initialTime: _parseTime(controller.text) ?? TimeOfDay.now(),
      ));
      if (picked == null) return;
      void apply() => controller.text = _formatTimeOfDay(picked);
      identical(controller, _startTime) ? _moveStart(apply) : apply();
    }

    return _PickerField(
      controller: controller,
      label: displayLabel,
      icon: Icons.access_time,
      onPick: pick,
      validator: required
          ? (value) => value == null || value.trim().isEmpty ? '$label is required' : null
          : null,
    );
  }

  Widget _buildDateTimeField(TextEditingController controller, String label, {String? hint}) {
    Future<void> pick() async {
      if (_picking) return;
      final current = DateTime.tryParse(controller.text.trim()) ?? DateTime.now();
      final date = await _onePicker(() => showDatePicker(
        context: context,
        initialDate: current,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      ));
      if (date == null || !mounted) return;
      final time = await _onePicker(() => showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(current),
      ));
      if (time == null) return;
      setState(() {
        controller.text = _formatDateTimeOnly(
          DateTime(date.year, date.month, date.day, time.hour, time.minute),
        );
      });
    }

    return _PickerField(
      controller: controller,
      label: label,
      hint: hint,
      icon: Icons.schedule,
      onPick: pick,
      // These are optional, so they can be cleared.
      onClear: () => setState(controller.clear),
    );
  }

  Widget _buildTimezoneDropdown() {
    final zones = _getCommonTimezones();
    final currentValue = _timezone.text.isEmpty ? zones.first : _timezone.text;
    
    return DropdownButtonFormField<String>(
      initialValue: zones.contains(currentValue) ? currentValue : zones.first,
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
              style: TextStyle(fontSize: 13, color: context.palette.textSecondary),
            ),
          )
        else
          ...List.generate(_speakers.length, (index) {
            final speaker = _speakers[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: context.palette.border),
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
                            style: TextStyle(fontSize: 12, color: context.palette.textMuted),
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
                          icon: Icon(Icons.delete, size: 18, color: context.palette.error),
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
              style: TextStyle(fontSize: 13, color: context.palette.textSecondary),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: context.palette.border),
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
                      horizontalInside: BorderSide(color: context.palette.border, width: 1),
                    ),
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          color: context.palette.primary.withValues(alpha: 0.08),
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
                                    icon: Icon(Icons.delete, size: 18, color: context.palette.error),
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
                          color: context.palette.primary.withValues(alpha: 0.12),
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
              style: TextStyle(fontSize: 13, color: context.palette.textSecondary),
            ),
          )
        else
          ...List.generate(_sessions.length, (index) {
            final session = _sessions[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: context.palette.border),
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
                            style: TextStyle(fontSize: 12, color: context.palette.textMuted),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${session['start_time'] ?? ''} - ${session['end_time'] ?? ''}',
                            style: TextStyle(fontSize: 12, color: context.palette.textMuted),
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
                          icon: Icon(Icons.delete, size: 18, color: context.palette.error),
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
              style: TextStyle(fontSize: 12, color: context.palette.warning),
            ),
          ),
      ],
    );
  }

  /// Speakers, sessions and fee tiers as saved, with their server ids.
  Future<void> _loadDetails(int eventId) async {
    final token = ref.read(authControllerProvider).session?.accessToken;
    if (token == null) return;
    try {
      final data = await ref.read(eventsRepositoryProvider).getEventDetails(eventId, token);
      List<Map<String, dynamic>> list(String key) =>
          (data[key] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
      String text(Object? v) => v?.toString() ?? '';
      if (!mounted) return;
      setState(() {
        _speakers = [
          for (final r in list('speakers'))
            {
              'person_id': text(r['person_id']),
              'fullname': text(r['fullname']),
              'title': text(r['title']),
              'organisation': text(r['organisation']),
            },
        ];
        _sessions = [
          for (final r in list('sessions'))
            {
              'session_id': text(r['session_id']),
              'title': text(r['title']),
              'speaker': text(r['speaker_name']),
              'start_time': _detailsTime(r['start_datetime'], _timezone.text),
              'end_time': _detailsTime(r['end_datetime'], _timezone.text),
            },
        ];
        _fees = [
          for (final r in list('fees'))
            {
              'fee_name': text(r['name']),
              'fee_type': text(r['fee_type']).toUpperCase(),
              'fee_amount': text(r['amount']),
            },
        ];
        // Paid events made before fees saved: show their price as one line,
        // so saving keeps it.
        final price = double.tryParse(_ticketPrice.text.trim()) ?? 0;
        if (_fees.isEmpty && !_isFree && price > 0) {
          _fees = [
            {'fee_name': 'Registration', 'fee_type': 'PARTICIPATION', 'fee_amount': _ticketPrice.text.trim()},
          ];
        }
        _detailsLoading = false;
        _setBaselineWhenLoaded();
      });
    } catch (error, stackTrace) {
      AppLogger.error('Could not load speakers, sessions and fees', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _detailsLoading = false;
        _detailsLoadFailed = true;
        // Still let a paid event be saved at its current price.
        final price = double.tryParse(_ticketPrice.text.trim()) ?? 0;
        if (_fees.isEmpty && !_isFree && price > 0) {
          _fees = [
            {'fee_name': 'Registration', 'fee_type': 'PARTICIPATION', 'fee_amount': _ticketPrice.text.trim()},
          ];
        }
        _setBaselineWhenLoaded();
      });
    }
  }

  /// "yyyy-MM-dd HH:mm" in the event's timezone [zone], the format the
  /// session dialog uses.
  static String _detailsTime(Object? iso, String zone) {
    final d = DateTime.tryParse(iso?.toString() ?? '');
    if (d == null) return '';
    return _formatDateTimeOnly(EventTimeZone.wallTime(d, zone) ?? d.toLocal());
  }

  /// [wall] (a date and time typed in the form) in the event's timezone, as
  /// ISO 8601 with the offset for that date, summer time included.
  String _iso(DateTime wall) => EventTimeZone.iso(wall, _timezone.text.trim())!;

  /// [_iso] of a "yyyy-MM-dd HH:mm" field; null when it is empty.
  String? _isoOfField(String text) {
    final wall = DateTime.tryParse(text.trim().replaceFirst(' ', 'T'));
    return wall == null ? null : _iso(wall);
  }

  /// Saves speakers, sessions and fee tiers after the event is saved.
  /// Returns false if that failed.
  Future<bool> _saveDetails(int eventId, String token) async {
    if (_detailsLoadFailed || _detailsLoading) return true; // nothing loaded, nothing changed
    try {
      await ref.read(eventsRepositoryProvider).putEventDetails(eventId, token, {
        'speakers': [
          for (final sp in _speakers)
            {
              if (int.tryParse(sp['person_id'] ?? '') != null)
                'person_id': int.parse(sp['person_id']!),
              'fullname': sp['fullname'] ?? '',
              'title': sp['title'],
              'organisation': sp['organisation'],
            },
        ],
        'sessions': [
          for (final se in _sessions)
            {
              if (int.tryParse(se['session_id'] ?? '') != null)
                'session_id': int.parse(se['session_id']!),
              'title': se['title'] ?? '',
              'speaker_name': se['speaker'],
              'start_datetime': _isoOfField(se['start_time'] ?? ''),
              'end_datetime': _isoOfField(se['end_time'] ?? ''),
            },
        ],
        'fees': [
          if (!_isFree)
            for (final f in _fees)
            {
              'name': f['fee_name'] ?? '',
              'fee_type': (f['fee_type'] ?? 'PARTICIPATION').toLowerCase(),
              'amount': double.tryParse((f['fee_amount'] ?? '').trim()) ?? 0,
            },
        ],
      });
      return true;
    } catch (error, stackTrace) {
      AppLogger.error('Could not save speakers, sessions and fees', error, stackTrace);
      return false;
    }
  }

  Future<void> _loadOrgs(int eventId) async {
    final token = ref.read(authControllerProvider).session?.accessToken;
    if (token == null) return;
    final repo = ref.read(eventsRepositoryProvider);
    try {
      final results = await Future.wait([
        repo.listEventOrgs(eventId, _sponsorKind.apiPath, token),
        repo.listEventOrgs(eventId, _partnerKind.apiPath, token),
      ]);
      List<Map<String, String>> toRows(List<Map<String, dynamic>> raw, _OrgKind kind) {
        final rows = [...raw]
          ..sort((a, b) => ((a['display_order'] as num?) ?? 0)
              .compareTo((b['display_order'] as num?) ?? 0));
        return rows
            .map((r) => <String, String>{
                  kind.idKey: '${r[kind.idKey]}',
                  'name': r['name']?.toString() ?? '',
                  kind.typeKey: r[kind.typeKey]?.toString() ?? kind.types.first,
                  'logo_url': r['logo_url']?.toString() ?? '',
                  'website_url': r['website_url']?.toString() ?? '',
                })
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _sponsors = toRows(results[0], _sponsorKind);
        _partners = toRows(results[1], _partnerKind);
        _loadedSponsorIds = _sponsors.map((r) => r[_sponsorKind.idKey]!).toSet();
        _loadedPartnerIds = _partners.map((r) => r[_partnerKind.idKey]!).toSet();
        _orgsLoading = false;
        _setBaselineWhenLoaded();
      });
    } catch (error, stackTrace) {
      AppLogger.error('Could not load sponsors and partners', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _orgsLoading = false;
        _orgsLoadFailed = true;
        _setBaselineWhenLoaded();
      });
    }
  }

  /// Saves sponsors and partners through their endpoints after the event
  /// itself is saved. Returns false if any change failed.
  Future<bool> _saveOrgs(int eventId, String token) async {
    if (_orgsLoadFailed) return true; // nothing was loaded, so nothing changed
    final repo = ref.read(eventsRepositoryProvider);
    var ok = true;
    Future<void> sync(
      List<Map<String, String>> rows,
      Set<String>? loaded,
      _OrgKind kind,
    ) async {
      final kept = <String>{};
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final body = <String, dynamic>{
          'name': row['name'],
          kind.typeKey: row[kind.typeKey],
          'logo_url': (row['logo_url'] ?? '').isEmpty ? null : row['logo_url'],
          'website_url': (row['website_url'] ?? '').isEmpty ? null : row['website_url'],
          'display_order': i,
        };
        final id = row[kind.idKey];
        try {
          if (id != null && id.isNotEmpty) {
            kept.add(id);
            await repo.updateEventOrg(eventId, kind.apiPath, int.parse(id), body, token);
          } else {
            await repo.createEventOrg(eventId, kind.apiPath, body, token);
          }
        } catch (error, stackTrace) {
          ok = false;
          AppLogger.error('Saving ${kind.noun.toLowerCase()} failed', error, stackTrace);
        }
      }
      for (final id in (loaded ?? const <String>{}).difference(kept)) {
        try {
          await repo.deleteEventOrg(eventId, kind.apiPath, int.parse(id), token);
        } catch (error, stackTrace) {
          ok = false;
          AppLogger.error('Removing ${kind.noun.toLowerCase()} failed', error, stackTrace);
        }
      }
    }

    await sync(_sponsors, _loadedSponsorIds, _sponsorKind);
    await sync(_partners, _loadedPartnerIds, _partnerKind);
    return ok;
  }

  Widget _buildSponsorsSection() => _buildOrgSection(_sponsors, _sponsorKind);

  Widget _buildPartnersSection() => _buildOrgSection(_partners, _partnerKind);

  Widget _buildOrgSection(List<Map<String, String>> items, _OrgKind kind) {
    if (_orgsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_orgsLoadFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          "Couldn't load ${kind.noun.toLowerCase()}s, so they can't be changed "
          'right now. Saving the event leaves them as they are.',
          style: TextStyle(fontSize: 13, color: context.palette.error),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No ${kind.noun.toLowerCase()}s added yet',
              style: TextStyle(fontSize: 13, color: context.palette.textSecondary),
            ),
          )
        else
          ...List.generate(items.length, (index) {
            final item = items[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: context.palette.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Column(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          onPressed: index > 0
                              ? () => setState(() {
                                    final temp = items[index];
                                    items[index] = items[index - 1];
                                    items[index - 1] = temp;
                                  })
                              : null,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 16),
                          padding: EdgeInsets.zero,
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 16),
                          onPressed: index < items.length - 1
                              ? () => setState(() {
                                    final temp = items[index];
                                    items[index] = items[index + 1];
                                    items[index + 1] = temp;
                                  })
                              : null,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 16),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _orgTypeLabel(item[kind.typeKey] ?? ''),
                            style: TextStyle(fontSize: 12, color: context.palette.textMuted),
                          ),
                          if ((item['logo_url'] ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Logo: ${item['logo_url']}',
                                style: TextStyle(fontSize: 11, color: context.palette.textMuted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _showOrgDialog(items, kind, index),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          icon: Icon(Icons.delete, size: 18, color: context.palette.error),
                          onPressed: () => setState(() => items.removeAt(index)),
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
          onPressed: () => _showOrgDialog(items, kind, null),
          icon: const Icon(Icons.add),
          label: Text('Add ${kind.noun}'),
        ),
      ],
    );
  }

  /// "TITLE_SPONSOR" → "Title Sponsor", "COMMUNITY_PARTNER" → "Community Partner".
  String _orgTypeLabel(String type) => type
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');

  void _showOrgDialog(List<Map<String, String>> items, _OrgKind kind, int? editIndex) {
    final existing = editIndex != null ? items[editIndex] : null;
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final logoUrlCtrl = TextEditingController(text: existing?['logo_url'] ?? '');
    final websiteUrlCtrl = TextEditingController(text: existing?['website_url'] ?? '');
    var selectedType = existing?[kind.typeKey] ?? kind.types.first;
    if (!kind.types.contains(selectedType)) selectedType = kind.types.first;

    InputDecoration field(String label, [String? hint]) => InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final canSave = nameCtrl.text.trim().isNotEmpty;
          return AlertDialog(
            title: Text('${editIndex == null ? 'Add' : 'Edit'} ${kind.noun}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: field('${kind.noun} Name *'),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: field('${kind.noun} Type *'),
                    items: kind.types
                        .map((type) => DropdownMenuItem(value: type, child: Text(_orgTypeLabel(type))))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => selectedType = value ?? kind.types.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: logoUrlCtrl,
                    decoration: field('Logo URL', 'https://example.com/logo.png'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: websiteUrlCtrl,
                    decoration: field('Website URL', 'https://example.com'),
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
                onPressed: canSave
                    ? () {
                        setState(() {
                          final row = <String, String>{
                            if (existing?[kind.idKey] != null) kind.idKey: existing![kind.idKey]!,
                            'name': nameCtrl.text.trim(),
                            kind.typeKey: selectedType,
                            'logo_url': logoUrlCtrl.text.trim(),
                            'website_url': websiteUrlCtrl.text.trim(),
                          };
                          if (editIndex == null) {
                            items.add(row);
                          } else {
                            items[editIndex] = row;
                          }
                        });
                        Navigator.pop(context);
                      }
                    : null,
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
                      _speakers[editIndex] = {..._speakers[editIndex], ...speaker};
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
                    initialValue: selectedType,
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
                    initialValue: selectedSpeaker.isEmpty ? null : selectedSpeaker,
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
                    showNotice(context, clashError, kind: NoticeKind.warning);
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
                      _sessions[editIndex] = {..._sessions[editIndex], ...session};
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
          key: _locationFieldKey,
          controller: _locationSearchController,
          decoration: InputDecoration(
            labelText: 'Search Location *',
            hintText: 'Type a place name or address...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _locationSelected
                ? IconButton(
                    icon: Icon(Icons.clear, color: context.palette.success),
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
                  _recheckLocationField();
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
              border: Border.all(color: context.palette.border),
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _locationSuggestions.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: context.palette.border),
              itemBuilder: (context, index) {
                final suggestion = _locationSuggestions[index];
                return ListTile(
                  dense: true,
                  leading: Icon(Icons.place, size: 18, color: context.palette.primary),
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
              color: context.palette.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.palette.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: context.palette.primary, size: 20),
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
    _recheckLocationField();
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

  /// Checks every field; if any is wrong, scrolls to the topmost one so the
  /// admin sees it. Returns whether all were fine.
  bool _checkFieldsAndShowFirstProblem() {
    final invalid = _formKey.currentState?.validateGranularly() ?? const {};
    if (invalid.isEmpty) return true;
    BuildContext? first;
    double? top;
    for (final field in invalid) {
      final box = field.context.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (top == null || y < top) {
        top = y;
        first = field.context;
      }
    }
    if (first != null) {
      Scrollable.ensureVisible(
        first,
        alignment: 0.2,
        duration: const Duration(milliseconds: 300),
      );
    }
    return false;
  }

  Future<void> _save() async {
    final missing = _missingRequiredFields();
    final fieldsOk = _checkFieldsAndShowFirstProblem();
    if (missing.isNotEmpty) {
      showNotice(context, 'Please fill in: ${missing.join(', ')}', kind: NoticeKind.warning);
      return;
    }
    if (!fieldsOk) return;

    // Parse and validate dates
    final startDate = _parseDate(_startDate.text);
    final endDate = _parseDate(_endDate.text);

    if (startDate == null || endDate == null) {
      if (mounted) {
        showNotice(context, 'Please enter valid dates', kind: NoticeKind.warning);
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
          showNotice(context, 'Please enter valid times', kind: NoticeKind.warning);
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
        showNotice(context, 'End time must be after start time', kind: NoticeKind.warning);
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
            showNotice(context, 'Registration closes must be on or after registration opens', kind: NoticeKind.warning);
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          showNotice(context, 'Invalid registration date format', kind: NoticeKind.warning);
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
              showNotice(context, 'Session "${session['title']}" end time must be after start time', kind: NoticeKind.warning);
            }
            return;
          }

          if (sessionStart.isBefore(startDateTime) || sessionEnd.isAfter(endDateTime)) {
            if (mounted) {
              showNotice(context, 'Session "${session['title']}" must be within event timeframe '
                    '(${_formatDateTimeOnly(startDateTime)} - ${_formatDateTimeOnly(endDateTime)})', kind: NoticeKind.warning);
            }
            return;
          }
        } catch (e) {
          if (mounted) {
            showNotice(context, 'Invalid session date/time format', kind: NoticeKind.warning);
          }
          return;
        }
      }
    }

    if (_isVirtual && _virtualUrl.text.trim().isEmpty) {
      if (mounted) {
        showNotice(context, 'Please enter meeting URL for virtual events', kind: NoticeKind.warning);
      }
      return;
    }

    if (!_isFree && (_fees.isEmpty || _feesTotal <= 0)) {
      if (mounted) {
        showNotice(context, 'A paid event needs at least one fee with an amount.', kind: NoticeKind.warning);
      }
      return;
    }

    if (!EventTimeZone.isKnown(_timezone.text.trim())) {
      if (mounted) {
        showNotice(context, 'Choose a timezone from the list.', kind: NoticeKind.warning);
      }
      return;
    }

    setState(() => _isSaving = true);

    try {
      final auth = ref.read(authControllerProvider);

      final data = <String, dynamic>{
        // No tagline: it is no longer edited, so a saved one is left as is.
        'title': _title.text.trim(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        'start_datetime': _iso(startDateTime),
        'end_datetime': _iso(endDateTime),
        'timezone': _timezone.text.trim(),
        'is_virtual': _isVirtual,
        'location_text': _isVirtual ? null : _location.text.trim().isEmpty ? null : _location.text.trim(),
        'location_maps_url': _isVirtual ? null : _locationMapsUrl.text.trim().isEmpty ? null : _locationMapsUrl.text.trim(),
        'virtual_url': _isVirtual ? _virtualUrl.text.trim() : null,
        'is_full_day': _isFullDay,
        'capacity': parseCapacity(_capacity.text),
        'max_guests': _maxGuests,
        'is_free': _isFree,
        // The price is the total of the fees (what checkout charges).
        'ticket_price': _isFree ? null : _feesTotal,
        'thumbnail_url': _thumbnailUrl.text.trim().isEmpty ? null : _thumbnailUrl.text.trim(),
        'banner_url': _bannerUrl.text.trim().isEmpty ? null : _bannerUrl.text.trim(),
        // Empty: opens when published (null), closes when the event starts.
        'registration_opens_at': _isoOfField(_registrationOpensAt.text),
        'registration_closes_at': _registrationClosesAt.text.trim().isEmpty
            ? _iso(startDateTime)
            : _isoOfField(_registrationClosesAt.text),
      };

      final repo = ref.read(eventsRepositoryProvider);
      final token = auth.session!.accessToken;
      final saved = widget.event == null
          ? await repo.createAdminEvent(data, token)
          : await repo.updateAdminEvent(widget.event!.eventId, data, token);

      // Speakers, sessions and fee tiers, then sponsors and partners, have
      // their own endpoints.
      final detailsSaved = await _saveDetails(saved.eventId, token);
      final orgsSaved = await _saveOrgs(saved.eventId, token);
      if (!detailsSaved && mounted) {
        showNotice(context, 'The event was saved, but its speakers, sessions or fee tiers could not be. '
              'Open the event again to check them.', kind: NoticeKind.error);
      } else if (!orgsSaved && mounted) {
        showNotice(context, 'The event was saved, but some sponsors or partners could not be. '
              'Open the event again to check them.', kind: NoticeKind.error);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to save event', error, stackTrace);
      if (!mounted) return;
      setState(() => _isSaving = false);
      showNotice(context, apiErrorMessage(error, action: 'save the event'), kind: NoticeKind.error);
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

/// A date or time field: shows the value, and a click anywhere on it opens
/// [onPick]. There is no typing, so nothing changes unless something is
/// picked.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.onPick,
    this.hint,
    this.onClear,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final Future<void> Function() onPick;
  final VoidCallback? onClear;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      validator: validator == null ? null : (_) => validator!(controller.text),
      builder: (field) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final text = value.text;
          return InkWell(
            onTap: () async {
              await onPick();
              field.didChange(controller.text);
            },
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              isEmpty: text.isEmpty,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                errorText: field.errorText,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                suffixIcon: onClear != null && text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: onClear,
                      )
                    : Icon(icon),
              ),
              child: Text(text.isEmpty ? '' : text),
            ),
          );
        },
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

