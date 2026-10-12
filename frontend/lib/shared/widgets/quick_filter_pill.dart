import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Quick filter pill, deliberately unlike the tabs (which navigate): fully
/// rounded and borderless; the active one solid gold with dark text. An
/// optional [count] sits inside the pill.
class QuickFilterPill extends StatelessWidget {
  const QuickFilterPill({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = active ? p.onPrimary : p.textSecondary;
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? p.primary : p.surfaceSubtle,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: p.surfaceHover,
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, 6, count == null ? 14 : 6, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTextStyles.labelMedium.copyWith(
                    fontSize: 12.8,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: 0,
                    color: fg,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: active
                          ? p.onPrimary.withValues(alpha: 0.16)
                          : p.textPrimary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.labelSmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
