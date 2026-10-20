/// The event page's Agenda.
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
/// - Session details: a card shows its type and pillar above the title
///   and "Presented by …" under it; a session of type Break is a band; when
///   sessions have two or more pillars, chips above the agenda filter by
///   pillar (break bands always show).
library;

import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../../../../shared/format.dart';
import '../../../../theme/app_palette.dart';
import '../../domain/agenda_slots.dart';
import '../../domain/event.dart';
import 'speakers_section.dart' show SpeakerAvatar;

class AgendaSection extends StatelessWidget {
  const AgendaSection({
    super.key,
    required this.sessions,
    this.people = const [],
    this.sponsors = const [],
  });

  final List<EventSession> sessions;

  /// The event's people, for the speakers under each session.
  final List<EventPerson> people;

  /// The event's sponsors, for "Presented by" on each session.
  final List<EventSponsor> sponsors;

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
          _AgendaPeople(
            byId: {for (final person in people) person.personId: person},
            sponsorsById: {for (final sponsor in sponsors) sponsor.sponsorId: sponsor},
            child: _BigAgenda(sessions: sessions),
          ),
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

class _BigAgenda extends StatefulWidget {
  const _BigAgenda({required this.sessions});

  final List<EventSession> sessions;

  @override
  State<_BigAgenda> createState() => _BigAgendaState();
}

class _BigAgendaState extends State<_BigAgenda> {
  /// The pillar chosen in the filter; null for all.
  String? _pillar;

  @override
  Widget build(BuildContext context) {
    final pillars = Agenda.pillars(widget.sessions);
    final pillar = pillars.contains(_pillar) ? _pillar : null;
    final shown = pillar == null
        ? widget.sessions
        : [
            for (final s in widget.sessions)
              if (s.pillar == pillar || Agenda.looksLikeBreak(s)) s,
          ];
    final days = Agenda.build(shown);
    final severalDays = days.length > 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pillars.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _PillarFilter(
                  pillars: pillars,
                  selected: pillar,
                  onSelected: (value) => setState(() => _pillar = value),
                ),
              ),
            for (final day in days) ...[
              if (severalDays) _DayHeading(date: day.date, first: identical(day, days.first)),
              for (final slot in day.slots)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _SlotView(slot: slot, width: width),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// "All · Main Event · Career Konnect …": one chip per pillar.
class _PillarFilter extends StatelessWidget {
  const _PillarFilter({required this.pillars, required this.selected, required this.onSelected});

  final List<String> pillars;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('All'),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final pillar in pillars)
          ChoiceChip(
            label: Text(pillar),
            selected: selected == pillar,
            onSelected: (on) => onSelected(on ? pillar : null),
          ),
      ],
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
  const _SlotView({required this.slot, required this.width});

  final AgendaSlot slot;
  final double width;

  @override
  Widget build(BuildContext context) {
    final sharedEnd = slot.sharedEnd;
    final time = sharedEnd != null ? formatTimeRange(slot.start, sharedEnd) : formatTime(slot.start);
    final showOwnEnd = sharedEnd == null;

    if (slot.isBreak) return _BreakBand(session: slot.sessions.single, time: time);

    if (!slot.isParallel) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: _TimePill(text: time)),
          const SizedBox(height: 8),
          _SessionCard(session: slot.sessions.single, showOwnEnd: showOwnEnd),
        ],
      );
    }

    if (width < AgendaSection.gridFrom) {
      return _ParallelSwipe(slot: slot, time: time, width: width, showOwnEnd: showOwnEnd);
    }

    final columns = width >= 900 ? 3 : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SlotHeader(time: time, count: slot.sessions.length),
        const SizedBox(height: 8),
        _SessionGrid(sessions: slot.sessions, columns: columns, showOwnEnd: showOwnEnd),
      ],
    );
  }
}

/// The time pill, and "N sessions at once" for parallel sessions.
class _SlotHeader extends StatelessWidget {
  const _SlotHeader({required this.time, required this.count, this.trailing});

  final String time;
  final int count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        _TimePill(text: time),
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
  const _TimePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: p.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: p.primary),
      ),
    );
  }
}

class _BreakBand extends StatelessWidget {
  const _BreakBand({required this.session, required this.time});

  final EventSession session;
  final String time;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.surfaceSubtle,
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
  });

  final AgendaSlot slot;
  final String time;
  final double width;
  final bool showOwnEnd;

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

/// One session: hall, title, subtitle, its speakers (or the old single
/// speaker line when it has no linked people), and its own end time when
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
    final linked = _AgendaPeople.resolve(context, session.people);
    final presenters = _AgendaPeople.presenters(context, session.presentedBy);
    final eyebrow = [
      ?session.typeLabel,
      ?session.pillar,
    ].join(' · ');
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
          if (eyebrow.isNotEmpty) ...[
            Text(
              eyebrow,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.primary, letterSpacing: 0.2),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
          ],
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
          if (presenters.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Presented by ${Agenda.joinNames([for (final s in presenters) s.name])}',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: p.textSecondary),
            ),
          ],
          if (linked.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SessionSpeakers(people: linked),
          ] else if (speaker.isNotEmpty) ...[
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

/// The event's people by id, for the session cards below it.
class _AgendaPeople extends InheritedWidget {
  const _AgendaPeople({required this.byId, this.sponsorsById = const {}, required super.child});

  final Map<int, EventPerson> byId;

  /// The event's sponsors by id, for "Presented by".
  final Map<int, EventSponsor> sponsorsById;

  /// [ids] as the event's sponsors, in order; ids not found are left out.
  static List<EventSponsor> presenters(BuildContext context, List<int> ids) {
    if (ids.isEmpty) return const [];
    final byId = context.dependOnInheritedWidgetOfExactType<_AgendaPeople>()?.sponsorsById ?? const {};
    return [
      for (final id in ids) ?byId[id],
    ];
  }

  /// [refs] as people with their role on the session, in order; ids not
  /// found (e.g. hidden) are left out.
  static List<(EventPerson, SessionPersonRef)> resolve(
    BuildContext context,
    List<SessionPersonRef> refs,
  ) {
    if (refs.isEmpty) return const [];
    final byId = context.dependOnInheritedWidgetOfExactType<_AgendaPeople>()?.byId ?? const {};
    return [
      for (final ref in refs)
        if (byId[ref.personId] case final person?) (person, ref),
    ];
  }

  @override
  bool updateShouldNotify(_AgendaPeople old) => old.byId != byId || old.sponsorsById != sponsorsById;
}

/// A session's speakers: photo or initials, name, title and company; a
/// moderator labelled. More than 3: the first 3, then "+N more" to see the
/// rest.
class _SessionSpeakers extends StatefulWidget {
  const _SessionSpeakers({required this.people});

  final List<(EventPerson, SessionPersonRef)> people;

  static const int shownFirst = 3;

  @override
  State<_SessionSpeakers> createState() => _SessionSpeakersState();
}

class _SessionSpeakersState extends State<_SessionSpeakers> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final people = widget.people;
    final more = people.length - _SessionSpeakers.shownFirst;
    final shown = _all || more <= 0 ? people : people.take(_SessionSpeakers.shownFirst).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (person, ref) in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SpeakerAvatar(
                  speaker: person,
                  radius: 12,
                  accentColor: p.primary,
                  initialsStyle: TextStyle(color: p.primary, fontWeight: FontWeight.bold, fontSize: 10),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: person.fullname,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.textPrimary),
                          children: [
                            if (ref.isModerator)
                              TextSpan(
                                text: ' · Moderator',
                                style: TextStyle(fontWeight: FontWeight.normal, color: p.textMuted),
                              ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_details(person).isNotEmpty)
                        Text(
                          _details(person),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: p.textSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (more > 0)
          InkWell(
            onTap: () => setState(() => _all = !_all),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                _all ? 'Show fewer' : '+$more more',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.primary),
              ),
            ),
          ),
      ],
    );
  }

  /// "Title · Company", whichever are set.
  static String _details(EventPerson person) => [
        if ((person.title ?? '').trim().isNotEmpty) person.title!.trim(),
        if ((person.organisation ?? '').trim().isNotEmpty) person.organisation!.trim(),
      ].join(' · ');
}
