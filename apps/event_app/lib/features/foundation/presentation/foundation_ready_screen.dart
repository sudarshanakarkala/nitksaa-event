import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/app_state.dart';
import '../../../routes/app_routes.dart';
import '../../../theme/theme_provider.dart';

class FoundationReadyScreen extends ConsumerWidget {
  const FoundationReadyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'NITKSAA Event App Foundation Ready',
                textAlign: TextAlign.center,
                style: textTheme.headlineMedium,
              ),
              const SizedBox(height: 40),
              _StatusRow(
                label: 'Firebase',
                value: AppState.firebaseInitialized
                    ? 'Initialized'
                    : 'Not Initialized',
                ok: AppState.firebaseInitialized,
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
              const SizedBox(height: 12),
              _StatusRow(
                label: 'Theme',
                value: _themeModeLabel(themeMode),
                ok: true,
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
              const SizedBox(height: 32),
              TextButton.icon(
                onPressed: () => context.go(AppRoutes.developer),
                icon: const Icon(Icons.developer_mode, size: 16),
                label: const Text('Open Developer Diagnostics'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    required this.ok,
    required this.colorScheme,
    required this.textTheme,
  });

  final String label;
  final String value;
  final bool ok;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          color: ok ? Colors.green : colorScheme.error,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text('$label: $value', style: textTheme.bodyMedium),
      ],
    );
  }
}
