import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'site_header.dart';

/// Lines page content up with the site header: the content's left edge is
/// always under the NITKSAA logo, whatever else takes room on the right
/// (e.g. NITiKa's rail).
///
/// The header centres a [SiteHeader.maxContentWidth] box in the *window*
/// with 40px side padding (16px on phones). A page area that starts at the
/// window's left edge but is narrower (NITiKa on its right) would centre
/// differently, so these insets are computed from the window, not the area.
abstract class PageInsets {
  static double side(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600 ? 16 : 40;

  /// Left edge of the header's content (the logo), from the window's left.
  static double contentLeft(BuildContext context) {
    final window = MediaQuery.sizeOf(context).width;
    return side(context) +
        math.max(0.0, (window - SiteHeader.maxContentWidth) / 2);
  }

  /// Width of the header's content box.
  static double contentWidth(BuildContext context) {
    final window = MediaQuery.sizeOf(context).width;
    return math.min(window, SiteHeader.maxContentWidth) - 2 * side(context);
  }

  /// Horizontal insets for an area [areaWidth] wide that starts at the
  /// window's left edge.
  ///
  /// [minLeft] keeps the content clear of something on the left (the
  /// Filters rail): content starts under the logo, or just right of that,
  /// whichever is further right.
  static EdgeInsets horizontal(BuildContext context, double areaWidth, {double minLeft = 0}) {
    final logo = contentLeft(context);
    final left = math.max(logo, minLeft);
    final right = math.max(side(context), areaWidth - logo - contentWidth(context));
    return EdgeInsets.only(left: left, right: right);
  }
}

/// [child] in the header's content column (see [PageInsets]).
class PageContainer extends StatelessWidget {
  const PageContainer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: PageInsets.horizontal(context, constraints.maxWidth),
        child: child,
      ),
    );
  }
}
