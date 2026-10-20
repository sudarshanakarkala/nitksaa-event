/// Phones: list pages give the screen to the list (`UI_PATTERNS.md`).
///
/// The top of a list page (Admin title and tabs, search and filters) stays
/// put. The site footer folds away while you scroll down a list and comes
/// back when you scroll up, reach the top or reach the end. The footer sits
/// below the list, so folding it never moves the cards. Only on phones
/// ([PhoneChrome.phoneBelow]) and short windows ([PhoneChrome.shortBelow]),
/// and only for lists long enough to need it.
///
/// [ListPage] decides from its body's scrolling and tells [AppShell] with a
/// [PhoneChromeNotification]. A list page that opts out (Check-in) sends
/// nothing, so the footer stays.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

abstract final class PhoneChrome {
  /// Below this width the footer folds away.
  static const double phoneBelow = 600;

  static bool isPhone(BuildContext context) => MediaQuery.sizeOf(context).width < phoneBelow;

  /// Below this height (a laptop's short browser window) list pages behave
  /// as on phones: the footer folds away and the top of the page is compact.
  static const double shortBelow = 800;

  static bool isShort(BuildContext context) => MediaQuery.sizeOf(context).height < shortBelow;

  /// Whether list pages fold the footer away: phones and short windows.
  static bool foldsFooter(BuildContext context) => isPhone(context) || isShort(context);

  /// Runs [fn] now, or after this frame when called during build or layout
  /// (scroll metrics can change mid-frame).
  static void safely(VoidCallback fn) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks || phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => fn());
    } else {
      fn();
    }
  }
}

/// From a list page to the app shell: hide or show the footer.
class PhoneChromeNotification extends Notification {
  const PhoneChromeNotification({required this.footerHidden});

  final bool footerHidden;
}

/// Turns a list's scrolling into hiding or showing the footer. Pure, so it
/// can be tested.
class PhoneChromeTracker {
  bool footerHidden = false;
  double _travel = 0;

  /// Lists that scroll less than this keep the footer.
  static const double minScrollExtent = 400;

  /// How far to scroll one way before the footer follows.
  static const double threshold = 24;

  /// Edges count from this close.
  static const double _edge = 4;

  /// A vertical scroll [metrics] moved by [delta] (positive = down the
  /// list). Returns whether the footer changed.
  bool onScroll(ScrollMetrics metrics, double delta) {
    if (metrics.axis != Axis.vertical) return false;
    final atTop = metrics.pixels <= metrics.minScrollExtent + _edge;
    final atEnd = metrics.pixels >= metrics.maxScrollExtent - _edge;
    if (atTop || atEnd) return showAll();
    if (delta == 0) return false;
    // Keep going one way; turning round starts the count again.
    if ((delta > 0) != (_travel > 0)) _travel = 0;
    _travel += delta;
    var hidden = footerHidden;
    final longEnough = metrics.maxScrollExtent >= minScrollExtent;
    if (_travel > threshold && longEnough) {
      hidden = true;
    } else if (_travel < -threshold) {
      hidden = false;
    }
    return _set(hidden);
  }

  /// The list's size changed (filters, loading). A list that can no
  /// longer scroll, or is back at the top, shows the footer again. Returns
  /// whether the footer changed.
  bool onMetrics(ScrollMetrics metrics) {
    if (metrics.axis != Axis.vertical) return false;
    if (metrics.maxScrollExtent <= _edge || metrics.pixels <= metrics.minScrollExtent + _edge) {
      return showAll();
    }
    return false;
  }

  /// Shows the footer. Returns whether it changed.
  bool showAll() {
    _travel = 0;
    return _set(false);
  }

  bool _set(bool hidden) {
    if (hidden == footerHidden) return false;
    footerHidden = hidden;
    return true;
  }
}

/// The footer folded away (animated) while [hidden], sliding down. Hidden,
/// it takes no space and can't be tapped.
class CollapsibleChrome extends StatelessWidget {
  const CollapsibleChrome({
    super.key,
    required this.hidden,
    required this.child,
  });

  final bool hidden;
  final Widget child;

  static const duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        duration: duration,
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        heightFactor: hidden ? 0 : 1,
        child: IgnorePointer(ignoring: hidden, child: child),
      ),
    );
  }
}
