import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'registration_backend_fake.dart';

/// The event card keeps Unregister (and a QR badge beside Join meeting) in
/// its ⋯ menu. These helpers reach it.

final Finder _moreActions = find.byTooltip('More actions');
final Finder _unregisterItem = find.widgetWithText(PopupMenuItem<int>, 'Unregister');

/// Opens the card's ⋯ menu.
Future<void> openCardMenu(WidgetTester tester) async {
  await tester.tap(_moreActions);
  await settleRequests(tester);
}

/// Closes an open menu without choosing anything (taps the barrier).
Future<void> closeCardMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(2, 2));
  await settleRequests(tester);
}

/// Presses Unregister in the card's ⋯ menu (the confirm dialog opens next).
Future<void> tapCardUnregister(WidgetTester tester) async {
  await openCardMenu(tester);
  await tester.tap(_unregisterItem);
  await settleRequests(tester);
}

/// Whether the card offers Unregister: true (enabled), false (disabled), or
/// null (not offered). Leaves the menu closed.
Future<bool?> cardUnregisterEnabled(WidgetTester tester) async {
  if (_moreActions.evaluate().isEmpty) return null;
  await openCardMenu(tester);
  final bool? enabled = _unregisterItem.evaluate().isEmpty
      ? null
      : tester.widget<PopupMenuItem<int>>(_unregisterItem).enabled;
  await closeCardMenu(tester);
  return enabled;
}
