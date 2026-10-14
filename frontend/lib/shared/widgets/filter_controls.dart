import 'package:flutter/material.dart';

import '../format.dart';
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
  const ResultCount({
    super.key,
    required this.count,
    required this.one,
    required this.many,
    this.extra,
  });

  final int count;
  final String one;
  final String many;

  /// Added after a dot, e.g. "· 3 registered".
  final String? extra;

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
          if (extra != null) TextSpan(text: ' · $extra'),
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

/// Reads a typed date: "15 Nov", "15 November", "15/11", "15-11-26",
/// "15 Nov 2026" or "15/11/2026" (day first). With no year it takes the next
/// one on or after [today]. Null when it isn't a date.
DateTime? parseFilterDate(String text, DateTime today) {
  final t = text.trim().toLowerCase().replaceAll(',', ' ');
  if (t.isEmpty) return null;
  int? day;
  int? month;
  int? year;
  final numeric = RegExp(r'^(\d{1,2})[\/\-. ](\d{1,2})(?:[\/\-. ](\d{2}|\d{4}))?$').firstMatch(t);
  final named = RegExp(r'^(\d{1,2})\s*([a-z]{3,})\.?(?:\s+(\d{2}|\d{4}))?$').firstMatch(t);
  if (numeric != null) {
    day = int.parse(numeric.group(1)!);
    month = int.parse(numeric.group(2)!);
    year = numeric.group(3) == null ? null : int.parse(numeric.group(3)!);
  } else if (named != null) {
    day = int.parse(named.group(1)!);
    final name = named.group(2)!;
    for (var m = 0; m < 12; m++) {
      if (name.startsWith(monthNames[m].toLowerCase())) month = m + 1;
    }
    year = named.group(3) == null ? null : int.parse(named.group(3)!);
  }
  if (day == null || month == null || month < 1 || month > 12 || day < 1) return null;
  if (year != null && year < 100) year += 2000;
  DateTime make(int y) => DateTime(y, month!, day!);
  bool real(DateTime d) => d.month == month && d.day == day; // no 31 Feb
  if (year != null) {
    final d = make(year);
    return real(d) ? d : null;
  }
  final start = DateTime(today.year, today.month, today.day);
  var d = make(today.year);
  if (d.isBefore(start)) d = make(today.year + 1);
  return real(d) ? d : null;
}

/// A date range: preset chips for the common windows, a slider with two
/// handles over the dates that occur, and the range. Null means any date.
///
/// In the Filters rail the range shows in words. [inline] (on the page,
/// Admin → Events) puts it all on one line on wide screens, with From and
/// To boxes you can type into ("15 Nov") and a clear ×; an empty box means
/// no limit on that side.
///
/// The handles snap to days, or to weeks on phones, where a finger can't
/// land on one day. Each handle shows its date while dragged.
class FilterDateRange extends StatefulWidget {
  const FilterDateRange({
    super.key,
    required this.label,
    required this.first,
    required this.last,
    required this.value,
    required this.onChanged,
    this.presets = const [],
    this.inline = false,
  });

  final String label;
  final bool inline;

  /// The slider's ends (e.g. the earliest and latest event).
  final DateTime first;
  final DateTime last;

  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;

  /// One-tap windows, e.g. ('Next 30 days', range). Tap the lit one to clear.
  final List<(String, DateTimeRange)> presets;

  @override
  State<FilterDateRange> createState() => _FilterDateRangeState();
}

class _FilterDateRangeState extends State<FilterDateRange> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();
  bool _fromBad = false;
  bool _toBad = false;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _same(DateTimeRange a, DateTimeRange b) =>
      DateUtils.isSameDay(a.start, b.start) && DateUtils.isSameDay(a.end, b.end);

  DateTime get _lo => _day(widget.first.isBefore(widget.last) ? widget.first : widget.last);

  int get _step => MediaQuery.sizeOf(context).width < 600 ? 7 : 1;

  int get _steps => (_day(widget.last).difference(_lo).inDays.abs() / _step).ceil().clamp(1, 100000);

  DateTime get _hi => _lo.add(Duration(days: _steps * _step));

  @override
  void initState() {
    super.initState();
    _fill();
    _fromFocus.addListener(() {
      if (!_fromFocus.hasFocus) _typed();
    });
    _toFocus.addListener(() {
      if (!_toFocus.hasFocus) _typed();
    });
  }

  @override
  void didUpdateWidget(FilterDateRange old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _fill();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  /// The boxes show the range (blank for an open end), except while typed in.
  void _fill() {
    final v = widget.value;
    String show(DateTime? d) => d == null ? '' : formatDate(d);
    if (!_fromFocus.hasFocus) {
      _from.text = show(v == null || !v.start.isAfter(_loSafe) ? null : v.start);
      _fromBad = false;
    }
    if (!_toFocus.hasFocus) {
      _to.text = show(v == null || !v.end.isBefore(_hiSafe) ? null : v.end);
      _toBad = false;
    }
  }

  // Bounds without MediaQuery (usable from initState): whole days.
  DateTime get _loSafe => _lo;
  DateTime get _hiSafe => _day(widget.last.isAfter(widget.first) ? widget.last : widget.first);

  void _typed() {
    final today = DateTime.now();
    final fromText = _from.text.trim();
    final toText = _to.text.trim();
    final from = fromText.isEmpty ? null : parseFilterDate(fromText, today);
    var to = toText.isEmpty ? null : parseFilterDate(toText, today);
    setState(() {
      _fromBad = fromText.isNotEmpty && from == null;
      _toBad = toText.isNotEmpty && to == null;
    });
    if (_fromBad || _toBad) return;
    // "To" with no year before "From": the year after.
    if (from != null && to != null && to.isBefore(from) && !RegExp(r'\d{4}|[\/\-. ]\d{2}$').hasMatch(toText)) {
      to = DateTime(to.year + 1, to.month, to.day);
    }
    if (from == null && to == null) {
      widget.onChanged(null);
      return;
    }
    final start = from ?? (to != null && to.isBefore(_loSafe) ? to : _loSafe);
    final end = to ?? (from != null && from.isAfter(_hiSafe) ? from : _hiSafe);
    widget.onChanged(start.isAfter(end) ? DateTimeRange(start: end, end: start) : DateTimeRange(start: start, end: end));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final step = _step;
    final steps = _steps;
    final lo = _lo;
    final hi = _hi;
    DateTime at(double v) => lo.add(Duration(days: v.round()));
    double pos(DateTime d) => _day(d).difference(lo).inDays.clamp(0, steps * step).toDouble();

    final range = widget.value;
    final values = range == null
        ? RangeValues(0, (steps * step).toDouble())
        : RangeValues(pos(range.start), pos(range.end));

    final chips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (name, window) in widget.presets)
          FilterChipToggle(
            label: name,
            selected: range != null && _same(range, window),
            onChanged: (on) => widget.onChanged(on ? window : null),
          ),
      ],
    );
    final slider = RangeSlider(
      values: values,
      min: 0,
      max: (steps * step).toDouble(),
      divisions: steps,
      labels: RangeLabels(formatShortDate(at(values.start)), formatShortDate(at(values.end))),
      onChanged: (v) {
        final start = at(v.start);
        final end = at(v.end);
        // Both handles at the ends: any date again.
        final all = !start.isAfter(lo) && !end.isBefore(hi);
        widget.onChanged(all ? null : DateTimeRange(start: start, end: end));
      },
    );

    if (!widget.inline) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterLabel(widget.label),
            const SizedBox(height: 8),
            if (widget.presets.isNotEmpty) chips,
            slider,
            Text(
              range == null
                  ? 'Any date'
                  : DateUtils.isSameDay(range.start, range.end)
                      ? formatDate(range.start)
                      : '${formatDate(range.start)} – ${formatDate(range.end)}',
              style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      );
    }

    Widget box(TextEditingController c, FocusNode f, String hint, bool bad) => SizedBox(
          width: 118,
          child: TextField(
            controller: c,
            focusNode: f,
            onSubmitted: (_) => _typed(),
            textInputAction: TextInputAction.done,
            style: AppTextStyles.bodySmall.copyWith(color: p.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: bad ? p.error : p.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: bad ? p.error : p.primary),
              ),
            ),
          ),
        );
    final boxes = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Type a date, e.g. 15 Nov',
          child: box(_from, _fromFocus, 'From', _fromBad),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('–', style: TextStyle(color: p.textMuted)),
        ),
        Tooltip(
          message: 'Type a date, e.g. 31 Dec',
          child: box(_to, _toFocus, 'To', _toBad),
        ),
        if (range != null)
          IconButton(
            tooltip: 'Any date',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            color: p.textMuted,
            icon: const Icon(Icons.close),
            onPressed: () => widget.onChanged(null),
          ),
      ],
    );

    if (MediaQuery.sizeOf(context).width >= 900) {
      return Row(
        children: [
          if (widget.presets.isNotEmpty) ...[chips, const SizedBox(width: 12)],
          Expanded(child: slider),
          const SizedBox(width: 8),
          boxes,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.presets.isNotEmpty) chips,
        slider,
        Align(alignment: Alignment.centerLeft, child: boxes),
      ],
    );
  }
}
