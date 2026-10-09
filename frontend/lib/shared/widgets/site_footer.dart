import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../site_links.dart';

/// Footer strip matching the association website
/// (website: components/core/Footer.jsx, styles/footer.css).
///
/// One 52px row, like the website: © line on the left, links on the right.
/// On narrow screens the links scroll sideways, with the © line last.
class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key});

  static const double maxContentWidth = 1520;
  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final compact = MediaQuery.sizeOf(context).width < 700;
    final year = DateTime.now().year;

    final copy = Text(
      '© $year NITK Surathkal Alumni Association',
      style: AppTextStyles.labelSmall.copyWith(
        color: p.textMuted,
        fontWeight: FontWeight.w400,
      ),
    );

    final linkItems = _withSeparators(context, [
        _FooterLink('Privacy & Cookies', route: SiteLinks.privacy),
        _FooterLink('Terms of Use', route: SiteLinks.terms),
        _FooterLink('Refund Policy', route: SiteLinks.refund),
        _FooterLink('Disclaimer', route: SiteLinks.disclaimer),
        _FooterLink('Feedback', route: SiteLinks.feedback),
        _FooterLink('About Us', url: SiteLinks.websiteAbout),
        _FooterLink('NITKSAA website', url: SiteLinks.website),
      ]);

    Widget row(List<Widget> children) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              children[i],
            ],
          ],
        );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        // Website --bg-nav: background at 92% (dark) / 95% (light).
        color: p.background.withValues(alpha: isDark ? 0.92 : 0.95),
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 40),
            child: compact
                // Fade at the right edge shows the row scrolls sideways;
                // the end padding lets the last item clear the fade.
                ? ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Colors.white, Colors.white, Colors.transparent],
                      stops: [0, 0.85, 1],
                    ).createShader(bounds),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(right: 48),
                      child: row([...linkItems, copy]),
                    ),
                  )
                : Row(
                    children: [
                      copy,
                      const SizedBox(width: 16),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            reverse: true,
                            child: row(linkItems),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  List<Widget> _withSeparators(BuildContext context, List<Widget> items) {
    final sepStyle = AppTextStyles.labelSmall.copyWith(
      color: context.palette.textMuted.withValues(alpha: 0.5),
    );
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        out.add(ExcludeSemantics(child: Text('·', style: sepStyle)));
      }
      out.add(items[i]);
    }
    return out;
  }
}

class _FooterLink extends StatefulWidget {
  const _FooterLink(this.label, {this.route, this.url});

  final String label;
  final String? route;
  final String? url;

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hover = false;

  Future<void> _open() async {
    if (widget.route != null) {
      context.go(widget.route!);
    } else if (widget.url != null) {
      await launchUrl(Uri.parse(widget.url!), webOnlyWindowName: '_blank');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final external = widget.url != null;
    return Semantics(
      link: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: _open,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: AppTextStyles.labelSmall.copyWith(
                  fontWeight: FontWeight.w400,
                  color: _hover ? p.primary : p.textSecondary,
                ),
              ),
              if (external) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.north_east,
                  size: 10,
                  color: _hover ? p.primary : p.textSecondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
