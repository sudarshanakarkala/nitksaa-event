import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Shared form pieces, following the website's `.field` look: a small
/// uppercase muted label above the control, an optional helper line below.
/// The controls themselves are plain `TextFormField`s styled by the theme.
/// See `UI_PATTERNS.md` → Forms.

/// Uppercase muted label above a field. [optional] adds "(optional)".
class FormFieldLabel extends StatelessWidget {
  const FormFieldLabel(this.text, {super.key, this.optional = false});

  final String text;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final label = optional ? '$text (optional)' : text;
    return Text(
      label.toUpperCase(),
      style: AppTextStyles.labelMedium.copyWith(color: context.palette.textMuted),
    );
  }
}

/// A label above any control, with an optional muted helper line below.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.helper,
    this.optional = false,
  });

  final String label;
  final Widget child;
  final String? helper;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormFieldLabel(label, optional: optional),
        const SizedBox(height: 6),
        child,
        if (helper != null) ...[
          const SizedBox(height: 6),
          Text(
            helper!,
            style: AppTextStyles.bodySmall.copyWith(color: context.palette.textMuted),
          ),
        ],
      ],
    );
  }
}

/// A value the person can see but not change, on a subtle surface with a border.
class ReadOnlyValue extends StatelessWidget {
  const ReadOnlyValue(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.surfaceSubtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.border),
      ),
      child: Text(
        text.isNotEmpty ? text : '—',
        style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
      ),
    );
  }
}

/// Eyebrow-style section heading inside a form ("YOUR DETAILS").
class FormSectionLabel extends StatelessWidget {
  const FormSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.eyebrow.copyWith(color: context.palette.primary),
    );
  }
}
