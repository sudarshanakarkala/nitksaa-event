import 'package:event_app/shared/widgets/page_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Insets for an area [areaWidth] wide in a window [windowWidth] wide.
Future<EdgeInsets> _insets(WidgetTester tester, double windowWidth, double areaWidth) async {
  late EdgeInsets insets;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: Size(windowWidth, 900)),
      child: Builder(
        builder: (context) {
          insets = PageInsets.horizontal(context, areaWidth);
          return const SizedBox();
        },
      ),
    ),
  );
  return insets;
}

void main() {
  testWidgets('content starts under the logo when NITiKa narrows the page', (tester) async {
    // 1920 window: the header's content starts at (1920 - 1520) / 2 + 40.
    final full = await _insets(tester, 1920, 1920);
    final narrowed = await _insets(tester, 1920, 1600); // NITiKa keeps 320
    expect(full.left, 240);
    expect(narrowed.left, 240);
    // The content never runs past the header's right edge either.
    expect(full.right, 240);
    expect(narrowed.right, 40);
  });

  testWidgets('narrower than the header: plain side padding', (tester) async {
    final laptop = await _insets(tester, 1366, 1338);
    expect(laptop.left, 40);
    expect(laptop.right, 40);
    final phone = await _insets(tester, 390, 390);
    expect(phone.left, 16);
    expect(phone.right, 16);
  });
}
