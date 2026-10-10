import 'package:flutter/material.dart';

/// NITiKa's limited markdown: paragraphs, `**bold**`, and `- ` / `* ` /
/// `1. ` lists. Everything else (links, headings, HTML) shows as plain text.
class AnswerText extends StatelessWidget {
  const AnswerText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  static final _bullet = RegExp(r'^\s*[-*]\s+(.*)$');
  static final _numbered = RegExp(r'^\s*(\d+)[.)]\s+(.*)$');

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final blocks = <Widget>[];
    final paragraph = <String>[];

    void flush() {
      if (paragraph.isEmpty) return;
      blocks.add(Text.rich(TextSpan(children: spans(paragraph.join('\n'), base))));
      paragraph.clear();
    }

    for (final line in text.split('\n')) {
      final bullet = _bullet.firstMatch(line);
      final numbered = bullet == null ? _numbered.firstMatch(line) : null;
      if (bullet != null || numbered != null) {
        flush();
        blocks.add(
          _ListItem(
            marker: bullet != null ? '•' : '${numbered!.group(1)}.',
            text: bullet != null ? bullet.group(1)! : numbered!.group(2)!,
            style: base,
          ),
        );
      } else if (line.trim().isEmpty) {
        flush();
      } else {
        paragraph.add(line);
      }
    }
    flush();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
            child: blocks[i],
          ),
      ],
    );
  }

  /// [text] with `**bold**` runs in bold. An unclosed `**` stays literal.
  static List<InlineSpan> spans(String text, TextStyle base) {
    final out = <InlineSpan>[];
    var rest = text;
    while (true) {
      final open = rest.indexOf('**');
      final close = open < 0 ? -1 : rest.indexOf('**', open + 2);
      if (open < 0 || close < 0) {
        if (rest.isNotEmpty) out.add(TextSpan(text: rest, style: base));
        return out;
      }
      if (open > 0) out.add(TextSpan(text: rest.substring(0, open), style: base));
      out.add(
        TextSpan(
          text: rest.substring(open + 2, close),
          style: base.copyWith(fontWeight: FontWeight.w700),
        ),
      );
      rest = rest.substring(close + 2);
    }
  }
}

class _ListItem extends StatelessWidget {
  const _ListItem({
    required this.marker,
    required this.text,
    required this.style,
  });

  final String marker;
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 20, child: Text(marker, style: style)),
        Expanded(
          child: Text.rich(TextSpan(children: AnswerText.spans(text, style))),
        ),
      ],
    );
  }
}
