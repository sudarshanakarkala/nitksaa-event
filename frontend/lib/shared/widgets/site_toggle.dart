import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';

/// The website's toggle switch (`.toggle-track` / `.toggle-thumb`): a 40×22
/// track with a 16px thumb, gold-tinted when on. Smaller and quieter than
/// Material's Switch. [onChanged] null = locked (dimmed).
class SiteToggle extends StatelessWidget {
  const SiteToggle({super.key, required this.value, required this.onChanged, this.tooltip});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onChanged != null;
    final toggle = Semantics(
      toggled: value,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? () => onChanged!(!value) : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.55,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 22,
              decoration: BoxDecoration(
                color: value ? p.primary.withValues(alpha: 0.2) : p.surface,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: value ? p.primary.withValues(alpha: 0.5) : p.border),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: value ? p.primary : p.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? toggle : Tooltip(message: tooltip!, child: toggle);
  }
}
