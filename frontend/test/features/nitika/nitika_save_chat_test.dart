// Save chat (overall admins): the conversation as a text file, to train and
// debug NITiKa.
//
// - The transcript has who saved it, each question and answer, the request
//   ids, SQL replies marked, tables as text and links.
// - Only an overall admin sees the button; it is greyed out until there is
//   a conversation.
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/nitika/data/nitika_api.dart';
import 'package:event_app/features/nitika/domain/nitika_models.dart';
import 'package:event_app/features/nitika/presentation/nitika_controller.dart';
import 'package:event_app/features/nitika/presentation/nitika_panel.dart';
import 'package:event_app/features/nitika/presentation/nitika_transcript.dart';
import 'package:event_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/nitika_fakes.dart';

void main() {
  group('nitikaTranscript', () {
    final savedAt = DateTime(2026, 10, 16, 14, 5);

    test('lists who saved it, the questions, answers and request ids', () {
      final text = nitikaTranscript(
        [
          const NitikaMessage.user(1, 'How many registered for the breakfast?'),
          const NitikaMessage.reply(
            2,
            NitikaReply(answer: '42 people are registered.', requestId: 'req-1'),
          ),
        ],
        savedAt: savedAt,
        savedBy: 'padmanand@outlook.com',
      );
      expect(text, startsWith('NITiKa chat, 16 Oct 2026, 14:05\n'));
      expect(text, contains('Saved by: padmanand@outlook.com (overall admin)'));
      expect(text, contains('You: How many registered for the breakfast?'));
      expect(text, contains('NITiKa: 42 people are registered.   [request id: req-1]'));
    });

    test('marks SQL replies and writes tables and links as text', () {
      final text = nitikaTranscript(
        [
          const NitikaMessage.reply(
            1,
            NitikaReply(
              mode: 'sql',
              table: NitikaTable(
                columns: ['Name', 'Status'],
                rows: [
                  ['Asha Rao', 'paid'],
                  ['Ravi K', null],
                ],
                rowCount: 5,
                truncated: true,
              ),
              links: [NitikaLink(label: 'Breakfast', path: '/events/86')],
            ),
          ),
        ],
        savedAt: savedAt,
      );
      expect(text, contains('NITiKa (SQL): '));
      expect(text, contains('(table, 5 rows, showing 2 of 5)'));
      expect(text, contains('  Name\tStatus'));
      expect(text, contains('  Asha Rao\tpaid'));
      expect(text, contains('  Ravi K\t\n'));
      expect(text, contains('Links: Breakfast → /events/86'));
    });

    test('file name has the date and time', () {
      expect(nitikaTranscriptName(savedAt), 'nitika-chat-2026-10-16-1405');
    });
  });

  Future<ScriptedNitikaApi> openPanel(WidgetTester tester, {required bool overallAdmin}) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = FakeAuthController()..restore(overallAdmin ? adminSession : sessionA);
    final api = ScriptedNitikaApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          nitikaApiProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: NitikaPanel(location: '/home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  IconButton saveButton(WidgetTester tester) =>
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.download_outlined));

  testWidgets('an overall admin sees Save chat, enabled once there is a chat',
      (tester) async {
    await openPanel(tester, overallAdmin: true);
    expect(find.byTooltip('Save chat'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'How many events this month?');
    await tester.pump(); // Send is enabled once the text is in
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('anyone else does not see Save chat', (tester) async {
    await openPanel(tester, overallAdmin: false);
    expect(find.byTooltip('Save chat'), findsNothing);
  });
}
