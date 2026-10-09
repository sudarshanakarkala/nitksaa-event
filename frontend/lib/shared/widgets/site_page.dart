import 'package:flutter/material.dart';

import 'page_header.dart';

/// Website-style page body: page heading and content.
///
/// Used by the policy and feedback pages. The header, menu and footer come
/// from the app shell (shared/widgets/app_shell.dart).
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

  /// Reading width for the page body.
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final side = compact ? 16.0 : 40.0;

    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
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
      ),
    );
  }
}
