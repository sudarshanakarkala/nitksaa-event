import 'package:flutter/material.dart';

import '../../../../shared/widgets/filter_controls.dart';
import '../../../../shared/widgets/quick_filter_pill.dart';
import '../../../admin/domain/registration_filters.dart' show compareCells;
import '../../domain/event.dart';

/// What the Events page and Admin → Events share (`ADMIN_LAYOUT_DESIGN.md`
/// §4, Events): the order of the cards, the fullness sort and the date line.

/// The event has ended (its end, or its start when it has none).
bool eventEnded(AppEvent e, [DateTime? now]) =>
    (e.endDatetime ?? e.startDatetime).isBefore(now ?? DateTime.now());

/// Share of seats taken; null with no capacity set (sorted last).
double? eventFill(AppEvent e) {
  final capacity = e.capacity;
  return capacity == null || capacity <= 0 ? null : e.registeredCount / capacity;
}

/// Card order by fullness. None: by date, in the Date button's direction.
enum EventFill {
  most('Most full'),
  least('Least full');

  const EventFill(this.label);
  final String label;
}

/// The cards in order.
/// - By date, soonest first: upcoming soonest at the top, then past most
///   recent first. Latest first: newest start at the top.
/// - By fullness: share of seats taken, no capacity last; ties in date order.
List<AppEvent> orderEvents(
  Iterable<AppEvent> events, {
  required bool soonestFirst,
  EventFill? fill,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final rows = events.toList();
  final List<AppEvent> byDate;
  if (soonestFirst) {
    final upcoming = rows.where((e) => !eventEnded(e, at)).toList()
      ..sort((a, b) => a.startDatetime.compareTo(b.startDatetime));
    final past = rows.where((e) => eventEnded(e, at)).toList()
      ..sort((a, b) => b.startDatetime.compareTo(a.startDatetime));
    byDate = [...upcoming, ...past];
  } else {
    byDate = rows..sort((a, b) => b.startDatetime.compareTo(a.startDatetime));
  }
  if (fill == null) return byDate;
  final indexed = [for (var i = 0; i < byDate.length; i++) (i, byDate[i])];
  indexed.sort((a, b) {
    final r = compareCells(eventFill(a.$2), eventFill(b.$2), ascending: fill == EventFill.least);
    return r != 0 ? r : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// The date presets on both Events pages: This week · This month ·
/// Next 90 days (all from today).
List<(String, DateTimeRange)> eventDatePresets(DateTime now) {
  final today = DateUtils.dateOnly(now);
  final endOfWeek = today.add(Duration(days: DateTime.daysPerWeek - today.weekday));
  final endOfMonth = DateTime(today.year, today.month + 1, 0);
  return [
    ('This week', DateTimeRange(start: today, end: endOfWeek)),
    ('This month', DateTimeRange(start: today, end: endOfMonth)),
    ('Next 90 days', DateTimeRange(start: today, end: today.add(const Duration(days: 90)))),
  ];
}

/// The Events date line: Date ↑/↓ (when [sortable]), the presets, the
/// slider over the events' own dates (and the next 90 days), From – To.
///
/// Date ↑ is soonest first, ↓ latest first; it's lit while the cards are in
/// date order ([dateOrder]). Tapped while sorted by fullness it goes back to
/// date order ([onDateOrder]); tapped again it flips ([onFlip]).
class EventDateLine extends StatelessWidget {
  const EventDateLine({
    super.key,
    required this.events,
    required this.value,
    required this.onChanged,
    required this.soonestFirst,
    required this.dateOrder,
    required this.onDateOrder,
    required this.onFlip,
    this.sortable = true,
    this.rail = false,
  });

  /// In the Filters rail: the order as its own section ("Order: Soonest
  /// first · Latest first"), then the dates stacked (presets, slider,
  /// From – To).
  final bool rail;

  /// All the events the page could show (sets the slider's span).
  final List<AppEvent> events;
  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;

  final bool soonestFirst;
  final bool dateOrder;
  final VoidCallback onDateOrder;
  final VoidCallback onFlip;

  /// Cards are on screen (the table sorts by its headings instead).
  final bool sortable;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final soon = today.add(const Duration(days: 90));
    var first = today;
    var last = soon;
    for (final e in events) {
      final d = DateUtils.dateOnly(e.startDatetime.toLocal());
      if (d.isBefore(first)) first = d;
      if (d.isAfter(last)) last = d;
    }
    if (rail) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sortable) ...[
            const FilterLabel('Order'),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              FilterChipToggle(
                label: 'Soonest first',
                selected: dateOrder && soonestFirst,
                onChanged: (_) {
                  if (!dateOrder) onDateOrder();
                  if (!soonestFirst) onFlip();
                },
              ),
              FilterChipToggle(
                label: 'Latest first',
                selected: dateOrder && !soonestFirst,
                onChanged: (_) {
                  if (!dateOrder) onDateOrder();
                  if (soonestFirst) onFlip();
                },
              ),
            ]),
            const SizedBox(height: 20),
          ],
          FilterDateRange(
            label: 'Starts',
            typed: true,
            first: first,
            last: last,
            value: value,
            presets: eventDatePresets(now),
            onChanged: onChanged,
          ),
        ],
      );
    }
    return FilterDateRange(
      inline: true,
      label: 'Starts',
      leading: sortable
          ? QuickFilterPill(
              label: soonestFirst ? 'Date ↑' : 'Date ↓',
              active: dateOrder,
              onTap: dateOrder ? onFlip : onDateOrder,
            )
          : null,
      first: first,
      last: last,
      value: value,
      presets: eventDatePresets(now),
      onChanged: onChanged,
    );
  }
}
