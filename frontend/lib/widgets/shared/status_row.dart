import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';

/// A reusable status row displaying a label, a value and an optional check / error icon.
class StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final bool ok;
  final ColorScheme? colorScheme;
  final TextStyle? textStyle;

  const StatusRow({
    Key? key,
    required this.label,
    required this.value,
    required this.ok,
    this.colorScheme,
    this.textStyle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme ?? Theme.of(context).colorScheme;
    final ts = textStyle ?? Theme.of(context).textTheme.bodyMedium;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          color: ok ? context.palette.success : cs.error,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text('$label: $value', style: ts),
      ],
    );
  }
}
