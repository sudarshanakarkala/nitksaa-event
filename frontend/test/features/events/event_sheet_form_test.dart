// An event's Google Sheet in the event form (B7, EVENT_FORM_REDESIGN.md phase 2).
//
// - Linked: speakers, agenda and sponsors are read-only ("From your sheet"),
//   can't be added, and Save leaves sponsors and partners alone.
// - Link and Refresh: asks before replacing typed entries, reads and saves
//   in one step, then shows the lists locked.
// - The sheet's problems are listed by tab and row.
// - Unlink makes them editable again.
// - Import: the Create form filled from the sheet; Save draft links it.
// - The speaker pop-up keeps email and phone.
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/domain/event.dart';
import 'package:event_app/features/events/domain/event_sheet.dart';
import 'package:event_app/features/events/presentation/screens/manage_events_screen.dart';
import 'package:event_app/features/events/presentation/widgets/speakers_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_isolation_fakes.dart';

const _link = 'https://docs.google.com/spreadsheets/d/1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcd/edit';

class _SheetRepo extends EventsRepository {
  Map<String, dynamic> details = const {'speakers': [], 'sessions': [], 'fees': []};
  List<Map<String, dynamic>> sponsors = const [];
  Map<String, dynamic>? created;
  Map<String, dynamic>? savedDetails;
  final orgCalls = <String>[];
  final refreshed = <({int eventId, String? url})>[];
  var unlinked = 0;
  Object? refreshError;

  /// What the server holds after a Refresh.
  Map<String, dynamic> detailsAfterRefresh = const {
    'speakers': [
      {'person_id': 5, 'fullname': 'Asha Rao', 'title': 'CTO', 'organisation': 'Acme', 'role': 'SPEAKER', 'batch': 'CS 2001'},
    ],
    'sessions': [
      {
        'session_id': 9, 'title': 'Keynote', 'start_datetime': '2099-01-10T03:30:00Z',
        'end_datetime': '2099-01-10T04:00:00Z', 'session_type': 'KEYNOTE', 'track': 'Hall A',
        'people': [{'name': 'Asha Rao', 'moderator': false}], 'presented_by': [],
      },
    ],
    'fees': [],
  };

  @override
  Future<AppEvent> createAdminEvent(Map<String, dynamic> data, String accessToken) async {
    created = data;
    return AppEvent(
      eventId: 900, slug: 'imported', title: data['title'] as String, status: 'draft',
      startDatetime: DateTime(2099, 1, 10, 9), timezone: 'Asia/Kolkata', isVirtual: false,
      registrationStatus: 'not_applicable', registeredCount: 0,
    );
  }

  @override
  Future<AppEvent> updateAdminEvent(int eventId, Map<String, dynamic> data, String accessToken) async =>
      createAdminEvent(data, accessToken);

  @override
  Future<Map<String, dynamic>> getEventDetails(int eventId, String accessToken) async => details;

  @override
  Future<Map<String, dynamic>> putEventDetails(int eventId, String accessToken, Map<String, dynamic> content) async {
    savedDetails = content;
    return content;
  }

  @override
  Future<List<Map<String, dynamic>>> listEventOrgs(int eventId, String kind, String accessToken) async =>
      kind == 'sponsors' ? sponsors : const [];

  @override
  Future<void> createEventOrg(int eventId, String kind, Map<String, dynamic> data, String accessToken) async =>
      orgCalls.add('create $kind');

  @override
  Future<void> updateEventOrg(int eventId, String kind, int id, Map<String, dynamic> data, String accessToken) async =>
      orgCalls.add('update $kind $id');

  @override
  Future<void> deleteEventOrg(int eventId, String kind, int id, String accessToken) async =>
      orgCalls.add('delete $kind $id');

  @override
  Future<SheetInfo> getSheetInfo(String accessToken) async => const SheetInfo(
        shareWith: 'reader@project.iam.gserviceaccount.com',
        templates: [(name: 'Blank', url: 'https://docs.google.com/spreadsheets/d/blank/copy')],
      );

  @override
  Future<SheetRefresh> refreshEventSheet(int eventId, String? url, String accessToken) async {
    refreshed.add((eventId: eventId, url: url));
    final error = refreshError;
    if (error != null) throw error;
    details = detailsAfterRefresh;
    sponsors = [
      {'sponsor_id': 3, 'name': 'Acme Corp', 'sponsor_type': 'GOLD_SPONSOR', 'display_order': 0, 'label': 'Co-presenter'},
    ];
    return SheetRefresh(
      url: url ?? _link,
      readAt: DateTime(2099, 1, 1, 12, 41),
      summary: const SheetSummary(sessions: 1, speakers: 1, sponsors: 1),
      warnings: const ['3 sessions are on 21 Feb 2026, outside the event\'s dates.'],
    );
  }

  @override
  Future<void> unlinkEventSheet(int eventId, String accessToken) async => unlinked++;
}

final _start = DateTime.utc(2099, 1, 10, 3, 30); // 09:00 IST

AppEvent _event({String? sheet}) => AppEvent(
      eventId: 42,
      slug: 'konnect',
      title: 'NITKonnect',
      status: 'draft',
      startDatetime: _start,
      endDatetime: _start.add(const Duration(hours: 8)),
      timezone: 'Asia/Kolkata',
      isVirtual: true,
      virtualUrl: 'https://meet.example.com/x',
      capacity: 500,
      agendaSheetUrl: sheet,
      agendaSheetReadAt: sheet == null ? null : DateTime(2099, 1, 1, 9, 5),
      registrationStatus: 'not_applicable',
      registeredCount: 0,
    );

Future<List<bool>> _open(WidgetTester tester, _SheetRepo repo, {AppEvent? event, SheetPreview? fromSheet}) async {
  tester.view.physicalSize = const Size(900, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = FakeAuthController()..logIn(sessionA);
  final result = <bool>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth),
        eventsRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  result.add(await showEventFormDialog(context, event: event, fromSheet: fromSheet)),
              child: const Text('open form'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open form'));
  await tester.pumpAndSettle();
  return result;
}

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  testWidgets('a linked sheet locks speakers, agenda and sponsors', (tester) async {
    final repo = _SheetRepo()
      ..details = _SheetRepo().detailsAfterRefresh
      ..sponsors = [
        {'sponsor_id': 3, 'name': 'Acme Corp', 'sponsor_type': 'GOLD_SPONSOR', 'display_order': 0},
      ];
    await _open(tester, repo, event: _event(sheet: _link));

    expect(_key('event-group-sheet'), findsOneWidget);
    expect(find.text('Unlink'), findsOneWidget);
    expect(find.textContaining('Last read 1 Jan, 09:05'), findsOneWidget);
    for (final group in ['speakers', 'agenda', 'sponsors']) {
      expect(_key('event-from-sheet-$group'), findsOneWidget, reason: group);
      expect(_key('event-remove-$group'), findsNothing, reason: group);
      expect(_key('event-add-$group'), findsNothing, reason: group);
    }
    expect(find.text('Add Speaker'), findsNothing);
    expect(find.text('Add Session'), findsNothing);
    expect(find.text('Add Sponsor'), findsNothing);
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.text('Asha Rao'), findsOneWidget);
    expect(find.textContaining('CS 2001'), findsOneWidget);
    expect(find.textContaining('Hall A · Keynote'), findsOneWidget);

    // Save leaves sponsors and partners alone; the sessions' dates aren't checked here.
    await tester.tap(_key('event-form-save'));
    await tester.pumpAndSettle();
    expect(repo.orgCalls, isEmpty);
  });

  testWidgets('link and refresh asks before replacing typed entries, then locks', (tester) async {
    final repo = _SheetRepo()
      ..details = {
        'speakers': [
          {'person_id': 1, 'fullname': 'Typed Person', 'title': '', 'organisation': 'X', 'role': 'SPEAKER'},
        ],
        'sessions': [],
        'fees': [],
      };
    await _open(tester, repo, event: _event());

    await tester.tap(_key('event-add-sheet'));
    await tester.pumpAndSettle();
    expect(_key('event-sheet-share-with'), findsOneWidget);
    expect(find.text('Blank'), findsOneWidget);

    await tester.enterText(_key('event-sheet-link'), _link);
    await tester.tap(_key('event-sheet-refresh'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The sheet will replace the 1 speaker here'), findsOneWidget);
    await tester.tap(_key('event-sheet-replace-confirm'));
    await tester.pumpAndSettle();

    expect(repo.refreshed.single, (eventId: 42, url: _link));
    expect(find.text('Typed Person'), findsNothing);
    expect(find.text('Asha Rao'), findsOneWidget);
    expect(_key('event-from-sheet-speakers'), findsOneWidget);
    expect(_key('event-sheet-warnings'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);

    // A Refresh saved the lists: closing doesn't ask about them.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard your changes?'), findsNothing);
  });

  testWidgets("the sheet's problems are listed and nothing changes", (tester) async {
    final repo = _SheetRepo()
      ..refreshError = const SheetProblem('The sheet has 2 problems to fix:', errors: [
        'Sessions, row 14: no start time.',
        "Sessions, row 9: speaker 'A. Rao' isn't on the Speakers tab.",
      ]);
    await _open(tester, repo, event: _event());
    await tester.tap(_key('event-add-sheet'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('event-sheet-link'), _link);
    await tester.tap(_key('event-sheet-refresh'));
    await tester.pumpAndSettle();

    expect(_key('event-sheet-problem'), findsOneWidget);
    expect(find.textContaining('Sessions, row 14: no start time.'), findsOneWidget);
    expect(find.textContaining('Nothing was changed'), findsOneWidget);
    expect(_key('event-from-sheet-speakers'), findsNothing);
    expect(find.text('Link and Refresh'), findsOneWidget);
  });

  testWidgets('unlink asks, then the lists can be edited again', (tester) async {
    final repo = _SheetRepo()..details = _SheetRepo().detailsAfterRefresh;
    await _open(tester, repo, event: _event(sheet: _link));

    await tester.tap(find.text('Unlink'));
    await tester.pumpAndSettle();
    await tester.tap(_key('event-sheet-unlink-confirm'));
    await tester.pumpAndSettle();

    expect(repo.unlinked, 1);
    expect(_key('event-group-sheet'), findsNothing);
    expect(_key('event-add-sheet'), findsOneWidget);
    expect(_key('event-from-sheet-speakers'), findsNothing);
    expect(find.text('Add Speaker'), findsOneWidget);
    expect(find.text('Asha Rao'), findsOneWidget);
  });

  testWidgets('import fills the create form; saving the draft links the sheet', (tester) async {
    final repo = _SheetRepo();
    const preview = SheetPreview(
      url: _link,
      event: {
        'title': 'November Biz Breakfast', 'timezone': 'Asia/Kolkata', 'is_full_day': false,
        'start': '2099-11-15 07:30', 'end': '2099-11-15 09:30', 'is_virtual': false,
        'location_text': 'BHIVE, Church Street', 'capacity': 75, 'is_free': false,
        'ticket_price': 100, 'max_guests': 2,
      },
      summary: SheetSummary(sessions: 4, speakers: 5),
    );
    final result = await _open(tester, repo, fromSheet: preview);

    expect(find.text('Create event from a sheet'), findsOneWidget);
    expect(find.textContaining('From your sheet: 4 sessions, 5 speakers'), findsOneWidget);
    await tester.tap(_key('event-form-save'));
    await tester.pumpAndSettle();

    final data = repo.created!;
    expect(data['title'], 'November Biz Breakfast');
    expect(data['location_text'], 'BHIVE, Church Street');
    expect(data['capacity'], 75);
    expect(data['max_guests'], 2);
    expect(data['is_free'], false);
    expect(data['ticket_price'], 100);
    expect(data['start_datetime'], startsWith('2099-11-15T07:30'));
    expect(repo.refreshed.single, (eventId: 900, url: _link));
    expect(result, [true]);
  });

  testWidgets('the speaker pop-up keeps email and phone', (tester) async {
    final repo = _SheetRepo()
      ..details = {
        'speakers': [
          {'person_id': 1, 'fullname': 'Asha Rao', 'title': 'CTO', 'organisation': 'Acme', 'role': 'SPEAKER',
           'email': 'asha@example.com', 'photo_url': 'https://x/p.jpg'},
        ],
        'sessions': [],
        'fees': [],
      };
    await _open(tester, repo, event: _event());
    expect(find.textContaining('asha@example.com'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit).first);
    await tester.pumpAndSettle();
    await tester.enterText(_key('speaker-phone'), '+91 98450 00000');
    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await tester.pumpAndSettle();
    await tester.tap(_key('event-form-save'));
    await tester.pumpAndSettle();

    final speaker = (repo.savedDetails!['speakers'] as List).single as Map<String, dynamic>;
    expect(speaker['email'], 'asha@example.com');
    expect(speaker['phone'], '+91 98450 00000');
    expect(speaker['photo_url'], 'https://x/p.jpg');
  });

  testWidgets('the speaker card shows the batch', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SpeakersSection(speakers: [
          EventPerson(personId: 1, role: 'SPEAKER', fullname: 'Padmanand Warrier',
              title: 'Founder', batch: 'Electrical & Electronics, 1981'),
        ]),
      ),
    ));
    expect(find.text('Electrical & Electronics, 1981'), findsOneWidget);
  });
}
