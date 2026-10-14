import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Centred message for a page or panel with nothing to show: empty, no
/// matches, couldn't load, not allowed. Icon, title, a line of detail and
/// an optional action (usually "Try again" or "Clear filters").
class StateMessage extends StatelessWidget {
  const StateMessage({super.key, this.icon, this.title, this.body, this.action});

  final IconData? icon;
  final String? title;

  /// More detail; left out when empty.
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final detail = body?.trim() ?? '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 44, color: p.textMuted),
              const SizedBox(height: 12),
            ],
            if (title != null)
              Text(
                title!,
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMedium.copyWith(color: p.textPrimary),
              ),
            if (detail.isNotEmpty) ...[
              if (title != null) const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
