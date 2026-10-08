import 'package:flutter/material.dart';

import 'page_header.dart';
import 'site_footer.dart';
import 'site_header.dart';

/// Website-style page: header, page heading, content, footer.
///
/// Used by the new pages (policies, feedback). Existing screens keep their
/// own scaffolds until a shared shell route exists.
class SitePage extends StatelessWidget {
  const SitePage({
    super.key,
    required this.title,
    required this.child,
    this.eyebrow,
    this.subtitle,
    this.maxContentWidth = 760,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget child;

  /// Reading width for the page body. The header and footer use the
  /// website's full container width.
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final side = compact ? 16.0 : 40.0;

    return Scaffold(
      body: Column(
        children: [
          // The floating theme toggle in main.dart is still active, so the
          // header's own toggle stays hidden for now.
          const SafeArea(bottom: false, child: SiteHeader(showThemeToggle: false)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    // Keeps the footer at the bottom on short pages.
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxContentWidth + side * 2),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(side, compact ? 24 : 40, side, 72),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                PageHeader(
                                  title: title,
                                  eyebrow: eyebrow,
                                  subtitle: subtitle,
                                ),
                                SizedBox(height: compact ? 24 : 32),
                                child,
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SiteFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
