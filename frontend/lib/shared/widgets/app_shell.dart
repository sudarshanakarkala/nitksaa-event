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
/// [assistant] is the right-rail slot (website: NITiKa). The header's chat
/// button opens it. From [assistantRailFrom] it is a 320px rail that
/// collapses to a 28px strip, and starts collapsed, as on the website; below
/// that the button opens it as a slide-in panel (tablets) or a full-height
/// sheet (phones).
class AppShell extends StatefulWidget {
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

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// The rail's state; kept across pages, like the website's.
  bool _railOpen = false;

  // Browser tab title per page. Set on every navigation, so leaving a page
  // always puts the right title back.
  static const _appTitle = 'NITKSAA Events';
  static final _pageTitles = <String, String>{
    AppRoutes.myEvents: 'My Events',
    AppRoutes.manageEvents: 'Manage Events',
    AppRoutes.feedback: 'Feedback',
    AppRoutes.privacy: Policy.privacy.title,
    AppRoutes.terms: Policy.terms.title,
    AppRoutes.refund: Policy.refund.title,
    AppRoutes.disclaimer: Policy.disclaimer.title,
  };

  String get _title {
    final location = widget.location;
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
    final assistant = widget.assistant;
    final assistantRail =
        assistant != null && width >= AppShell.assistantRailFrom;

    return Title(
      title: _title,
      color: context.palette.primary,
      child: Scaffold(
        endDrawer: wide ? null : SiteNavDrawer(location: widget.location),
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: SiteHeader(
                onAssistant: assistant == null
                    ? null
                    : assistantRail
                    ? _toggleRail
                    : () => _openAssistant(context, width, assistant),
                assistantOpen: assistantRail && _railOpen,
              ),
            ),
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
                          Expanded(child: widget.child),
                          _AssistantRail(
                            open: _railOpen,
                            onToggle: _toggleRail,
                            child: assistant,
                          ),
                        ],
                      )
                    : widget.child,
              ),
            ),
            const SafeArea(top: false, child: SiteFooter()),
          ],
        ),
      ),
    );
  }

  void _toggleRail() => setState(() => _railOpen = !_railOpen);

  void _openAssistant(BuildContext context, double width, Widget assistant) {
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
      barrierLabel: 'Close NITiKa',
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
class _AssistantRail extends StatelessWidget {
  const _AssistantRail({
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: open ? 320 : 28,
      decoration: BoxDecoration(
        color: p.card,
        border: Border(left: BorderSide(color: p.border)),
      ),
      clipBehavior: Clip.hardEdge,
      child: open
          ? OverflowBox(
              alignment: Alignment.topRight,
              minWidth: 320,
              maxWidth: 320,
              child: Stack(
                children: [
                  Positioned.fill(child: child),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      tooltip: 'Collapse NITiKa',
                      iconSize: 18,
                      color: p.textMuted,
                      icon: const Icon(Icons.chevron_right),
                      onPressed: onToggle,
                    ),
                  ),
                ],
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: IconButton(
                tooltip: 'Open NITiKa',
                iconSize: 16,
                padding: const EdgeInsets.only(top: 12),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: p.textMuted,
                icon: const Icon(Icons.chevron_left),
                onPressed: onToggle,
              ),
            ),
    );
  }
}
