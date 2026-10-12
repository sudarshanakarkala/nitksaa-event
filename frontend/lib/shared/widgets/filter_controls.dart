import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Filter section label in the Filters rail, website `.filter-label`: small
/// uppercase, 70% gold. Same look as the Events page.
class FilterLabel extends StatelessWidget {
  const FilterLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppTextStyles.eyebrow.copyWith(
          fontSize: 11.5,
          letterSpacing: 0.9,
          color: context.palette.primary.withValues(alpha: 0.7),
        ),
      );
}

/// On/off chip in the Filters rail (website filter chip). Same look as the
/// Events page.
class FilterChipToggle extends StatelessWidget {
  const FilterChipToggle({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => onChanged(!selected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? p.primary.withValues(alpha: 0.14) : p.surfaceSubtle,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.primary.withValues(alpha: selected ? 0.5 : 0.14)),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            fontSize: 12.8,
            height: 1.2,
            color: selected ? p.primary : p.textSecondary,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// A rail section: label, then its chips (multi-select; none = all).
class FilterChipSection extends StatelessWidget {
  const FilterChipSection({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;

  /// Value → chip text.
  final Map<String, String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterLabel(label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in options.entries)
                FilterChipToggle(
                  label: entry.value,
                  selected: selected.contains(entry.key),
                  onChanged: (on) => onChanged(
                    on ? {...selected, entry.key} : ({...selected}..remove(entry.key)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Count line under the pills, as on the Events page: "**24** events".
class ResultCount extends StatelessWidget {
  const ResultCount({super.key, required this.count, required this.one, required this.many});

  final int count;
  final String one;
  final String many;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$count',
            style: TextStyle(color: p.primary, fontWeight: FontWeight.w600),
          ),
          TextSpan(text: count == 1 ? ' $one' : ' $many'),
        ],
      ),
      style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary),
    );
  }
}

/// The filters on phones: the same rail content in a bottom sheet, rebuilt
/// as choices change.
Future<void> showFilterSheet(
  BuildContext context, {
  required WidgetBuilder builder,
  VoidCallback? onClear,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Filters',
                        style: AppTextStyles.titleLarge.copyWith(
                          fontSize: 17,
                          color: context.palette.textPrimary,
                        ),
                      ),
                    ),
                    if (onClear != null)
                      TextButton(
                        onPressed: () {
                          onClear();
                          setSheet(() {});
                        },
                        child: const Text('Clear all'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  // Rebuild the sheet on every tap inside it.
                  child: Listener(
                    onPointerUp: (_) => Future.microtask(() {
                      if (context.mounted) setSheet(() {});
                    }),
                    child: SingleChildScrollView(child: builder(context)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
