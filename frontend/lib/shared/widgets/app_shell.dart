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
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  /// Current route path: picks the tab title and the active nav item.
  final String location;
  final Widget child;

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
    final wide = MediaQuery.sizeOf(context).width >= SiteHeader.navBreakpoint;

    return Title(
      title: _title,
      color: context.palette.primary,
      child: Scaffold(
        endDrawer: wide ? null : SiteNavDrawer(location: location),
        body: Column(
          children: [
            const SafeArea(bottom: false, child: SiteHeader()),
            Expanded(
              // The header and footer handle the safe-area insets.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                removeBottom: true,
                child: child,
              ),
            ),
            const SafeArea(top: false, child: SiteFooter()),
          ],
        ),
      ),
    );
  }
}
