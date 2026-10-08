import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../site_links.dart';

/// Footer strip matching the association website
/// (website: components/core/Footer.jsx, styles/footer.css).
///
/// © line on the left, policy links on the right; wraps on phones.
class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key});

  static const double maxContentWidth = 1520;

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

    final links = Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: compact ? WrapAlignment.start : WrapAlignment.end,
      children: _withSeparators(context, [
        _FooterLink('Privacy & Cookies', route: SiteLinks.privacy),
        _FooterLink('Terms of Use', route: SiteLinks.terms),
        _FooterLink('Refund Policy', route: SiteLinks.refund),
        _FooterLink('Disclaimer', route: SiteLinks.disclaimer),
        _FooterLink('Feedback', route: SiteLinks.feedback),
        _FooterLink('About Us', url: SiteLinks.websiteAbout),
        _FooterLink('NITKSAA website', url: SiteLinks.website),
      ]),
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: p.background.withValues(alpha: 0.96),
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 40,
              vertical: compact ? 14 : 16,
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [links, const SizedBox(height: 10), copy],
                  )
                : Row(
                    children: [
                      copy,
                      const SizedBox(width: 16),
                      Expanded(child: links),
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
