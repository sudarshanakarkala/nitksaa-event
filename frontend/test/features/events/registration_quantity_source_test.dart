// Guard for ISSUE-006: nothing on the attendee's path from the event page to
// payment mentions a pass count or a quantity, so there is nothing to
// multiply a price by. It reads the source files, so it runs on the VM only.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The files an attendee's registration and payment pass through.
///
/// The admin event form (`manage_events_screen.dart`) and the event model's
/// `registrationMinQuantity` / `registrationMaxQuantity` are left out: they
/// are admin-only settings that the backend does not store (ISSUE-015).
const _attendeeFlow = [
  'lib/features/events/presentation/screens/event_detail_screen.dart',
  'lib/features/events/presentation/screens/checkout_screen.dart',
  'lib/features/events/presentation/providers/event_detail_provider.dart',
  'lib/features/events/data/events_repository.dart',
  'lib/routes/app_router.dart',
  'lib/routes/app_routes.dart',
];

final _quantityWording = RegExp(
  r'quantity|passcount|no of passes|number of passes|per pass|grandtotal',
  caseSensitive: false,
);

void main() {
  for (final path in _attendeeFlow) {
    test('Test E: $path has no pass count or quantity', () {
      final source = File(path).readAsStringSync();
      final found = _quantityWording.allMatches(source).map((m) => m.group(0));
      expect(found, isEmpty);
    });
  }
}
