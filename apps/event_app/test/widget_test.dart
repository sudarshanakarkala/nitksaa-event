import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:event_app/features/foundation/presentation/foundation_ready_screen.dart';

void main() {
  testWidgets('Foundation screen renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: FoundationReadyScreen(),
        ),
      ),
    );
    expect(find.text('NITKSAA Event App Foundation Ready'), findsOneWidget);
  });
}
