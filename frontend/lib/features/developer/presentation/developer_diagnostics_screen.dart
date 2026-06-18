import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/app_state.dart';
import '../../../core/logger/app_logger.dart';
import '../../../routes/app_routes.dart';
import '../../../theme/theme_provider.dart';
import '../../auth/services/auth_session_store.dart';
import '../../auth/services/google_sign_in_initializer.dart';
import '../../../widgets/shared/shared_screen.dart';
import '../../../widgets/shared/status_row.dart';

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
          const SizedBox(height: 20),
          const DiagnosticSectionHeader(title: 'Quick Actions'),
          _QuickActionsCard(
            runningAll: _runningAll,
            exporting: _exporting,
            clearing: _clearing,
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
            'Alumni can register. Confirmation email sent. Join link visible post-registration.',
        items: [
          items[DiagnosticId.registrationApi]!,
          items[DiagnosticId.myRegistration]!,
          items[DiagnosticId.capacityGuard]!,
          items[DiagnosticId.confirmationEmail]!,
          items[DiagnosticId.joinLinkVisibility]!,
        ],
      ),
      DiagnosticCategory(
        title: 'Admin / Attendees',
        description:
            'Admin can manage attendees. Full end-to-end stable. Demo-ready.',
        items: [
          items[DiagnosticId.attendeeListApi]!,
          items[DiagnosticId.attendeeExport]!,
          items[DiagnosticId.adminRoleGuard]!,
          items[DiagnosticId.auditTrail]!,
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
      DiagnosticId.eventsApi: DiagnosticItem.placeholder(
        id: DiagnosticId.eventsApi,
        title: 'Events API Test',
        description: 'Coming soon: list and browse events API validation.',
        icon: Icons.event_outlined,
        apiDetails: diagnosticApiDetails[DiagnosticId.eventsApi]!,
      ),
      DiagnosticId.eventDetailApi: DiagnosticItem.placeholder(
        id: DiagnosticId.eventDetailApi,
        title: 'Event Detail API Test',
        description: 'Coming soon: event detail endpoint validation.',
        icon: Icons.event_note_outlined,
        apiDetails: diagnosticApiDetails[DiagnosticId.eventDetailApi]!,
      ),
      DiagnosticId.eventCreationApi: DiagnosticItem.placeholder(
        id: DiagnosticId.eventCreationApi,
        title: 'Event Creation API Test',
        description: 'Coming soon: staff event creation API validation.',
        icon: Icons.add_box_outlined,
        apiDetails: diagnosticApiDetails[DiagnosticId.eventCreationApi]!,
      ),
      DiagnosticId.eventPublish: DiagnosticItem.placeholder(
        id: DiagnosticId.eventPublish,
        title: 'Event Publish/Unpublish Test',
        description: 'Coming soon: event visibility workflow validation.',
        icon: Icons.published_with_changes_outlined,
        apiDetails: diagnosticApiDetails[DiagnosticId.eventPublish]!,
      ),
      DiagnosticId.registrationApi: DiagnosticItem.placeholder(
        id: DiagnosticId.registrationApi,
        title: 'Registration API Test',
        description: 'Coming soon: attendee registration API validation.',
        icon: Icons.app_registration_outlined,
        apiDetails: diagnosticApiDetails[DiagnosticId.registrationApi]!,
      ),
      DiagnosticId.myRegistration: DiagnosticItem.placeholder(
        id: DiagnosticId.myRegistration,
        title: 'My Registration Test',
        description: 'Coming soon: current user registration lookup.',
        icon: Icons.fact_check_outlined,
        apiDetails: diagnosticApiDetails[DiagnosticId.myRegistration]!,
      ),
      DiagnosticId.capacityGuard: DiagnosticItem.placeholder(
        id: DiagnosticId.capacityGuard,
        title: 'Capacity Guard Test',
        description: 'Coming soon: capacity and waitlist behavior validation.',
        icon: Icons.groups_2_outlined,
        apiDetails: diagnosticApiDetails[DiagnosticId.capacityGuard]!,
      ),
      DiagnosticId.confirmationEmail: DiagnosticItem.placeholder(
        id: DiagnosticId.confirmationEmail,
        title: 'Confirmation Email Test',
        description: 'Coming soon: registration email confirmation validation.',
        icon: Icons.mark_email_read_outlined,
        apiDetails: diagnosticApiDetails[DiagnosticId.confirmationEmail]!,
      ),
      DiagnosticId.joinLinkVisibility: DiagnosticItem.placeholder(
        id: DiagnosticId.joinLinkVisibility,
        title: 'Join Link Visibility Test',
        description: 'Coming soon: post-registration join link validation.',
        icon: Icons.link_outlined,
        apiDetails: diagnosticApiDetails[DiagnosticId.joinLinkVisibility]!,
      ),
      DiagnosticId.attendeeListApi: DiagnosticItem.placeholder(
        id: DiagnosticId.attendeeListApi,
        title: 'Attendee List API Test',
        description: 'Coming soon: admin attendee list API validation.',
        icon: Icons.people_alt_outlined,
        apiDetails: diagnosticApiDetails[DiagnosticId.attendeeListApi]!,
      ),
      DiagnosticId.attendeeExport: DiagnosticItem.placeholder(
        id: DiagnosticId.attendeeExport,
        title: 'Attendee Export Test',
        description: 'Coming soon: attendee export workflow validation.',
        icon: Icons.download_outlined,
        apiDetails: diagnosticApiDetails[DiagnosticId.attendeeExport]!,
      ),
      DiagnosticId.adminRoleGuard: DiagnosticItem.placeholder(
        id: DiagnosticId.adminRoleGuard,
        title: 'Admin Role Guard Test',
        description: 'Coming soon: admin-only access guard validation.',
        icon: Icons.admin_panel_settings_outlined,
        apiDetails: diagnosticApiDetails[DiagnosticId.adminRoleGuard]!,
      ),
      DiagnosticId.auditTrail: DiagnosticItem.placeholder(
        id: DiagnosticId.auditTrail,
        title: 'Audit Trail Test',
        description: 'Coming soon: audit trail write/read validation.',
        icon: Icons.history_edu_outlined,
        apiDetails: diagnosticApiDetails[DiagnosticId.auditTrail]!,
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
      DiagnosticId.eventsApi ||
      DiagnosticId.eventDetailApi ||
      DiagnosticId.eventCreationApi ||
      DiagnosticId.eventPublish ||
      DiagnosticId.registrationApi ||
      DiagnosticId.myRegistration ||
      DiagnosticId.capacityGuard ||
      DiagnosticId.confirmationEmail ||
      DiagnosticId.joinLinkVisibility ||
      DiagnosticId.attendeeListApi ||
      DiagnosticId.attendeeExport ||
      DiagnosticId.adminRoleGuard ||
      DiagnosticId.auditTrail => _ComingSoonDiagnosticDetail(item: item),
    };
  }
}

class _ComingSoonDiagnosticDetail extends StatelessWidget {
  const _ComingSoonDiagnosticDetail({required this.item});

  final DiagnosticItem item;

  @override
  Widget build(BuildContext context) {
    return DiagnosticDetailScaffold(
      title: item.title,
      description: item.description,
      apiDetails: item.apiDetails,
      result: const DiagnosticRunState(status: DiagnosticStatus.notApplicable),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.construction_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'This diagnostic will be enabled when the related API is implemented.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
    final firebaseAppName = AppState.firebaseInitialized
        ? _safeFirebaseAppName()
        : 'N/A';
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

// ---------------------------------------------------------------------------
// Helper widgets (unchanged from original file, kept for completeness)
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel({required this.title});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
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
    final report =
        'NITKSAA Event Debug Tools\n'
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
          onPressed: _backendLoading ? null : _validateFirebaseTokenWithBackend,
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
              onPressed: _backendLoading
                  ? null
                  : _validateFirebaseTokenWithBackend,
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
        final response = await devDio
            .post<Map<String, dynamic>>(
              '/api/v1/auth/firebase',
              data: {'token': token},
            )
            .timeout(const Duration(seconds: 30));
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
    final userName =
        _authMeResponse?['fullname']?.toString() ??
        _backendLoginResponse?['fullname']?.toString() ??
        user?.displayName ??
        'N/A';
    final email =
        _authMeResponse?['email']?.toString() ??
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
            value:
                user?.uid ??
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
                          style: Theme.of(context).textTheme.bodyMedium
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
  attendeeExport,
  adminRoleGuard,
  auditTrail,
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
    featureName: 'Events API Test',
    method: 'GET',
    path: '/api/v1/events',
    authRequirement: 'No',
    purpose: 'Public published event listing.',
    implementationStatus: 'Planned / Placeholder',
    sampleResponse:
        '{"events":[{"id":"...","slug":"annual-meet","title":"Annual Meet","starts_at":"2026-06-30T10:00:00Z"}]}',
    uiGuidance: 'Event list screen with upcoming/past tabs.',
  ),
  DiagnosticId.eventDetailApi: BackendApiDetails(
    featureName: 'Event Detail API Test',
    method: 'GET',
    path: '/api/v1/events/{slug}',
    authRequirement: 'No',
    purpose: 'Public event detail.',
    implementationStatus: 'Planned / Placeholder',
    sampleResponse:
        '{"slug":"annual-meet","title":"Annual Meet","location":"NITK","speakers":[],"registration_open":true}',
    uiGuidance:
        'Event detail page with title, date, location, speakers, registration CTA.',
  ),
  DiagnosticId.eventCreationApi: BackendApiDetails(
    featureName: 'Event Creation API Test',
    method: 'POST',
    path: '/api/v1/events',
    authRequirement: 'Admin/Coordinator required',
    purpose: 'Staff creates event.',
    implementationStatus: 'Planned / Placeholder',
    sampleResponse: '{"id":"...","status":"draft","title":"New Event"}',
    uiGuidance: 'Admin event creation form.',
  ),
  DiagnosticId.eventPublish: BackendApiDetails(
    featureName: 'Event Publish/Unpublish Test',
    method: 'PATCH',
    path: '/api/v1/events/{id}/status',
    authRequirement: 'Admin/Coordinator required',
    purpose: 'Publish/unpublish event.',
    implementationStatus: 'Planned / Placeholder',
    sampleResponse: '{"id":"...","status":"published"}',
    uiGuidance:
        'Use explicit publish/unpublish action with current status chip.',
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
    path: '/api/v1/events/{id}/attendees',
    authRequirement: 'Admin/Coordinator required',
    purpose: 'Admin views registered attendees.',
    implementationStatus: 'Planned / Placeholder',
    sampleResponse:
        '{"attendees":[{"name":"...","email":"...","status":"confirmed"}]}',
    uiGuidance: 'Admin attendee table with search/filter controls.',
  ),
  DiagnosticId.attendeeExport: BackendApiDetails(
    featureName: 'Attendee Export Test',
    method: 'GET',
    path: '/api/v1/events/{id}/attendees/export',
    authRequirement: 'Admin/Coordinator required',
    purpose: 'Export CSV.',
    implementationStatus: 'Planned / Placeholder',
    sampleResponse: 'text/csv attendee export stream.',
    uiGuidance: 'Use a download/export icon action in admin attendee tools.',
  ),
  DiagnosticId.adminRoleGuard: BackendApiDetails(
    featureName: 'Admin Role Guard Test',
    method: 'VARIES',
    path: 'protected admin/event endpoints',
    authRequirement: 'Admin/Coordinator required',
    purpose: 'Verify unauthorized users get 403.',
    implementationStatus: 'Planned / Placeholder',
    sampleResponse: '{"detail":"forbidden"}',
    uiGuidance: 'Show access denied state and avoid rendering admin controls.',
  ),
  DiagnosticId.auditTrail: BackendApiDetails(
    featureName: 'Audit Trail Test',
    method: 'GET',
    path: '/api/v1/dev/diagnostics/audit or future admin audit endpoint',
    authRequirement: 'Admin/dev required',
    purpose: 'Verify state-changing actions are recorded.',
    implementationStatus: 'Planned / Placeholder',
    sampleResponse: '{"entries":[{"action":"event.updated","actor":"..."}]}',
    uiGuidance:
        'Display recent audit entries with actor, action, and timestamp.',
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
  }) : initialStatus = DiagnosticStatus.notApplicable,
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
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        if (item.statusNote != null)
                          Text(
                            item.statusNote!,
                            style: Theme.of(context).textTheme.labelSmall
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
    required this.onRunAll,
    required this.onExport,
    required this.onClear,
  });

  final bool runningAll;
  final bool exporting;
  final bool clearing;
  final VoidCallback onRunAll;
  final VoidCallback onExport;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: runningAll ? null : onRunAll,
              icon: runningAll
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_circle_outline),
              label: const Text('Run All Diagnostics'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: exporting ? null : onExport,
              icon: const Icon(Icons.ios_share_outlined),
              label: const Text('Export Diagnostic Report'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: clearing ? null : onClear,
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Clear Cached Data'),
            ),
          ],
        ),
      ),
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
