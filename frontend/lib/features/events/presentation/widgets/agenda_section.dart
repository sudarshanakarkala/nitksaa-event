/// The event page's Agenda (B1).
///
/// - Small events (no two sessions at the same time, e.g. the breakfast):
///   today's simple list, unchanged.
/// - Big events (NITKonnect): sessions grouped by time slot
///   ([Agenda.build]). A slot's time pill shows the range when every session
///   ends together, otherwise the start, and each card its own end. Parallel
///   sessions sit in a grid (3 or 2 across) when there is room, and swipe
///   sideways on phones, with the next card peeking in and "1 of 6".
///   A break is a full-width band. The hall (`track`) and the subtitle
///   (`description`) show when set.
library;

import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../../../../shared/format.dart';
import '../../../../theme/app_palette.dart';
import '../../domain/agenda_slots.dart';
import '../../domain/event.dart';
import 'event_brand.dart';

class AgendaSection extends StatelessWidget {
  const AgendaSection({super.key, required this.sessions, this.accent});

  final List<EventSession> sessions;

  /// A branded event's accent (B6): time pills filled with it, break bands
  /// tinted with it. Null: the theme.
  final Color? accent;

  /// Whether this agenda gets the big-event layout (and the page puts it
  /// first).
  static bool isBig(List<EventSession> sessions) => Agenda.hasParallel(sessions);

  /// Below this width parallel sessions swipe; at or above it they sit in a
  /// grid.
  static const double gridFrom = 560;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Agenda',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: p.primary),
        ),
        const SizedBox(height: 12),
        if (sessions.isEmpty)
          Text('Agenda will be updated soon.', style: TextStyle(fontSize: 14, color: p.textMuted))
        else if (!isBig(sessions))
          ..._simpleList(context)
        else
          _BigAgenda(sessions: sessions, accent: accent),
      ],
    );
  }

  /// Today's list: time, then "Title - Speaker".
  List<Widget> _simpleList(BuildContext context) {
    return [
      for (final item in sessions)
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatTimeRange(item.startDatetime, item.endDatetime),
                style: TextStyle(color: context.palette.primary, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(_simpleTitle(item), style: const TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ),
    ];
  }

  static String _simpleTitle(EventSession session) {
    final parts = [
      session.title,
      if (session.speakerName != null && session.speakerName!.trim().isNotEmpty)
        session.speakerName!.trim(),
    ];
    return parts.join(' - ');
  }
}

class _BigAgenda extends StatelessWidget {
  const _BigAgenda({required this.sessions, this.accent});

  final List<EventSession> sessions;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final days = Agenda.build(sessions);
    final severalDays = days.length > 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final day in days) ...[
              if (severalDays) _DayHeading(date: day.date, first: identical(day, days.first)),
              for (final slot in day.slots)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _SlotView(slot: slot, width: width, accent: accent),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.date, required this.first});

  final DateTime date;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 8, bottom: 10),
      child: Text(
        '${weekdayNames[date.weekday - 1]} ${formatDate(date)}',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.textSecondary, letterSpacing: 0.3),
      ),
    );
  }
}

class _SlotView extends StatelessWidget {
  const _SlotView({required this.slot, required this.width, this.accent});

  final AgendaSlot slot;
  final double width;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final sharedEnd = slot.sharedEnd;
    final time = sharedEnd != null ? formatTimeRange(slot.start, sharedEnd) : formatTime(slot.start);
    final showOwnEnd = sharedEnd == null;

    if (slot.isBreak) return _BreakBand(session: slot.sessions.single, time: time, accent: accent);

    if (!slot.isParallel) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: _TimePill(text: time, accent: accent)),
          const SizedBox(height: 8),
          _SessionCard(session: slot.sessions.single, showOwnEnd: showOwnEnd),
        ],
      );
    }

    if (width < AgendaSection.gridFrom) {
      return _ParallelSwipe(
        slot: slot,
        time: time,
        width: width,
        showOwnEnd: showOwnEnd,
        accent: accent,
      );
    }

    final columns = width >= 900 ? 3 : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SlotHeader(time: time, count: slot.sessions.length, accent: accent),
        const SizedBox(height: 8),
        _SessionGrid(sessions: slot.sessions, columns: columns, showOwnEnd: showOwnEnd),
      ],
    );
  }
}

/// The time pill, and "N sessions at once" for parallel sessions.
class _SlotHeader extends StatelessWidget {
  const _SlotHeader({required this.time, required this.count, this.trailing, this.accent});

  final String time;
  final int count;
  final Widget? trailing;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        _TimePill(text: time, accent: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$count sessions at once',
            style: TextStyle(fontSize: 13, color: p.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill({required this.text, this.accent});

  final String text;

  /// Branded: filled with the accent, text black or white to suit it.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final brand = accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: brand ?? p.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: brand == null ? p.primary : EventBrand.onFill(brand),
        ),
      ),
    );
  }
}

class _BreakBand extends StatelessWidget {
  const _BreakBand({required this.session, required this.time, this.accent});

  final EventSession session;
  final String time;

  /// Branded: the band tinted with the accent.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final brand = accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: brand == null
            ? p.surfaceSubtle
            : Color.alphaBlend(brand.withValues(alpha: 0.16), p.surfaceSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_cafe_outlined, size: 16, color: p.textMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${session.title.trim()} · $time',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rows of [columns] cards; the cards in a row are the same height.
class _SessionGrid extends StatelessWidget {
  const _SessionGrid({required this.sessions, required this.columns, required this.showOwnEnd});

  final List<EventSession> sessions;
  final int columns;
  final bool showOwnEnd;

  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < sessions.length; i += columns) {
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        if (c > 0) cells.add(const SizedBox(width: _gap));
        final index = i + c;
        cells.add(Expanded(
          child: index < sessions.length
              ? _SessionCard(session: sessions[index], showOwnEnd: showOwnEnd, compact: true)
              : const SizedBox.shrink(),
        ));
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: _gap));
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// Phones: parallel sessions side by side, swiped one at a time.
class _ParallelSwipe extends StatefulWidget {
  const _ParallelSwipe({
    required this.slot,
    required this.time,
    required this.width,
    required this.showOwnEnd,
    this.accent,
  });

  final AgendaSlot slot;
  final String time;
  final double width;
  final bool showOwnEnd;
  final Color? accent;

  @override
  State<_ParallelSwipe> createState() => _ParallelSwipeState();
}

class _ParallelSwipeState extends State<_ParallelSwipe> {
  static const double _gap = 10;
  final _controller = ScrollController();
  int _index = 0;

  double get _cardWidth => widget.width * 0.82;
  double get _step => _cardWidth + _gap;
  int get _count => widget.slot.sessions.length;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    final index = (_controller.offset / _step).round().clamp(0, _count - 1);
    if (index != _index) setState(() => _index = index);
  }

  /// After a swipe, settle on the nearest card.
  bool _onScrollEnd(ScrollEndNotification _) {
    if (!_controller.hasClients) return false;
    final target = (_index * _step).clamp(0.0, _controller.position.maxScrollExtent).toDouble();
    if ((_controller.offset - target).abs() > 1) {
      scheduleMicrotask(() {
        if (!mounted || !_controller.hasClients) return;
        _controller.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sessions = widget.slot.sessions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SlotHeader(
          time: widget.time,
          count: _count,
          accent: widget.accent,
          trailing: Text(
            '${_index + 1} of $_count',
            style: TextStyle(fontSize: 12, color: p.textMuted),
          ),
        ),
        const SizedBox(height: 8),
        NotificationListener<ScrollEndNotification>(
          onNotification: _onScrollEnd,
          child: ScrollConfiguration(
            // Mouse drags swipe too (a narrow desktop window).
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
                PointerDeviceKind.stylus,
              },
              scrollbars: false,
            ),
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < sessions.length; i++) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      SizedBox(
                        width: _cardWidth,
                        child: _SessionCard(
                          session: sessions[i],
                          showOwnEnd: widget.showOwnEnd,
                          compact: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One session: hall, title, subtitle, speaker, and its own end time when
/// the slot's sessions end at different times.
class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.showOwnEnd, this.compact = false});

  final EventSession session;
  final bool showOwnEnd;

  /// In a grid or swipe row: the subtitle is cut at 3 lines.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hall = session.track?.trim() ?? '';
    final subtitle = session.description?.trim() ?? '';
    final speaker = session.speakerName?.trim() ?? '';
    final end = session.endDatetime;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hall.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.meeting_room_outlined, size: 14, color: p.textMuted),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    hall,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: p.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          Text(
            session.title,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.textPrimary),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: compact ? 3 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
              style: TextStyle(fontSize: 13, color: p.textSecondary),
            ),
          ],
          if (speaker.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.person_outline, size: 14, color: p.textSecondary),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(speaker, style: TextStyle(fontSize: 12, color: p.textSecondary)),
                ),
              ],
            ),
          ],
          if (showOwnEnd && end != null) ...[
            const SizedBox(height: 6),
            Text('Until ${formatTime(end)}', style: TextStyle(fontSize: 12, color: p.textMuted)),
          ],
        ],
      ),
    );
  }
}
