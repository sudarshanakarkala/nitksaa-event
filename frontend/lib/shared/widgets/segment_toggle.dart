import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

class SegmentOption<T> {
  const SegmentOption(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Bordered two-or-more-way switch, like the website's Cards / Table toggle:
/// the selected segment is gold on a faint gold fill. A two-way switch also
/// flips when its selected side is clicked.
class SegmentToggle<T> extends StatelessWidget {
  const SegmentToggle({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) VerticalDivider(width: 1, thickness: 1, color: p.border),
            _segment(context, options[i]),
          ],
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, SegmentOption<T> option) {
    final p = context.palette;
    final active = option.value == selected;
    final color = active ? p.primary : p.textSecondary;
    return Material(
      color: active ? p.primary.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        // With two options the active one flips to the other, so clicking
        // the highlighted side also switches (Table → Cards).
        onTap: !active
            ? () => onChanged(option.value)
            : options.length == 2
            ? () => onChanged(options.firstWhere((o) => o.value != option.value).value)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              if (option.icon != null) ...[
                Icon(option.icon, size: 15, color: color),
                const SizedBox(width: 6),
              ],
              Text(
                option.label,
                style: AppTextStyles.labelLarge.copyWith(
                  color: color,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
