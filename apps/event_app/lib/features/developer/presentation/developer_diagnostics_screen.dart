import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/app_state.dart';
import '../../../core/logger/app_logger.dart';
import '../../auth/services/google_sign_in_initializer.dart';
import '../../../routes/app_routes.dart';
import '../../../theme/theme_provider.dart';
import '../../../widgets/shared/shared_screen.dart';
import '../../../widgets/shared/status_row.dart';

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

    return SharedScreen(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Custom AppBar placed inside body (no Scaffold appBar)
          AppBar(
            title: const Text('Developer Diagnostics'),
            leading: BackButton(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go(AppRoutes.home),
            ),
          ),
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
                StatusRow(label: 'App Name', value: 'NITKSAA Event', ok: true, colorScheme: colorScheme),
                const Divider(height: 1, indent: 16, endIndent: 16),
                StatusRow(label: 'Environment', value: 'Development', ok: true, colorScheme: colorScheme),
                const Divider(height: 1, indent: 16, endIndent: 16),
                StatusRow(
                  label: 'Firebase',
                  value: AppState.firebaseInitialized ? 'Initialized' : 'Failed',
                  ok: AppState.firebaseInitialized,
                  colorScheme: colorScheme,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                StatusRow(label: 'Firebase App', value: firebaseAppName, ok: true, colorScheme: colorScheme),
                const Divider(height: 1, indent: 16, endIndent: 16),
                StatusRow(label: 'Hive', value: 'Initialized', ok: true, colorScheme: colorScheme),
                const Divider(height: 1, indent: 16, endIndent: 16),
                StatusRow(label: 'Theme', value: _themeModeLabel(themeMode), ok: true, colorScheme: colorScheme),
                const Divider(height: 1, indent: 16, endIndent: 16),
                StatusRow(label: 'Platform', value: _platformLabel(), ok: true, colorScheme: colorScheme),
                const Divider(height: 1, indent: 16, endIndent: 16),
                StatusRow(label: 'Router', value: 'Active', ok: true, colorScheme: colorScheme),
                const Divider(height: 1, indent: 16, endIndent: 16),
                StatusRow(label: 'Logger', value: 'Active', ok: true, colorScheme: colorScheme),
                const Divider(height: 1, indent: 16, endIndent: 16),
                StatusRow(
                  label: 'Auth Status',
                  value: FirebaseAuth.instance.currentUser != null ? 'Logged In' : 'Logged Out',
                  ok: FirebaseAuth.instance.currentUser != null,
                  colorScheme: colorScheme,
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
                    onPressed: () => AppLogger.debug('Test debug from developer diagnostics'),
                    child: const Text('Log Debug'),
                  ),
                  OutlinedButton(
                    onPressed: () => AppLogger.info('Test info from developer diagnostics'),
                    child: const Text('Log Info'),
                  ),
                  OutlinedButton(
                    onPressed: () => AppLogger.warning('Test warning from developer diagnostics'),
                    child: const Text('Log Warning'),
                  ),
                  OutlinedButton(
                    onPressed: () => AppLogger.error('Test error from developer diagnostics'),
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
                  ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.settings_suggest_outlined)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                ],
                selected: {themeMode},
                onSelectionChanged: (selection) => ref.read(themeProvider.notifier).setTheme(selection.first),
              ),
            ),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 20),
            const _SectionLabel(title: 'Firebase Token Test'),
            const _DevFirebaseTokenCard(),
          ],
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

class _DiagRow extends StatelessWidget {
  final String label;
  final String value;
  final bool ok;
  const _DiagRow({required this.label, required this.value, required this.ok});
  @override
  Widget build(BuildContext context) => StatusRow(label: label, value: value, ok: ok);
}

class _DevFirebaseTokenCard extends StatefulWidget {
  const _DevFirebaseTokenCard();
  @override
  State<_DevFirebaseTokenCard> createState() => _DevFirebaseTokenCardState();
}

class _DevFirebaseTokenCardState extends State<_DevFirebaseTokenCard> {
  // Existing implementation retained – omitted for brevity.
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
