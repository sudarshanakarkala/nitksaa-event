/// Phones: list pages give the screen to the list (`UI_PATTERNS.md`).
///
/// Scrolling down a list hides what sits above it (the Admin title and
/// tabs, the search and filter rows) and the site footer; scrolling up, or
/// reaching the top, brings them back; the footer also comes back at the
/// end of the list. Only on phones ([PhoneChrome.phoneBelow]), only for
/// lists long enough to need it, and never while the keyboard is open.
///
/// [ListPage] decides from its body's scrolling and tells the page around
/// it with a [PhoneChromeNotification]; [AppShell] (footer) and the Admin
/// screen (title and tabs) listen and fold away with [CollapsibleChrome].
/// A list page that opts out (Check-in) sends nothing, so nothing moves.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

abstract final class PhoneChrome {
  /// Below this width the chrome folds away.
  static const double phoneBelow = 600;

  static bool isPhone(BuildContext context) => MediaQuery.sizeOf(context).width < phoneBelow;

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

/// From a list page to the page around it: hide or show the header above
/// and the footer below.
class PhoneChromeNotification extends Notification {
  const PhoneChromeNotification({required this.headerHidden, required this.footerHidden});

  final bool headerHidden;
  final bool footerHidden;
}

/// Turns a list's scrolling into hide / show. Pure, so it can be tested.
class PhoneChromeTracker {
  bool headerHidden = false;
  bool footerHidden = false;
  double _travel = 0;

  /// Lists that scroll less than this keep everything in place (folding
  /// the chrome away could leave too little to scroll).
  static const double minScrollExtent = 400;

  /// How far to scroll one way before the chrome follows.
  static const double threshold = 24;

  /// Edges count from this close.
  static const double _edge = 4;

  /// A vertical scroll [metrics] moved by [delta] (positive = down the
  /// list). Returns whether anything changed.
  bool onScroll(ScrollMetrics metrics, double delta, {bool keyboardOpen = false}) {
    if (metrics.axis != Axis.vertical) return false;
    final atTop = metrics.pixels <= metrics.minScrollExtent + _edge;
    final atEnd = metrics.pixels >= metrics.maxScrollExtent - _edge;
    if (atTop) {
      _travel = 0;
      return _set(header: false, footer: false);
    }
    if (delta == 0) return false;
    // Keep going one way; turning round starts the count again.
    if ((delta > 0) != (_travel > 0)) _travel = 0;
    _travel += delta;
    var header = headerHidden;
    var footer = footerHidden;
    // Only a long list folds the chrome away. Once folded, the list is
    // shorter by the chrome's height, so this isn't asked again until it
    // comes back (no flicker near the limit).
    final canHide = headerHidden || metrics.maxScrollExtent >= minScrollExtent;
    if (_travel > threshold && !keyboardOpen && canHide) {
      header = true;
      footer = true;
    } else if (_travel < -threshold) {
      header = false;
      footer = false;
    }
    if (atEnd) footer = false;
    return _set(header: header, footer: footer);
  }

  /// The list's size changed (filters, loading). A list that can no
  /// longer scroll, or is back at the top, shows everything again (else it
  /// could never be scrolled back). Returns whether anything changed.
  bool onMetrics(ScrollMetrics metrics) {
    if (metrics.axis != Axis.vertical) return false;
    if (metrics.maxScrollExtent <= _edge || metrics.pixels <= metrics.minScrollExtent + _edge) {
      return showAll();
    }
    return false;
  }

  /// Shows everything. Returns whether anything changed.
  bool showAll() {
    _travel = 0;
    return _set(header: false, footer: false);
  }

  bool _set({required bool header, required bool footer}) {
    if (header == headerHidden && footer == footerHidden) return false;
    headerHidden = header;
    footerHidden = footer;
    return true;
  }
}

/// [child] folded away (animated) while [hidden]: a header slides up, a
/// footer ([fromTop] false) slides down. Hidden, it takes no space and
/// can't be tapped.
class CollapsibleChrome extends StatelessWidget {
  const CollapsibleChrome({
    super.key,
    required this.hidden,
    required this.child,
    this.fromTop = true,
  });

  final bool hidden;
  final bool fromTop;
  final Widget child;

  static const duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        duration: duration,
        curve: Curves.easeOut,
        alignment: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
        heightFactor: hidden ? 0 : 1,
        child: IgnorePointer(ignoring: hidden, child: child),
      ),
    );
  }
}
