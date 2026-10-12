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

/// Website `select` filter: one choice from a list you can type into
/// ("All …" clears it). For lists too long for chips, such as branches.
class FilterSearchSelect extends StatelessWidget {
  const FilterSearchSelect({
    super.key,
    required this.label,
    required this.allLabel,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;

  /// The "no filter" entry, e.g. "All branches".
  final String allLabel;

  /// Value → text.
  final Map<String, String> options;

  /// The chosen value, or null for all.
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final known = value != null && options.containsKey(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterLabel(label),
          const SizedBox(height: 8),
          DropdownMenu<String>(
            // Rebuild when the choice is cleared from outside.
            key: ValueKey(value),
            initialSelection: known ? value : '',
            expandedInsets: EdgeInsets.zero,
            enableFilter: true,
            requestFocusOnTap: true,
            menuHeight: 320,
            hintText: allLabel,
            dropdownMenuEntries: [
              DropdownMenuEntry<String>(value: '', label: allLabel),
              for (final entry in options.entries)
                DropdownMenuEntry<String>(value: entry.key, label: entry.value),
            ],
            onSelected: (v) => onChanged(v == null || v.isEmpty ? null : v),
          ),
        ],
      ),
    );
  }
}

/// Website "Graduation Era": decade buttons (1990s, 2000s …) and a From /
/// To year range. Choosing a decade clears the years, and typing a year
/// clears the decade.
class FilterYearRange extends StatefulWidget {
  const FilterYearRange({
    super.key,
    required this.label,
    required this.decades,
    required this.decade,
    required this.from,
    required this.to,
    required this.onChanged,
  });

  final String label;

  /// Decades to offer, e.g. [1990, 2000, 2010].
  final List<int> decades;
  final int? decade;
  final int? from;
  final int? to;

  /// (decade, from, to).
  final void Function(int? decade, int? from, int? to) onChanged;

  @override
  State<FilterYearRange> createState() => _FilterYearRangeState();
}

class _FilterYearRangeState extends State<FilterYearRange> {
  late final _from = TextEditingController(text: widget.from?.toString() ?? '');
  late final _to = TextEditingController(text: widget.to?.toString() ?? '');

  @override
  void didUpdateWidget(FilterYearRange old) {
    super.didUpdateWidget(old);
    // Keep the boxes in step when the range is cleared or set elsewhere.
    final from = widget.from?.toString() ?? '';
    final to = widget.to?.toString() ?? '';
    if (_from.text != from && int.tryParse(_from.text) != widget.from) _from.text = from;
    if (_to.text != to && int.tryParse(_to.text) != widget.to) _to.text = to;
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _typed() {
    final from = int.tryParse(_from.text.trim());
    final to = int.tryParse(_to.text.trim());
    widget.onChanged(null, from, to);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    InputDecoration box(String hint) => InputDecoration(
          hintText: hint,
          isDense: true,
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterLabel(widget.label),
          const SizedBox(height: 8),
          if (widget.decades.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in widget.decades)
                  FilterChipToggle(
                    label: '${d}s',
                    selected: widget.decade == d,
                    onChanged: (on) {
                      _from.clear();
                      _to.clear();
                      widget.onChanged(on ? d : null, null, null);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _from,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: box('From year'),
                  style: AppTextStyles.bodySmall.copyWith(color: p.textPrimary),
                  onChanged: (_) => _typed(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('–', style: TextStyle(color: p.textMuted)),
              ),
              Expanded(
                child: TextField(
                  controller: _to,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: box('To year'),
                  style: AppTextStyles.bodySmall.copyWith(color: p.textPrimary),
                  onChanged: (_) => _typed(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
