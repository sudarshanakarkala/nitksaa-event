// Events and Google Sheets: two modes, never mixed.
//
// - DIY (Create event): the form as before; no way to attach a sheet.
// - Imported (Import): Edit event is read-only, with the sheet card (Open,
//   Refresh, Unlink). Refresh lists changes to the event before saving them.
// - The sheet's problems are listed by tab and row.
// - Unlink is one way: the event becomes DIY, editable here.
// - Import: the Create form filled from the sheet; Save draft links it.
// - The speaker pop-up keeps email and phone (both modes).
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
  final refreshed = <({int eventId, String? url, bool confirm})>[];
  var unlinked = 0;
  Object? refreshError;

  /// What the Event tab would change (asked before saving).
  List<SheetChange> eventChanges = const [];

  /// The event as the admin API returns it after a Refresh.
  AppEvent? eventAfterRefresh;

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
  Future<AppEvent> getAdminEvent(int eventId, String accessToken) async =>
      eventAfterRefresh ?? _event(sheet: _link);

  @override
  Future<SheetRefresh> refreshEventSheet(int eventId, String? url, String accessToken, {bool confirm = false}) async {
    refreshed.add((eventId: eventId, url: url, confirm: confirm));
    final error = refreshError;
    if (error != null) throw error;
    if (eventChanges.isNotEmpty && !confirm) {
      return SheetRefresh(url: _link, summary: const SheetSummary(), needsConfirm: true, changes: eventChanges);
    }
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

AppEvent _event({String? sheet, String title = 'NITKonnect'}) => AppEvent(
      eventId: 42,
      slug: 'konnect',
      title: title,
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
  testWidgets('a DIY event has no way to attach a sheet', (tester) async {
    await _open(tester, _SheetRepo(), event: _event());
    expect(find.text('Google Sheet'), findsNothing);
    expect(_key('event-imported-view'), findsNothing);
    expect(find.text('Event Title *'), findsOneWidget);
  });

  testWidgets('an imported event is read-only, with the sheet card', (tester) async {
    final repo = _SheetRepo()
      ..details = _SheetRepo().detailsAfterRefresh
      ..sponsors = [
        {'sponsor_id': 3, 'name': 'Acme Corp', 'sponsor_type': 'GOLD_SPONSOR', 'display_order': 0},
      ];
    await _open(tester, repo, event: _event(sheet: _link));

    expect(_key('event-imported-view'), findsOneWidget);
    expect(_key('event-sheet-linked'), findsOneWidget);
    expect(find.textContaining('Last read 1 Jan, 09:05'), findsOneWidget);
    // Nothing to add or edit: no fields, no "+", no Add or Edit buttons.
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('Add more only if'), findsNothing);
    for (final label in ['Add Speaker', 'Add Session', 'Add Sponsor']) {
      expect(find.text(label), findsNothing, reason: label);
    }
    expect(find.byIcon(Icons.edit), findsNothing);
    // What the sheet set, as text.
    expect(find.text('Speakers · 1'), findsOneWidget);
    expect(find.textContaining('CTO, Acme, CS 2001'), findsOneWidget);
    expect(find.textContaining('Hall A · Keynote'), findsOneWidget);
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    final save = tester.widget<FilledButton>(_key('event-form-save'));
    expect(save.onPressed, isNull); // nothing to save
  });

  testWidgets('refresh lists changes to the event, then applies them', (tester) async {
    final repo = _SheetRepo()
      ..eventChanges = const [(field: 'Title', from: 'NITKonnect', to: 'NITKonnect 2027')]
      ..eventAfterRefresh = _event(sheet: _link, title: 'NITKonnect 2027');
    await _open(tester, repo, event: _event(sheet: _link));

    await tester.tap(_key('event-sheet-refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Apply the changes from your sheet?'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(repo.refreshed.single.confirm, isFalse);

    await tester.tap(_key('sheet-changes-apply'));
    await tester.pumpAndSettle();
    expect(repo.refreshed.last.confirm, isTrue);
    expect(find.text('NITKonnect 2027'), findsOneWidget);
    // In the speakers list and on her session.
    expect(find.text('Speakers · 1'), findsOneWidget);
    expect(find.text('Asha Rao'), findsNWidgets(2));
    expect(_key('event-sheet-warnings'), findsOneWidget);
  });

  testWidgets('cancelling the changes saves nothing', (tester) async {
    final repo = _SheetRepo()..eventChanges = const [(field: 'Capacity', from: '500', to: '1000')];
    await _open(tester, repo, event: _event(sheet: _link));
    await tester.tap(_key('event-sheet-refresh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(repo.refreshed.length, 1);
    expect(repo.refreshed.single.confirm, isFalse);
  });

  testWidgets("the sheet's problems are listed and nothing changes", (tester) async {
    final repo = _SheetRepo()
      ..refreshError = const SheetProblem('The sheet has 2 problems to fix:', errors: [
        'Sessions, row 14: no start time.',
        "Sessions, row 9: speaker 'A. Rao' isn't on the Speakers tab.",
      ]);
    await _open(tester, repo, event: _event(sheet: _link));
    await tester.tap(_key('event-sheet-refresh'));
    await tester.pumpAndSettle();

    expect(_key('event-sheet-problem'), findsOneWidget);
    expect(find.textContaining('Sessions, row 14: no start time.'), findsOneWidget);
    expect(find.textContaining('Nothing was changed'), findsOneWidget);
  });

  testWidgets('unlink is one way: the event becomes editable here', (tester) async {
    final repo = _SheetRepo()..details = _SheetRepo().detailsAfterRefresh;
    await _open(tester, repo, event: _event(sheet: _link));

    await tester.tap(_key('event-sheet-unlink'));
    await tester.pumpAndSettle();
    expect(find.textContaining("can't be linked to a sheet again"), findsOneWidget);
    await tester.tap(_key('event-sheet-unlink-confirm'));
    await tester.pumpAndSettle();

    expect(repo.unlinked, 1);
    expect(_key('event-imported-view'), findsNothing);
    expect(find.text('Event Title *'), findsOneWidget);
    expect(find.text('Add Speaker'), findsOneWidget);
    expect(find.text('Asha Rao'), findsOneWidget);
    expect(find.text('Google Sheet'), findsNothing);
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
    // The form already showed the sheet's event: linked without a second question.
    expect(repo.refreshed.single, (eventId: 900, url: _link, confirm: true));
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
