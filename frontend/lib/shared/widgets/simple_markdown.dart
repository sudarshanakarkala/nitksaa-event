import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Small markdown renderer for the policy pages, styled like the website's
/// `.prose` class (global.css).
///
/// Supports what the policy files use: `#`/`##`/`###` headings, paragraphs,
/// `-`/`*` bullet lists, `---` rules, hard line breaks (two trailing spaces),
/// `**bold**`, `*italic*`, `[links](url)`. HTML comments are skipped.
/// Deliberately no package dependency.
class SimpleMarkdown extends StatefulWidget {
  const SimpleMarkdown(this.data, {super.key});

  final String data;

  @override
  State<SimpleMarkdown> createState() => _SimpleMarkdownState();
}

sealed class _Block {}

class _Heading extends _Block {
  _Heading(this.level, this.text);
  final int level;
  final String text;
}

class _Paragraph extends _Block {
  _Paragraph(this.text);
  final String text;
}

class _Bullets extends _Block {
  _Bullets(this.items);
  final List<String> items;
}

class _Rule extends _Block {}

class _SimpleMarkdownState extends State<SimpleMarkdown> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  static List<_Block> _parse(String source) {
    final withoutComments =
        source.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '').replaceAll('\r\n', '\n');
    final lines = withoutComments.split('\n');
    final blocks = <_Block>[];
    var i = 0;

    bool isBullet(String l) => RegExp(r'^\s*[-*] ').hasMatch(l);
    bool isHeading(String l) => RegExp(r'^#{1,6} ').hasMatch(l);
    bool isRule(String l) => RegExp(r'^\s*(-{3,}|\*{3,})\s*$').hasMatch(l);

    while (i < lines.length) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        i++;
        continue;
      }
      if (isRule(line)) {
        blocks.add(_Rule());
        i++;
        continue;
      }
      if (isHeading(line)) {
        final hashes = line.indexOf(' ');
        // `#` and `##` both render as section headings, like the website.
        final level = hashes <= 2 ? 2 : 3;
        blocks.add(_Heading(level, line.substring(hashes + 1).trim()));
        i++;
        continue;
      }
      if (isBullet(line)) {
        final items = <String>[];
        while (i < lines.length && isBullet(lines[i])) {
          items.add(lines[i].replaceFirst(RegExp(r'^\s*[-*] '), '').trim());
          i++;
        }
        blocks.add(_Bullets(items));
        continue;
      }
      final buffer = StringBuffer();
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !isHeading(lines[i]) &&
          !isBullet(lines[i]) &&
          !isRule(lines[i])) {
        final l = lines[i];
        final hardBreak = l.endsWith('  ');
        buffer.write(l.trim());
        buffer.write(hardBreak ? '\n' : ' ');
        i++;
      }
      blocks.add(_Paragraph(buffer.toString().trimRight()));
    }
    return blocks;
  }

  /// Inline: **bold**, *italic*, [text](url).
  List<InlineSpan> _inline(String text, TextStyle base, AppPalette p) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|\[([^\]]+)\]\(([^)]+)\)');
    var last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      if (m.group(1) != null) {
        spans.add(TextSpan(
          text: m.group(1),
          style: TextStyle(fontWeight: FontWeight.w600, color: p.textPrimary),
        ));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(
          text: m.group(2),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else {
        final url = m.group(4)!;
        final recognizer = TapGestureRecognizer()
          ..onTap = () => launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
        _recognizers.add(recognizer);
        spans.add(TextSpan(
          text: m.group(3),
          style: TextStyle(
            color: p.primary,
            decoration: TextDecoration.underline,
            decorationColor: p.primary,
          ),
          recognizer: recognizer,
        ));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final body = AppTextStyles.bodyMedium.copyWith(
      fontSize: 14,
      height: 1.75,
      color: p.textSecondary,
    );
    final h2 = AppTextStyles.bodyMedium.copyWith(
      fontSize: 15.2,
      fontWeight: FontWeight.w500,
      color: p.textPrimary,
      height: 1.4,
    );
    final h3 = AppTextStyles.bodyMedium.copyWith(
      fontSize: 13.1,
      fontWeight: FontWeight.w600,
      color: p.textSecondary,
      letterSpacing: 0.65,
      height: 1.4,
    );

    final blocks = _parse(widget.data);
    final children = <Widget>[];

    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final first = i == 0;
      switch (b) {
        case _Heading(:final level, :final text):
          children.add(Padding(
            padding: EdgeInsets.only(
              top: first ? 0 : (level == 2 ? 32 : 20),
              bottom: level == 2 ? 10 : 6,
            ),
            child: Text(
              level == 2 ? text : text.toUpperCase(),
              style: level == 2 ? h2 : h3,
            ),
          ));
        case _Paragraph(:final text):
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text.rich(TextSpan(style: body, children: _inline(text, body, p))),
          ));
        case _Bullets(:final items):
          children.add(Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 10, left: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 16, child: Text('•', style: body)),
                        Expanded(
                          child: Text.rich(
                            TextSpan(style: body, children: _inline(item, body, p)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ));
        case _Rule():
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Divider(color: p.border, height: 1),
          ));
      }
    }

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
