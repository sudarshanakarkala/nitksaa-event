import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/app_state.dart';
import '../../../core/logger/app_logger.dart';
import '../../../routes/app_routes.dart';
import '../../../theme/theme_provider.dart';
import '../../auth/services/auth_controller.dart';
import '../../auth/services/auth_session_store.dart';
import '../../auth/services/google_sign_in_initializer.dart';

class DeveloperDiagnosticsScreen extends ConsumerStatefulWidget {
  const DeveloperDiagnosticsScreen({super.key});

  @override
  ConsumerState<DeveloperDiagnosticsScreen> createState() =>
      _DeveloperDiagnosticsScreenState();
}

class _DeveloperDiagnosticsScreenState
    extends ConsumerState<DeveloperDiagnosticsScreen> {
  final Map<DiagnosticId, DiagnosticRunState> _runState = {};

  bool _runningAll = false;
  bool _exporting = false;
  bool _clearing = false;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('Not available.')));
    }

    final categories = _diagnosticCategories(ref.watch(themeProvider));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Diagnostics'),
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const _ProductionWarningBanner(),
          const SizedBox(height: 12),
          _QaSummaryCard(
            categories: categories,
            runState: _runState,
          ),
          const SizedBox(height: 12),
          const DiagnosticSectionHeader(title: 'Quick Actions'),
          _QuickActionsCard(
            runningAll: _runningAll,
            exporting: _exporting,
            clearing: _clearing,
            onOpenEvents: _openEvents,
            onRunEventDiag: _openEventDiagnostics,
            onRunRegDiag: _openRegistrationDiagnostics,
            onRunAdminDiag: _openAdminDiagnostics,
            onRunAll: _runAllDiagnostics,
            onExport: _exportDiagnosticReport,
            onClear: _clearCachedData,
          ),
          const SizedBox(height: 20),
          const DiagnosticSectionHeader(title: 'Diagnostic Center'),
          for (final category in categories)
            DiagnosticCategorySection(
              category: category,
              runState: _runState,
              onOpenDetail: _openDetail,
            ),
        ],
      ),
    );
  }

  void _openEvents() {
    context.go(AppRoutes.events);
  }

  void _openEventDiagnostics() {
    final items = _diagnosticItems(ref.read(themeProvider));
    _openDetail(items[DiagnosticId.eventsApi]!);
  }

  void _openRegistrationDiagnostics() {
    final items = _diagnosticItems(ref.read(themeProvider));
    _openDetail(items[DiagnosticId.registrationApi]!);
  }

  void _openAdminDiagnostics() {
    final items = _diagnosticItems(ref.read(themeProvider));
    _openDetail(items[DiagnosticId.attendeeListApi]!);
  }

  List<DiagnosticCategory> _diagnosticCategories(ThemeMode mode) {
    final items = _diagnosticItems(mode);
    return [
      DiagnosticCategory(
        title: 'General',
        description:
            'Core app health, runtime tools, network, and UI controls.',
        initiallyExpanded: true,
        items: [
          items[DiagnosticId.foundation]!,
          items[DiagnosticId.logger]!,
          items[DiagnosticId.theme]!,
          items[DiagnosticId.network]!,
          items[DiagnosticId.performance]!,
          items[DiagnosticId.debugTools]!,
        ],
      ),
      DiagnosticCategory(
        title: 'Authentication',
        description: 'Auth done end-to-end. Backend and DB standing.',
        initiallyExpanded: true,
        items: [
          items[DiagnosticId.firebaseToken]!,
          items[DiagnosticId.backendAuth]!,
          items[DiagnosticId.authMe]!,
        ],
      ),
      DiagnosticCategory(
        title: 'Database',
        description: 'Backend and DB standing.',
        initiallyExpanded: true,
        items: [
          items[DiagnosticId.eventUsers]!,
          items[DiagnosticId.databaseTables]!,
        ],
      ),
      DiagnosticCategory(
        title: 'Event Management',
        description:
            'Staff can create events. Public can browse and view details.',
        items: [
          items[DiagnosticId.eventsApi]!,
          items[DiagnosticId.eventDetailApi]!,
          items[DiagnosticId.eventCreationApi]!,
          items[DiagnosticId.eventPublish]!,
        ],
      ),
      DiagnosticCategory(
        title: 'Registration',
        description:
            'Alumni can register. Full flow: alumni profile, eligibility, register, my-registration, '
            'duplicate guard, capacity, join link, email, audit. '
            'Capacity guard and email checks are part of full registration diagnostics.',
        items: [
          items[DiagnosticId.week3UxShowcase]!,
          items[DiagnosticId.registrationApi]!,
          items[DiagnosticId.myRegistration]!,
        ],
      ),
      DiagnosticCategory(
        title: 'Admin / Attendees',
        description:
            'Phase 2 implemented. Admin can view, search, filter, export attendees, '
            'audit registrations, and run UC-01–UC-10 full diagnostics.',
        items: [
          items[DiagnosticId.attendeeListApi]!,
          items[DiagnosticId.attendeeSearchTest]!,
          items[DiagnosticId.attendeeBatchFilter]!,
          items[DiagnosticId.attendeeExport]!,
          items[DiagnosticId.auditTrail]!,
          items[DiagnosticId.adminRoleGuard]!,
        ],
      ),
      DiagnosticCategory(
        title: 'Alumni Database',
        description:
            'Verify alumni_db records and diagnose login mapping issues. '
            'Use to find why users appear as user_type=other with ref_id=NULL.',
        items: [
          items[DiagnosticId.alumniSearchEmail]!,
          items[DiagnosticId.alumniSearchPrefix]!,
          items[DiagnosticId.alumniLookupId]!,
          items[DiagnosticId.alumniLoginTrace]!,
        ],
      ),
      DiagnosticCategory(
        title: 'Week 5 — Event Enrichment',
        description:
            'Backend diagnostic suites for Week 5: event options, people/speakers, '
            'sponsors (tier ordering), partners (alphabetical ordering), and analytics logging. '
            '48 automated tests total. Run "Week 5 — All Suites" as the go/no-go check.',
        items: [
          items[DiagnosticId.week5All]!,
          items[DiagnosticId.week5EventOptions]!,
          items[DiagnosticId.week5People]!,
          items[DiagnosticId.week5SponsorsPartners]!,
          items[DiagnosticId.week5Analytics]!,
        ],
      ),
    ];
  }

  Map<DiagnosticId, DiagnosticItem> _diagnosticItems(ThemeMode mode) {
    return {
      DiagnosticId.foundation: DiagnosticItem(
        id: DiagnosticId.foundation,
        title: 'Foundation Status',
        description: 'App, Firebase, Hive, router, platform, and auth status.',
        icon: Icons.foundation_outlined,
        initialStatus: AppState.firebaseInitialized
            ? DiagnosticStatus.ok
            : DiagnosticStatus.error,
        apiDetails: diagnosticApiDetails[DiagnosticId.foundation]!,
      ),
      DiagnosticId.logger: DiagnosticItem(
        id: DiagnosticId.logger,
        title: 'Logger Test',
        description: 'Emit debug, info, warning, and error test logs.',
        icon: Icons.article_outlined,
        initialStatus: DiagnosticStatus.info,
        apiDetails: diagnosticApiDetails[DiagnosticId.logger]!,
      ),
      DiagnosticId.theme: DiagnosticItem(
        id: DiagnosticId.theme,
        title: 'Theme Control',
        description: 'Switch light, system, and dark theme modes.',
        icon: Icons.palette_outlined,
        initialStatus: DiagnosticStatus.info,
        apiDetails: diagnosticApiDetails[DiagnosticId.theme]!,
        statusNote: _themeModeLabel(mode),
      ),
      DiagnosticId.firebaseToken: DiagnosticItem(
        id: DiagnosticId.firebaseToken,
        title: 'Firebase Token Test',
        description: 'Capture a debug Firebase token preview after sign-in.',
        icon: Icons.key_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.firebaseToken]!,
      ),
      DiagnosticId.backendAuth: DiagnosticItem(
        id: DiagnosticId.backendAuth,
        title: 'Backend Auth Test',
        description: 'Exchange Firebase token with backend auth endpoint.',
        icon: Icons.verified_user_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.backendAuth]!,
      ),
      DiagnosticId.authMe: DiagnosticItem(
        id: DiagnosticId.authMe,
        title: '/auth/me Test',
        description: 'Validate backend JWT and current user response.',
        icon: Icons.person_search_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.authMe]!,
      ),
      DiagnosticId.eventUsers: DiagnosticItem(
        id: DiagnosticId.eventUsers,
        title: 'Event Users Test',
        description: 'Inspect event_users diagnostics through backend API.',
        icon: Icons.manage_accounts_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.eventUsers]!,
      ),
      DiagnosticId.databaseTables: DiagnosticItem(
        id: DiagnosticId.databaseTables,
        title: 'Database Tables Test',
        description: 'List diagnostic database tables and inspect rows.',
        icon: Icons.table_chart_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.databaseTables]!,
      ),
      DiagnosticId.network: DiagnosticItem(
        id: DiagnosticId.network,
        title: 'Network Test',
        description: 'Check backend base URL and health endpoint reachability.',
        icon: Icons.wifi_tethering_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.network]!,
      ),
      DiagnosticId.performance: DiagnosticItem(
        id: DiagnosticId.performance,
        title: 'App Performance',
        description: 'Review app runtime and rendering diagnostics notes.',
        icon: Icons.speed_outlined,
        initialStatus: DiagnosticStatus.info,
        apiDetails: diagnosticApiDetails[DiagnosticId.performance]!,
      ),
      DiagnosticId.debugTools: DiagnosticItem(
        id: DiagnosticId.debugTools,
        title: 'Debug Tools',
        description: 'Export reports, clear cache, and access debug utilities.',
        icon: Icons.build_outlined,
        initialStatus: DiagnosticStatus.info,
        apiDetails: diagnosticApiDetails[DiagnosticId.debugTools]!,
      ),
      DiagnosticId.eventsApi: DiagnosticItem(
        id: DiagnosticId.eventsApi,
        title: 'Public Events API Test',
        description:
            'Calls GET /api/v1/events/public?period=upcoming. Verifies 200, events array, '
            'and that virtual_url/join_url are not exposed publicly.',
        icon: Icons.public_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.eventsApi]!,
      ),
      DiagnosticId.eventDetailApi: DiagnosticItem(
        id: DiagnosticId.eventDetailApi,
        title: 'Event Detail API Test',
        description:
            'Calls GET /api/v1/events/public/{event_id}. Uses Event ID picker. '
            'Verifies title, status present and virtual_url not leaked in public payload.',
        icon: Icons.event_note_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.eventDetailApi]!,
      ),
      DiagnosticId.eventCreationApi: DiagnosticItem(
        id: DiagnosticId.eventCreationApi,
        title: 'Event List API Test',
        description:
            'Calls GET /api/v1/events?page=1&per_page=20 (admin auth). '
            'Verifies 200, total field, and events array present.',
        icon: Icons.list_alt_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.eventCreationApi]!,
      ),
      DiagnosticId.eventPublish: DiagnosticItem(
        id: DiagnosticId.eventPublish,
        title: 'Event Admin Detail Test',
        description:
            'Calls GET /api/v1/events/{event_id} (admin auth). Uses Event ID picker. '
            'Verifies admin can see full details including status and capacity.',
        icon: Icons.manage_search_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.eventPublish]!,
      ),
      DiagnosticId.registrationApi: DiagnosticItem(
        id: DiagnosticId.registrationApi,
        title: 'Registration Flow Test',
        description:
            'Run full registration diagnostics: alumni profile, eligibility, register, my-registration, duplicate guard.',
        icon: Icons.app_registration_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.registrationApi]!,
      ),
      DiagnosticId.myRegistration: DiagnosticItem(
        id: DiagnosticId.myRegistration,
        title: 'My Registration Test',
        description:
            'Verify current user registration lookup and registration list endpoint.',
        icon: Icons.fact_check_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.myRegistration]!,
      ),
      DiagnosticId.capacityGuard: DiagnosticItem(
        id: DiagnosticId.capacityGuard,
        title: 'Capacity Guard Test',
        description:
            'Verify that a full event rejects new registrations with event_full.',
        icon: Icons.groups_2_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.capacityGuard]!,
      ),
      DiagnosticId.confirmationEmail: DiagnosticItem(
        id: DiagnosticId.confirmationEmail,
        title: 'Confirmation Email Status',
        description:
            'Verify confirmation_email_status is written after registration (log mode).',
        icon: Icons.mark_email_read_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.confirmationEmail]!,
      ),
      DiagnosticId.joinLinkVisibility: DiagnosticItem(
        id: DiagnosticId.joinLinkVisibility,
        title: 'Join Link Visibility Test',
        description:
            'Verify join_url appears for virtual registered events and is absent from public API.',
        icon: Icons.link_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.joinLinkVisibility]!,
      ),
      DiagnosticId.attendeeListApi: DiagnosticItem(
        id: DiagnosticId.attendeeListApi,
        title: 'Attendee List API Test',
        description:
            'Calls GET /api/v1/admin/events/{id}/attendees?page=1&per_page=20. '
            'Verifies 200, attendees array, and no join_url/virtual_url leakage. '
            'All rows must have status=registered.',
        icon: Icons.people_alt_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.attendeeListApi]!,
      ),
      DiagnosticId.attendeeSearchTest: DiagnosticItem(
        id: DiagnosticId.attendeeSearchTest,
        title: 'Attendee Search Test',
        description:
            'Calls GET /admin/events/{id}/attendees?search={term}. '
            'Verifies filtered result does not crash and returns array.',
        icon: Icons.search_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.attendeeSearchTest]!,
      ),
      DiagnosticId.attendeeBatchFilter: DiagnosticItem(
        id: DiagnosticId.attendeeBatchFilter,
        title: 'Batch Year Filter Test',
        description:
            'Calls GET /admin/events/{id}/attendees?batch_year={year}. '
            'Verifies rows match batch year when filter is applied.',
        icon: Icons.filter_list_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.attendeeBatchFilter]!,
      ),
      DiagnosticId.attendeeExport: DiagnosticItem(
        id: DiagnosticId.attendeeExport,
        title: 'Attendee Export Test',
        description:
            'Calls GET /api/v1/admin/events/{id}/attendees/export. '
            'Verifies CSV response contains all 8 required columns and no virtual_url/qr_token.',
        icon: Icons.download_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.attendeeExport]!,
      ),
      DiagnosticId.adminRoleGuard: DiagnosticItem(
        id: DiagnosticId.adminRoleGuard,
        title: 'Admin Attendee Full Diagnostics',
        description:
            'Calls GET /api/v1/dev/diagnostics/attendees?event_id={id}. '
            'Runs UC-01 through UC-10 and displays full pass/fail results.',
        icon: Icons.admin_panel_settings_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.adminRoleGuard]!,
      ),
      DiagnosticId.auditTrail: DiagnosticItem(
        id: DiagnosticId.auditTrail,
        title: 'Registration Audit Test',
        description:
            'Calls GET /api/v1/admin/events/{id}/registrations?page=1&per_page=20. '
            'Verifies cancelled rows visible, all status values preserved.',
        icon: Icons.history_edu_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.auditTrail]!,
      ),
      DiagnosticId.week3UxShowcase: DiagnosticItem(
        id: DiagnosticId.week3UxShowcase,
        title: 'Week 3 UX Showcase',
        description:
            'Full visual demonstration: happy path, physical/virtual flows, '
            'my registration, negative states, security, audit, email, and snapshots.',
        icon: Icons.auto_awesome_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.week3UxShowcase]!,
      ),
      DiagnosticId.alumniSearchEmail: DiagnosticItem(
        id: DiagnosticId.alumniSearchEmail,
        title: 'Search by Email',
        description:
            'Search alumni_db for an exact email match. '
            'Shows full alumni record if found.',
        icon: Icons.search_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.alumniSearchEmail]!,
      ),
      DiagnosticId.alumniSearchPrefix: DiagnosticItem(
        id: DiagnosticId.alumniSearchPrefix,
        title: 'Search by Prefix',
        description:
            'Search alumni_db by email prefix or name fragment. '
            'Returns up to 50 matching records.',
        icon: Icons.manage_search_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.alumniSearchPrefix]!,
      ),
      DiagnosticId.alumniLookupId: DiagnosticItem(
        id: DiagnosticId.alumniLookupId,
        title: 'Lookup by Alumni ID',
        description:
            'Fetch the full alumni record for a known alumni_id (ref_id).',
        icon: Icons.badge_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.alumniLookupId]!,
      ),
      DiagnosticId.alumniLoginTrace: DiagnosticItem(
        id: DiagnosticId.alumniLoginTrace,
        title: 'Login Mapping Trace',
        description:
            'Trace why a user may appear as user_type=other with ref_id=NULL. '
            'Shows alumni_db lookup result, expected mapping, and actual event_users row.',
        icon: Icons.troubleshoot_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.alumniLoginTrace]!,
      ),
      DiagnosticId.week5EventOptions: DiagnosticItem(
        id: DiagnosticId.week5EventOptions,
        title: 'Event Options Diagnostic',
        description:
            'Runs 6 automated backend tests for is_full_day, is_free, and ticket_price. '
            'Creates test events, verifies admin and public responses, checks backward compatibility.',
        icon: Icons.event_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.week5EventOptions]!,
      ),
      DiagnosticId.week5People: DiagnosticItem(
        id: DiagnosticId.week5People,
        title: 'People / Speakers Diagnostic',
        description:
            'Runs 14 automated backend tests for event people CRUD. '
            'Verifies all 7 roles, visibility gating, speakers[] derivation, HOST exclusion, update, and delete.',
        icon: Icons.people_outline,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.week5People]!,
      ),
      DiagnosticId.week5SponsorsPartners: DiagnosticItem(
        id: DiagnosticId.week5SponsorsPartners,
        title: 'Sponsors & Partners Diagnostic',
        description:
            'Runs 17 automated backend tests. '
            'Verifies sponsor tier ordering (TITLE → GOLD → SILVER → BRONZE → ASSOCIATE), '
            'partner alphabetical ordering, visibility gating, CRUD, and separate list keys.',
        icon: Icons.handshake_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.week5SponsorsPartners]!,
      ),
      DiagnosticId.week5Analytics: DiagnosticItem(
        id: DiagnosticId.week5Analytics,
        title: 'Analytics Logging Diagnostic',
        description:
            'Runs 11 automated backend tests for event_activity_log. '
            'Verifies 6 action types, metadata JSONB, source_app, and no secret leakage.',
        icon: Icons.analytics_outlined,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.week5Analytics]!,
      ),
      DiagnosticId.week5All: DiagnosticItem(
        id: DiagnosticId.week5All,
        title: 'Week 5 — All Suites',
        description:
            'Runs all 48 Week 5 backend diagnostic tests in one call: '
            'event-options (6), people (14), sponsors-partners (17), analytics (11). '
            'Use as go/no-go check before any Week 5 backend deployment.',
        icon: Icons.check_circle_outline,
        initialStatus: DiagnosticStatus.notApplicable,
        apiDetails: diagnosticApiDetails[DiagnosticId.week5All]!,
      ),
    };
  }

  Future<void> _openDetail(DiagnosticItem item) async {
    final result = await Navigator.of(context).push<DiagnosticRunState>(
      MaterialPageRoute(
        builder: (_) => DiagnosticDetailScreen(item: item),
        settings: RouteSettings(name: 'developer/${item.id.name}'),
      ),
    );

    if (result == null || !mounted) return;
    setState(() => _runState[item.id] = result);
  }

  Future<void> _runAllDiagnostics() async {
    setState(() => _runningAll = true);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AuthDiagnosticDetail(
          title: 'Run All Diagnostics',
          mode: _AuthDiagnosticMode.fullValidation,
          autoRunFullValidation: true,
          apiDetails: diagnosticApiDetails[DiagnosticId.backendAuth]!,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _runningAll = false;
      final timestamp = DateTime.now();
      _runState[DiagnosticId.firebaseToken] = DiagnosticRunState(
        status: DiagnosticStatus.info,
        lastRun: timestamp,
      );
      _runState[DiagnosticId.backendAuth] = DiagnosticRunState(
        status: DiagnosticStatus.info,
        lastRun: timestamp,
      );
      _runState[DiagnosticId.authMe] = DiagnosticRunState(
        status: DiagnosticStatus.info,
        lastRun: timestamp,
      );
      _runState[DiagnosticId.eventUsers] = DiagnosticRunState(
        status: DiagnosticStatus.info,
        lastRun: timestamp,
      );
      _runState[DiagnosticId.databaseTables] = DiagnosticRunState(
        status: DiagnosticStatus.info,
        lastRun: timestamp,
      );
    });
  }

  Future<void> _exportDiagnosticReport() async {
    setState(() => _exporting = true);
    final report = _buildDiagnosticReport(
      _diagnosticCategories(ref.read(themeProvider)),
    );
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _runState[DiagnosticId.debugTools] = DiagnosticRunState(
        status: DiagnosticStatus.ok,
        lastRun: DateTime.now(),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostic report copied to clipboard.')),
    );
  }

  Future<void> _clearCachedData() async {
    setState(() => _clearing = true);
    try {
      final store = AuthSessionStore();
      await store.initialize();
      await store.clear();
      if (!mounted) return;
      setState(() {
        _clearing = false;
        _runState[DiagnosticId.debugTools] = DiagnosticRunState(
          status: DiagnosticStatus.warning,
          lastRun: DateTime.now(),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cached backend session cleared.')),
      );
    } catch (error, stackTrace) {
      AppLogger.error('Dev cache clear failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _clearing = false;
        _runState[DiagnosticId.debugTools] = DiagnosticRunState(
          status: DiagnosticStatus.error,
          lastRun: DateTime.now(),
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Clear cache failed: $error')));
    }
  }

  String _buildDiagnosticReport(List<DiagnosticCategory> categories) {
    final buffer = StringBuffer()
      ..writeln('NITKSAA Event Developer Diagnostics')
      ..writeln('Generated: ${DateTime.now().toLocal()}')
      ..writeln('Debug build: $kDebugMode')
      ..writeln('');

    for (final category in categories) {
      buffer
        ..writeln(
          '${category.title}: ${diagnosticStatusLabel(categoryStatus(category, _runState))}',
        )
        ..writeln('Goal: ${category.description}');
      for (final item in category.items) {
        final state = _runState[item.id] ?? const DiagnosticRunState();
        buffer
          ..writeln(
            '- ${item.title}: ${diagnosticStatusLabel(state.effectiveStatus(item))}',
          )
          ..writeln('  ${item.description}')
          ..writeln('  Last run: ${formatDiagnosticTimestamp(state.lastRun)}');
      }
      buffer.writeln('');
    }
    return buffer.toString();
  }
}

class DiagnosticDetailScreen extends StatelessWidget {
  const DiagnosticDetailScreen({super.key, required this.item});

  final DiagnosticItem item;

  @override
  Widget build(BuildContext context) {
    return switch (item.id) {
      DiagnosticId.foundation => const _FoundationDetail(),
      DiagnosticId.logger => const _LoggerDetail(),
      DiagnosticId.theme => const _ThemeDetail(),
      DiagnosticId.firebaseToken => _AuthDiagnosticDetail(
          title: 'Firebase Token Test',
          mode: _AuthDiagnosticMode.firebaseToken,
          apiDetails: diagnosticApiDetails[DiagnosticId.firebaseToken]!,
        ),
      DiagnosticId.backendAuth => _AuthDiagnosticDetail(
          title: 'Backend Auth Test',
          mode: _AuthDiagnosticMode.backendAuth,
          apiDetails: diagnosticApiDetails[DiagnosticId.backendAuth]!,
        ),
      DiagnosticId.authMe => _AuthDiagnosticDetail(
          title: '/auth/me Test',
          mode: _AuthDiagnosticMode.authMe,
          apiDetails: diagnosticApiDetails[DiagnosticId.authMe]!,
        ),
      DiagnosticId.eventUsers => _AuthDiagnosticDetail(
          title: 'Event Users Test',
          mode: _AuthDiagnosticMode.eventUsers,
          apiDetails: diagnosticApiDetails[DiagnosticId.eventUsers]!,
        ),
      DiagnosticId.databaseTables => _AuthDiagnosticDetail(
          title: 'Database Tables Test',
          mode: _AuthDiagnosticMode.databaseTables,
          apiDetails: diagnosticApiDetails[DiagnosticId.databaseTables]!,
        ),
      DiagnosticId.network => const _NetworkDetail(),
      DiagnosticId.performance => const _PerformanceDetail(),
      DiagnosticId.debugTools => const _DebugToolsDetail(),
      DiagnosticId.week3UxShowcase ||
      DiagnosticId.registrationApi ||
      DiagnosticId.myRegistration ||
      DiagnosticId.capacityGuard ||
      DiagnosticId.confirmationEmail ||
      DiagnosticId.joinLinkVisibility =>
        _RegistrationDiagnosticDetail(item: item),
      DiagnosticId.eventsApi ||
      DiagnosticId.eventDetailApi ||
      DiagnosticId.eventCreationApi ||
      DiagnosticId.eventPublish =>
        _EventManagementDiagnosticDetail(item: item),
      DiagnosticId.attendeeListApi ||
      DiagnosticId.attendeeSearchTest ||
      DiagnosticId.attendeeBatchFilter ||
      DiagnosticId.attendeeExport ||
      DiagnosticId.adminRoleGuard ||
      DiagnosticId.auditTrail =>
        _AdminAttendeeDiagnosticDetail(item: item),
      DiagnosticId.alumniSearchEmail ||
      DiagnosticId.alumniSearchPrefix ||
      DiagnosticId.alumniLookupId ||
      DiagnosticId.alumniLoginTrace =>
        _AlumniDiagnosticDetail(item: item),
      DiagnosticId.week5EventOptions ||
      DiagnosticId.week5People ||
      DiagnosticId.week5SponsorsPartners ||
      DiagnosticId.week5Analytics ||
      DiagnosticId.week5All =>
        _Week5DiagnosticDetail(item: item),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Week 5 — Event Enrichment Diagnostic Detail
// ─────────────────────────────────────────────────────────────────────────────

class _Week5DiagnosticDetail extends StatefulWidget {
  const _Week5DiagnosticDetail({required this.item});

  final DiagnosticItem item;

  @override
  State<_Week5DiagnosticDetail> createState() => _Week5DiagnosticDetailState();
}

class _Week5DiagnosticDetailState extends State<_Week5DiagnosticDetail> {
  bool _loading = false;
  Map<String, dynamic>? _result;
  String? _error;

  String get _endpoint {
    return switch (widget.item.id) {
      DiagnosticId.week5EventOptions    => '/api/v1/dev/diagnostics/week5/event-options',
      DiagnosticId.week5People          => '/api/v1/dev/diagnostics/week5/people',
      DiagnosticId.week5SponsorsPartners => '/api/v1/dev/diagnostics/week5/sponsors-partners',
      DiagnosticId.week5Analytics       => '/api/v1/dev/diagnostics/week5/analytics',
      DiagnosticId.week5All             => '/api/v1/dev/diagnostics/week5/all',
      _ => '/api/v1/dev/diagnostics/week5/all',
    };
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final resp = await devDio
          .get<Map<String, dynamic>>(
            _endpoint,
            options: Options(headers: {'X-Dev-User': 'admin'}),
          )
          .timeout(const Duration(seconds: 60));
      if (!mounted) return;
      setState(() => _result = resp.data);
    } catch (e, st) {
      AppLogger.error('Week 5 diagnostic failed', e, st);
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final overallStatus = result?['status'] as String?;
    final totalPassed   = result?['passed']   as int?;
    final totalFailed   = result?['failed']   as int?;
    final totalTests    = result?['total']    as int?;
    final warnings      = result?['warnings'] as int?;

    DiagnosticRunState? runState;
    if (result != null) {
      runState = DiagnosticRunState(
        status: overallStatus == 'ok'
            ? DiagnosticStatus.ok
            : overallStatus == 'warning'
                ? DiagnosticStatus.warning
                : DiagnosticStatus.error,
        lastRun: DateTime.now(),
      );
    }

    return DiagnosticDetailScaffold(
      title: widget.item.title,
      description: widget.item.description,
      result: runState,
      apiDetails: widget.item.apiDetails,
      children: [
        // Run button
        ElevatedButton.icon(
          onPressed: _loading ? null : _run,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_outlined, size: 18),
          label: Text(_loading ? 'Running…' : 'Run Diagnostic'),
        ),
        const SizedBox(height: 16),

        // Error
        if (_error != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          ),

        // Summary card
        if (result != null) ...[
          Card(
            child: Column(
              children: [
                _DiagRow(
                  label: 'Status',
                  value: overallStatus?.toUpperCase() ?? '—',
                  status: overallStatus == 'ok'
                      ? DiagnosticStatus.ok
                      : overallStatus == 'warning'
                          ? DiagnosticStatus.warning
                          : DiagnosticStatus.error,
                ),
                _divider,
                _DiagRow(label: 'Total tests', value: '$totalTests'),
                _divider,
                _DiagRow(
                  label: 'Passed',
                  value: '$totalPassed',
                  status: (totalPassed ?? 0) > 0 ? DiagnosticStatus.ok : null,
                ),
                _divider,
                _DiagRow(
                  label: 'Failed',
                  value: '$totalFailed',
                  status: (totalFailed ?? 0) > 0 ? DiagnosticStatus.error : null,
                ),
                if ((warnings ?? 0) > 0) ...[
                  _divider,
                  _DiagRow(
                    label: 'Warnings',
                    value: '$warnings',
                    status: DiagnosticStatus.warning,
                  ),
                ],
                if (result['test_event_id'] != null) ...[
                  _divider,
                  _DiagRow(label: 'Test event ID', value: '${result['test_event_id']}'),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Per-suite breakdown for /all
          if (result.containsKey('suites')) ...[
            const Text(
              'Suite Breakdown',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            for (final suite in (result['suites'] as List))
              _Week5SuiteCard(suite: suite as Map<String, dynamic>),
          ]
          // Per-test results for individual suites
          else if (result.containsKey('results')) ...[
            const Text(
              'Test Results',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            _Week5ResultsCard(results: (result['results'] as List).cast<Map<String, dynamic>>()),
          ],
        ],
      ],
    );
  }
}

class _Week5SuiteCard extends StatelessWidget {
  const _Week5SuiteCard({required this.suite});

  final Map<String, dynamic> suite;

  @override
  Widget build(BuildContext context) {
    final scope   = suite['scope']  as String? ?? '—';
    final passed  = suite['passed'] as int?    ?? 0;
    final total   = suite['total']  as int?    ?? 0;
    final status  = suite['status'] as String? ?? 'failed';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          status == 'ok' ? Icons.check_circle_outline : Icons.error_outline,
          color: status == 'ok' ? Colors.green : Colors.redAccent,
          size: 20,
        ),
        title: Text(
          scope,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '$passed/$total passed',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          if (suite.containsKey('results'))
            _Week5ResultsCard(
              results: (suite['results'] as List).cast<Map<String, dynamic>>(),
            ),
        ],
      ),
    );
  }
}

class _Week5ResultsCard extends StatelessWidget {
  const _Week5ResultsCard({required this.results});

  final List<Map<String, dynamic>> results;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (int i = 0; i < results.length; i++) ...[
            if (i > 0) _divider,
            _Week5TestRow(result: results[i]),
          ],
        ],
      ),
    );
  }
}

class _Week5TestRow extends StatelessWidget {
  const _Week5TestRow({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final id      = result['id']      as String? ?? '—';
    final name    = result['name']    as String? ?? '—';
    final status  = result['status']  as String? ?? 'FAIL';
    final details = result['details'] as String? ?? '';

    final (icon, color) = switch (status) {
      'PASS'    => (Icons.check_circle_outline, Colors.green),
      'WARNING' => (Icons.warning_amber_outlined, Colors.orange),
      _         => (Icons.cancel_outlined, Colors.redAccent),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '[$id] $name',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (details.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      details,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Alumni Database Diagnostic Detail
// ─────────────────────────────────────────────────────────────────────────────

class _AlumniDiagnosticDetail extends StatefulWidget {
  const _AlumniDiagnosticDetail({required this.item});

  final DiagnosticItem item;

  @override
  State<_AlumniDiagnosticDetail> createState() =>
      _AlumniDiagnosticDetailState();
}

class _AlumniDiagnosticDetailState extends State<_AlumniDiagnosticDetail> {
  String? _backendAccessToken;

  // ── Search by Email ──────────────────────────────────────────────────────
  final TextEditingController _emailCtrl = TextEditingController();
  bool _emailLoading = false;
  Map<String, dynamic>? _emailResult;
  String? _emailError;

  // ── Search by Prefix ─────────────────────────────────────────────────────
  final TextEditingController _prefixCtrl = TextEditingController();
  bool _prefixLoading = false;
  Map<String, dynamic>? _prefixResult;
  String? _prefixError;

  // ── Lookup by Alumni ID ──────────────────────────────────────────────────
  final TextEditingController _idCtrl = TextEditingController();
  bool _idLoading = false;
  Map<String, dynamic>? _idResult;
  String? _idError;

  // ── Login Mapping Trace ──────────────────────────────────────────────────
  final TextEditingController _traceEmailCtrl = TextEditingController();
  bool _traceLoading = false;
  Map<String, dynamic>? _traceResult;
  String? _traceError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _prefixCtrl.dispose();
    _idCtrl.dispose();
    _traceEmailCtrl.dispose();
    super.dispose();
  }

  // ── shared token helper ──────────────────────────────────────────────────

  Future<String> _getToken() async {
    final existing = _backendAccessToken;
    if (existing != null && existing.isNotEmpty) return existing;

    final store = AuthSessionStore();
    final session = await store.load();
    if (session != null && session.accessToken.isNotEmpty) {
      if (mounted) setState(() => _backendAccessToken = session.accessToken);
      return session.accessToken;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError(
        'Not signed in. Complete the Backend Auth diagnostic first.',
      );
    }
    final firebaseToken = await user.getIdToken(true);
    if (firebaseToken == null || firebaseToken.isEmpty) {
      throw StateError('Firebase ID token unavailable.');
    }
    final resp = await devDio.post<Map<String, dynamic>>(
      '/api/v1/auth/firebase',
      data: {'token': firebaseToken},
    );
    final accessToken = resp.data?['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Backend access token exchange failed.');
    }
    if (mounted) setState(() => _backendAccessToken = accessToken);
    return accessToken;
  }

  // ── API calls ────────────────────────────────────────────────────────────

  Future<void> _searchByEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _emailError = 'Enter an email address.');
      return;
    }
    setState(() {
      _emailLoading = true;
      _emailError = null;
      _emailResult = null;
    });
    try {
      final token = await _getToken();
      final response = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/dev/diagnostics/alumni/search',
            queryParameters: {'email': email},
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _emailResult = response.data);
    } catch (e, st) {
      AppLogger.error('Alumni search by email failed', e, st);
      if (!mounted) return;
      setState(() => _emailError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _emailLoading = false);
    }
  }

  Future<void> _searchByPrefix() async {
    final prefix = _prefixCtrl.text.trim();
    if (prefix.isEmpty) {
      setState(() => _prefixError = 'Enter a prefix or name fragment.');
      return;
    }
    setState(() {
      _prefixLoading = true;
      _prefixError = null;
      _prefixResult = null;
    });
    try {
      final token = await _getToken();
      final response = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/dev/diagnostics/alumni/search-prefix',
            queryParameters: {'prefix': prefix},
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _prefixResult = response.data);
    } catch (e, st) {
      AppLogger.error('Alumni search by prefix failed', e, st);
      if (!mounted) return;
      setState(() => _prefixError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _prefixLoading = false);
    }
  }

  Future<void> _lookupById(String alumniId) async {
    final id = alumniId.trim();
    if (id.isEmpty) {
      setState(() => _idError = 'Enter an alumni_id.');
      return;
    }
    setState(() {
      _idLoading = true;
      _idError = null;
      _idResult = null;
    });
    try {
      final token = await _getToken();
      final response = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/dev/diagnostics/alumni/${Uri.encodeComponent(id)}',
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _idResult = response.data);
    } catch (e, st) {
      AppLogger.error('Alumni lookup by ID failed', e, st);
      if (!mounted) return;
      setState(() => _idError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _idLoading = false);
    }
  }

  Future<void> _traceLogin() async {
    final email = _traceEmailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _traceError = 'Enter an email address.');
      return;
    }
    setState(() {
      _traceLoading = true;
      _traceError = null;
      _traceResult = null;
    });
    try {
      final token = await _getToken();
      final response = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/dev/diagnostics/alumni/login-trace',
            queryParameters: {'email': email},
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _traceResult = response.data);
    } catch (e, st) {
      AppLogger.error('Login mapping trace failed', e, st);
      if (!mounted) return;
      setState(() => _traceError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _traceLoading = false);
    }
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DiagnosticDetailScaffold(
      title: widget.item.title,
      description: widget.item.description,
      apiDetails: widget.item.apiDetails,
      children: _buildContent(context),
    );
  }

  List<Widget> _buildContent(BuildContext context) {
    return switch (widget.item.id) {
      DiagnosticId.alumniSearchEmail => _buildSearchEmail(context),
      DiagnosticId.alumniSearchPrefix => _buildSearchPrefix(context),
      DiagnosticId.alumniLookupId => _buildLookupId(context),
      DiagnosticId.alumniLoginTrace => _buildLoginTrace(context),
      _ => const [],
    };
  }

  // ── Search by Email ──────────────────────────────────────────────────────

  List<Widget> _buildSearchEmail(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final records = _emailResult?['records'] as List? ?? const [];
    final found = _emailResult?['found'] == true;
    final count = _emailResult?['count'] as int? ?? 0;

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Backend: $backendBaseUrl',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
              const SizedBox(height: 12),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Enter alumni email',
                  hintText: 'full email address',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _emailLoading ? null : _searchByEmail,
                icon: _emailLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                label: const Text('Search Alumni'),
              ),
              if (_emailError != null) ...[
                const SizedBox(height: 8),
                _errorChip(context, _emailError!),
              ],
              if (_emailResult != null) ...[
                const SizedBox(height: 16),
                _foundBadge(context, found, count),
                const SizedBox(height: 12),
                for (final r in records)
                  _alumniRecordCard(context,
                      Map<String, dynamic>.from(r as Map)),
                _jsonBlockWithCopy(
                    context, 'GET /alumni/search response', _emailResult),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  // ── Search by Prefix ─────────────────────────────────────────────────────

  List<Widget> _buildSearchPrefix(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final records = _prefixResult?['records'] as List? ?? const [];
    final count = _prefixResult?['count'] as int? ?? 0;

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Backend: $backendBaseUrl',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
              const SizedBox(height: 12),
              TextField(
                controller: _prefixCtrl,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Enter email/name prefix',
                  hintText: 'e.g. sudarshana',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.manage_search_outlined),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _prefixLoading ? null : _searchByPrefix,
                icon: _prefixLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                label: const Text('Search Prefix'),
              ),
              if (_prefixError != null) ...[
                const SizedBox(height: 8),
                _errorChip(context, _prefixError!),
              ],
              if (_prefixResult != null) ...[
                const SizedBox(height: 16),
                Row(children: [
                  _countBadge(context, count),
                  const SizedBox(width: 8),
                  Text('records found',
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
                const SizedBox(height: 12),
                for (final r in records)
                  _prefixResultRow(context,
                      Map<String, dynamic>.from(r as Map)),
                _jsonBlockWithCopy(
                    context, 'GET /alumni/search-prefix response', _prefixResult),
              ],
            ],
          ),
        ),
      ),
      if (_idResult != null || _idLoading || _idError != null) ...[
        const SizedBox(height: 16),
        _buildLookupIdCard(context),
      ],
    ];
  }

  Widget _prefixResultRow(BuildContext context, Map<String, dynamic> r) {
    final cs = Theme.of(context).colorScheme;
    final alumniId = r['alumni_id']?.toString() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _idCtrl.text = alumniId;
          _lookupById(alumniId);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r['fullname']?.toString() ?? '—',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                  const SizedBox(height: 2),
                  Text(r['email']?.toString() ?? '—',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.primary,
                          )),
                  Text(alumniId,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontFamily: 'monospace',
                          )),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }

  // ── Lookup by Alumni ID ──────────────────────────────────────────────────

  List<Widget> _buildLookupId(BuildContext context) {
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _buildLookupIdInner(context),
        ),
      ),
    ];
  }

  Widget _buildLookupIdCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildLookupIdInner(context),
      ),
    );
  }

  Widget _buildLookupIdInner(BuildContext context) {
    final record = _idResult?['record'] as Map?;
    final found = _idResult?['found'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _idCtrl,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Enter alumni_id',
            hintText: 'UUID or ref_id value',
            border: OutlineInputBorder(),
            isDense: true,
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _idLoading
              ? null
              : () => _lookupById(_idCtrl.text),
          icon: _idLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.person_search_outlined),
          label: const Text('Lookup Alumni ID'),
        ),
        if (_idError != null) ...[
          const SizedBox(height: 8),
          _errorChip(context, _idError!),
        ],
        if (_idResult != null) ...[
          const SizedBox(height: 16),
          _foundBadge(context, found, found ? 1 : 0),
          if (record != null) ...[
            const SizedBox(height: 12),
            _alumniRecordCard(context, Map<String, dynamic>.from(record)),
          ],
          _jsonBlockWithCopy(
              context, 'GET /alumni/{alumni_id} response', _idResult),
        ],
      ],
    );
  }

  // ── Login Mapping Trace ──────────────────────────────────────────────────

  List<Widget> _buildLoginTrace(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final alumniLookup = _traceResult?['alumni_lookup'] as Map?;
    final expectedMapping =
        _traceResult?['expected_event_user_mapping'] as Map?;
    final existingEu = _traceResult?['existing_event_user'] as Map?;
    final diagnosis = _traceResult?['diagnosis'] as Map?;

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Backend: $backendBaseUrl',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
              const SizedBox(height: 4),
              Text(
                'Simulates POST /auth/firebase lookup without a Firebase token. '
                'Shows why a user may appear as user_type=other.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _traceEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Enter alumni email',
                  hintText: 'full email address',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.troubleshoot_outlined),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _traceLoading ? null : _traceLogin,
                icon: _traceLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.travel_explore_outlined),
                label: const Text('Trace Login Mapping'),
              ),
              if (_traceError != null) ...[
                const SizedBox(height: 8),
                _errorChip(context, _traceError!),
              ],
              if (_traceResult != null) ...[
                const SizedBox(height: 20),

                // ── Diagnosis banner ─────────────────────────────────────
                if (diagnosis != null)
                  _diagnosisBanner(context, diagnosis),
                const SizedBox(height: 16),

                // ── Alumni DB found ──────────────────────────────────────
                _traceSection(context, 'Alumni DB Lookup',
                    Icons.school_outlined, cs.primary, [
                  _traceRow(context, 'Found',
                      alumniLookup?['found'] == true ? 'Yes' : 'No',
                      status: alumniLookup?['found'] == true
                          ? DiagnosticStatus.ok
                          : DiagnosticStatus.error),
                  if (alumniLookup?['found'] == true) ...[
                    _traceRow(context, 'Alumni ID',
                        alumniLookup?['alumni_id']?.toString() ?? '—'),
                    _traceRow(context, 'Name',
                        alumniLookup?['fullname']?.toString() ?? '—'),
                    _traceRow(context, 'Email',
                        alumniLookup?['email']?.toString() ?? '—'),
                    _traceRow(context, 'Grad Year',
                        alumniLookup?['graduationyear']?.toString() ?? '—'),
                    _traceRow(context, 'Status',
                        alumniLookup?['registrationstatus']?.toString() ?? '—'),
                  ],
                ]),
                const SizedBox(height: 12),

                // ── Expected mapping ─────────────────────────────────────
                if (expectedMapping != null)
                  _traceSection(context, 'Expected event_users Mapping',
                      Icons.route_outlined, cs.secondary, [
                    _traceRow(context, 'Expected user_type',
                        expectedMapping['expected_user_type']?.toString() ?? '—'),
                    _traceRow(context, 'Expected ref_id',
                        expectedMapping['expected_ref_id']?.toString() ?? 'NULL'),
                    _traceRow(context, 'Expected grad year',
                        expectedMapping['expected_graduation_year']?.toString() ?? '—'),
                    _traceRow(context, 'Is active',
                        expectedMapping['is_active'] == true ? 'Yes' : 'No',
                        status: expectedMapping['is_active'] == true
                            ? DiagnosticStatus.ok
                            : DiagnosticStatus.warning),
                  ]),
                if (expectedMapping != null) const SizedBox(height: 12),

                // ── Existing event_users row ─────────────────────────────
                _traceSection(context, 'Existing event_users Row',
                    Icons.table_rows_outlined, cs.tertiary, [
                  _traceRow(context, 'Found',
                      existingEu?['found'] == true ? 'Yes' : 'No',
                      status: existingEu?['found'] == true
                          ? DiagnosticStatus.ok
                          : DiagnosticStatus.warning),
                  if (existingEu?['found'] == true) ...[
                    _traceRow(context, 'user_type',
                        existingEu?['user_type']?.toString() ?? '—',
                        status: existingEu?['user_type'] == 'alumni'
                            ? DiagnosticStatus.ok
                            : DiagnosticStatus.error),
                    _traceRow(context, 'ref_id',
                        existingEu?['ref_id']?.toString() ?? 'NULL',
                        status: existingEu?['ref_id'] != null
                            ? DiagnosticStatus.ok
                            : DiagnosticStatus.error),
                    _traceRow(context, 'graduation_year',
                        existingEu?['graduation_year']?.toString() ?? 'NULL'),
                    _traceRow(context, 'last_login',
                        existingEu?['last_login']?.toString() ?? '—'),
                  ],
                ]),
                const SizedBox(height: 12),

                _jsonBlockWithCopy(context, 'GET /alumni/login-trace response',
                    _traceResult),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  Widget _diagnosisBanner(BuildContext context, Map diagnosis) {
    final cs = Theme.of(context).colorScheme;
    final result = diagnosis['result']?.toString() ?? '';
    final reason = diagnosis['reason']?.toString() ?? '';
    final isPassed = result == 'pass_mapping_correct';
    final isWarning = result.startsWith('warning_');

    final (bg, fg, icon) = isPassed
        ? (
            Colors.green.withValues(alpha: 0.12),
            Colors.green.shade800,
            Icons.check_circle_outline,
          )
        : isWarning
            ? (
                cs.tertiaryContainer,
                cs.onTertiaryContainer,
                Icons.warning_amber_outlined,
              )
            : (
                cs.errorContainer,
                cs.onErrorContainer,
                Icons.error_outline,
              );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isPassed
                ? Colors.green.withValues(alpha: 0.3)
                : isWarning
                    ? cs.tertiary.withValues(alpha: 0.3)
                    : cs.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isPassed ? 'PASS' : isWarning ? 'WARNING' : 'FAIL',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              result,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(height: 6),
          Text(reason,
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(color: fg)),
        ],
      ),
    );
  }

  Widget _traceSection(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    List<Widget> rows,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                      )),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }

  Widget _traceRow(
    BuildContext context,
    String label,
    String value, {
    DiagnosticStatus? status,
  }) {
    final cs = Theme.of(context).colorScheme;
    Widget? statusIcon;
    if (status != null) {
      statusIcon = Icon(
        status == DiagnosticStatus.ok
            ? Icons.check_circle_outline
            : status == DiagnosticStatus.error
                ? Icons.error_outline
                : Icons.warning_amber_outlined,
        size: 14,
        color: status == DiagnosticStatus.ok
            ? Colors.green
            : status == DiagnosticStatus.error
                ? cs.error
                : cs.tertiary,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(
          width: 120,
          child: Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  )),
        ),
        Expanded(
          child: SelectableText(value,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500)),
        ),
        if (statusIcon != null) ...[
          const SizedBox(width: 4),
          statusIcon,
        ],
      ]),
    );
  }

  // ── shared helpers ───────────────────────────────────────────────────────

  Widget _alumniRecordCard(BuildContext context, Map<String, dynamic> r) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r['fullname']?.toString() ?? '—',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final entry in r.entries)
            if (entry.key != 'fullname')
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(entry.key,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              )),
                    ),
                    Expanded(
                      child: SelectableText(
                          entry.value?.toString() ?? 'null',
                          style:
                              Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _foundBadge(BuildContext context, bool found, int count) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = found
        ? (Colors.green.withValues(alpha: 0.12), Colors.green.shade800)
        : (cs.errorContainer, cs.onErrorContainer);
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            found ? Icons.check_circle_outline : Icons.search_off_outlined,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 6),
          Text(found ? 'Found — $count record(s)' : 'Not Found',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: fg, fontWeight: FontWeight.w700)),
        ]),
      ),
    ]);
  }

  Widget _countBadge(BuildContext context, int count) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$count',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              )),
    );
  }

  Widget _errorChip(BuildContext context, String error) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, size: 14, color: cs.onErrorContainer),
        const SizedBox(width: 6),
        Expanded(
          child: SelectableText(error,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onErrorContainer)),
        ),
      ]),
    );
  }

  Widget _jsonBlockWithCopy(
      BuildContext context, String title, Object? value) {
    if (value == null) return const SizedBox.shrink();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(value);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(title, style: Theme.of(context).textTheme.labelLarge),
        subtitle: const Text('Show Raw JSON'),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: jsonStr));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('JSON copied.')),
                      );
                    },
                    icon: const Icon(Icons.copy_outlined, size: 14),
                    label: const Text('Copy JSON'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                SelectableText(
                  jsonStr,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Event Management Diagnostic Detail
// ─────────────────────────────────────────────────────────────────────────────

class _EventManagementDiagnosticDetail extends StatefulWidget {
  const _EventManagementDiagnosticDetail({required this.item});
  final DiagnosticItem item;

  @override
  State<_EventManagementDiagnosticDetail> createState() =>
      _EventManagementDiagnosticDetailState();
}

class _EventManagementDiagnosticDetailState
    extends State<_EventManagementDiagnosticDetail> {
  final TextEditingController _eventIdController = TextEditingController();

  bool _publicEventsLoading = false;
  Map<String, dynamic>? _publicEventsResult;
  String? _publicEventsError;

  bool _eventListLoading = false;
  Map<String, dynamic>? _eventListResult;
  String? _eventListError;

  bool _eventDetailLoading = false;
  Map<String, dynamic>? _eventDetailResult;
  String? _eventDetailError;

  bool _adminDetailLoading = false;
  Map<String, dynamic>? _adminDetailResult;
  String? _adminDetailError;

  @override
  void dispose() {
    _eventIdController.dispose();
    super.dispose();
  }

  String get _eventId => _eventIdController.text.trim();

  Future<void> _runPublicEventsTest() async {
    setState(() {
      _publicEventsLoading = true;
      _publicEventsError = null;
      _publicEventsResult = null;
    });
    try {
      final resp = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/events/public',
            queryParameters: {'period': 'upcoming'},
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final data = resp.data ?? <String, dynamic>{};
      final events = data['events'] as List? ?? [];
      final leaked = events.any((e) {
        final m = e as Map;
        return m.containsKey('virtual_url') || m.containsKey('join_url');
      });
      setState(() => _publicEventsResult = {
            ...data,
            '_meta': {
              'event_count': events.length,
              'virtual_url_leaked': leaked,
              'verification':
                  leaked ? 'FAIL: virtual_url/join_url in public response' : 'PASS',
            },
          });
    } catch (e, st) {
      AppLogger.error('Public events test failed', e, st);
      if (!mounted) return;
      setState(() => _publicEventsError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _publicEventsLoading = false);
    }
  }

  Future<void> _runEventListTest() async {
    setState(() {
      _eventListLoading = true;
      _eventListError = null;
      _eventListResult = null;
    });
    try {
      final resp = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/events',
            queryParameters: {'page': 1, 'per_page': 20},
            options: Options(headers: {'X-Dev-User': 'admin'}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final data = resp.data ?? <String, dynamic>{};
      setState(() => _eventListResult = {
            ...data,
            '_meta': {
              'total': data['total'],
              'events_count': (data['events'] as List?)?.length ?? 0,
              'verification':
                  (data.containsKey('total') && data.containsKey('events'))
                      ? 'PASS'
                      : 'FAIL: missing total or events fields',
            },
          });
    } catch (e, st) {
      AppLogger.error('Event list test failed', e, st);
      if (!mounted) return;
      setState(() => _eventListError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _eventListLoading = false);
    }
  }

  Future<void> _runEventDetailTest() async {
    final id = _eventId;
    if (id.isEmpty) {
      setState(() => _eventDetailError = 'Enter Event ID in the picker first.');
      return;
    }
    setState(() {
      _eventDetailLoading = true;
      _eventDetailError = null;
      _eventDetailResult = null;
    });
    try {
      final resp = await devDio
          .get<Map<String, dynamic>>('/api/v1/events/public/$id')
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final data = resp.data ?? <String, dynamic>{};
      final leaked = data.containsKey('virtual_url') || data.containsKey('join_url');
      setState(() => _eventDetailResult = {
            ...data,
            '_meta': {
              'has_title': data.containsKey('title'),
              'has_status': data.containsKey('status'),
              'virtual_url_leaked': leaked,
              'verification': leaked
                  ? 'FAIL: virtual_url/join_url leaked in public detail'
                  : 'PASS',
            },
          });
    } catch (e, st) {
      AppLogger.error('Event detail test failed', e, st);
      if (!mounted) return;
      setState(() => _eventDetailError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _eventDetailLoading = false);
    }
  }

  Future<void> _runAdminDetailTest() async {
    final id = _eventId;
    if (id.isEmpty) {
      setState(() => _adminDetailError = 'Enter Event ID in the picker first.');
      return;
    }
    setState(() {
      _adminDetailLoading = true;
      _adminDetailError = null;
      _adminDetailResult = null;
    });
    try {
      final resp = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/events/$id',
            options: Options(headers: {'X-Dev-User': 'admin'}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final data = resp.data ?? <String, dynamic>{};
      setState(() => _adminDetailResult = {
            ...data,
            '_meta': {
              'has_status': data.containsKey('status'),
              'has_capacity': data.containsKey('capacity'),
              'verification':
                  (data.containsKey('event_id') && data.containsKey('status'))
                      ? 'PASS'
                      : 'FAIL: missing event_id or status',
            },
          });
    } catch (e, st) {
      AppLogger.error('Admin event detail test failed', e, st);
      if (!mounted) return;
      setState(() => _adminDetailError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _adminDetailLoading = false);
    }
  }

  Widget _sectionHeader(String text, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 20,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorChip(String error) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 14, color: cs.onErrorContainer),
            const SizedBox(width: 6),
            Expanded(
              child: SelectableText(
                error,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _runButton(String label, bool loading, VoidCallback? onPressed) {
    return OutlinedButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cloud_sync_outlined, size: 18),
      label: Text(label),
    );
  }

  Widget _eventIdPickerCard() {
    return _SmartEventSelectorCard(
      controller: _eventIdController,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DiagnosticDetailScaffold(
      title: 'Event Management Diagnostics',
      description:
          'Run all event management API tests. §1 and §2 require no auth. '
          '§3 and §4 use the Event ID picker.',
      apiDetails: widget.item.apiDetails,
      children: [
        _eventIdPickerCard(),
        _sectionHeader('§1  Public Events API', Icons.public_outlined),
        Text(
          'GET /api/v1/events/public?period=upcoming  ·  No auth required',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        _runButton('Run  →  GET /events/public', _publicEventsLoading,
            _runPublicEventsTest),
        if (_publicEventsError != null) _errorChip(_publicEventsError!),
        _jsonBlock(context, 'Public events response', _publicEventsResult),
        _sectionHeader(
            '§2  Event List API (Admin)', Icons.list_alt_outlined),
        Text(
          'GET /api/v1/events?page=1&per_page=20  ·  Admin JWT required',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        _runButton('Run  →  GET /events (admin)', _eventListLoading,
            _runEventListTest),
        if (_eventListError != null) _errorChip(_eventListError!),
        _jsonBlock(context, 'Event list response', _eventListResult),
        _sectionHeader(
            '§3  Event Detail API (Public)', Icons.event_note_outlined),
        Text(
          'GET /api/v1/events/public/{event_id}  ·  No auth  ·  Uses Event ID picker',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        _runButton('Run  →  GET /events/public/{id}', _eventDetailLoading,
            _runEventDetailTest),
        if (_eventDetailError != null) _errorChip(_eventDetailError!),
        _jsonBlock(context, 'Event detail response', _eventDetailResult),
        _sectionHeader(
            '§4  Event Admin Detail', Icons.manage_search_outlined),
        Text(
          'GET /api/v1/events/{event_id}  ·  Admin JWT required  ·  Uses Event ID picker',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        _runButton('Run  →  GET /events/{id} (admin)', _adminDetailLoading,
            _runAdminDetailTest),
        if (_adminDetailError != null) _errorChip(_adminDetailError!),
        _jsonBlock(context, 'Admin event detail response', _adminDetailResult),
        const SizedBox(height: 40),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin / Attendees Diagnostic Detail
// ─────────────────────────────────────────────────────────────────────────────

class _AdminAttendeeDiagnosticDetail extends StatefulWidget {
  const _AdminAttendeeDiagnosticDetail({required this.item});
  final DiagnosticItem item;

  @override
  State<_AdminAttendeeDiagnosticDetail> createState() =>
      _AdminAttendeeDiagnosticDetailState();
}

class _AdminAttendeeDiagnosticDetailState
    extends State<_AdminAttendeeDiagnosticDetail> {
  final TextEditingController _eventIdController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _batchYearController = TextEditingController();

  bool _listLoading = false;
  Map<String, dynamic>? _listResult;
  String? _listError;

  bool _searchLoading = false;
  Map<String, dynamic>? _searchResult;
  String? _searchError;

  bool _batchLoading = false;
  Map<String, dynamic>? _batchResult;
  String? _batchError;

  bool _exportLoading = false;
  String? _exportResult;
  String? _exportError;

  bool _auditLoading = false;
  Map<String, dynamic>? _auditResult;
  String? _auditError;

  bool _fullDiagLoading = false;
  Map<String, dynamic>? _fullDiagResult;
  String? _fullDiagError;
  String? _fullDiagStatus;

  @override
  void dispose() {
    _eventIdController.dispose();
    _searchController.dispose();
    _batchYearController.dispose();
    super.dispose();
  }

  String get _eventId => _eventIdController.text.trim();

  Future<void> _runAttendeeList() async {
    final id = _eventId;
    if (id.isEmpty) {
      setState(() => _listError = 'Enter Event ID in the picker first.');
      return;
    }
    setState(() {
      _listLoading = true;
      _listError = null;
      _listResult = null;
    });
    try {
      final resp = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/admin/events/$id/attendees',
            queryParameters: {'page': 1, 'per_page': 20},
            options: Options(headers: {'X-Dev-User': 'admin'}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final data = resp.data ?? <String, dynamic>{};
      final attendees = data['attendees'] as List? ?? [];
      final leaked = attendees.any((a) {
        final m = a as Map;
        return m.containsKey('virtual_url') || m.containsKey('join_url');
      });
      final onlyRegistered = attendees.isEmpty ||
          attendees.every((a) => (a as Map)['status'] == 'registered');
      setState(() => _listResult = {
            ...data,
            '_meta': {
              'total': data['total'],
              'attendees_returned': attendees.length,
              'virtual_url_leaked': leaked,
              'all_status_registered': onlyRegistered,
              'verification':
                  (!leaked && onlyRegistered) ? 'PASS' : 'FAIL',
            },
          });
    } catch (e, st) {
      AppLogger.error('Attendee list test failed', e, st);
      if (!mounted) return;
      setState(() => _listError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _listLoading = false);
    }
  }

  Future<void> _runAttendeeSearch() async {
    final id = _eventId;
    if (id.isEmpty) {
      setState(() => _searchError = 'Enter Event ID in the picker first.');
      return;
    }
    setState(() {
      _searchLoading = true;
      _searchError = null;
      _searchResult = null;
    });
    try {
      final search = _searchController.text.trim();
      final params = <String, dynamic>{'page': 1, 'per_page': 20};
      if (search.isNotEmpty) params['search'] = search;
      final resp = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/admin/events/$id/attendees',
            queryParameters: params,
            options: Options(headers: {'X-Dev-User': 'admin'}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final data = resp.data ?? <String, dynamic>{};
      setState(() => _searchResult = {
            ...data,
            '_meta': {
              'search_term': search.isEmpty ? '(none — returns all)' : search,
              'results_count': (data['attendees'] as List?)?.length ?? 0,
              'total': data['total'],
              'verification':
                  data.containsKey('attendees') ? 'PASS' : 'FAIL',
            },
          });
    } catch (e, st) {
      AppLogger.error('Attendee search test failed', e, st);
      if (!mounted) return;
      setState(() => _searchError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  Future<void> _runBatchFilter() async {
    final id = _eventId;
    if (id.isEmpty) {
      setState(() => _batchError = 'Enter Event ID in the picker first.');
      return;
    }
    setState(() {
      _batchLoading = true;
      _batchError = null;
      _batchResult = null;
    });
    try {
      final batchYear = _batchYearController.text.trim();
      final params = <String, dynamic>{'page': 1, 'per_page': 20};
      if (batchYear.isNotEmpty) {
        params['batch_year'] = int.tryParse(batchYear) ?? batchYear;
      }
      final resp = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/admin/events/$id/attendees',
            queryParameters: params,
            options: Options(headers: {'X-Dev-User': 'admin'}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final data = resp.data ?? <String, dynamic>{};
      final attendees = data['attendees'] as List? ?? [];
      final allMatch = batchYear.isEmpty ||
          attendees.every((a) =>
              (a as Map)['batch_year_snapshot']?.toString() == batchYear);
      setState(() => _batchResult = {
            ...data,
            '_meta': {
              'batch_year_filter': batchYear.isEmpty ? '(none)' : batchYear,
              'results_count': attendees.length,
              'all_match_batch': allMatch,
              'verification': allMatch
                  ? 'PASS'
                  : 'FAIL: some rows have different batch_year',
            },
          });
    } catch (e, st) {
      AppLogger.error('Batch filter test failed', e, st);
      if (!mounted) return;
      setState(() => _batchError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _batchLoading = false);
    }
  }

  Future<void> _runAttendeeExport() async {
    final id = _eventId;
    if (id.isEmpty) {
      setState(() => _exportError = 'Enter Event ID in the picker first.');
      return;
    }
    setState(() {
      _exportLoading = true;
      _exportError = null;
      _exportResult = null;
    });
    try {
      final resp = await devDio
          .get<String>(
            '/api/v1/admin/events/$id/attendees/export',
            options: Options(
              headers: {'X-Dev-User': 'admin'},
              responseType: ResponseType.plain,
            ),
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      final csv = resp.data ?? '';
      final lines = csv.split('\n');
      final header = lines.isNotEmpty ? lines[0].replaceAll('﻿', '') : '';
      const expected = [
        'registration_number',
        'fullname_snapshot',
        'email_snapshot',
        'batch_year_snapshot',
        'branch_snapshot',
        'phone_snapshot',
        'registered_at',
        'status',
      ];
      final hasAllCols = expected.every((col) => header.contains(col));
      final hasLeaked = header.contains('virtual_url') ||
          header.contains('join_url') ||
          header.contains('qr_token');
      final dataRows =
          lines.where((l) => l.trim().isNotEmpty).length - 1;
      setState(() => _exportResult =
          'Header: $header\n\nData rows (excl. header): ${dataRows < 0 ? 0 : dataRows}\n\n'
          'All 8 required columns: ${hasAllCols ? "PASS ✓" : "FAIL ✗"}\n'
          'No sensitive fields leaked: ${!hasLeaked ? "PASS ✓" : "FAIL ✗"}');
    } catch (e, st) {
      AppLogger.error('Attendee export test failed', e, st);
      if (!mounted) return;
      setState(() => _exportError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _exportLoading = false);
    }
  }

  Future<void> _runAudit() async {
    final id = _eventId;
    if (id.isEmpty) {
      setState(() => _auditError = 'Enter Event ID in the picker first.');
      return;
    }
    setState(() {
      _auditLoading = true;
      _auditError = null;
      _auditResult = null;
    });
    try {
      final resp = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/admin/events/$id/registrations',
            queryParameters: {'page': 1, 'per_page': 20},
            options: Options(headers: {'X-Dev-User': 'admin'}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final data = resp.data ?? <String, dynamic>{};
      final regs = data['registrations'] as List? ?? [];
      final statuses =
          regs.map((r) => (r as Map)['status']).toSet().toList();
      setState(() => _auditResult = {
            ...data,
            '_meta': {
              'total': data['total'],
              'returned': regs.length,
              'statuses_found': statuses.toString(),
              'verification':
                  data.containsKey('registrations') ? 'PASS' : 'FAIL',
            },
          });
    } catch (e, st) {
      AppLogger.error('Registration audit test failed', e, st);
      if (!mounted) return;
      setState(() => _auditError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _auditLoading = false);
    }
  }

  Future<void> _runFullDiagnostics() async {
    final id = _eventId;
    if (id.isEmpty) {
      setState(() => _fullDiagError = 'Enter Event ID in the picker first.');
      return;
    }
    setState(() {
      _fullDiagLoading = true;
      _fullDiagError = null;
      _fullDiagResult = null;
      _fullDiagStatus = 'Running UC-01 through UC-10 (may take ~10s)...';
    });
    try {
      final resp = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/dev/diagnostics/attendees',
            queryParameters: {'event_id': id},
            options: Options(headers: {'X-Dev-User': 'admin'}),
          )
          .timeout(const Duration(seconds: 60));
      if (!mounted) return;
      final data = resp.data ?? <String, dynamic>{};
      final passed = data['passed'] as int? ?? 0;
      final failed = data['failed'] as int? ?? 0;
      final total = data['total'] as int? ?? 0;
      setState(() {
        _fullDiagResult = data;
        _fullDiagError = null;
        _fullDiagStatus =
            'Completed: $passed/$total passed, $failed failed.';
      });
    } catch (e, st) {
      AppLogger.error('Admin attendee full diagnostics failed', e, st);
      if (!mounted) return;
      setState(() {
        _fullDiagStatus = 'Failed: ${errorMessage(e)}';
        _fullDiagError = errorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _fullDiagLoading = false);
    }
  }

  Widget _sectionHeader(String text, IconData icon, {Color? accent}) {
    final cs = Theme.of(context).colorScheme;
    final color = accent ?? cs.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorChip(String error) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 14, color: cs.onErrorContainer),
            const SizedBox(width: 6),
            Expanded(
              child: SelectableText(
                error,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _runButton(String label, bool loading, VoidCallback? onPressed) {
    return OutlinedButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cloud_sync_outlined, size: 18),
      label: Text(label),
    );
  }

  Widget _plainTextBlock(String title, String? value) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: true,
        title: Text(title,
            style: Theme.of(context).textTheme.labelLarge),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _ucResultCard(Map<String, dynamic> r) {
    final isPassed = r['status'] == 'PASS';
    final uc = r['uc'] as String? ?? '';
    final name = r['name'] as String? ?? r['feature'] as String? ?? '';
    final error = r['error'] as String?;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: isPassed
          ? Colors.green.withValues(alpha: 0.05)
          : cs.errorContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isPassed
              ? Colors.green.withValues(alpha: 0.2)
              : cs.error.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPassed
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color: isPassed ? Colors.green : cs.error,
                  size: 18,
                ),
                const SizedBox(width: 8),
                if (uc.isNotEmpty) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isPassed
                          ? Colors.green.withValues(alpha: 0.12)
                          : cs.errorContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      uc,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isPassed
                                ? Colors.green.shade800
                                : cs.onErrorContainer,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                DiagnosticStatusBadge(
                  status: isPassed
                      ? DiagnosticStatus.ok
                      : DiagnosticStatus.error,
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 4),
              Text(
                error,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _eventIdPickerCard() {
    return _SmartEventSelectorCard(
      controller: _eventIdController,
    );
  }

  @override
  Widget build(BuildContext context) {
    final passed = _fullDiagResult?['passed'] as int? ?? 0;
    final failed = _fullDiagResult?['failed'] as int? ?? 0;
    final total = _fullDiagResult?['total'] as int? ?? 0;
    final results = _fullDiagResult?['results'] as List? ?? [];
    final cs = Theme.of(context).colorScheme;

    return DiagnosticDetailScaffold(
      title: 'Admin / Attendees Diagnostics',
      description:
          'Run attendee management API tests. Enter Event ID in the picker, '
          'then run individual tests or §6 Full Diagnostics for UC-01–UC-10.',
      apiDetails: widget.item.apiDetails,
      children: [
        _eventIdPickerCard(),

        // §1 Attendee List
        _sectionHeader('§1  Attendee List', Icons.people_alt_outlined),
        Text(
          'GET /api/v1/admin/events/{id}/attendees?page=1&per_page=20  ·  Admin JWT',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        _runButton('Run  →  GET /attendees', _listLoading, _runAttendeeList),
        if (_listError != null) _errorChip(_listError!),
        _jsonBlock(context, 'Attendee list response', _listResult),

        // §2 Attendee Search
        _sectionHeader('§2  Attendee Search', Icons.search_outlined),
        Text(
          'GET /admin/events/{id}/attendees?search={term}  ·  Admin JWT',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            labelText: 'Search term (optional — blank returns all)',
            border: OutlineInputBorder(),
            isDense: true,
            prefixIcon: Icon(Icons.search_outlined),
          ),
        ),
        const SizedBox(height: 6),
        _runButton('Run  →  GET /attendees?search=...', _searchLoading,
            _runAttendeeSearch),
        if (_searchError != null) _errorChip(_searchError!),
        _jsonBlock(context, 'Search results', _searchResult),

        // §3 Batch Year Filter
        _sectionHeader('§3  Batch Year Filter', Icons.filter_list_outlined),
        Text(
          'GET /admin/events/{id}/attendees?batch_year={year}  ·  Admin JWT',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _batchYearController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Batch year (e.g. 2005 — blank returns all)',
            border: OutlineInputBorder(),
            isDense: true,
            prefixIcon: Icon(Icons.school_outlined),
          ),
        ),
        const SizedBox(height: 6),
        _runButton('Run  →  GET /attendees?batch_year=...', _batchLoading,
            _runBatchFilter),
        if (_batchError != null) _errorChip(_batchError!),
        _jsonBlock(context, 'Batch filter results', _batchResult),

        // §4 Attendee Export
        _sectionHeader('§4  Attendee Export (CSV)', Icons.download_outlined),
        Text(
          'GET /api/v1/admin/events/{id}/attendees/export  ·  Admin JWT  ·  Checks CSV headers',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        _runButton('Run  →  GET /attendees/export', _exportLoading,
            _runAttendeeExport),
        if (_exportError != null) _errorChip(_exportError!),
        _plainTextBlock('CSV export verification', _exportResult),

        // §5 Registration Audit
        _sectionHeader(
            '§5  Registration Audit', Icons.history_edu_outlined),
        Text(
          'GET /api/v1/admin/events/{id}/registrations?page=1&per_page=20  ·  Admin JWT',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        _runButton('Run  →  GET /registrations (audit)', _auditLoading,
            _runAudit),
        if (_auditError != null) _errorChip(_auditError!),
        _jsonBlock(context, 'Registration audit response', _auditResult),

        // §6 Full Admin Diagnostics
        _sectionHeader(
          '§6  Full Admin Diagnostics (UC-01–UC-10)',
          Icons.admin_panel_settings_outlined,
          accent: cs.secondary,
        ),
        Text(
          'GET /api/v1/dev/diagnostics/attendees?event_id={id}  ·  Admin JWT',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: _fullDiagLoading ? null : _runFullDiagnostics,
          icon: _fullDiagLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.admin_panel_settings_outlined),
          label: const Text('Run Full Diagnostics  →  UC-01 through UC-10'),
        ),
        if (_fullDiagStatus != null) ...[
          const SizedBox(height: 8),
          Text(
            _fullDiagStatus!,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (_fullDiagResult != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              _pill(
                '$passed PASS',
                Colors.green.withValues(alpha: 0.12),
                Colors.green.shade800,
              ),
              const SizedBox(width: 8),
              _pill(
                '$failed FAIL',
                failed > 0 ? cs.errorContainer : cs.surfaceContainerHighest,
                failed > 0 ? cs.onErrorContainer : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'of $total',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...results.map(
              (r) => _ucResultCard(Map<String, dynamic>.from(r as Map))),
        ],
        if (_fullDiagError != null) _errorChip(_fullDiagError!),
        _jsonBlock(context, 'Raw diagnostic response', _fullDiagResult),

        const SizedBox(height: 40),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Smart Event Selector Card — loads events from admin API, drives the picker
// ─────────────────────────────────────────────────────────────────────────────

class _SmartEventSelectorCard extends StatefulWidget {
  const _SmartEventSelectorCard({
    required this.controller,
  });

  final TextEditingController controller;

  @override
  State<_SmartEventSelectorCard> createState() =>
      _SmartEventSelectorCardState();
}

class _SmartEventSelectorCardState extends State<_SmartEventSelectorCard> {
  bool _loading = false;
  List<Map<String, dynamic>> _events = [];
  String? _error;
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await devDio.get<Map<String, dynamic>>(
        '/api/v1/events',
        queryParameters: {'page': 1, 'per_page': 50},
        options: Options(headers: {'X-Dev-User': 'admin'}),
      );
      final list = resp.data?['events'] as List? ?? [];
      if (!mounted) return;
      final events = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        _events = events;
        _loading = false;
      });
      // Auto-select if controller already has a value
      final existing = int.tryParse(widget.controller.text.trim());
      if (existing != null && events.any((e) => e['event_id'] == existing)) {
        setState(() => _selectedId = existing);
      } else if (events.isNotEmpty) {
        // Auto-select the first published event
        final first = events.firstWhere(
          (e) => e['status'] == 'published',
          orElse: () => events.first,
        );
        final id = first['event_id'] as int?;
        if (id != null) {
          setState(() => _selectedId = id);
          widget.controller.text = id.toString();
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  'Event Selector',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16),
                    tooltip: 'Reload events',
                    onPressed: _load,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Select an event from the dropdown or enter an ID manually.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                'Could not load events: $_error',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.error),
              ),
            ],
            if (_events.isEmpty && !_loading && _error == null) ...[
              const SizedBox(height: 8),
              Text(
                'No events found. Create and publish an event in the Admin Portal first.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            if (_events.isNotEmpty) ...[
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Select Event',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                child: DropdownButton<int>(
                  value: _selectedId,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  items: _events.map((e) {
                    final id = e['event_id'] as int?;
                    final title = e['title']?.toString() ?? 'Event $id';
                    final status = e['status']?.toString() ?? '';
                    final isVirtual = e['is_virtual'] as bool? ?? false;
                    final count = e['registered_count']?.toString() ?? '0';
                    final cap = e['capacity']?.toString() ?? '∞';
                    return DropdownMenuItem<int>(
                      value: id,
                      child: Text(
                        '[$id] $title  ·  $status  ·  ${isVirtual ? 'Virtual' : 'Physical'}  ·  $count/$cap',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  }).toList(),
                  onChanged: (id) {
                    if (id == null) return;
                    setState(() => _selectedId = id);
                    widget.controller.text = id.toString();
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: widget.controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Event ID (manual override)',
                hintText: 'Type to override dropdown selection',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.tag_outlined),
              ),
              onChanged: (v) {
                final id = int.tryParse(v.trim());
                if (id != null && id != _selectedId) {
                  setState(() => _selectedId = id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RegistrationDiagnosticDetail extends StatefulWidget {
  const _RegistrationDiagnosticDetail({required this.item});

  final DiagnosticItem item;

  @override
  State<_RegistrationDiagnosticDetail> createState() =>
      _RegistrationDiagnosticDetailState();
}

class _RegistrationDiagnosticDetailState
    extends State<_RegistrationDiagnosticDetail> {
  // ── Section 0: Run All Diagnostics ──────────────────────────────────────
  bool _loading = false;
  String? _status;
  Map<String, dynamic>? _diagResult;
  DiagnosticRunState? _runState;
  String? _backendAccessToken;

  // ── Event ID picker (shared for §2, §3, §5) ─────────────────────────────
  final TextEditingController _eventIdController = TextEditingController();

  // ── Section 1: Alumni Autofill ───────────────────────────────────────────
  bool _autofillLoading = false;
  Map<String, dynamic>? _autofillResult;
  String? _autofillError;

  // ── Section 2: Eligibility ───────────────────────────────────────────────
  bool _eligibilityLoading = false;
  Map<String, dynamic>? _eligibilityResult;
  String? _eligibilityError;

  // ── Section 3: Registration Action ──────────────────────────────────────
  bool _registerLoading = false;
  Map<String, dynamic>? _registerResult;
  String? _registerError;

  // ── Section 5: My Registration ───────────────────────────────────────────
  bool _myRegLoading = false;
  Map<String, dynamic>? _myRegResult;
  String? _myRegError;

  // ── Section 6: My Registrations List ────────────────────────────────────
  bool _myRegListLoading = false;
  Map<String, dynamic>? _myRegListResult;
  String? _myRegListError;

  // ── Section 8: Public API Leak Validation ────────────────────────────────
  bool _publicLeakLoading = false;
  Map<String, dynamic>? _publicLeakResult;
  String? _publicLeakError;

  // ── Section 9: Audit Trail ───────────────────────────────────────────────
  bool _auditLogLoading = false;
  Map<String, dynamic>? _auditLogResult;
  String? _auditLogError;

  @override
  void dispose() {
    _eventIdController.dispose();
    super.dispose();
  }

  String get _eventId => _eventIdController.text.trim();

  // ─────────────────────────────────────────────────────────────────────────
  // build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DiagnosticDetailScaffold(
      title: widget.item.title,
      description: widget.item.description,
      apiDetails: widget.item.apiDetails,
      result: _runState,
      children: [
        // ── Section 0: Run All Diagnostics ───────────────────────────────
        _runAllCard(),
        const SizedBox(height: 8),

        // ── Event ID Picker ───────────────────────────────────────────────
        _eventIdPickerCard(),

        // ── Section 1: Alumni Autofill Preview ───────────────────────────
        _sectionHeader('§1  Alumni Autofill Preview', Icons.person_pin_outlined),
        _alumniAutofillProto(),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _autofillLoading ? null : _fetchAutofill,
          icon: _autofillLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_download_outlined, size: 18),
          label: const Text('Fetch  →  GET /alumni/me'),
        ),
        if (_autofillError != null) _errorChip(_autofillError!),
        _jsonBlock(context, 'GET /api/v1/alumni/me response', _autofillResult),

        // ── Section 2: Registration Eligibility Preview ───────────────────
        _sectionHeader('§2  Registration Eligibility Preview', Icons.rule_outlined),
        _eligibilityProto(),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _eligibilityLoading ? null : _fetchEligibility,
          icon: _eligibilityLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_download_outlined, size: 18),
          label: const Text('Check  →  GET /events/{id}/registration-eligibility'),
        ),
        if (_eligibilityError != null) _errorChip(_eligibilityError!),
        _jsonBlock(context, 'GET /registration-eligibility response', _eligibilityResult),

        // ── Section 3: Registration Action Preview ────────────────────────
        _sectionHeader('§3  Registration Action Preview', Icons.app_registration_outlined),
        _registerProto(),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _registerLoading ? null : _doRegister,
          icon: _registerLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_outlined, size: 18),
          label: const Text('Register (Dev)  →  POST /events/{id}/register'),
        ),
        if (_registerError != null) _errorChip(_registerError!),
        _jsonBlock(context, 'POST /register response', _registerResult),

        // ── Section 4: Confirmation Screen Preview ────────────────────────
        _sectionHeader('§4  Confirmation Screen Preview', Icons.check_circle_outline),
        _confirmationProto(),

        // ── Section 5: My Registration Preview ────────────────────────────
        _sectionHeader('§5  My Registration Preview', Icons.badge_outlined),
        _myRegistrationProto(),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _myRegLoading ? null : _fetchMyRegistration,
          icon: _myRegLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_download_outlined, size: 18),
          label: const Text('Fetch  →  GET /events/{id}/my-registration'),
        ),
        if (_myRegError != null) _errorChip(_myRegError!),
        _jsonBlock(context, 'GET /my-registration response', _myRegResult),

        // ── Section 6: My Registrations List Preview ──────────────────────
        _sectionHeader('§6  My Registrations List Preview', Icons.list_alt_outlined),
        _myRegistrationsListProto(),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _myRegListLoading ? null : _fetchMyRegistrationsList,
          icon: _myRegListLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_download_outlined, size: 18),
          label: const Text('Fetch  →  GET /my/registrations'),
        ),
        if (_myRegListError != null) _errorChip(_myRegListError!),
        _jsonBlock(context, 'GET /my/registrations response', _myRegListResult),

        // ── Section 7: Negative State Gallery ────────────────────────────
        _sectionHeader('§7  Negative State Gallery', Icons.block_outlined),
        _negativeStateGallery(),

        // ── Part C: Frontend Developer Reference Notes ────────────────────
        _sectionHeader('Dev Reference Notes', Icons.book_outlined,
            accent: cs.tertiary),
        _devReferenceNotes(),

        // ── §8: Security Demonstration ────────────────────────────────────
        _sectionHeader('§8  Security Demonstration', Icons.security_outlined,
            accent: cs.error),
        _joinLinkMatrixCard(),
        const SizedBox(height: 8),
        _sectionHeader('  Public API Leak Validation', Icons.verified_outlined,
            accent: cs.error),
        _publicLeakCard(),

        // ── §9: Audit Trail Demonstration ─────────────────────────────────
        _sectionHeader('§9  Audit Trail Demonstration',
            Icons.history_edu_outlined,
            accent: cs.secondary),
        _auditTrailCard(),

        // ── §10: Email Demonstration ──────────────────────────────────────
        _sectionHeader('§10  Email Demonstration',
            Icons.mark_email_read_outlined,
            accent: cs.tertiary),
        _emailDemoCard(),

        // ── §11: Snapshot Demonstration ───────────────────────────────────
        _sectionHeader('§11  Snapshot Demonstration',
            Icons.compare_arrows_outlined,
            accent: cs.tertiary),
        _snapshotDemoCard(),

        // ── §12: Database Rules Demonstration ────────────────────────────
        _sectionHeader('§12  Database Rules Demonstration',
            Icons.rule_folder_outlined),
        _databaseRulesCard(),

        const SizedBox(height: 40),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section 0: Run All Diagnostics card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _runAllCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Backend: $backendBaseUrl'),
            const SizedBox(height: 4),
            Text(
              'Runs all 13 registration diagnostics on the backend. Requires alumni account.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _runDiagnostics,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.app_registration_outlined),
              label: const Text('Run All Registration Diagnostics'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(
                _status!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            if (_diagResult != null) ...[
              const SizedBox(height: 16),
              _resultSummary(),
              const SizedBox(height: 12),
              _resultList(),
            ],
            _jsonBlock(context, 'Raw diagnostic response', _diagResult),
          ],
        ),
      ),
    );
  }

  Widget _resultSummary() {
    final passed = _diagResult?['passed'] as int? ?? 0;
    final failed = _diagResult?['failed'] as int? ?? 0;
    final total = _diagResult?['total'] as int? ?? 0;
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        _pill('$passed PASS', Colors.green.withValues(alpha: 0.12), Colors.green.shade800),
        const SizedBox(width: 8),
        _pill(
          '$failed FAIL',
          failed > 0 ? colorScheme.errorContainer : colorScheme.surfaceContainerHighest,
          failed > 0 ? colorScheme.onErrorContainer : colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text('of $total',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                )),
      ],
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
              )),
    );
  }

  Widget _resultList() {
    final results = _diagResult?['results'] as List? ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in results)
          _resultCard(Map<String, dynamic>.from(r as Map)),
      ],
    );
  }

  Widget _resultCard(Map<String, dynamic> r) {
    final isPassed = r['status'] == 'PASS';
    final isFailed = r['status'] == 'FAIL';
    final feature = r['feature'] as String? ?? '';
    final error = r['error'] as String?;
    final durationMs = r['duration_ms'] as int? ?? 0;
    final response = r['response'] as Map?;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPassed
                      ? Icons.check_circle_outline
                      : isFailed
                          ? Icons.error_outline
                          : Icons.remove_circle_outline,
                  color: isPassed
                      ? Colors.green
                      : isFailed
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(feature,
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                DiagnosticStatusBadge(
                  status: isPassed
                      ? DiagnosticStatus.ok
                      : isFailed
                          ? DiagnosticStatus.error
                          : DiagnosticStatus.notApplicable,
                ),
              ],
            ),
            if (response != null && response.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final entry in response.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(entry.key,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: SelectableText(entry.value?.toString() ?? 'null',
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
            ],
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(error,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                      )),
            ],
            const SizedBox(height: 4),
            Text('$durationMs ms',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    )),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Event ID Picker card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _eventIdPickerCard() {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.tune_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text('Event ID Picker',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text(
              'Used by §2 Eligibility, §3 Register, §5 My Registration.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _eventIdController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Event ID',
                hintText: 'Enter a published event ID',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.tag_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Shared prototype helpers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _sectionHeader(String text, IconData icon, {Color? accent}) {
    final cs = Theme.of(context).colorScheme;
    final color = accent ?? cs.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    )),
          ),
        ],
      ),
    );
  }

  Widget _protoFrame({required String label, required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border.all(color: cs.primary.withValues(alpha: 0.25), width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(children: [
              Icon(Icons.phone_android_outlined, size: 13, color: cs.onPrimaryContainer),
              const SizedBox(width: 6),
              Text('PROTOTYPE — $label',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      )),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _protoHeading(String text) {
    return Text(text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700));
  }

  Widget _protoPlaceholder(String text, {IconData icon = Icons.info_outline}) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  )),
        ),
      ],
    );
  }

  Widget _profileRow(IconData icon, String label, String? value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value ?? '—',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500)),
          ),
        ]),
      ),
    );
  }

  Widget _statusPill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg)),
    );
  }

  Widget _errorChip(String error) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(Icons.error_outline, size: 14, color: cs.onErrorContainer),
          const SizedBox(width: 6),
          Expanded(
            child: SelectableText(error,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onErrorContainer)),
          ),
        ]),
      ),
    );
  }

  String _formatDateTime(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}'
          ' ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section 1: Alumni Autofill Preview
  // ─────────────────────────────────────────────────────────────────────────

  Widget _alumniAutofillProto() {
    // GET /alumni/me returns the alumni object directly (no "alumni" wrapper key)
    final data = _autofillResult;
    final cs = Theme.of(context).colorScheme;
    return _protoFrame(
      label: 'Profile Autofill Screen',
      child: data != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _protoHeading('Confirm Your Profile'),
                const SizedBox(height: 4),
                Text(
                  'Pre-filled from NITKSAA alumni records. Read-only for Week 3.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                _profileRow(Icons.person_outline, 'Name', data['fullname'] as String?),
                _profileRow(Icons.email_outlined, 'Email', data['email'] as String?),
                _profileRow(Icons.phone_outlined, 'Phone', data['phone'] as String?),
                _profileRow(Icons.school_outlined, 'Batch', data['batch_year']?.toString()),
                _profileRow(Icons.business_outlined, 'Branch', data['branch'] as String?),
                _profileRow(Icons.verified_outlined, 'Status',
                    data['is_active'] == true ? 'Active' : 'Inactive'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: null,
                  child: const Text('Confirm & Continue to Register'),
                ),
              ],
            )
          : _protoPlaceholder(
              'Press "Fetch Alumni Profile" to load real profile data.',
              icon: Icons.person_search_outlined,
            ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section 2: Registration Eligibility Preview
  // ─────────────────────────────────────────────────────────────────────────

  Widget _eligibilityProto() {
    // GET /events/{id}/registration-eligibility returns flat:
    // {event_id, eligibility_status: "eligible"|"already_registered"|..., message, registered_count, capacity}
    final data = _eligibilityResult;
    final cs = Theme.of(context).colorScheme;
    final eligStatus = data?['eligibility_status'] as String?;

    return _protoFrame(
      label: 'Event Detail — Registration State',
      child: data != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _protoHeading('Event ID: ${data['event_id']}'),
                const SizedBox(height: 6),
                Row(children: [
                  _statusPill(
                    '${data['registered_count']}/${data['capacity'] ?? '∞'} registered',
                    cs.surfaceContainerHighest,
                    cs.onSurfaceVariant,
                  ),
                ]),
                const SizedBox(height: 12),
                _eligibilityBanner(eligStatus, data['message'] as String? ?? ''),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: null,
                  child: Text(_eligibilityCta(eligStatus)),
                ),
              ],
            )
          : _protoPlaceholder(
              'Enter an event ID above and press "Check Eligibility".',
              icon: Icons.rule_outlined,
            ),
    );
  }

  Widget _eligibilityBanner(String? eligStatus, String message) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg, icon) = _uiStateStyle(eligStatus, cs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(icon, size: 16, color: fg),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w500,
                  )),
        ),
      ]),
    );
  }

  // Maps eligibility_status from the actual API (v2) to visual style.
  // v2 values: eligible, already_registered, full, closed, not_open_yet, ineligible
  // Note: POST /register uses different detail strings (event_full, registration_closed,
  // registration_not_open_yet) — these are HTTP error codes, not eligibility_status values.
  (Color, Color, IconData) _uiStateStyle(String? eligStatus, ColorScheme cs) {
    return switch (eligStatus) {
      'eligible' => (
          Colors.green.withValues(alpha: 0.12),
          Colors.green.shade800,
          Icons.check_circle_outline,
        ),
      'already_registered' => (
          cs.secondaryContainer,
          cs.onSecondaryContainer,
          Icons.check_circle,
        ),
      'full' => (cs.errorContainer, cs.onErrorContainer, Icons.do_not_disturb_outlined),
      'closed' => (cs.errorContainer, cs.onErrorContainer, Icons.lock_clock_outlined),
      'not_open_yet' => (
          cs.tertiaryContainer,
          cs.onTertiaryContainer,
          Icons.hourglass_top_outlined,
        ),
      _ => (cs.surfaceContainerHighest, cs.onSurfaceVariant, Icons.info_outline),
    };
  }

  String _eligibilityCta(String? eligStatus) {
    return switch (eligStatus) {
      'eligible' => 'Register',
      'already_registered' => 'View My Registration',
      'full' => 'Event Full',
      'closed' => 'Registration Closed',
      'not_open_yet' => 'Registration Not Open Yet',
      _ => 'Check Eligibility',
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section 3: Registration Action Preview
  // ─────────────────────────────────────────────────────────────────────────

  Widget _registerProto() {
    // POST /events/{id}/register returns flat response:
    // {registration_id, registration_number, status, fullname_snapshot, email_snapshot,
    //  batch_year_snapshot, branch_snapshot, join_url, confirmation_email_status, event: {...}}
    final data = _registerResult;
    final regNum = data?['registration_number'] as String?;
    final cs = Theme.of(context).colorScheme;

    return _protoFrame(
      label: 'Register for Event',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _protoHeading('Confirm & Register'),
          const SizedBox(height: 4),
          Text(
            'Profile pre-filled from NITKSAA alumni records. Tap Register to confirm.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (data != null) ...[
            _profileRow(Icons.person_outline, 'Name', data['fullname_snapshot'] as String?),
            _profileRow(Icons.email_outlined, 'Email', data['email_snapshot'] as String?),
            _profileRow(Icons.school_outlined, 'Batch', data['batch_year_snapshot']?.toString()),
            _profileRow(Icons.business_outlined, 'Branch', data['branch_snapshot'] as String?),
          ] else ...[
            _protoPlaceholder('Alumni profile will appear here after §1 fetch.'),
          ],
          const SizedBox(height: 8),
          if (regNum == null)
            FilledButton(onPressed: null, child: const Text('Register'))
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Registered: $regNum',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade800,
                        ),
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section 4: Confirmation Screen Preview
  // ─────────────────────────────────────────────────────────────────────────

  Widget _confirmationProto() {
    // POST /events/{id}/register returns flat:
    // {registration_number, status, join_url, confirmation_email_status, event: {is_virtual, ...}}
    final data = _registerResult;
    final cs = Theme.of(context).colorScheme;

    if (data == null) {
      return _protoFrame(
        label: 'Registration Confirmation Screen',
        child: _protoPlaceholder(
          'Run §3 Registration Action first to see the live confirmation.',
          icon: Icons.check_circle_outline,
        ),
      );
    }

    final regNum = data['registration_number'] as String? ?? '—';
    final joinUrl = data['join_url'] as String?;
    final emailStatusVal = data['confirmation_email_status'] as String? ?? 'unknown';
    final event = data['event'] as Map?;
    final isVirtual = event?['is_virtual'] == true;
    final secondaryMsg = isVirtual && joinUrl != null
        ? 'Join link is now available for this webinar.'
        : 'Your registration number is $regNum.';

    return _protoFrame(
      label: 'Registration Confirmation Screen',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 48),
          const SizedBox(height: 8),
          Text(
            "You're registered.",
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            secondaryMsg,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(children: [
              Text('Registration Number',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: cs.onPrimaryContainer)),
              const SizedBox(height: 4),
              SelectableText(
                regNum,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onPrimaryContainer,
                      letterSpacing: 1.2,
                    ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          if (isVirtual && joinUrl != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.video_call_outlined, color: cs.onSecondaryContainer, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Join Link Available',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onSecondaryContainer,
                              )),
                      SelectableText(joinUrl,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSecondaryContainer,
                              )),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
          ],
          _emailStatusRow(emailStatusVal),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.badge_outlined),
            label: const Text('View My Registration'),
          ),
        ],
      ),
    );
  }

  Widget _emailStatusRow(String status) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color, text) = switch (status) {
      'sent' => (Icons.mark_email_read_outlined, Colors.green, 'Confirmation email sent'),
      'failed' => (
          Icons.email_outlined,
          cs.error,
          'Email could not be sent — save your registration number',
        ),
      'skipped' => (Icons.email_outlined, cs.onSurfaceVariant, 'Email skipped (dev mode)'),
      _ => (Icons.hourglass_top_outlined, cs.onSurfaceVariant, 'Email status: $status'),
    };
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Expanded(
        child: Text(text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
      ),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section 5: My Registration Preview
  // ─────────────────────────────────────────────────────────────────────────

  Widget _myRegistrationProto() {
    // GET /events/{id}/my-registration returns flat (same shape as register response):
    // {registration_number, status, registered_at, join_url, event: {is_virtual, location_text, title}}
    final data = _myRegResult;
    final event = data?['event'] as Map?;
    final isRegistered = data?['status'] == 'registered';
    final cs = Theme.of(context).colorScheme;

    return _protoFrame(
      label: 'My Registration Detail',
      child: (data != null && isRegistered)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _protoHeading(event?['title'] as String? ?? 'Event'),
                const SizedBox(height: 12),
                _profileRow(Icons.confirmation_number_outlined, 'Reg #',
                    data['registration_number'] as String?),
                _profileRow(Icons.event_outlined, 'Status', data['status'] as String?),
                _profileRow(Icons.schedule_outlined, 'Registered',
                    _formatDateTime(data['registered_at'] as String?)),
                if (event?['is_virtual'] == true) ...[
                  const SizedBox(height: 8),
                  if ((data['join_url'] as String?) != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        Icon(Icons.video_call_outlined,
                            color: cs.onSecondaryContainer, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Join Link',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: cs.onSecondaryContainer,
                                      )),
                              SelectableText(data['join_url'] as String,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: cs.onSecondaryContainer,
                                      )),
                            ],
                          ),
                        ),
                      ]),
                    )
                  else
                    _protoPlaceholder('Join link not yet available.',
                        icon: Icons.video_call_outlined),
                ] else if (event?['location_text'] != null) ...[
                  _profileRow(Icons.location_on_outlined, 'Venue',
                      event!['location_text'] as String?),
                ],
              ],
            )
          : _protoPlaceholder(
              data != null
                  ? 'Not registered for this event.'
                  : 'Enter event ID above and press "Fetch My Registration".',
              icon: Icons.badge_outlined,
            ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section 6: My Registrations List Preview
  // ─────────────────────────────────────────────────────────────────────────

  Widget _myRegistrationsListProto() {
    final list = _myRegListResult?['registrations'] as List?;
    final total = _myRegListResult?['total'] as int?;

    return _protoFrame(
      label: 'My Registrations List',
      child: (list != null && list.isNotEmpty)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _protoHeading('My Registrations'),
                if (total != null) ...[
                  const SizedBox(height: 2),
                  Text('$total registration(s) found',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 12),
                for (final item in list)
                  _registrationListCard(Map<String, dynamic>.from(item as Map)),
              ],
            )
          : _protoPlaceholder(
              _myRegListResult != null
                  ? 'No registrations found.'
                  : 'Press "Fetch My Registrations" to load the list.',
              icon: Icons.list_alt_outlined,
            ),
    );
  }

  Widget _registrationListCard(Map<String, dynamic> item) {
    final cs = Theme.of(context).colorScheme;
    final event = item['event'] as Map? ?? {};
    // join_url is at top level of each registration item (not under an "access" key)
    final isVirtual = event['is_virtual'] == true;
    final joinUrl = item['join_url'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(event['title'] as String? ?? 'Event',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              _statusPill(
                isVirtual ? 'Virtual' : 'Physical',
                isVirtual ? cs.secondaryContainer : cs.tertiaryContainer,
                isVirtual ? cs.onSecondaryContainer : cs.onTertiaryContainer,
              ),
            ]),
            const SizedBox(height: 4),
            Text(item['registration_number'] as String? ?? '—',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: cs.primary,
                    )),
            const SizedBox(height: 4),
            Text(_formatDateTime(item['registered_at'] as String?),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
            if (isVirtual && joinUrl != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.video_call_outlined, size: 14, color: cs.secondary),
                const SizedBox(width: 4),
                Expanded(
                  child: SelectableText(joinUrl,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.secondary)),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section 7: Negative State Gallery
  // ─────────────────────────────────────────────────────────────────────────

  Widget _negativeStateGallery() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Static reference cards for all error states. No API call needed.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        _negativeCard('alumni_only', Icons.group_off_outlined,
            'Only NITKSAA alumni can register for this event. '
            '(POST error detail="alumni_only"; eligibility returns eligibility_status="ineligible")',
            'Contact Support',
            isError: true),
        _negativeCard('alumni_not_active', Icons.person_off_outlined,
            'Your alumni profile is not active. Please contact support. '
            '(POST error detail="alumni_not_active"; eligibility returns eligibility_status="ineligible")',
            'Contact Support',
            isError: true),
        _negativeCard('already_registered', Icons.check_circle,
            "You're already registered for this event. "
            '(POST error detail="already_registered"; eligibility returns eligibility_status="already_registered")',
            'View My Registration'),
        _negativeCard('event_full', Icons.do_not_disturb_outlined,
            'This event is full. No more registrations accepted. '
            '(POST error detail="event_full"; eligibility returns eligibility_status="full")',
            'Register button disabled',
            isError: true),
        _negativeCard('registration_closed', Icons.lock_clock_outlined,
            'Registration is closed for this event. '
            '(POST error detail="registration_closed"; eligibility returns eligibility_status="closed")',
            'Register button disabled',
            isError: true),
        _negativeCard('registration_not_open_yet', Icons.hourglass_top_outlined,
            'Registration is not open yet. Check back later. '
            '(POST error detail="registration_not_open_yet"; eligibility returns eligibility_status="not_open_yet")',
            'Register button disabled',
            isWarning: true),
        _negativeCard('event_not_published', Icons.event_busy_outlined,
            'This event is not available for registration.',
            'N/A',
            isError: true),
        _negativeCard('confirm_profile_required', Icons.warning_amber_outlined,
            'Please confirm your profile before registering.',
            'Confirm Profile',
            isWarning: true),
        _negativeCard('email_failed (non-blocking)', Icons.email_outlined,
            "You're registered. Confirmation email could not be sent. Please save your registration number.",
            'Save Registration Number',
            isWarning: true),
      ],
    );
  }

  Widget _negativeCard(
    String errorCode,
    IconData icon,
    String message,
    String cta, {
    bool isError = false,
    bool isWarning = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = isError
        ? (cs.errorContainer, cs.onErrorContainer)
        : isWarning
            ? (cs.tertiaryContainer, cs.onTertiaryContainer)
            : (cs.secondaryContainer, cs.onSecondaryContainer);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
              child: Text(errorCode,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      )),
            ),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon,
                  size: 18,
                  color: isError
                      ? cs.error
                      : isWarning
                          ? cs.tertiary
                          : cs.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message, style: Theme.of(context).textTheme.bodySmall),
              ),
            ]),
            const SizedBox(height: 6),
            Text('CTA: $cta',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    )),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Part C: Frontend Developer Reference Notes
  // ─────────────────────────────────────────────────────────────────────────

  Widget _devReferenceNotes() {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Frontend Developer Reference Notes',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _refNote('1. Profile autofill',
                'Call GET /alumni/me after login. Fields are read-only for Week 3. '
                'Display with a confirm button before allowing registration.'),
            _refNote('2. Registration flow order',
                '① GET /alumni/me → autofill profile\n'
                '② GET /events/{id}/registration-eligibility → check eligibility_status\n'
                '③ POST /events/{id}/register — body: {"attendee_note": "optional"}'),
            _refNote('3. Confirmation screen',
                'Show registration_number prominently in a pill/chip. '
                'Display join_url for virtual events. '
                'Show email status as a secondary non-blocking message.'),
            _refNote('4. join_url security rule',
                'join_url only appears in authenticated user endpoints '
                '(/my-registration, /my/registrations). '
                'Never in the public events API. Never in the virtual_url field.'),
            _refNote('5. Error codes → UI state (v2 values)',
                'POST detail "alumni_only" / eligibility "ineligible" → "Alumni only" message\n'
                'POST detail "alumni_not_active" / eligibility "ineligible" → "Contact support"\n'
                'POST detail "event_full" / eligibility "full" → disabled register button\n'
                'POST detail "registration_closed" / eligibility "closed" → disabled register button\n'
                'POST detail "registration_not_open_yet" / eligibility "not_open_yet" → disabled register button\n'
                'POST detail "already_registered" / eligibility "already_registered" → "View Registration" CTA\n'
                'eligibility "ineligible" → read message field to distinguish alumni_only vs alumni_not_active'),
            _refNote('6. Email failure handling',
                'Never block the UI on email failure. Registration is confirmed even if '
                'confirmation_email_status = "failed". '
                'Show a banner asking the user to save their number.'),
            _refNote('7. Week 3 scope',
                'Physical + virtual registration only. '
                'No waitlist, no payment, no QR codes, no attendance. '
                'Add-to-calendar payload is in the response but .ics generation is deferred.'),
          ],
        ),
      ),
    );
  }

  Widget _refNote(String heading, String body) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: cs.primary)),
          const SizedBox(height: 2),
          Text(body,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // §8: Security Demonstration widgets
  // ─────────────────────────────────────────────────────────────────────────

  Widget _joinLinkMatrixCard() {
    final cs = Theme.of(context).colorScheme;
    const rows = [
      ('registered', 'virtual', 'published', true),
      ('cancelled', 'virtual', 'published', false),
      ('registered', 'physical', 'published', false),
      ('registered', 'virtual', 'draft', false),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Join Link Visibility Matrix',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Only one combination of conditions exposes join_url.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            // Header row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                _matrixCell('Registration', isHeader: true),
                _matrixCell('Event Type', isHeader: true),
                _matrixCell('Status', isHeader: true),
                _matrixCell('Join Link', isHeader: true),
              ]),
            ),
            const SizedBox(height: 4),
            for (final r in rows)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: r.$4
                      ? Colors.green.withValues(alpha: 0.08)
                      : cs.surfaceContainerLowest,
                  border: Border.all(
                    color: r.$4
                        ? Colors.green.withValues(alpha: 0.3)
                        : cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  _matrixCell(r.$1),
                  _matrixCell(r.$2),
                  _matrixCell(r.$3),
                  Expanded(
                    child: Row(children: [
                      Icon(
                        r.$4
                            ? Icons.check_circle
                            : Icons.cancel_outlined,
                        size: 14,
                        color: r.$4 ? Colors.green : cs.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        r.$4 ? 'Visible' : 'Hidden',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: r.$4 ? Colors.green.shade800 : cs.error,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.lock_outlined,
                    size: 14, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'join_url is only exposed when: status=registered AND '
                    'is_virtual=true AND event_status=published.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _matrixCell(String text, {bool isHeader = false}) {
    return Expanded(
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: isHeader ? FontWeight.w700 : FontWeight.w500,
              color: isHeader
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _publicLeakCard() {
    final cs = Theme.of(context).colorScheme;
    final leakedFields = _publicLeakResult?['leaked_fields'] as List?;
    final passed = _publicLeakResult != null && (leakedFields?.isEmpty ?? true);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Verify: Public Event Payload has no virtual_url or join_url',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _publicLeakLoading ? null : _fetchPublicLeak,
              icon: _publicLeakLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.security_outlined, size: 18),
              label: const Text('Check  →  GET /events/public/{id}'),
            ),
            if (_publicLeakError != null) _errorChip(_publicLeakError!),
            if (_publicLeakResult != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: passed
                      ? Colors.green.withValues(alpha: 0.1)
                      : cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: passed
                        ? Colors.green.withValues(alpha: 0.3)
                        : cs.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(children: [
                  Icon(
                    passed ? Icons.verified : Icons.warning_amber_outlined,
                    color: passed ? Colors.green : cs.onErrorContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          passed ? 'PASS — No sensitive fields leaked' : 'FAIL — Fields leaked',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: passed
                                    ? Colors.green.shade800
                                    : cs.onErrorContainer,
                              ),
                        ),
                        if (!passed && leakedFields != null)
                          Text(leakedFields.join(', '),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: cs.onErrorContainer)),
                      ],
                    ),
                  ),
                ]),
              ),
              _jsonBlock(context, 'Public event payload', _publicLeakResult),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // §9: Audit Trail Demonstration
  // ─────────────────────────────────────────────────────────────────────────

  Widget _auditTrailCard() {
    final cs = Theme.of(context).colorScheme;
    final rows =
        (_auditLogResult?['rows'] as List?)?.take(8).toList() ?? const [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Latest audit log rows from event_audit_log. '
              'Records are written automatically on every state-changing action.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _auditLogLoading ? null : _fetchAuditLog,
              icon: _auditLogLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.history_edu_outlined, size: 18),
              label: const Text(
                  'Fetch  →  GET /dev/diagnostics/db/event_audit_log'),
            ),
            if (_auditLogError != null) _errorChip(_auditLogError!),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final r in rows)
                _auditRowCard(Map<String, dynamic>.from(r as Map)),
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 14,
                      color: cs.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Audit records written automatically on every '
                      'registration, cancellation, and event status change.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSecondaryContainer,
                          ),
                    ),
                  ),
                ]),
              ),
            ] else if (_auditLogResult != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No audit rows found.'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _auditRowCard(Map<String, dynamic> row) {
    final cs = Theme.of(context).colorScheme;
    final eventType = row['event_type']?.toString() ?? '—';
    final entityType = row['entity_type']?.toString() ?? '—';
    final entityId = row['entity_id']?.toString() ?? '—';
    final createdAt = row['created_at']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: cs.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eventType,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('$entityType #$entityId',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        Text(
          _formatDateTime(createdAt),
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // §10: Email Demonstration
  // ─────────────────────────────────────────────────────────────────────────

  Widget _emailDemoCard() {
    final cs = Theme.of(context).colorScheme;
    final data = _registerResult;

    if (data == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _protoPlaceholder(
            'Run §3 Registration Action first to see live email status.',
            icon: Icons.mark_email_read_outlined,
          ),
        ),
      );
    }

    final emailStatus =
        data['confirmation_email_status'] as String? ?? 'unknown';
    final sentAt = data['confirmation_email_sent_at'] as String?;
    final regNum = data['registration_number'] as String? ?? '—';

    final (icon, color, label) = switch (emailStatus) {
      'sent' => (
          Icons.mark_email_read_outlined,
          Colors.green,
          'Confirmation email sent'
        ),
      'failed' => (Icons.email_outlined, cs.error, 'Email delivery failed'),
      'skipped' => (
          Icons.email_outlined,
          cs.onSurfaceVariant,
          'Email skipped (dev/log mode)'
        ),
      _ => (
          Icons.hourglass_top_outlined,
          cs.onSurfaceVariant,
          'Email status: $emailStatus'
        ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _profileRow(Icons.confirmation_number_outlined, 'Reg #', regNum),
            _profileRow(Icons.schedule_outlined, 'Sent At',
                sentAt != null ? _formatDateTime(sentAt) : '—'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: emailStatus == 'sent'
                    ? Colors.green.withValues(alpha: 0.1)
                    : emailStatus == 'failed'
                        ? cs.errorContainer
                        : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          )),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, size: 14,
                    color: cs.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Email delivery never blocks registration success. '
                    'Registration is confirmed even if confirmation_email_status = "failed".',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onTertiaryContainer,
                        ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // §11: Snapshot Demonstration
  // ─────────────────────────────────────────────────────────────────────────

  Widget _snapshotDemoCard() {
    final cs = Theme.of(context).colorScheme;
    final profile = _autofillResult;
    final reg = _registerResult;

    if (profile == null && reg == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _protoPlaceholder(
            'Fetch §1 Alumni Profile and run §3 Registration to compare.',
            icon: Icons.compare_arrows_outlined,
          ),
        ),
      );
    }

    final fields = [
      ('Full Name', 'fullname', 'fullname_snapshot'),
      ('Batch Year', 'batch_year', 'batch_year_snapshot'),
      ('Branch', 'branch', 'branch_snapshot'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text('Alumni Profile (live)',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const Icon(Icons.compare_arrows_outlined, size: 16),
              Expanded(
                child: Text('Registration Snapshot',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 12),
            for (final f in fields) _snapshotRow(f.$1, f.$2, f.$3, profile, reg),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.save_outlined, size: 14,
                    color: cs.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Snapshot fields are frozen at registration time. '
                    'Changes to the alumni profile after registration do not affect the snapshot.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onTertiaryContainer,
                        ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _snapshotRow(
    String label,
    String profileKey,
    String snapshotKey,
    Map<String, dynamic>? profile,
    Map<String, dynamic>? reg,
  ) {
    final cs = Theme.of(context).colorScheme;
    final liveVal = profile?[profileKey]?.toString() ?? '—';
    final snapVal = reg?[snapshotKey]?.toString() ?? '—';
    final match = liveVal == snapVal;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          )),
                  const SizedBox(height: 2),
                  Text(liveVal,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Icon(
              match ? Icons.compare_arrows : Icons.warning_amber_outlined,
              size: 16,
              color: match ? cs.primary : cs.error,
            ),
          ),
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          )),
                  const SizedBox(height: 2),
                  Text(snapVal,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // §12: Database Rules Demonstration
  // ─────────────────────────────────────────────────────────────────────────

  Widget _databaseRulesCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dbRuleCard(
          icon: Icons.tag_outlined,
          title: 'Unique Registration Number',
          rule:
              'NITKSAA-{year}-{registration_id:06d} — generated server-side.',
          purpose:
              'Guarantees a human-readable, globally unique identifier for every registration.',
          status: 'Verified — format enforced by registration_service.py',
        ),
        _dbRuleCard(
          icon: Icons.lock_outlined,
          title: 'Partial Unique Registration',
          rule: 'UNIQUE (event_id, firebase_uid) WHERE status = \'registered\'.',
          purpose:
              'Prevents double-registration for the same user + event combination '
              'while allowing re-registration after cancellation.',
          status: 'Verified — partial index in migration 008',
        ),
        _dbRuleCard(
          icon: Icons.refresh_outlined,
          title: 'Re-registration After Cancellation',
          rule:
              'Cancelled registrations are soft-deleted (status=\'cancelled\'). '
              'A new row is inserted on re-registration.',
          purpose:
              'Preserves full audit history. The partial unique index permits re-registration.',
          status: 'Verified — tested in Diag 6 (duplicate guard)',
        ),
        _dbRuleCard(
          icon: Icons.groups_outlined,
          title: 'Registered Count Excludes Cancelled',
          rule:
              'COUNT(*) WHERE event_id=\$id AND status=\'registered\' — '
              'cancelled rows not counted.',
          purpose:
              'Capacity guard is accurate. Cancelling frees up a slot for another registrant.',
          status: 'Verified — tested in Diag 7 (capacity guard)',
        ),
      ],
    );
  }

  Widget _dbRuleCard({
    required IconData icon,
    required String title,
    required String rule,
    required String purpose,
    required String status,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 6),
            _dbRuleRow('Rule', rule),
            _dbRuleRow('Purpose', purpose),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: Colors.green.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_outline,
                    size: 12, color: Colors.green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(status,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dbRuleRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    )),
          ),
          Expanded(
            child: Text(value,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Fetch methods
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _fetchAutofill() async {
    if (!mounted) return;
    setState(() {
      _autofillLoading = true;
      _autofillError = null;
    });
    try {
      final token = await _ensureBackendAccessToken();
      final response = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/alumni/me',
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _autofillResult = response.data);
    } catch (e, st) {
      AppLogger.error('Alumni autofill fetch failed', e, st);
      if (!mounted) return;
      setState(() => _autofillError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _autofillLoading = false);
    }
  }

  Future<void> _fetchEligibility() async {
    if (!mounted) return;
    final eventId = _eventId;
    if (eventId.isEmpty) {
      setState(() => _eligibilityError = 'Enter an event ID in the picker above.');
      return;
    }
    setState(() {
      _eligibilityLoading = true;
      _eligibilityError = null;
    });
    try {
      final token = await _ensureBackendAccessToken();
      final response = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/events/$eventId/registration-eligibility',
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _eligibilityResult = response.data);
    } catch (e, st) {
      AppLogger.error('Eligibility fetch failed', e, st);
      if (!mounted) return;
      setState(() => _eligibilityError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _eligibilityLoading = false);
    }
  }

  Future<void> _doRegister() async {
    if (!mounted) return;
    final eventId = _eventId;
    if (eventId.isEmpty) {
      setState(() => _registerError = 'Enter an event ID in the picker above.');
      return;
    }
    setState(() {
      _registerLoading = true;
      _registerError = null;
    });
    try {
      final token = await _ensureBackendAccessToken();
      final response = await devDio
          .post<Map<String, dynamic>>(
            '/api/v1/events/$eventId/register',
            data: {
              'confirm_profile': true,
              'attendee_note': 'Dev diagnostics prototype test',
            },
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() => _registerResult = response.data);
    } catch (e, st) {
      AppLogger.error('Registration action failed', e, st);
      if (!mounted) return;
      setState(() => _registerError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _registerLoading = false);
    }
  }

  Future<void> _fetchMyRegistration() async {
    if (!mounted) return;
    final eventId = _eventId;
    if (eventId.isEmpty) {
      setState(() => _myRegError = 'Enter an event ID in the picker above.');
      return;
    }
    setState(() {
      _myRegLoading = true;
      _myRegError = null;
    });
    try {
      final token = await _ensureBackendAccessToken();
      final response = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/events/$eventId/my-registration',
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _myRegResult = response.data);
    } catch (e, st) {
      AppLogger.error('My registration fetch failed', e, st);
      if (!mounted) return;
      setState(() => _myRegError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _myRegLoading = false);
    }
  }

  Future<void> _fetchMyRegistrationsList() async {
    if (!mounted) return;
    setState(() {
      _myRegListLoading = true;
      _myRegListError = null;
    });
    try {
      final token = await _ensureBackendAccessToken();
      final response = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/my/registrations',
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _myRegListResult = response.data);
    } catch (e, st) {
      AppLogger.error('My registrations list fetch failed', e, st);
      if (!mounted) return;
      setState(() => _myRegListError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _myRegListLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // §8: Public API leak check fetch
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _fetchPublicLeak() async {
    if (!mounted) return;
    final eventId = _eventId;
    if (eventId.isEmpty) {
      setState(() =>
          _publicLeakError = 'Enter an event ID in the picker above.');
      return;
    }
    setState(() {
      _publicLeakLoading = true;
      _publicLeakError = null;
    });
    try {
      final response = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/events/public/$eventId',
          )
          .timeout(const Duration(seconds: 15));
      final data = response.data ?? <String, dynamic>{};
      const forbidden = ['virtual_url', 'join_url', 'created_by_firebase_uid'];
      final leaked = forbidden.where((f) => data.containsKey(f)).toList();
      if (!mounted) return;
      setState(() => _publicLeakResult = {
            ...data,
            'leaked_fields': leaked,
          });
    } catch (e, st) {
      AppLogger.error('Public leak check failed', e, st);
      if (!mounted) return;
      setState(() => _publicLeakError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _publicLeakLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // §9: Audit trail fetch
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _fetchAuditLog() async {
    if (!mounted) return;
    setState(() {
      _auditLogLoading = true;
      _auditLogError = null;
    });
    try {
      final token = await _ensureBackendAccessToken();
      final response = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/dev/diagnostics/db/event_audit_log',
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _auditLogResult = response.data);
    } catch (e, st) {
      AppLogger.error('Audit log fetch failed', e, st);
      if (!mounted) return;
      setState(() => _auditLogError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _auditLogLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section 0: Run All diagnostics
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _runDiagnostics() async {
    setState(() {
      _loading = true;
      _status = 'Authenticating...';
      _diagResult = null;
    });

    try {
      final token = await _ensureBackendAccessToken();

      setState(() => _status = 'Running registration diagnostics (may take ~10s)...');

      final response = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/dev/diagnostics/registrations',
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          )
          .timeout(const Duration(seconds: 90));

      final data = response.data ?? <String, dynamic>{};
      final passed = data['passed'] as int? ?? 0;
      final failed = data['failed'] as int? ?? 0;
      final total = data['total'] as int? ?? 0;

      if (!mounted) return;
      setState(() {
        _diagResult = data;
        _status = 'Completed: $passed/$total passed, $failed failed.';
        _runState = DiagnosticRunState(
          status: failed == 0 ? DiagnosticStatus.ok : DiagnosticStatus.warning,
          lastRun: DateTime.now(),
        );
      });
    } catch (error, stackTrace) {
      AppLogger.error('Registration diagnostic failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _status = 'Failed: ${errorMessage(error)}';
        _runState = DiagnosticRunState(
          status: DiagnosticStatus.error,
          lastRun: DateTime.now(),
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _ensureBackendAccessToken() async {
    final existing = _backendAccessToken;
    if (existing != null && existing.isNotEmpty) return existing;

    // Prefer the stored session so alumni don't need to re-authenticate
    final store = AuthSessionStore();
    final session = await store.load();
    if (session != null && session.accessToken.isNotEmpty) {
      if (mounted) setState(() => _backendAccessToken = session.accessToken);
      return session.accessToken;
    }

    // Fall back to a fresh Firebase token exchange
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError(
        'Not signed in. Complete the Backend Auth diagnostic first.',
      );
    }
    final firebaseToken = await user.getIdToken(true);
    if (firebaseToken == null || firebaseToken.isEmpty) {
      throw StateError('Firebase ID token unavailable.');
    }
    final resp = await devDio.post<Map<String, dynamic>>(
      '/api/v1/auth/firebase',
      data: {'token': firebaseToken},
    );
    final accessToken = resp.data?['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Backend access token exchange failed.');
    }
    if (mounted) setState(() => _backendAccessToken = accessToken);
    return accessToken;
  }
}

class DiagnosticDetailScaffold extends StatelessWidget {
  const DiagnosticDetailScaffold({
    super.key,
    required this.title,
    required this.description,
    required this.children,
    this.result,
    this.apiDetails,
  });

  final String title;
  final String description;
  final List<Widget> children;
  final DiagnosticRunState? result;
  final BackendApiDetails? apiDetails;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(onPressed: () => Navigator.of(context).pop(result)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          if (apiDetails != null) ...[
            BackendApiDetailsCard(details: apiDetails!),
            const SizedBox(height: 16),
          ],
          ...children,
        ],
      ),
    );
  }
}

class _FoundationDetail extends ConsumerWidget {
  const _FoundationDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final firebaseAppName =
        AppState.firebaseInitialized ? _safeFirebaseAppName() : 'N/A';
    final result = DiagnosticRunState(
      status: AppState.firebaseInitialized
          ? DiagnosticStatus.ok
          : DiagnosticStatus.error,
      lastRun: DateTime.now(),
    );

    return DiagnosticDetailScaffold(
      title: 'Foundation Status',
      description: 'Current app foundation, routing, platform, and auth state.',
      result: result,
      apiDetails: diagnosticApiDetails[DiagnosticId.foundation]!,
      children: [
        Card(
          child: Column(
            children: [
              const _DiagRow(label: 'App Name', value: 'NITKSAA Event'),
              _divider,
              const _DiagRow(label: 'Environment', value: 'Development'),
              _divider,
              _DiagRow(
                label: 'Firebase',
                value: AppState.firebaseInitialized ? 'Initialized' : 'Failed',
                status: AppState.firebaseInitialized
                    ? DiagnosticStatus.ok
                    : DiagnosticStatus.error,
              ),
              _divider,
              _DiagRow(label: 'Firebase App', value: firebaseAppName),
              _divider,
              const _DiagRow(
                label: 'Hive',
                value: 'Initialized',
                status: DiagnosticStatus.ok,
              ),
              _divider,
              _DiagRow(label: 'Theme Mode', value: _themeModeLabel(themeMode)),
              _divider,
              _DiagRow(label: 'Platform', value: platformLabel()),
              _divider,
              const _DiagRow(
                label: 'Router',
                value: 'Active',
                status: DiagnosticStatus.ok,
              ),
              _divider,
              const _DiagRow(
                label: 'Logger',
                value: 'Active',
                status: DiagnosticStatus.ok,
              ),
              _divider,
              _DiagRow(
                label: 'Auth Status',
                value: FirebaseAuth.instance.currentUser != null
                    ? 'Logged In'
                    : 'Logged Out',
                status: FirebaseAuth.instance.currentUser != null
                    ? DiagnosticStatus.ok
                    : DiagnosticStatus.info,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _safeFirebaseAppName() {
    try {
      return Firebase.app().name;
    } catch (_) {
      return 'Unknown';
    }
  }
}

class _LoggerDetail extends StatelessWidget {
  const _LoggerDetail();

  @override
  Widget build(BuildContext context) {
    final result = DiagnosticRunState(
      status: DiagnosticStatus.info,
      lastRun: DateTime.now(),
    );

    return DiagnosticDetailScaffold(
      title: 'Logger Test',
      description: 'Emit test messages through the app logger.',
      result: result,
      apiDetails: diagnosticApiDetails[DiagnosticId.logger]!,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      AppLogger.debug('Test debug from developer diagnostics'),
                  icon: const Icon(Icons.bug_report_outlined),
                  label: const Text('Log Debug'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      AppLogger.info('Test info from developer diagnostics'),
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Log Info'),
                ),
                OutlinedButton.icon(
                  onPressed: () => AppLogger.warning(
                    'Test warning from developer diagnostics',
                  ),
                  icon: const Icon(Icons.warning_amber_outlined),
                  label: const Text('Log Warning'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      AppLogger.error('Test error from developer diagnostics'),
                  icon: const Icon(Icons.error_outline),
                  label: const Text('Log Error'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemeDetail extends ConsumerWidget {
  const _ThemeDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final result = DiagnosticRunState(
      status: DiagnosticStatus.info,
      lastRun: DateTime.now(),
    );

    return DiagnosticDetailScaffold(
      title: 'Theme Control',
      description: 'Switch the app theme mode for visual verification.',
      result: result,
      apiDetails: diagnosticApiDetails[DiagnosticId.theme]!,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.settings_suggest_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {themeMode},
              onSelectionChanged: (selection) =>
                  ref.read(themeProvider.notifier).setTheme(selection.first),
            ),
          ),
        ),
      ],
    );
  }
}

class _NetworkDetail extends StatefulWidget {
  const _NetworkDetail();

  @override
  State<_NetworkDetail> createState() => _NetworkDetailState();
}

class _NetworkDetailState extends State<_NetworkDetail> {
  bool _loading = false;
  String? _status;
  Map<String, dynamic>? _healthResponse;
  DiagnosticRunState? _result;

  @override
  Widget build(BuildContext context) {
    return DiagnosticDetailScaffold(
      title: 'Network Test',
      description: 'Check backend base URL and /api/v1/health reachability.',
      result: _result,
      apiDetails: diagnosticApiDetails[DiagnosticId.network]!,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SummaryField(label: 'Backend Base URL', value: backendBaseUrl),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loading ? null : _runHealthCheck,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering_outlined),
                  label: const Text('Run Health Check'),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(_status!),
                ],
                _jsonBlock(context, 'Health response', _healthResponse),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _runHealthCheck() async {
    setState(() {
      _loading = true;
      _status = 'Checking backend health...';
    });

    try {
      final response = await devDio
          .get<Map<String, dynamic>>('/api/v1/health')
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _healthResponse = response.data ?? <String, dynamic>{};
        _status = 'Backend health endpoint responded.';
        _result = DiagnosticRunState(
          status: DiagnosticStatus.ok,
          lastRun: DateTime.now(),
        );
      });
    } catch (error, stackTrace) {
      AppLogger.error('Dev network health check failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _status = 'Network check failed: ${errorMessage(error)}';
        _result = DiagnosticRunState(
          status: DiagnosticStatus.error,
          lastRun: DateTime.now(),
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _PerformanceDetail extends StatelessWidget {
  const _PerformanceDetail();

  @override
  Widget build(BuildContext context) {
    final result = DiagnosticRunState(
      status: DiagnosticStatus.info,
      lastRun: DateTime.now(),
    );
    return DiagnosticDetailScaffold(
      title: 'App Performance',
      description: 'Runtime diagnostics useful during emulator verification.',
      result: result,
      apiDetails: diagnosticApiDetails[DiagnosticId.performance]!,
      children: [
        Card(
          child: Column(
            children: [
              _DiagRow(
                label: 'Build Mode',
                value: kDebugMode ? 'Debug' : 'Release',
              ),
              _divider,
              _DiagRow(label: 'Platform', value: platformLabel()),
              _divider,
              const _DiagRow(
                label: 'Renderer',
                value: 'Flutter engine managed',
                status: DiagnosticStatus.info,
              ),
              _divider,
              const _DiagRow(
                label: 'Manual Check',
                value: 'Use DevTools for frame timing',
                status: DiagnosticStatus.info,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DebugToolsDetail extends StatefulWidget {
  const _DebugToolsDetail();

  @override
  State<_DebugToolsDetail> createState() => _DebugToolsDetailState();
}

class _DebugToolsDetailState extends State<_DebugToolsDetail> {
  bool _clearing = false;
  bool _exporting = false;
  String? _status;
  DiagnosticRunState? _result;

  @override
  Widget build(BuildContext context) {
    return DiagnosticDetailScaffold(
      title: 'Debug Tools',
      description: 'Clipboard export and local diagnostic cache utilities.',
      result: _result,
      apiDetails: diagnosticApiDetails[DiagnosticId.debugTools]!,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _exporting ? null : _exportDebugSummary,
                  icon: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_outlined),
                  label: const Text('Export Diagnostic Report'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _clearing ? null : _clearCache,
                  icon: _clearing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Clear Cached Data'),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(_status!),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportDebugSummary() async {
    setState(() => _exporting = true);
    final report = 'NITKSAA Event Debug Tools\n'
        'Generated: ${DateTime.now().toLocal()}\n'
        'Platform: ${platformLabel()}\n'
        'Firebase initialized: ${AppState.firebaseInitialized}\n';
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _status = 'Debug report copied to clipboard.';
      _result = DiagnosticRunState(
        status: DiagnosticStatus.ok,
        lastRun: DateTime.now(),
      );
    });
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    try {
      final store = AuthSessionStore();
      await store.initialize();
      await store.clear();
      if (!mounted) return;
      setState(() {
        _clearing = false;
        _status = 'Cached backend session cleared.';
        _result = DiagnosticRunState(
          status: DiagnosticStatus.warning,
          lastRun: DateTime.now(),
        );
      });
    } catch (error, stackTrace) {
      AppLogger.error('Dev clear cache failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _clearing = false;
        _status = 'Clear cache failed: $error';
        _result = DiagnosticRunState(
          status: DiagnosticStatus.error,
          lastRun: DateTime.now(),
        );
      });
    }
  }
}

enum _AuthDiagnosticMode {
  firebaseToken,
  backendAuth,
  authMe,
  eventUsers,
  databaseTables,
  fullValidation,
}

class _AuthDiagnosticDetail extends StatefulWidget {
  const _AuthDiagnosticDetail({
    required this.title,
    required this.mode,
    required this.apiDetails,
    this.autoRunFullValidation = false,
  });

  final String title;
  final _AuthDiagnosticMode mode;
  final BackendApiDetails apiDetails;
  final bool autoRunFullValidation;

  @override
  State<_AuthDiagnosticDetail> createState() => _AuthDiagnosticDetailState();
}

class _AuthDiagnosticDetailState extends State<_AuthDiagnosticDetail> {
  bool _loading = false;
  bool _backendLoading = false;
  bool _meLoading = false;
  bool _tablesLoading = false;
  bool _tableLoading = false;
  bool _fullValidationLoading = false;
  int _validationPassed = 0;
  int _validationFailed = 0;
  String? _firebaseIdToken;
  String? _backendAccessToken;
  String? _tokenPreview;
  String? _status;
  String? _backendStatus;
  String? _meStatus;
  String? _tableStatus;
  DateTime? _lastValidationAt;
  DateTime? _lastTablesRefreshedAt;
  DateTime? _lastTableRefreshedAt;
  Map<String, dynamic>? _backendLoginResponse;
  Map<String, dynamic>? _authMeResponse;
  List<Map<String, dynamic>> _tables = const [];
  Map<String, dynamic>? _selectedTableData;
  DiagnosticRunState? _result;

  @override
  void initState() {
    super.initState();
    if (widget.autoRunFullValidation) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runFullValidation());
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    return DiagnosticDetailScaffold(
      title: widget.title,
      description: _descriptionForMode(widget.mode),
      result: _result,
      apiDetails: widget.apiDetails,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Backend: $backendBaseUrl'),
                const SizedBox(height: 12),
                _authSummary(firebaseUser),
                const SizedBox(height: 12),
                ..._actionsForMode(widget.mode),
                _statusMessages(),
                if (_tokenPreview != null) _tokenPreviewBlock(),
                _jsonBlock(
                  context,
                  'Backend login response',
                  _backendLoginResponse,
                ),
                _jsonBlock(context, '/auth/me response', _authMeResponse),
                if (_showsTables(widget.mode)) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Database Viewer',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tables refreshed: ${formatDiagnosticTimestamp(_lastTablesRefreshedAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  _tableCards(),
                  _selectedTableView(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _descriptionForMode(_AuthDiagnosticMode mode) => switch (mode) {
        _AuthDiagnosticMode.firebaseToken =>
          'Get a Firebase ID token in debug mode and show only a shortened preview.',
        _AuthDiagnosticMode.backendAuth =>
          'Validate Firebase authentication through the backend JWT exchange.',
        _AuthDiagnosticMode.authMe =>
          'Validate the backend JWT against /api/v1/auth/me.',
        _AuthDiagnosticMode.eventUsers =>
          'Fetch the event_users diagnostic table through the backend.',
        _AuthDiagnosticMode.databaseTables =>
          'Refresh database table metadata and inspect diagnostic rows.',
        _AuthDiagnosticMode.fullValidation =>
          'Run Firebase token, backend login, /auth/me, event_users, and table checks.',
      };

  List<Widget> _actionsForMode(_AuthDiagnosticMode mode) {
    final fullButton = FilledButton.icon(
      onPressed: _fullValidationLoading ? null : _runFullValidation,
      icon: _fullValidationLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.play_circle_outline),
      label: const Text('Run Full Validation'),
    );

    return switch (mode) {
      _AuthDiagnosticMode.firebaseToken => [
          FilledButton.icon(
            onPressed: _loading ? null : _getFirebaseIdToken,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.key_outlined),
            label: const Text('Dev: Get Firebase ID Token'),
          ),
          if (_firebaseIdToken != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _copyFirebaseIdToken,
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy Firebase ID Token'),
            ),
          ],
        ],
      _AuthDiagnosticMode.backendAuth => [
          FilledButton.icon(
            onPressed:
                _backendLoading ? null : _validateFirebaseTokenWithBackend,
            icon: _backendLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_user_outlined),
            label: const Text('Validate Firebase Token with Backend'),
          ),
        ],
      _AuthDiagnosticMode.authMe => [
          FilledButton.icon(
            onPressed: _meLoading ? null : _validateAuthMe,
            icon: _meLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_search_outlined),
            label: const Text('Validate /auth/me'),
          ),
        ],
      _AuthDiagnosticMode.eventUsers => [
          FilledButton.icon(
            onPressed: _tableLoading ? null : _refreshEventUsers,
            icon: _tableLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.manage_accounts_outlined),
            label: const Text('Refresh event_users'),
          ),
        ],
      _AuthDiagnosticMode.databaseTables => [
          FilledButton.icon(
            onPressed: _tablesLoading ? null : _refreshTables,
            icon: _tablesLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.table_chart_outlined),
            label: const Text('Refresh Database Tables'),
          ),
        ],
      _AuthDiagnosticMode.fullValidation => [
          fullButton,
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed:
                    _backendLoading ? null : _validateFirebaseTokenWithBackend,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Backend Login'),
              ),
              OutlinedButton.icon(
                onPressed: _meLoading ? null : _validateAuthMe,
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('/auth/me'),
              ),
              OutlinedButton.icon(
                onPressed: _tableLoading ? null : _refreshEventUsers,
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('event_users'),
              ),
              OutlinedButton.icon(
                onPressed: _tablesLoading ? null : _refreshTables,
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Tables'),
              ),
            ],
          ),
        ],
    };
  }

  bool _showsTables(_AuthDiagnosticMode mode) {
    return mode == _AuthDiagnosticMode.eventUsers ||
        mode == _AuthDiagnosticMode.databaseTables ||
        mode == _AuthDiagnosticMode.fullValidation;
  }

  Widget _statusMessages() {
    final messages = [
      _status,
      _backendStatus,
      _meStatus,
      _tableStatus,
    ].whereType<String>().toList();
    if (messages.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final message in messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tokenPreviewBlock() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Token length: ${_firebaseIdToken?.length ?? 0}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            _tokenPreview!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Future<void> _getFirebaseIdToken() async {
    setState(() {
      _loading = true;
      _firebaseIdToken = null;
      _tokenPreview = null;
      _status = kIsWeb
          ? 'Getting Firebase ID token...'
          : 'Starting Google sign-in...';
    });

    try {
      User? user;

      if (kIsWeb) {
        user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          final provider = GoogleAuthProvider();
          provider.addScope('email');
          provider.addScope('profile');
          final userCredential = await FirebaseAuth.instance.signInWithPopup(
            provider,
          );
          user = userCredential.user;
        }
      } else {
        await GoogleSignInInitializer.ensureInitialized();
        final googleUser = await GoogleSignIn.instance.authenticate();
        final googleAuth = googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );
        final userCredential = await FirebaseAuth.instance.signInWithCredential(
          credential,
        );
        user = userCredential.user;
      }

      final token = await user?.getIdToken(true);

      if (user == null || token == null) {
        throw StateError('FirebaseAuth did not return a user/token.');
      }

      debugPrint('Firebase UID: ${user.uid}');
      debugPrint('Email: ${user.email}');
      debugPrint('Display name: ${user.displayName ?? ''}');
      debugPrint('Firebase ID Token length: ${token.length}');
      debugPrint('Firebase ID Token preview: ${shortToken(token)}');

      if (!mounted) return;
      setState(() {
        _firebaseIdToken = token;
        _tokenPreview = shortToken(token);
        _status = 'Firebase ID token captured.';
        _lastValidationAt = DateTime.now();
        _result = DiagnosticRunState(
          status: DiagnosticStatus.ok,
          lastRun: _lastValidationAt,
        );
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'Dev Firebase ID token generation failed',
        error,
        stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _status = 'Failed: $error';
        _result = DiagnosticRunState(
          status: DiagnosticStatus.error,
          lastRun: DateTime.now(),
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _validateFirebaseTokenWithBackend() async {
    setState(() {
      _backendLoading = true;
      _backendStatus = 'Validating Firebase token with backend...';
    });

    try {
      final token = await _freshFirebaseIdToken();
      final response = await devDio.post<Map<String, dynamic>>(
        '/api/v1/auth/firebase',
        data: {'token': token},
      );
      final data = response.data ?? <String, dynamic>{};
      final accessToken = data['access_token'] as String?;

      if (accessToken == null || accessToken.isEmpty) {
        throw StateError('Backend did not return an access token.');
      }

      if (!mounted) return;
      setState(() {
        _firebaseIdToken = token;
        _tokenPreview = shortToken(token);
        _backendAccessToken = accessToken;
        _backendLoginResponse = data;
        _backendStatus = 'Backend login status: ${data['status'] ?? 'ok'}';
        _lastValidationAt = DateTime.now();
        _result = DiagnosticRunState(
          status: DiagnosticStatus.ok,
          lastRun: _lastValidationAt,
        );
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'Dev backend Firebase validation failed',
        error,
        stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _backendStatus = 'Backend login failed: ${errorMessage(error)}';
        _result = DiagnosticRunState(
          status: DiagnosticStatus.error,
          lastRun: DateTime.now(),
        );
      });
    } finally {
      if (mounted) setState(() => _backendLoading = false);
    }
  }

  Future<void> _validateAuthMe() async {
    setState(() {
      _meLoading = true;
      _meStatus = 'Validating /auth/me...';
    });

    try {
      final accessToken = await _ensureBackendAccessToken();
      final response = await devDio.get<Map<String, dynamic>>(
        '/api/v1/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );

      if (!mounted) return;
      setState(() {
        _authMeResponse = response.data ?? <String, dynamic>{};
        _meStatus = '/auth/me returned authenticated user.';
        _lastValidationAt = DateTime.now();
        _result = DiagnosticRunState(
          status: DiagnosticStatus.ok,
          lastRun: _lastValidationAt,
        );
      });
    } catch (error, stackTrace) {
      AppLogger.error('Dev /auth/me validation failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _meStatus = '/auth/me failed: ${errorMessage(error)}';
        _result = DiagnosticRunState(
          status: DiagnosticStatus.error,
          lastRun: DateTime.now(),
        );
      });
    } finally {
      if (mounted) setState(() => _meLoading = false);
    }
  }

  Future<void> _runFullValidation() async {
    setState(() {
      _fullValidationLoading = true;
      _validationPassed = 0;
      _validationFailed = 0;
      _status = 'Running Firebase token validation...';
      _backendStatus = 'Pending backend login...';
      _meStatus = 'Pending /auth/me...';
      _tableStatus = 'Pending database validation...';
    });

    var passed = 0;
    var failed = 0;
    String? accessToken;

    try {
      final token = await _freshFirebaseIdToken().timeout(
        const Duration(seconds: 30),
      );
      passed += 1;
      if (!mounted) return;
      setState(() {
        _firebaseIdToken = token;
        _tokenPreview = shortToken(token);
        _status = 'Firebase token available.';
        _validationPassed = passed;
        _validationFailed = failed;
      });

      try {
        final response = await devDio.post<Map<String, dynamic>>(
          '/api/v1/auth/firebase',
          data: {'token': token},
        ).timeout(const Duration(seconds: 30));
        final data = response.data ?? <String, dynamic>{};
        accessToken = data['access_token'] as String?;
        if (accessToken == null || accessToken.isEmpty) {
          throw StateError('Backend did not return an access token.');
        }
        passed += 2;
        if (!mounted) return;
        setState(() {
          _backendAccessToken = accessToken;
          _backendLoginResponse = data;
          _backendStatus = 'Backend login passed; JWT generated.';
          _validationPassed = passed;
          _validationFailed = failed;
        });
      } catch (error, stackTrace) {
        failed += 2;
        AppLogger.error(
          'Dev full validation backend login failed',
          error,
          stackTrace,
        );
        if (!mounted) return;
        setState(() {
          _backendStatus = 'Backend login failed: ${errorMessage(error)}';
          _validationPassed = passed;
          _validationFailed = failed;
        });
      }
    } catch (error, stackTrace) {
      failed += 6;
      AppLogger.error(
        'Dev full validation Firebase token failed',
        error,
        stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _status = 'Firebase token failed: ${errorMessage(error)}';
        _backendStatus = 'Skipped backend login.';
        _meStatus = 'Skipped /auth/me.';
        _tableStatus = 'Skipped database validation.';
        _validationPassed = passed;
        _validationFailed = failed;
        _lastValidationAt = DateTime.now();
        _fullValidationLoading = false;
        _result = DiagnosticRunState(
          status: DiagnosticStatus.error,
          lastRun: _lastValidationAt,
        );
      });
      return;
    }

    if (accessToken != null && accessToken.isNotEmpty) {
      await _runAuthMeStep(accessToken, passed, failed);
      passed = _validationPassed;
      failed = _validationFailed;
      await _runTableListStep(accessToken, passed, failed);
      passed = _validationPassed;
      failed = _validationFailed;
      await _runEventUsersStep(accessToken, passed, failed);
    }

    if (!mounted) return;
    setState(() {
      _lastValidationAt = DateTime.now();
      _fullValidationLoading = false;
      _result = DiagnosticRunState(
        status: _validationFailed == 0
            ? DiagnosticStatus.ok
            : DiagnosticStatus.warning,
        lastRun: _lastValidationAt,
      );
    });
  }

  Future<void> _runAuthMeStep(
    String accessToken,
    int passed,
    int failed,
  ) async {
    try {
      final response = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/auth/me',
            options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
          )
          .timeout(const Duration(seconds: 30));
      passed += 1;
      if (!mounted) return;
      setState(() {
        _authMeResponse = response.data ?? <String, dynamic>{};
        _meStatus = '/auth/me passed.';
        _validationPassed = passed;
        _validationFailed = failed;
      });
    } catch (error, stackTrace) {
      failed += 1;
      AppLogger.error('Dev full validation /auth/me failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _meStatus = '/auth/me failed: ${errorMessage(error)}';
        _validationPassed = passed;
        _validationFailed = failed;
      });
    }
  }

  Future<void> _runTableListStep(
    String accessToken,
    int passed,
    int failed,
  ) async {
    try {
      final response = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/dev/diagnostics/db/tables',
            options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
          )
          .timeout(const Duration(seconds: 30));
      final rawTables = response.data?['tables'];
      final tables = rawTables is List
          ? rawTables
              .whereType<Map>()
              .map((table) => Map<String, dynamic>.from(table))
              .toList()
          : <Map<String, dynamic>>[];
      passed += 1;
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _tableStatus = 'Database tables loaded.';
        _lastTablesRefreshedAt = DateTime.now();
        _validationPassed = passed;
        _validationFailed = failed;
      });
    } catch (error, stackTrace) {
      failed += 1;
      AppLogger.error(
        'Dev full validation table list failed',
        error,
        stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _tableStatus = 'Database tables failed: ${errorMessage(error)}';
        _validationPassed = passed;
        _validationFailed = failed;
      });
    }
  }

  Future<void> _runEventUsersStep(
    String accessToken,
    int passed,
    int failed,
  ) async {
    try {
      final response = await devDio
          .get<Map<String, dynamic>>(
            '/api/v1/dev/diagnostics/db/event_users',
            options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
          )
          .timeout(const Duration(seconds: 30));
      passed += 1;
      if (!mounted) return;
      setState(() {
        _selectedTableData = response.data ?? <String, dynamic>{};
        _tableStatus = 'event_users loaded.';
        _lastTableRefreshedAt = DateTime.now();
        _validationPassed = passed;
        _validationFailed = failed;
      });
    } catch (error, stackTrace) {
      failed += 1;
      AppLogger.error(
        'Dev full validation event_users failed',
        error,
        stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _tableStatus = 'event_users failed: ${errorMessage(error)}';
        _validationPassed = passed;
        _validationFailed = failed;
      });
    }
  }

  Future<void> _refreshTables() async {
    setState(() {
      _tablesLoading = true;
      _tableStatus = 'Refreshing database table list...';
    });

    try {
      final accessToken = await _ensureBackendAccessToken();
      final response = await devDio.get<Map<String, dynamic>>(
        '/api/v1/dev/diagnostics/db/tables',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final rawTables = response.data?['tables'];
      final tables = rawTables is List
          ? rawTables
              .whereType<Map>()
              .map((table) => Map<String, dynamic>.from(table))
              .toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _tables = tables;
        _tableStatus = 'Database table list refreshed.';
        _lastTablesRefreshedAt = DateTime.now();
        _result = DiagnosticRunState(
          status: DiagnosticStatus.ok,
          lastRun: _lastTablesRefreshedAt,
        );
      });
    } catch (error, stackTrace) {
      AppLogger.error('Dev database table refresh failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _tableStatus = 'Table refresh failed: ${errorMessage(error)}';
        _result = DiagnosticRunState(
          status: DiagnosticStatus.error,
          lastRun: DateTime.now(),
        );
      });
    } finally {
      if (mounted) setState(() => _tablesLoading = false);
    }
  }

  Future<void> _refreshEventUsers() => _refreshTable('event_users');

  Future<void> _refreshTable(String tableName) async {
    setState(() {
      _tableLoading = true;
      _tableStatus = 'Refreshing $tableName...';
    });

    try {
      final accessToken = await _ensureBackendAccessToken();
      final response = await devDio.get<Map<String, dynamic>>(
        '/api/v1/dev/diagnostics/db/$tableName',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );

      if (!mounted) return;
      setState(() {
        _selectedTableData = response.data ?? <String, dynamic>{};
        _tableStatus = '$tableName refreshed.';
        _lastTableRefreshedAt = DateTime.now();
        _result = DiagnosticRunState(
          status: DiagnosticStatus.ok,
          lastRun: _lastTableRefreshedAt,
        );
      });
    } catch (error, stackTrace) {
      AppLogger.error('Dev database table fetch failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _selectedTableData = {
          'table': tableName,
          'available': false,
          'row_count': 0,
          'rows': const [],
          'error': errorMessage(error),
        };
        _tableStatus = '$tableName failed: ${errorMessage(error)}';
        _result = DiagnosticRunState(
          status: DiagnosticStatus.error,
          lastRun: DateTime.now(),
        );
      });
    } finally {
      if (mounted) setState(() => _tableLoading = false);
    }
  }

  Future<String> _freshFirebaseIdToken() async {
    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await _getFirebaseIdToken();
      user = FirebaseAuth.instance.currentUser;
    }

    final token = await user?.getIdToken(true);
    if (user == null || token == null || token.isEmpty) {
      throw StateError('Firebase user or ID token is unavailable.');
    }
    return token;
  }

  Future<String> _ensureBackendAccessToken() async {
    final existing = _backendAccessToken;
    if (existing != null && existing.isNotEmpty) return existing;

    final token = await _freshFirebaseIdToken();
    final response = await devDio.post<Map<String, dynamic>>(
      '/api/v1/auth/firebase',
      data: {'token': token},
    );
    final accessToken = response.data?['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Backend access token is unavailable.');
    }

    if (mounted) {
      setState(() {
        _firebaseIdToken = token;
        _tokenPreview = shortToken(token);
        _backendAccessToken = accessToken;
        _backendLoginResponse = response.data ?? <String, dynamic>{};
        _backendStatus =
            'Backend login status: ${response.data?['status'] ?? 'ok'}';
      });
    }
    return accessToken;
  }

  Future<void> _copyFirebaseIdToken() async {
    final token = _firebaseIdToken;
    if (token == null) return;

    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Firebase ID token copied.')));
  }

  Widget _authSummary(User? user) {
    final backendFailed =
        _backendStatus?.toLowerCase().contains('failed') ?? false;
    final meFailed = _meStatus?.toLowerCase().contains('failed') ?? false;
    final userName = _authMeResponse?['fullname']?.toString() ??
        _backendLoginResponse?['fullname']?.toString() ??
        user?.displayName ??
        'N/A';
    final email = _authMeResponse?['email']?.toString() ??
        _backendLoginResponse?['email']?.toString() ??
        user?.email ??
        'N/A';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusPill(
                'Firebase Login',
                indicatorStateFor(
                  user != null,
                  _status?.startsWith('Failed') ?? false,
                ),
              ),
              _statusPill(
                'Backend Login',
                indicatorStateFor(_backendLoginResponse != null, backendFailed),
              ),
              _statusPill(
                'JWT Generated',
                indicatorStateFor(_backendAccessToken != null, backendFailed),
              ),
              _statusPill(
                '/auth/me',
                indicatorStateFor(_authMeResponse != null, meFailed),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SummaryField(label: 'User', value: userName),
          const SizedBox(height: 8),
          _SummaryField(label: 'Email', value: email),
          const SizedBox(height: 8),
          _SummaryField(
            label: 'Firebase UID',
            value: user?.uid ??
                _authMeResponse?['firebase_uid']?.toString() ??
                'N/A',
          ),
          const SizedBox(height: 8),
          _SummaryField(
            label: 'Last Validation',
            value: formatDiagnosticTimestamp(_lastValidationAt),
          ),
          if (_validationPassed > 0 || _validationFailed > 0) ...[
            const SizedBox(height: 8),
            _SummaryField(
              label: 'Full Validation',
              value: 'Passed: $_validationPassed  Failed: $_validationFailed',
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusPill(String label, IndicatorState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final (text, color, foreground) = switch (state) {
      IndicatorState.passed => (
          'OK $label',
          Colors.green.withValues(alpha: 0.12),
          Colors.green.shade800,
        ),
      IndicatorState.failed => (
          'ERROR $label',
          colorScheme.errorContainer,
          colorScheme.onErrorContainer,
        ),
      IndicatorState.pending => (
          'PENDING $label',
          colorScheme.surfaceContainerHighest,
          colorScheme.onSurfaceVariant,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _tableCards() {
    if (_tablesLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_tables.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text('No table metadata loaded.'),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          for (final table in _tables)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _tableLoading
                    ? null
                    : () => _refreshTable(table['name'].toString()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          table['name']?.toString() ?? 'unknown',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (table['available'] == true)
                        _CountBadge(
                          value: table['row_count']?.toString() ?? '0',
                        )
                      else
                        Flexible(
                          child: Text(
                            table['error']?.toString() ?? 'Unavailable',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _selectedTableView() {
    final data = _selectedTableData;
    if (_tableLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (data == null) return const SizedBox.shrink();

    final tableName = data['table']?.toString() ?? 'table';
    final rows = data['rows'] is List ? data['rows'] as List : const [];
    final error = data['error'];

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$tableName (${data['row_count'] ?? rows.length} rows)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            'Last refreshed: ${formatDiagnosticTimestamp(_lastTableRefreshedAt)}',
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              'Error: $error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ] else if (rows.isEmpty) ...[
            const SizedBox(height: 8),
            const Text('No rows found.'),
          ] else ...[
            const SizedBox(height: 8),
            for (var index = 0; index < rows.length; index++)
              _rowCard(
                tableName,
                index + 1,
                Map<String, dynamic>.from(rows[index] as Map),
              ),
          ],
        ],
      ),
    );
  }

  Widget _rowCard(String tableName, int index, Map<String, dynamic> row) {
    final title = rowTitle(tableName, row, index);
    final fields = displayFieldsForRow(tableName, row);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final entry in fields.entries) _KeyValueLine(entry: entry),
          ],
        ),
      ),
    );
  }
}

enum DiagnosticId {
  foundation,
  logger,
  theme,
  firebaseToken,
  backendAuth,
  authMe,
  eventUsers,
  databaseTables,
  network,
  performance,
  debugTools,
  eventsApi,
  eventDetailApi,
  eventCreationApi,
  eventPublish,
  registrationApi,
  myRegistration,
  capacityGuard,
  confirmationEmail,
  joinLinkVisibility,
  attendeeListApi,
  attendeeSearchTest,
  attendeeBatchFilter,
  attendeeExport,
  adminRoleGuard,
  auditTrail,
  week3UxShowcase,
  alumniSearchEmail,
  alumniSearchPrefix,
  alumniLookupId,
  alumniLoginTrace,
  week5EventOptions,
  week5People,
  week5SponsorsPartners,
  week5Analytics,
  week5All,
}

enum DiagnosticStatus { ok, info, warning, error, notApplicable }

enum IndicatorState { passed, pending, failed }

const Map<DiagnosticId, BackendApiDetails> diagnosticApiDetails = {
  DiagnosticId.foundation: BackendApiDetails(
    featureName: 'Foundation Status',
    method: 'GET',
    path: '/api/v1/health',
    authRequirement: 'No',
    purpose:
        'Verify backend health when needed; local rows also inspect app foundation state.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"status":"ok","version":"1.0.0","env":"development","db":"ok"}',
    uiGuidance: 'Use to show environment, platform, and backend reachability.',
  ),
  DiagnosticId.logger: BackendApiDetails(
    featureName: 'Logger Test',
    method: 'NONE',
    path: 'No backend API',
    authRequirement: 'No',
    purpose: 'Emit local app log messages for debug verification.',
    implementationStatus: 'Implemented',
    sampleResponse: 'Local log output only.',
    uiGuidance: 'Keep logger controls in debug-only tools.',
  ),
  DiagnosticId.theme: BackendApiDetails(
    featureName: 'Theme Control',
    method: 'NONE',
    path: 'No backend API',
    authRequirement: 'No',
    purpose: 'Switch app theme mode locally for visual verification.',
    implementationStatus: 'Implemented',
    sampleResponse: 'No network response.',
    uiGuidance: 'Use segmented controls for Light, System, and Dark.',
  ),
  DiagnosticId.firebaseToken: BackendApiDetails(
    featureName: 'Firebase Token Test',
    method: 'NONE',
    path: 'FirebaseAuth.currentUser.getIdToken(true)',
    authRequirement: 'Firebase user required',
    purpose: 'Get Firebase ID token from FirebaseAuth.currentUser.',
    implementationStatus: 'Implemented',
    sampleResponse:
        'Short token preview only; full token must not be shown in production UI.',
    uiGuidance: 'Show token length and shortened preview only in debug UI.',
  ),
  DiagnosticId.backendAuth: BackendApiDetails(
    featureName: 'Backend Auth Test',
    method: 'POST',
    path: '/api/v1/auth/firebase',
    authRequirement: 'Firebase ID token required',
    purpose: 'Exchange Firebase token for backend JWT.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"status":"ok","access_token":"<jwt>","token_type":"bearer","firebase_uid":"...","user_type":"alumni","fullname":"..."}',
    uiGuidance:
        'On success, persist backend JWT through the auth session store.',
  ),
  DiagnosticId.authMe: BackendApiDetails(
    featureName: '/auth/me Test',
    method: 'GET',
    path: '/api/v1/auth/me',
    authRequirement: 'Backend JWT required',
    purpose: 'Validate current backend session.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"firebase_uid":"...","email":"member@example.com","fullname":"...","user_type":"alumni","ref_id":"...","graduation_year":2010}',
    uiGuidance:
        'Use as startup/session guard validation before protected routes.',
  ),
  DiagnosticId.eventUsers: BackendApiDetails(
    featureName: 'Event Users Test',
    method: 'GET',
    path: '/api/v1/dev/diagnostics/db/event_users',
    authRequirement: 'Backend JWT required, debug/dev only',
    purpose: 'Verify event_users records.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"table":"event_users","available":true,"row_count":1,"rows":[{"email":"...","user_type":"alumni"}]}',
    uiGuidance:
        'Use compact row cards for user type, ref ID, and suspension state.',
  ),
  DiagnosticId.databaseTables: BackendApiDetails(
    featureName: 'Database Tables Test',
    method: 'GET',
    path: '/api/v1/dev/diagnostics/db/tables',
    authRequirement: 'Backend JWT required, debug/dev only',
    purpose: 'Verify events_db tables.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"tables":[{"name":"event_users","available":true,"row_count":1}]}',
    uiGuidance: 'Use count badges and drill-down rows for table inspection.',
  ),
  DiagnosticId.network: BackendApiDetails(
    featureName: 'Network Test',
    method: 'GET',
    path: '/api/v1/health',
    authRequirement: 'No',
    purpose: 'Verify backend base URL and health endpoint reachability.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"status":"ok","version":"1.0.0","env":"development","db":"ok"}',
    uiGuidance: 'Show configured backend URL and response payload.',
  ),
  DiagnosticId.performance: BackendApiDetails(
    featureName: 'App Performance',
    method: 'NONE',
    path: 'No backend API',
    authRequirement: 'No',
    purpose: 'Review local runtime and rendering diagnostics notes.',
    implementationStatus: 'Implemented',
    sampleResponse: 'No network response.',
    uiGuidance:
        'Use Flutter DevTools for frame timing and performance details.',
  ),
  DiagnosticId.debugTools: BackendApiDetails(
    featureName: 'Debug Tools',
    method: 'NONE',
    path: 'No backend API',
    authRequirement: 'No',
    purpose:
        'Export local diagnostic report and clear cached backend session data.',
    implementationStatus: 'Implemented',
    sampleResponse: 'Clipboard report or local cache cleanup status.',
    uiGuidance: 'Keep destructive debug actions explicit and debug-only.',
  ),
  DiagnosticId.eventsApi: BackendApiDetails(
    featureName: 'Public Events API Test',
    method: 'GET',
    path: '/api/v1/events/public?period=upcoming',
    authRequirement: 'None (public endpoint)',
    purpose:
        'Verify public event listing: 200 response, events array present, '
        'virtual_url and join_url NOT exposed in public payload.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"events":[{"event_id":1,"title":"Annual Meet","status":"published"}],"total":1}',
    uiGuidance: 'Event list screen with upcoming/past tabs. No auth header needed.',
  ),
  DiagnosticId.eventDetailApi: BackendApiDetails(
    featureName: 'Event Detail API Test',
    method: 'GET',
    path: '/api/v1/events/public/{event_id}',
    authRequirement: 'None (public endpoint)',
    purpose:
        'Verify public event detail: title, status, start/end present. '
        'virtual_url must NOT appear in public detail response.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"event_id":1,"title":"Annual Meet","status":"published","start_datetime":"..."}',
    uiGuidance: 'Use Event ID picker. Run to verify no virtual_url leak.',
  ),
  DiagnosticId.eventCreationApi: BackendApiDetails(
    featureName: 'Event List API Test',
    method: 'GET',
    path: '/api/v1/events?page=1&per_page=20',
    authRequirement: 'Admin JWT required',
    purpose:
        'Admin-authenticated event listing. Verifies total field and events array '
        'are present in paginated response.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"events":[{"event_id":1,"title":"Annual Meet","status":"published"}],"total":1,"page":1,"per_page":20}',
    uiGuidance: 'Requires completed Backend Auth diagnostic to get token.',
  ),
  DiagnosticId.eventPublish: BackendApiDetails(
    featureName: 'Event Admin Detail Test',
    method: 'GET',
    path: '/api/v1/events/{event_id}',
    authRequirement: 'Admin JWT required',
    purpose:
        'Admin detail endpoint for a specific event. Verifies admin can see '
        'full details including status, capacity, virtual_url (if virtual).',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"event_id":1,"title":"Annual Meet","status":"published","capacity":100,"is_virtual":false}',
    uiGuidance: 'Use Event ID picker. Requires admin JWT.',
  ),
  DiagnosticId.registrationApi: BackendApiDetails(
    featureName: 'Registration API Test',
    method: 'POST',
    path: '/api/v1/events/{id}/register',
    authRequirement: 'Backend JWT required',
    purpose: 'Alumni registers for event.',
    implementationStatus: 'Planned / Placeholder',
    sampleResponse: '{"registration_id":"...","status":"confirmed"}',
    uiGuidance: 'Registration confirmation screen.',
  ),
  DiagnosticId.myRegistration: BackendApiDetails(
    featureName: 'My Registration Test',
    method: 'GET',
    path: '/api/v1/events/{id}/my-registration',
    authRequirement: 'Backend JWT required',
    purpose: 'Check if current user is registered.',
    implementationStatus: 'Planned / Placeholder',
    sampleResponse: '{"registered":true,"status":"confirmed","join_url":"..."}',
    uiGuidance: 'Show current registration status on event detail page.',
  ),
  DiagnosticId.capacityGuard: BackendApiDetails(
    featureName: 'Capacity Guard Test',
    method: 'GET',
    path: '/api/v1/events/{slug}',
    authRequirement: 'No',
    purpose: 'Uses registered_count and capacity to show full/open status.',
    implementationStatus: 'Planned / Placeholder',
    sampleResponse: '{"capacity":100,"registered_count":100,"is_full":true}',
    uiGuidance:
        'Disable/register CTA or show full state when capacity is reached.',
  ),
  DiagnosticId.confirmationEmail: BackendApiDetails(
    featureName: 'Confirmation Email Test',
    method: 'TRIGGER',
    path: 'POST /api/v1/events/{id}/register',
    authRequirement: 'Backend JWT required',
    purpose: 'Verify confirmation email flag/status.',
    implementationStatus: 'Planned / Placeholder',
    sampleResponse: '{"registration_id":"...","confirmation_email_sent":true}',
    uiGuidance: 'Show confirmation messaging after registration succeeds.',
  ),
  DiagnosticId.joinLinkVisibility: BackendApiDetails(
    featureName: 'Join Link Visibility Test',
    method: 'GET',
    path: '/api/v1/events/{id}/my-registration',
    authRequirement: 'Backend JWT required',
    purpose: 'Show join_url only after registration.',
    implementationStatus: 'Planned / Placeholder',
    sampleResponse: '{"registered":true,"join_url":"https://..."}',
    uiGuidance: 'Hide join link until backend confirms registration.',
  ),
  DiagnosticId.attendeeListApi: BackendApiDetails(
    featureName: 'Attendee List API Test',
    method: 'GET',
    path: '/api/v1/admin/events/{event_id}/attendees?page=1&per_page=20',
    authRequirement: 'Admin JWT required',
    purpose:
        'Admin views registered attendees. Verifies 200, attendees array, total, '
        'and that no join_url/virtual_url appears. All rows status=registered.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"attendees":[{"registration_id":1,"fullname_snapshot":"...","status":"registered"}],"total":1,"page":1,"per_page":20}',
    uiGuidance: 'Admin attendee table. Requires Event ID picker and admin JWT.',
  ),
  DiagnosticId.attendeeSearchTest: BackendApiDetails(
    featureName: 'Attendee Search Test',
    method: 'GET',
    path: '/api/v1/admin/events/{event_id}/attendees?search={term}',
    authRequirement: 'Admin JWT required',
    purpose:
        'ILIKE search on fullname_snapshot. Verifies filtered result '
        'does not crash and returns attendees array.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"attendees":[{"fullname_snapshot":"John Doe","status":"registered"}],"total":1}',
    uiGuidance: 'Enter search term in the search field then run.',
  ),
  DiagnosticId.attendeeBatchFilter: BackendApiDetails(
    featureName: 'Batch Year Filter Test',
    method: 'GET',
    path: '/api/v1/admin/events/{event_id}/attendees?batch_year={year}',
    authRequirement: 'Admin JWT required',
    purpose:
        'Exact batch_year_snapshot filter. Verifies returned rows '
        'all match the requested batch year.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"attendees":[{"batch_year_snapshot":2005,"status":"registered"}],"total":1}',
    uiGuidance: 'Enter a batch year (e.g. 2005) in the batch year field then run.',
  ),
  DiagnosticId.attendeeExport: BackendApiDetails(
    featureName: 'Attendee Export Test',
    method: 'GET',
    path: '/api/v1/admin/events/{event_id}/attendees/export',
    authRequirement: 'Admin JWT required',
    purpose:
        'CSV export of active attendees. Verifies CSV headers contain all 8 required columns '
        'and no virtual_url, join_url, or qr_token is present.',
    implementationStatus: 'Implemented',
    sampleResponse:
        'registration_number,fullname_snapshot,email_snapshot,batch_year_snapshot,branch_snapshot,phone_snapshot,registered_at,status',
    uiGuidance:
        'Response is text/csv with UTF-8 BOM. Header row checked for required 8 columns.',
  ),
  DiagnosticId.adminRoleGuard: BackendApiDetails(
    featureName: 'Admin Attendee Full Diagnostics',
    method: 'GET',
    path: '/api/v1/dev/diagnostics/attendees?event_id={event_id}',
    authRequirement: 'Admin JWT required (dev endpoint)',
    purpose:
        'Runs UC-01 through UC-10 on the attendee management implementation: '
        'list, search, batch filter, pagination, export, cancelled hidden, '
        'cancelled in registrations, admin guard, 404, empty state.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"passed":10,"failed":0,"total":10,"results":[{"feature":"UC-01 Attendees visible","status":"PASS"}]}',
    uiGuidance:
        'UC-01–UC-10 verification. Requires Event ID picker and admin JWT.',
  ),
  DiagnosticId.auditTrail: BackendApiDetails(
    featureName: 'Registration Audit Test',
    method: 'GET',
    path: '/api/v1/admin/events/{event_id}/registrations?page=1&per_page=20',
    authRequirement: 'Admin JWT required',
    purpose:
        'Audit view: all registration statuses including cancelled. '
        'Verifies registrations array, total, and that cancelled rows are visible.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"registrations":[{"registration_id":1,"status":"registered"},{"registration_id":2,"status":"cancelled"}],"total":2}',
    uiGuidance: 'Shows all statuses. Unlike attendees list, cancelled rows appear here.',
  ),
  DiagnosticId.week3UxShowcase: BackendApiDetails(
    featureName: 'Week 3 UX Showcase',
    method: 'MULTIPLE',
    path: 'All Week 3 registration endpoints',
    authRequirement: 'Backend JWT required (alumni account)',
    purpose:
        'Full visual demonstration of all Week 3 registration workflows, '
        'security rules, audit trail, email, and snapshot behaviour.',
    implementationStatus: 'Implemented',
    sampleResponse: 'Interactive showcase — runs live against backend.',
    uiGuidance:
        'Use as Product Owner demo, frontend developer reference, and backend validation.',
  ),
  DiagnosticId.alumniSearchEmail: BackendApiDetails(
    featureName: 'Alumni Search by Email',
    method: 'GET',
    path: '/api/v1/dev/diagnostics/alumni/search?email=<email>',
    authRequirement: 'Backend JWT required, dev only',
    purpose:
        'Search alumni_db for a record matching the given email (case-insensitive, trimmed). '
        'Diagnose whether an alumni exists in alumni_db for a specific address.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"found":true,"count":1,"records":[{"alumni_id":"...","fullname":"...","email":"..."}]}',
    uiGuidance:
        'Enter any email — shows full alumni record if found. '
        'Not found means the alumni_db has no matching record.',
  ),
  DiagnosticId.alumniSearchPrefix: BackendApiDetails(
    featureName: 'Alumni Search by Prefix',
    method: 'GET',
    path: '/api/v1/dev/diagnostics/alumni/search-prefix?prefix=<prefix>',
    authRequirement: 'Backend JWT required, dev only',
    purpose:
        'Search alumni_db by email prefix or name fragment. '
        'Useful when the exact email is unknown.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"count":2,"records":[{"alumni_id":"...","fullname":"...","email":"..."}]}',
    uiGuidance:
        'Enter a partial email or partial name. '
        'Tap a result row to look up that alumni_id directly.',
  ),
  DiagnosticId.alumniLookupId: BackendApiDetails(
    featureName: 'Alumni Lookup by ID',
    method: 'GET',
    path: '/api/v1/dev/diagnostics/alumni/{alumni_id}',
    authRequirement: 'Backend JWT required, dev only',
    purpose:
        'Fetch the full alumni record from alumni_db using a known alumni_id (ref_id).',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"found":true,"record":{"alumni_id":"...","fullname":"...","registrationstatus":"Self-Verified"}}',
    uiGuidance:
        'Use after a prefix search to inspect the full alumni row.',
  ),
  DiagnosticId.alumniLoginTrace: BackendApiDetails(
    featureName: 'Login Mapping Trace',
    method: 'GET',
    path: '/api/v1/dev/diagnostics/alumni/login-trace?email=<email>',
    authRequirement: 'Backend JWT required, dev only',
    purpose:
        'Simulate the alumni lookup + event_users join that POST /auth/firebase performs. '
        'Shows why a user appears as user_type=other with ref_id=NULL.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"alumni_lookup":{"found":true},"existing_event_user":{"user_type":"other","ref_id":null},'
        '"diagnosis":{"result":"fail_alumni_exists_but_event_user_not_mapped"}}',
    uiGuidance:
        'Key diagnostic: shows PASS/FAIL result with reason. '
        'fail_alumni_exists_but_event_user_not_mapped means the ON CONFLICT bug is the root cause.',
  ),
  DiagnosticId.week5EventOptions: BackendApiDetails(
    featureName: 'Week 5 — Event Options',
    method: 'GET',
    path: '/api/v1/dev/diagnostics/week5/event-options',
    authRequirement: 'X-Dev-User: admin (dev only)',
    purpose:
        'Verify is_full_day, is_free, and ticket_price fields: create, read public, '
        'and backward-compat checks for existing events. 6 automated tests.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"status":"ok","scope":"week5_event_options","total":6,"passed":6,"failed":0}',
    uiGuidance: 'Run to verify Phase 1 event options are stored and returned correctly.',
  ),
  DiagnosticId.week5People: BackendApiDetails(
    featureName: 'Week 5 — People / Speakers',
    method: 'GET',
    path: '/api/v1/dev/diagnostics/week5/people',
    authRequirement: 'X-Dev-User: admin (dev only)',
    purpose:
        'Full CRUD for event people: HOST, SPEAKER, PANELIST, CHIEF_GUEST, GUEST_OF_HONOUR roles. '
        'Verifies is_visible gating, speakers[] derivation (4 roles), and HOST exclusion. 14 automated tests.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"status":"ok","scope":"week5_people","total":14,"passed":14,"failed":0}',
    uiGuidance:
        'Run to verify people CRUD, visibility gating, and speakers[] derivation rule.',
  ),
  DiagnosticId.week5SponsorsPartners: BackendApiDetails(
    featureName: 'Week 5 — Sponsors & Partners',
    method: 'GET',
    path: '/api/v1/dev/diagnostics/week5/sponsors-partners',
    authRequirement: 'X-Dev-User: admin (dev only)',
    purpose:
        'Full CRUD for sponsors (5 types, tier ordering) and partners (7 types, alphabetical ordering). '
        'Verifies is_visible gating, tier rank ordering for sponsors, and partner_type alpha ordering. 17 automated tests.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"status":"ok","scope":"week5_sponsors_partners","total":17,"passed":17,"failed":0}',
    uiGuidance:
        'Run to verify sponsor tier ordering (TITLE > GOLD > SILVER > BRONZE > ASSOCIATE) '
        'and partner alphabetical ordering.',
  ),
  DiagnosticId.week5Analytics: BackendApiDetails(
    featureName: 'Week 5 — Analytics Logging',
    method: 'GET',
    path: '/api/v1/dev/diagnostics/week5/analytics',
    authRequirement: 'X-Dev-User: admin (dev only)',
    purpose:
        'Verify event_activity_log writes for 6 action types, metadata JSONB storage, '
        'source_app presence, and no secrets in metadata. 11 automated tests.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"status":"ok","scope":"week5_analytics","total":11,"passed":11,"failed":0}',
    uiGuidance:
        'Run to verify analytics fire-and-forget logging works end-to-end against the local DB.',
  ),
  DiagnosticId.week5All: BackendApiDetails(
    featureName: 'Week 5 — All Suites',
    method: 'GET',
    path: '/api/v1/dev/diagnostics/week5/all',
    authRequirement: 'X-Dev-User: admin (dev only)',
    purpose:
        'Runs all four Week 5 diagnostic suites in sequence: event-options, people, '
        'sponsors-partners, analytics. Returns combined summary with per-suite breakdown. '
        '48 automated tests total.',
    implementationStatus: 'Implemented',
    sampleResponse:
        '{"status":"ok","total":48,"passed":48,"failed":0,"warnings":0,"suites":[...]}',
    uiGuidance:
        'Use as the single go/no-go check before any Week 5 deployment. '
        'Expect: status=ok, passed=48, failed=0, warnings=0.',
  ),
};

class DiagnosticItem {
  const DiagnosticItem({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.initialStatus,
    required this.apiDetails,
    this.statusNote,
    this.comingSoon = false,
  });

  const DiagnosticItem.placeholder({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.apiDetails,
  })  : initialStatus = DiagnosticStatus.notApplicable,
        statusNote = 'Coming Soon',
        comingSoon = true;

  final DiagnosticId id;
  final String title;
  final String description;
  final IconData icon;
  final DiagnosticStatus initialStatus;
  final BackendApiDetails apiDetails;
  final String? statusNote;
  final bool comingSoon;
}

class BackendApiDetails {
  const BackendApiDetails({
    required this.featureName,
    required this.method,
    required this.path,
    required this.authRequirement,
    required this.purpose,
    required this.implementationStatus,
    this.sampleResponse,
    this.uiGuidance,
  });

  final String featureName;
  final String method;
  final String path;
  final String authRequirement;
  final String purpose;
  final String implementationStatus;
  final String? sampleResponse;
  final String? uiGuidance;

  String get compactApiLabel {
    if (method == 'NONE') return 'API: No backend API';
    if (method == 'TRIGGER') return 'API: Triggered by $path';
    return 'API: $method $path';
  }
}

class DiagnosticCategory {
  const DiagnosticCategory({
    required this.title,
    required this.description,
    required this.items,
    this.initiallyExpanded = false,
  });

  final String title;
  final String description;
  final List<DiagnosticItem> items;
  final bool initiallyExpanded;
}

class DiagnosticRunState {
  const DiagnosticRunState({this.status, this.lastRun});

  final DiagnosticStatus? status;
  final DateTime? lastRun;

  DiagnosticStatus effectiveStatus(DiagnosticItem item) {
    return status ?? item.initialStatus;
  }
}

class DiagnosticOverviewRow extends StatelessWidget {
  const DiagnosticOverviewRow({
    super.key,
    required this.item,
    required this.runState,
    required this.onTap,
  });

  final DiagnosticItem item;
  final DiagnosticRunState runState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 6),
                    DiagnosticApiSummary(details: item.apiDetails),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DiagnosticStatusBadge(
                          status: runState.effectiveStatus(item),
                        ),
                        Text(
                          'Last run: ${formatDiagnosticTimestamp(runState.lastRun)}',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        if (item.statusNote != null)
                          Text(
                            item.statusNote!,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class DiagnosticApiSummary extends StatelessWidget {
  const DiagnosticApiSummary({super.key, required this.details});

  final BackendApiDetails details;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(
          details.compactApiLabel,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
        Text(
          'Auth: ${details.authRequirement}',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class BackendApiDetailsCard extends StatelessWidget {
  const BackendApiDetailsCard({super.key, required this.details});

  final BackendApiDetails details;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Backend API Details',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _ApiDetailLine(label: 'Feature', value: details.featureName),
            _ApiDetailLine(label: 'API', value: details.compactApiLabel),
            _ApiDetailLine(label: 'HTTP Method', value: details.method),
            _ApiDetailLine(
              label: 'Auth Required',
              value: details.authRequirement,
            ),
            _ApiDetailLine(label: 'Purpose', value: details.purpose),
            _ApiDetailLine(
              label: 'Implementation',
              value: details.implementationStatus,
            ),
            if (details.sampleResponse != null)
              _ApiDetailLine(
                label: 'Sample Response',
                value: details.sampleResponse!,
              ),
            if (details.uiGuidance != null)
              _ApiDetailLine(label: 'UI Guidance', value: details.uiGuidance!),
          ],
        ),
      ),
    );
  }
}

class _ApiDetailLine extends StatelessWidget {
  const _ApiDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 2),
          SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class DiagnosticCategorySection extends StatelessWidget {
  const DiagnosticCategorySection({
    super.key,
    required this.category,
    required this.runState,
    required this.onOpenDetail,
  });

  final DiagnosticCategory category;
  final Map<DiagnosticId, DiagnosticRunState> runState;
  final ValueChanged<DiagnosticItem> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
        initiallyExpanded: category.initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        title: Row(
          children: [
            Expanded(
              child: Text(
                category.title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            DiagnosticStatusBadge(status: categoryStatus(category, runState)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '${category.items.length} diagnostics',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
        children: [
          for (final item in category.items)
            DiagnosticOverviewRow(
              item: item,
              runState: runState[item.id] ?? const DiagnosticRunState(),
              onTap: () => onOpenDetail(item),
            ),
        ],
      ),
      ),
    );
  }
}

class DiagnosticStatusBadge extends StatelessWidget {
  const DiagnosticStatusBadge({super.key, required this.status});

  final DiagnosticStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, background, foreground) = switch (status) {
      DiagnosticStatus.ok => (
          'OK',
          Colors.green.withValues(alpha: 0.12),
          Colors.green.shade800,
        ),
      DiagnosticStatus.info => (
          'INFO',
          colorScheme.secondaryContainer,
          colorScheme.onSecondaryContainer,
        ),
      DiagnosticStatus.warning => (
          'WARNING',
          Colors.amber.withValues(alpha: 0.18),
          Colors.amber.shade900,
        ),
      DiagnosticStatus.error => (
          'ERROR',
          colorScheme.errorContainer,
          colorScheme.onErrorContainer,
        ),
      DiagnosticStatus.notApplicable => (
          'N/A',
          colorScheme.surfaceContainerHighest,
          colorScheme.onSurfaceVariant,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class DiagnosticSectionHeader extends StatelessWidget {
  const DiagnosticSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.runningAll,
    required this.exporting,
    required this.clearing,
    required this.onOpenEvents,
    required this.onRunEventDiag,
    required this.onRunRegDiag,
    required this.onRunAdminDiag,
    required this.onRunAll,
    required this.onExport,
    required this.onClear,
  });

  final bool runningAll;
  final bool exporting;
  final bool clearing;
  final VoidCallback onOpenEvents;
  final VoidCallback onRunEventDiag;
  final VoidCallback onRunRegDiag;
  final VoidCallback onRunAdminDiag;
  final VoidCallback onRunAll;
  final VoidCallback onExport;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Navigate ──────────────────────────────────────────────────────────
        _sectionLabel(context, 'Navigate'),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: _navTile(
            context,
            icon: Icons.event_outlined,
            label: 'Open Events',
            onTap: onOpenEvents,
          ),
        ),
        const SizedBox(height: 8),
        _adminPortalLinks(context),
        const SizedBox(height: 16),
        // ── Run ───────────────────────────────────────────────────────────────
        _sectionLabel(context, 'Run'),
        const SizedBox(height: 8),
        // Section diagnostics — three compact action rows
        _sectionRunButton(
          context,
          icon: Icons.event_outlined,
          label: 'Run Event Diagnostics',
          sublabel: 'Public, list, detail, admin detail',
          onTap: onRunEventDiag,
        ),
        const SizedBox(height: 6),
        _sectionRunButton(
          context,
          icon: Icons.app_registration_outlined,
          label: 'Run Registration Diagnostics',
          sublabel: '13-check backend flow + UX showcase',
          onTap: onRunRegDiag,
        ),
        const SizedBox(height: 6),
        _sectionRunButton(
          context,
          icon: Icons.people_alt_outlined,
          label: 'Run Attendee / Admin Diagnostics',
          sublabel: 'List · search · export · UC-01–UC-10',
          onTap: onRunAdminDiag,
        ),
        const SizedBox(height: 8),
        // Run All Diagnostics — hero action
        Material(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: runningAll ? null : onRunAll,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: runningAll
                        ? Padding(
                            padding: const EdgeInsets.all(11),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          )
                        : Icon(
                            Icons.play_circle_filled,
                            color: colorScheme.onPrimaryContainer,
                            size: 28,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Run All Diagnostics',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Auth · DB · Events · Registration',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onPrimaryContainer
                                    .withValues(alpha: 0.72),
                              ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    runningAll
                        ? Icons.hourglass_top_outlined
                        : Icons.arrow_forward_ios,
                    color: colorScheme.onPrimaryContainer,
                    size: 15,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ── Utilities ─────────────────────────────────────────────────────────
        _sectionLabel(context, 'Utilities'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _utilityButton(
                context,
                icon: exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_outlined, size: 17),
                label: 'Export Report',
                onTap: exporting ? null : onExport,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _utilityButton(
                context,
                icon: clearing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cleaning_services_outlined, size: 17),
                label: 'Clear Cache',
                onTap: clearing ? null : onClear,
                destructive: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _adminPortalLinks(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const adminBase = 'http://localhost:5173';
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ADMIN PORTAL',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
            ),
            const SizedBox(height: 8),
            for (final (label, path) in [
              ('Events', '/events'),
              ('Attendees', '/attendees'),
              ('Registrations', '/registrations'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, size: 12, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        '$adminBase$path',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
    );
  }

  Widget _sectionRunButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String sublabel,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                    ),
                    Text(
                      sublabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 14, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: colorScheme.onPrimaryContainer, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _utilityButton(
    BuildContext context, {
    required Widget icon,
    required String label,
    required VoidCallback? onTap,
    bool destructive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final fgColor = destructive
        ? colorScheme.error
        : colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: destructive
                  ? colorScheme.error.withValues(alpha: 0.4)
                  : colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconTheme(
                data: IconThemeData(color: fgColor, size: 17),
                child: icon,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: fgColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QA Summary Card
// ─────────────────────────────────────────────────────────────────────────────

class _QaSummaryCard extends StatelessWidget {
  const _QaSummaryCard({
    required this.categories,
    required this.runState,
  });

  final List<DiagnosticCategory> categories;
  final Map<DiagnosticId, DiagnosticRunState> runState;

  @override
  Widget build(BuildContext context) {
    final allItems = categories.expand((c) => c.items).toList();
    final statuses = allItems
        .map((item) => (runState[item.id] ?? const DiagnosticRunState()).effectiveStatus(item))
        .toList();

    final passed = statuses.where((s) => s == DiagnosticStatus.ok).length;
    final failed = statuses.where((s) => s == DiagnosticStatus.error).length;
    final warning = statuses.where((s) => s == DiagnosticStatus.warning).length;
    final notRun = statuses
        .where((s) => s == DiagnosticStatus.notApplicable || s == DiagnosticStatus.info)
        .length;
    final total = allItems.length;

    final lastRun = runState.values
        .map((s) => s.lastRun)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (best, t) => best == null || t.isAfter(best) ? t : best);

    final session = AuthController.instance.session;
    final userEmail = session?.email ?? '—';
    final userType = session?.userType ?? '—';
    final isAdmin = userType == 'admin';
    final isAlumni = userType == 'alumni';

    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  'QA Summary',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                ),
                const Spacer(),
                Text(
                  'Last run: ${formatDiagnosticTimestamp(lastRun)}',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Status counts row
            Row(
              children: [
                _QaBadge(label: '$passed', sublabel: 'PASS', color: Colors.green.shade700, bg: Colors.green.withValues(alpha: 0.10)),
                const SizedBox(width: 6),
                _QaBadge(label: '$failed', sublabel: 'FAIL', color: failed > 0 ? cs.error : cs.onSurfaceVariant, bg: failed > 0 ? cs.errorContainer : cs.surfaceContainerHighest),
                const SizedBox(width: 6),
                _QaBadge(label: '$warning', sublabel: 'WARN', color: Colors.orange.shade700, bg: Colors.orange.withValues(alpha: 0.10)),
                const SizedBox(width: 6),
                _QaBadge(label: '$notRun', sublabel: 'N/A', color: cs.onSurfaceVariant, bg: cs.surface),
                const SizedBox(width: 6),
                _QaBadge(label: '$total', sublabel: 'TOTAL', color: cs.onSurface, bg: cs.surface),
              ],
            ),
            const SizedBox(height: 10),
            // Environment row
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _QaEnvChip(icon: Icons.link_outlined, label: backendBaseUrl),
                _QaEnvChip(icon: Icons.person_outline, label: userEmail),
                _QaEnvChip(
                  icon: isAdmin
                      ? Icons.admin_panel_settings_outlined
                      : isAlumni
                          ? Icons.school_outlined
                          : Icons.person_outline,
                  label: userType,
                  highlight: isAdmin || isAlumni,
                  highlightColor: isAdmin ? cs.tertiary : cs.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QaBadge extends StatelessWidget {
  const _QaBadge({
    required this.label,
    required this.sublabel,
    required this.color,
    required this.bg,
  });

  final String label;
  final String sublabel;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
          Text(
            sublabel,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _QaEnvChip extends StatelessWidget {
  const _QaEnvChip({
    required this.icon,
    required this.label,
    this.highlight = false,
    this.highlightColor,
  });

  final IconData icon;
  final String label;
  final bool highlight;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = highlight ? (highlightColor ?? cs.primary) : cs.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _ProductionWarningBanner extends StatelessWidget {
  const _ProductionWarningBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.errorContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: colorScheme.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Developer Diagnostics - Not for Production UI',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryField extends StatelessWidget {
  const _SummaryField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 34),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _KeyValueLine extends StatelessWidget {
  const _KeyValueLine({required this.entry});

  final MapEntry<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 360;
          final label = Text(
            entry.key,
            style: const TextStyle(fontWeight: FontWeight.w600),
          );
          final value = SelectableText(entry.value?.toString() ?? 'NULL');
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: 2), value],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 132, child: label),
              Expanded(child: value),
            ],
          );
        },
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({required this.label, required this.value, this.status});

  final String label;
  final String value;
  final DiagnosticStatus? status;

  @override
  Widget build(BuildContext context) {
    Widget? statusIcon;
    if (status != null) {
      statusIcon = Icon(
        status == DiagnosticStatus.ok
            ? Icons.check_circle_outline
            : status == DiagnosticStatus.error
                ? Icons.error_outline
                : Icons.info_outline,
        color: status == DiagnosticStatus.ok
            ? Colors.green
            : status == DiagnosticStatus.error
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
        size: 16,
      );
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(label),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            if (statusIcon != null) ...[const SizedBox(width: 6), statusIcon],
          ],
        ),
      ),
    );
  }
}

const _divider = Divider(height: 1, indent: 16, endIndent: 16);

Dio get devDio => Dio(
      BaseOptions(
        baseUrl: backendBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        headers: const {'Content-Type': 'application/json'},
      ),
    );

String get backendBaseUrl {
  const configured = String.fromEnvironment('DEV_BACKEND_BASE_URL');
  if (configured.isNotEmpty) return configured;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://127.0.0.1:8000';
}

String _themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };

String platformLabel() {
  if (kIsWeb) return 'Web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
}

String formatDiagnosticTimestamp(DateTime? timestamp) {
  if (timestamp == null) return 'Never';
  final local = timestamp.toLocal();
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
  final day = local.day.toString().padLeft(2, '0');
  final month = months[local.month - 1];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day-$month-${local.year} $hour:$minute';
}

String diagnosticStatusLabel(DiagnosticStatus status) {
  return switch (status) {
    DiagnosticStatus.ok => 'OK',
    DiagnosticStatus.info => 'INFO',
    DiagnosticStatus.warning => 'WARNING',
    DiagnosticStatus.error => 'ERROR',
    DiagnosticStatus.notApplicable => 'N/A',
  };
}

DiagnosticStatus categoryStatus(
  DiagnosticCategory category,
  Map<DiagnosticId, DiagnosticRunState> runState,
) {
  final statuses = category.items
      .map(
        (item) => (runState[item.id] ?? const DiagnosticRunState())
            .effectiveStatus(item),
      )
      .toList();

  if (statuses.contains(DiagnosticStatus.error)) return DiagnosticStatus.error;
  if (statuses.contains(DiagnosticStatus.warning)) {
    return DiagnosticStatus.warning;
  }

  final implemented = category.items.where((item) => !item.comingSoon).toList();
  if (implemented.isEmpty) return DiagnosticStatus.notApplicable;

  final implementedStatuses = implemented
      .map(
        (item) => (runState[item.id] ?? const DiagnosticRunState())
            .effectiveStatus(item),
      )
      .toList();
  final runnableStatuses = implementedStatuses
      .where((status) => status != DiagnosticStatus.info)
      .toList();

  if (runnableStatuses.isEmpty) return DiagnosticStatus.info;
  if (runnableStatuses.every((status) => status == DiagnosticStatus.ok)) {
    return DiagnosticStatus.ok;
  }
  if (implementedStatuses.every((status) => status == DiagnosticStatus.info)) {
    return DiagnosticStatus.info;
  }
  if (implementedStatuses.every(
    (status) => status == DiagnosticStatus.notApplicable,
  )) {
    return DiagnosticStatus.notApplicable;
  }
  return DiagnosticStatus.info;
}

String shortToken(String token) {
  if (token.length <= 40) return token;
  return '${token.substring(0, 20)}...${token.substring(token.length - 20)}';
}

String errorMessage(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    return status == null ? error.message ?? error.type.name : '$status $data';
  }
  return error.toString();
}

IndicatorState indicatorStateFor(bool passed, bool failed) {
  if (passed) return IndicatorState.passed;
  if (failed) return IndicatorState.failed;
  return IndicatorState.pending;
}

Widget _jsonBlock(BuildContext context, String title, Object? value) {
  if (value == null) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 12),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(title, style: Theme.of(context).textTheme.labelLarge),
      subtitle: const Text('Show Raw Response'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(value),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
      ],
    ),
  );
}

String rowTitle(String tableName, Map<String, dynamic> row, int index) {
  if (tableName == 'event_users') {
    return row['fullname']?.toString() ??
        row['email']?.toString() ??
        'User $index';
  }
  return row['title']?.toString() ??
      row['event_type']?.toString() ??
      row['notification_id']?.toString() ??
      'Row $index';
}

Map<String, dynamic> displayFieldsForRow(
  String tableName,
  Map<String, dynamic> row,
) {
  if (tableName == 'event_users') {
    return {
      'Email': row['email'],
      'User Type': row['user_type'],
      'Ref ID': row['ref_id'],
      'Graduation Year': row['graduation_year'],
      'Last Login': row['last_login'],
      'Suspended': row['is_suspended'],
    };
  }

  final preferred = <String>[
    'event_id',
    'title',
    'email',
    'status',
    'event_type',
    'entity_type',
    'created_at',
    'updated_at',
    'registered_at',
    'checked_in_at',
    'scanned_at',
  ];
  final fields = <String, dynamic>{};
  for (final key in preferred) {
    if (row.containsKey(key)) fields[titleCase(key)] = row[key];
  }
  if (fields.isNotEmpty) return fields;
  return row.map((key, value) => MapEntry(titleCase(key), value));
}

String titleCase(String value) {
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
