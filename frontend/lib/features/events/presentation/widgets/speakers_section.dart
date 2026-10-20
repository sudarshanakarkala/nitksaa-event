/// The event page's Speakers (B1).
///
/// - Up to [SpeakersSection.compactFrom] speakers (the breakfast): today's
///   list, unchanged.
/// - More (NITKonnect has 83): "Speakers · 83", a search box (name, title or
///   company), a compact grid (4, 3 or 2 across with room, one column on
///   phones), the first 12, then "Show all 83 speakers".
library;

import 'package:flutter/material.dart';

import '../../../../theme/app_palette.dart';
import '../../domain/event.dart';

class SpeakersSection extends StatefulWidget {
  const SpeakersSection({super.key, required this.speakers});

  final List<EventPerson> speakers;

  /// More speakers than this get the grid, search and "Show all".
  static const int compactFrom = 12;

  static bool isBig(List<EventPerson> speakers) => speakers.length > compactFrom;

  @override
  State<SpeakersSection> createState() => _SpeakersSectionState();
}

class _SpeakersSectionState extends State<SpeakersSection> {
  final _search = TextEditingController();
  String _query = '';
  bool _showAll = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final speakers = widget.speakers;
    final big = SpeakersSection.isBig(speakers);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: 'Speakers',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: p.primary),
            children: [
              if (big)
                TextSpan(
                  text: ' · ${speakers.length}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: p.textMuted),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (speakers.isEmpty)
          Text('Speaker details will be updated soon.', style: TextStyle(fontSize: 14, color: p.textMuted))
        else if (!big)
          for (final sp in speakers) _SpeakerRow(speaker: sp, bottom: 16, avatarRadius: 20)
        else
          ..._bigList(context),
      ],
    );
  }

  List<Widget> _bigList(BuildContext context) {
    final p = context.palette;
    final all = widget.speakers;
    final query = _query.trim().toLowerCase();
    final matches = query.isEmpty ? all : all.where((s) => _matches(s, query)).toList();
    final limited = query.isEmpty && !_showAll && matches.length > SpeakersSection.compactFrom;
    final shown = limited ? matches.take(SpeakersSection.compactFrom).toList() : matches;

    return [
      TextField(
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          hintText: 'Search speakers',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      if (shown.isEmpty)
        Text(
          'No speakers match "${_query.trim()}".',
          style: TextStyle(fontSize: 14, color: p.textMuted),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final columns = w >= 840 ? 4 : (w >= 640 ? 3 : (w >= 480 ? 2 : 1));
            return _SpeakerGrid(speakers: shown, columns: columns);
          },
        ),
      if (query.isEmpty && matches.length > SpeakersSection.compactFrom) ...[
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => setState(() => _showAll = !_showAll),
          child: Text(_showAll ? 'Show fewer' : 'Show all ${all.length} speakers'),
        ),
      ],
    ];
  }

  static bool _matches(EventPerson s, String query) {
    for (final field in [s.fullname, s.title, s.organisation]) {
      if (field != null && field.toLowerCase().contains(query)) return true;
    }
    return false;
  }
}

class _SpeakerGrid extends StatelessWidget {
  const _SpeakerGrid({required this.speakers, required this.columns});

  final List<EventPerson> speakers;
  final int columns;

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    final rows = <Widget>[];
    for (var i = 0; i < speakers.length; i += columns) {
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        if (c > 0) cells.add(const SizedBox(width: gap));
        final index = i + c;
        cells.add(Expanded(
          child: index < speakers.length
              ? _SpeakerRow(speaker: speakers[index], bottom: gap, avatarRadius: 18, compact: true)
              : const SizedBox.shrink(),
        ));
      }
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// Avatar, name, and "Title, Company".
class _SpeakerRow extends StatelessWidget {
  const _SpeakerRow({
    required this.speaker,
    required this.bottom,
    required this.avatarRadius,
    this.compact = false,
  });

  final EventPerson speaker;
  final double bottom;
  final double avatarRadius;

  /// In the grid: name and details cut at two lines each.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Row(
        crossAxisAlignment: compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SpeakerAvatar(
            speaker: speaker,
            radius: avatarRadius,
            accentColor: p.primary,
            initialsStyle: TextStyle(
              color: p.primary,
              fontWeight: FontWeight.bold,
              fontSize: compact ? 13 : null,
            ),
          ),
          SizedBox(width: compact ? 10 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  speaker.fullname,
                  maxLines: compact ? 2 : null,
                  overflow: compact ? TextOverflow.ellipsis : null,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  speaker.subtitle,
                  maxLines: compact ? 2 : null,
                  overflow: compact ? TextOverflow.ellipsis : null,
                  style: TextStyle(fontSize: 12, color: p.textMuted),
                ),
                // NITK batch (B7), e.g. "Electrical & Electronics, 1981".
                if ((speaker.batch ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    speaker.batch!.trim(),
                    key: const ValueKey('speaker-batch'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: p.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A speaker's photo, or their initials when there is none or it fails.
class SpeakerAvatar extends StatelessWidget {
  const SpeakerAvatar({
    super.key,
    required this.speaker,
    required this.radius,
    required this.accentColor,
    required this.initialsStyle,
  });

  final EventPerson speaker;
  final double radius;
  final Color accentColor;
  final TextStyle initialsStyle;

  @override
  Widget build(BuildContext context) {
    final photoUrl = speaker.photoUrl?.trim();
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: accentColor.withValues(alpha: 0.15),
      child: Text(speaker.initials, style: initialsStyle),
    );

    if (photoUrl == null || photoUrl.isEmpty) {
      return fallback;
    }

    return ClipOval(
      child: Image.network(
        photoUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
