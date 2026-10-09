import 'package:flutter/material.dart';

import '../../features/policies/policy_screen.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_palette.dart';
import 'site_footer.dart';
import 'site_header.dart';

/// One app shell for every attendee page, like the website's AppLayout
/// (website: components/core/AppLayout.jsx).
///
/// Sticky header (with the nav links, or a menu button on narrow screens)
/// and sticky footer; the page content scrolls between them. Screens render
/// only their own body.
///
/// [assistant] is the right-rail slot (website: NITiKa). Empty for now.
/// From [assistantRailFrom] it is a collapsible 320px rail; below that a
/// floating chat button opens it (slide-in panel on tablets, full-height
/// sheet on phones).
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.location,
    required this.child,
    this.assistant,
  });

  /// Current route path: picks the tab title and the active nav item.
  final String location;
  final Widget child;
  final Widget? assistant;

  static const double assistantRailFrom = 1200;

  // Browser tab title per page. Set on every navigation, so leaving a page
  // always puts the right title back.
  static const _appTitle = 'NITKSAA Events';
  static final _pageTitles = {
    AppRoutes.myEvents: 'My Events',
    AppRoutes.manageEvents: 'Manage Events',
    AppRoutes.feedback: 'Feedback',
    AppRoutes.privacy: Policy.privacy.title,
    AppRoutes.terms: Policy.terms.title,
    AppRoutes.refund: Policy.refund.title,
    AppRoutes.disclaimer: Policy.disclaimer.title,
  };

  String get _title {
    var page = _pageTitles[location];
    if (page == null) {
      if (location.endsWith('/checkout')) {
        page = 'Checkout';
      } else if (location.endsWith('/registrations')) {
        page = 'Registrations';
      } else if (location.startsWith('/events/')) {
        page = 'Event';
      }
    }
    return page == null ? _appTitle : '$_appTitle · $page';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= SiteHeader.navBreakpoint;
    final assistantRail = assistant != null && width >= assistantRailFrom;

    return Title(
      title: _title,
      color: context.palette.primary,
      child: Scaffold(
        endDrawer: wide ? null : SiteNavDrawer(location: location),
        floatingActionButton: assistant != null && !assistantRail
            ? FloatingActionButton(
                tooltip: 'Assistant',
                onPressed: () => _openAssistant(context, width),
                child: const Icon(Icons.chat_bubble_outline),
              )
            : null,
        body: Column(
          children: [
            const SafeArea(bottom: false, child: SiteHeader()),
            Expanded(
              // The header and footer handle the safe-area insets.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                removeBottom: true,
                child: assistantRail
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: child),
                          _AssistantRail(child: assistant!),
                        ],
                      )
                    : child,
              ),
            ),
            const SafeArea(top: false, child: SiteFooter()),
          ],
        ),
      ),
    );
  }
}

extension on AppShell {
  void _openAssistant(BuildContext context, double width) {
    final p = context.palette;
    if (width < 600) {
      // Phones: full-height sheet, room for the conversation and keyboard.
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SizedBox(
          height: MediaQuery.sizeOf(context).height,
          child: assistant,
        ),
      );
      return;
    }
    // Tablets: panel sliding in from the right.
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close assistant',
      barrierColor: p.overlay,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: p.surface,
          child: SizedBox(width: 360, height: double.infinity, child: assistant),
        ),
      ),
      transitionBuilder: (_, animation, _, panel) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic))
            .animate(animation),
        child: panel,
      ),
    );
  }
}

/// Website right rail: 320px, collapsible to a 28px strip.
class _AssistantRail extends StatefulWidget {
  const _AssistantRail({required this.child});

  final Widget child;

  @override
  State<_AssistantRail> createState() => _AssistantRailState();
}

class _AssistantRailState extends State<_AssistantRail> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: _open ? 320 : 28,
      decoration: BoxDecoration(
        color: p.card,
        border: Border(left: BorderSide(color: p.border)),
      ),
      clipBehavior: Clip.hardEdge,
      child: _open
          ? OverflowBox(
              alignment: Alignment.topRight,
              minWidth: 320,
              maxWidth: 320,
              child: Stack(
                children: [
                  Positioned.fill(child: widget.child),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      tooltip: 'Hide assistant',
                      iconSize: 18,
                      color: p.textMuted,
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => setState(() => _open = false),
                    ),
                  ),
                ],
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: IconButton(
                tooltip: 'Show assistant',
                iconSize: 16,
                padding: const EdgeInsets.only(top: 12),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: p.textMuted,
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _open = true),
              ),
            ),
    );
  }
}
