import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Coloured pill for a state: event cards, admin tables, Payments, the
/// Dashboard. The tone is a palette colour with its usual meaning
/// (`UI_PATTERNS.md`: green done, yellow attention, red failed, blue info).
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.tone});

  /// An event's status (draft, published, cancelled, completed).
  factory StatusBadge.event(BuildContext context, String status) {
    final p = context.palette;
    final (label, tone) = switch (status) {
      'draft' => ('Draft', p.warning),
      'published' => ('Published', p.success),
      'cancelled' => ('Cancelled', p.error),
      'completed' => ('Completed', p.textMuted),
      _ => (status, p.textMuted),
    };
    return StatusBadge(label: label, tone: tone);
  }

  /// Payment mode: TEST or LIVE, always shown so practice payments are never
  /// mistaken for real money.
  factory StatusBadge.paymentMode(BuildContext context, String mode) {
    final p = context.palette;
    final live = mode == 'live';
    return StatusBadge(label: live ? 'LIVE' : 'TEST', tone: live ? p.success : p.info);
  }

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: tone,
        ),
      ),
    );
  }
}
