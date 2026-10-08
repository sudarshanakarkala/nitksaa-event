import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../shared/widgets/simple_markdown.dart';
import '../../shared/widgets/site_page.dart';
import '../../theme/app_palette.dart';

/// The policy pages. Texts live in assets/policies/ (copied from the
/// association website, plus the interim refund policy).
enum Policy {
  privacy(
    title: 'Privacy & Cookie Policy',
    subtitle: 'How we collect, use, and protect your information.',
    asset: 'assets/policies/Privacy_and_Cookie_Policy.md',
  ),
  terms(
    title: 'Terms of Use',
    subtitle: 'The rules and conditions governing use of this platform.',
    asset: 'assets/policies/Terms_of_Use.md',
  ),
  refund(
    title: 'Refund & Cancellation Policy',
    subtitle: 'How cancellations and refunds work for paid events.',
    asset: 'assets/policies/Refund_and_Cancellation_Policy.md',
  ),
  disclaimer(
    title: 'Website Disclaimer',
    subtitle: null,
    asset: 'assets/policies/Website_Disclaimer.md',
  );

  const Policy({required this.title, required this.subtitle, required this.asset});

  final String title;
  final String? subtitle;
  final String asset;
}

class PolicyScreen extends StatefulWidget {
  const PolicyScreen({super.key, required this.policy});

  final Policy policy;

  @override
  State<PolicyScreen> createState() => _PolicyScreenState();
}

class _PolicyScreenState extends State<PolicyScreen> {
  late Future<String> _text;

  @override
  void initState() {
    super.initState();
    _text = rootBundle.loadString(widget.policy.asset);
  }

  @override
  void didUpdateWidget(PolicyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.policy != widget.policy) {
      _text = rootBundle.loadString(widget.policy.asset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Title(
      title: 'NITKSAA Events · ${widget.policy.title}',
      color: p.primary,
      child: SitePage(
        title: widget.policy.title,
        subtitle: widget.policy.subtitle,
        child: FutureBuilder<String>(
          future: _text,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                'This page could not be loaded. Please try again later.',
                style: TextStyle(color: p.error),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return SimpleMarkdown(snapshot.data!);
          },
        ),
      ),
    );
  }
}
