import 'package:flutter/material.dart';
import '../../../widgets/material/app_scaffold.dart';

class InfoScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool showLoading;

  const InfoScreen({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.showLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: null,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (showLoading) ...[
              const SizedBox(height: 48),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.blue),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
