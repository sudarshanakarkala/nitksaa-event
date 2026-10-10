import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Page heading block matching the website's PageHeader:
/// optional gold eyebrow, serif title, short gold rule, optional subtitle.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final compact = MediaQuery.sizeOf(context).width < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!.toUpperCase(),
            style: AppTextStyles.eyebrow.copyWith(color: p.primary),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          title,
          style: AppTextStyles.headlineLarge.copyWith(
            color: p.textPrimary,
            fontSize: compact ? 28 : 35,
          ),
        ),
        const SizedBox(height: 12),
        // Gold divider: 48×2, gold fading to transparent.
        Container(
          width: 48,
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [p.primary, p.primary.withValues(alpha: 0)],
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 12),
          Text(
            subtitle!,
            style: AppTextStyles.bodyMedium.copyWith(
              color: p.textSecondary,
              fontSize: 15,
            ),
          ),
        ],
      ],
    );
  }
}
