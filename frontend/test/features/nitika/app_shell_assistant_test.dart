import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/nitika/data/nitika_api.dart';
import 'package:event_app/features/nitika/presentation/nitika_panel.dart';
import 'package:event_app/shared/widgets/app_shell.dart';
import 'package:event_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/nitika_fakes.dart';

/// The shell as the router builds it, signed in or not, at [width].
Future<void> pumpShell(
  WidgetTester tester, {
  required double width,
  bool enabled = true,
  bool signedIn = true,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final auth = FakeAuthController()..restore(signedIn ? sessionA : null);
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(
          location: state.uri.path,
          assistant: nitikaAssistant(
            enabled: enabled,
            signedIn: auth.isAuthenticated,
            location: state.uri.path,
          ),
          child: child,
        ),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const Text('Events page')),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth),
        nitikaApiProvider.overrideWithValue(ScriptedNitikaApi()),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

final nitikaButton = find.byTooltip('NITiKa');
final panel = find.byType(NitikaPanel);

void main() {
  testWidgets('switched off: no NITiKa button, no panel', (tester) async {
    await pumpShell(tester, width: 1400, enabled: false);
    expect(nitikaButton, findsNothing);
    expect(panel, findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('signed out: no NITiKa button, no panel', (tester) async {
    await pumpShell(tester, width: 1400, signedIn: false);
    expect(nitikaButton, findsNothing);
    expect(panel, findsNothing);
  });

  testWidgets('desktop: the rail starts collapsed; the header button '
      'opens and collapses it', (tester) async {
    await pumpShell(tester, width: 1400);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(panel, findsNothing);
    expect(find.byTooltip('Open NITiKa'), findsOneWidget);

    await tester.tap(nitikaButton);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(tester.getSize(find.byTooltip('Collapse NITiKa')), isNotNull);

    await tester.tap(nitikaButton);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);

    // The strip's own button opens it too.
    await tester.tap(find.byTooltip('Open NITiKa'));
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
  });

  testWidgets('tablet: the header button opens the slide-in panel', (
    tester,
  ) async {
    await pumpShell(tester, width: 1000);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(nitikaButton);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, 360);

    await tester.tap(find.byTooltip('Close assistant'));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
  });

  for (final width in [320.0, 360.0, 400.0]) {
    testWidgets('phone at ${width.toInt()} px: the header fits and the '
        'button opens the sheet', (tester) async {
      await pumpShell(tester, width: width);
      expect(tester.takeException(), isNull); // no header overflow
      expect(find.byType(FloatingActionButton), findsNothing);

      await tester.tap(nitikaButton);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  }
}
