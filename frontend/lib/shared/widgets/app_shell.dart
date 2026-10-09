import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../routes/app_routes.dart';
import 'app_bottom_nav.dart';
import 'app_sidebar.dart';
import 'site_footer.dart';
import 'site_header.dart';

/// One app shell for every attendee page, like the website's AppLayout
/// (website: components/core/AppLayout.jsx).
///
/// Header on top; sidebar (≥ 900px) or bottom nav (< 900px); footer at the
/// end of the page content. Screens render only their own body.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  /// Current route path, used to pick the active bottom-nav tab.
  final String location;
  final Widget child;

  static const double menuBreakpoint = 900;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Screens own their scroll views, so the footer is revealed when the
  // page's vertical scroll reaches its end (or the page doesn't scroll).
  bool _footerVisible = true;

  // Hysteresis: showing the footer shrinks the viewport by its height,
  // so hide only once the user is clearly away from the end.
  static const double _showWithin = 1;
  static const double _hideBeyond = 200;

  bool _onMetrics(ScrollMetrics m, BuildContext? source) {
    if (m.axis != Axis.vertical) return false;
    // Ignore the outgoing page while a route transition runs.
    if (source != null && !(ModalRoute.of(source)?.isCurrent ?? true)) {
      return false;
    }
    final after = m.extentAfter;
    final visible =
        _footerVisible ? after <= _hideBeyond : after <= _showWithin;
    if (visible != _footerVisible) {
      void apply() {
        if (mounted) setState(() => _footerVisible = visible);
      }

      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        SchedulerBinding.instance.addPostFrameCallback((_) => apply());
      } else {
        apply();
      }
    }
    return false;
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // New page: show the footer until its scroll view reports otherwise.
    if (oldWidget.location != widget.location) _footerVisible = true;
  }

  int get _navIndex {
    final path = widget.location;
    if (path.startsWith(AppRoutes.myEvents)) return 1;
    if (path.startsWith(AppRoutes.manageEvents) || path.startsWith('/admin/')) {
      return 2;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppShell.menuBreakpoint;

    final content = NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onMetrics(n.metrics, n.context),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onMetrics(n.metrics, n.context),
        // The header already handles the top inset.
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: widget.child,
        ),
      ),
    );

    return Scaffold(
      body: Column(
        children: [
          const SafeArea(bottom: false, child: SiteHeader()),
          Expanded(
            child: Row(
              children: [
                if (wide) const AppSidebar(),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: content),
                      if (_footerVisible) const SiteFooter(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide ? null : AppBottomNav(currentIndex: _navIndex),
    );
  }
}
