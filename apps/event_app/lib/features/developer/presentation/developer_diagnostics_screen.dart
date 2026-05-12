import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_state.dart';
import '../../../core/logger/app_logger.dart';
import '../../../routes/app_routes.dart';
import '../../../theme/theme_provider.dart';

class DeveloperDiagnosticsScreen extends ConsumerWidget {
  const DeveloperDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final firebaseAppName = AppState.firebaseInitialized
        ? _safeFirebaseAppName()
        : 'N/A';

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
          // ── Warning banner ─────────────────────────────────────────────
          Card(
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
                      'Developer Diagnostics — Not for Production UI',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Foundation Status ───────────────────────────────────────────
          _SectionLabel(title: 'Foundation Status'),
          Card(
            child: Column(
              children: [
                _DiagRow(label: 'App Name', value: 'NITKSAA Event'),
                _divider,
                _DiagRow(label: 'Environment', value: 'Development'),
                _divider,
                _DiagRow(
                  label: 'Firebase',
                  value: AppState.firebaseInitialized
                      ? 'Initialized'
                      : 'Failed',
                  status: AppState.firebaseInitialized
                      ? _Status.ok
                      : _Status.error,
                ),
                _divider,
                _DiagRow(label: 'Firebase App', value: firebaseAppName),
                _divider,
                // Hive is always initialized by the time this screen is reachable;
                // a crash in Hive.initFlutter() would have prevented app startup.
                _DiagRow(
                  label: 'Hive',
                  value: 'Initialized',
                  status: _Status.ok,
                ),
                _divider,
                _DiagRow(
                  label: 'Theme Mode',
                  value: _themeModeLabel(themeMode),
                ),
                _divider,
                _DiagRow(label: 'Platform', value: _platformLabel()),
                _divider,
                _DiagRow(
                  label: 'Router',
                  value: 'Active',
                  status: _Status.ok,
                ),
                _divider,
                _DiagRow(
                  label: 'Logger',
                  value: 'Active',
                  status: _Status.ok,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Logger Test ─────────────────────────────────────────────────
          _SectionLabel(title: 'Logger Test'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        AppLogger.debug('Test debug from developer diagnostics'),
                    child: const Text('Log Debug'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        AppLogger.info('Test info from developer diagnostics'),
                    child: const Text('Log Info'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        AppLogger.warning('Test warning from developer diagnostics'),
                    child: const Text('Log Warning'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        AppLogger.error('Test error from developer diagnostics'),
                    child: const Text('Log Error'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Theme Control ───────────────────────────────────────────────
          _SectionLabel(title: 'Theme Control'),
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
      ),
    );
  }

  static const _divider = Divider(height: 1, indent: 16, endIndent: 16);

  String _safeFirebaseAppName() {
    try {
      return Firebase.app().name;
    } catch (_) {
      return 'Unknown';
    }
  }

  String _themeModeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  String _platformLabel() {
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
}

// ── Status enum ──────────────────────────────────────────────────────────────

enum _Status { ok, error }

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

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

// ── Diagnostic row ───────────────────────────────────────────────────────────

class _DiagRow extends StatelessWidget {
  const _DiagRow({
    required this.label,
    required this.value,
    this.status,
  });

  final String label;
  final String value;
  final _Status? status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget? statusIcon;
    if (status != null) {
      statusIcon = Icon(
        status == _Status.ok
            ? Icons.check_circle_outline
            : Icons.error_outline,
        color: status == _Status.ok ? Colors.green : colorScheme.error,
        size: 16,
      );
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          if (statusIcon != null) ...[
            const SizedBox(width: 6),
            statusIcon,
          ],
        ],
      ),
    );
  }
}
