// Event setup, phase 1 (EVENT_FORM_REDESIGN.md): the create/edit form.
//
// - Create shows the essentials only and saves a draft (the description is
//   optional), with the usual registration times and no tagline.
// - Edit shows the groups that hold data, "+" for the rest; a group can be
//   added and removed (asking first when it holds data, cleared on save).
// - Registration closing at the start shows as no custom dates.
// - Closing with unsaved changes asks first.
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/domain/event.dart';
import 'package:event_app/features/events/presentation/screens/manage_events_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_isolation_fakes.dart';

/// Records what the form saves; answers loads with [details] and [sponsors].
class _FormRepo extends EventsRepository {
  Map<String, dynamic>? created;
  Map<String, dynamic>? updated;
  Map<String, dynamic>? savedDetails;
  Map<String, dynamic> details = const {'speakers': [], 'sessions': [], 'fees': []};
  List<Map<String, dynamic>> sponsors = const [];
  final deletedOrgs = <int>[];

  AppEvent _saved(int id, Map<String, dynamic> data) => AppEvent(
        eventId: id,
        slug: 'event-$id',
        title: data['title'] as String? ?? 'Event',
        status: 'draft',
        startDatetime: DateTime(2099, 1, 10, 9),
        timezone: 'Asia/Kolkata',
        isVirtual: data['is_virtual'] as bool? ?? false,
        registrationStatus: 'not_applicable',
        registeredCount: 0,
      );

  @override
  Future<AppEvent> createAdminEvent(Map<String, dynamic> data, String accessToken) async {
    created = data;
    return _saved(900, data);
  }

  @override
  Future<AppEvent> updateAdminEvent(
    int eventId,
    Map<String, dynamic> data,
    String accessToken,
  ) async {
    updated = data;
    return _saved(eventId, data);
  }

  @override
  Future<Map<String, dynamic>> getEventDetails(int eventId, String accessToken) async =>
      details;

  @override
  Future<Map<String, dynamic>> putEventDetails(
    int eventId,
    String accessToken,
    Map<String, dynamic> content,
  ) async {
    savedDetails = content;
    return content;
  }

  @override
  Future<List<Map<String, dynamic>>> listEventOrgs(
    int eventId,
    String kind,
    String accessToken,
  ) async =>
      kind == 'sponsors' ? sponsors : const [];

  @override
  Future<void> createEventOrg(
    int eventId,
    String kind,
    Map<String, dynamic> data,
    String accessToken,
  ) async {}

  @override
  Future<void> updateEventOrg(
    int eventId,
    String kind,
    int id,
    Map<String, dynamic> data,
    String accessToken,
  ) async {}

  @override
  Future<void> deleteEventOrg(
    int eventId,
    String kind,
    int id,
    String accessToken,
  ) async {
    deletedOrgs.add(id);
  }
}

final _start = DateTime.utc(2099, 1, 10, 3, 30); // 09:00 IST

AppEvent _event({
  String? thumbnailUrl,
  int maxGuests = 0,
  DateTime? registrationClosesAt,
}) =>
    AppEvent(
      eventId: 42,
      slug: 'breakfast',
      title: 'Bangalore Breakfast',
      description: 'Breakfast with alumni.',
      status: 'draft',
      startDatetime: _start,
      endDatetime: _start.add(const Duration(hours: 2)),
      timezone: 'Asia/Kolkata',
      isVirtual: true,
      virtualUrl: 'https://meet.example.com/x',
      capacity: 120,
      thumbnailUrl: thumbnailUrl,
      maxGuests: maxGuests,
      registrationClosesAt: registrationClosesAt,
      registrationStatus: 'not_applicable',
      registeredCount: 0,
    );

/// Opens the form from a button; [result] gets what the dialog returned.
Future<List<bool>> _open(WidgetTester tester, _FormRepo repo, {AppEvent? event}) async {
  tester.view.physicalSize = const Size(900, 3200);
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
              onPressed: () async => result.add(await showEventFormDialog(context, event: event)),
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

Finder _field(String label) => find.widgetWithText(TextFormField, label);
Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _tapToggle(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.widgetWithText(Row, label).last, matching: find.byType(Switch)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('create shows the essentials only', (tester) async {
    await _open(tester, _FormRepo());

    expect(find.text('Create event'), findsOneWidget);
    expect(find.text('Save draft'), findsOneWidget);
    expect(find.text('Seats and price'), findsOneWidget);
    expect(find.textContaining('After saving, open Edit event'), findsOneWidget);
    for (final key in ['event-add-speakers', 'event-add-guests', 'event-max-guests']) {
      expect(_key(key), findsNothing, reason: key);
    }
    expect(find.textContaining('Tagline'), findsNothing);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('saves without a description, with the usual times',
      (tester) async {
    final repo = _FormRepo();
    final result = await _open(tester, repo);

    await tester.enterText(_field('Event Title *'), 'Breakfast meet');
    await tester.enterText(_field('Capacity *'), '100');
    await _tapToggle(tester, 'Online event');
    await tester.enterText(_field('Meeting URL *'), 'https://meet.example.com/x');
    await tester.tap(_key('event-form-save'));
    await tester.pumpAndSettle();

    final data = repo.created!;
    expect(data['title'], 'Breakfast meet');
    expect(data['description'], isNull);
    expect(data['capacity'], 100);
    expect(data['max_guests'], 0);
    expect(data['is_free'], true);
    expect(data.containsKey('tagline'), isFalse);
    expect(data['registration_opens_at'], isNull);
    expect(data['registration_closes_at'], data['start_datetime']);
    expect(result, [true]);
  });

  testWidgets('edit shows the groups with data, and + for the rest',
      (tester) async {
    final repo = _FormRepo()
      ..details = {
        'speakers': [
          {'person_id': 1, 'fullname': 'Asha Rao', 'title': 'Panelist', 'organisation': 'NITK'},
        ],
        'sessions': [],
        'fees': [],
      };
    await _open(tester, repo, event: _event(thumbnailUrl: 'https://x/t.png', maxGuests: 2));

    expect(find.text('Edit event'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    for (final group in ['images', 'guests', 'speakers']) {
      expect(_key('event-group-$group'), findsOneWidget, reason: group);
      expect(_key('event-add-$group'), findsNothing, reason: group);
    }
    for (final group in ['registrationDates', 'agenda', 'sponsors']) {
      expect(_key('event-group-$group'), findsNothing, reason: group);
      expect(_key('event-add-$group'), findsOneWidget, reason: group);
    }
    expect(find.text('Asha Rao'), findsOneWidget);
  });

  testWidgets('an existing sponsor shows its group', (tester) async {
    final repo = _FormRepo()
      ..sponsors = [
        {'sponsor_id': 7, 'name': 'KreditBee', 'sponsor_type': 'TITLE_SPONSOR', 'display_order': 0},
      ];
    await _open(tester, repo, event: _event());
    expect(_key('event-group-sponsors'), findsOneWidget);
    expect(find.text('KreditBee'), findsOneWidget);
  });

  testWidgets('a group can be added, and removed without asking when empty',
      (tester) async {
    await _open(tester, _FormRepo(), event: _event());

    await tester.tap(_key('event-add-agenda'));
    await tester.pumpAndSettle();
    expect(_key('event-group-agenda'), findsOneWidget);
    expect(find.text('No sessions added yet'), findsOneWidget);

    await tester.tap(_key('event-remove-agenda'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(_key('event-group-agenda'), findsNothing);
    expect(_key('event-add-agenda'), findsOneWidget);
  });

  testWidgets('removing a group with data asks, then clears it on save',
      (tester) async {
    final repo = _FormRepo()
      ..sponsors = [
        {'sponsor_id': 7, 'name': 'KreditBee', 'sponsor_type': 'TITLE_SPONSOR', 'display_order': 0},
      ];
    await _open(tester, repo, event: _event(thumbnailUrl: 'https://x/t.png', maxGuests: 3));

    await tester.tap(_key('event-remove-images'));
    await tester.pumpAndSettle();
    expect(find.text('Remove images?'), findsOneWidget);
    expect(find.text('The thumbnail and banner will be removed when you save.'), findsOneWidget);
    await tester.tap(_key('event-group-remove-confirm'));
    await tester.pumpAndSettle();
    expect(_key('event-group-images'), findsNothing);

    await tester.tap(_key('event-remove-guests'));
    await tester.pumpAndSettle();
    await tester.tap(_key('event-group-remove-confirm'));
    await tester.pumpAndSettle();

    await tester.tap(_key('event-remove-sponsors'));
    await tester.pumpAndSettle();
    await tester.tap(_key('event-group-remove-confirm'));
    await tester.pumpAndSettle();

    await tester.tap(_key('event-form-save'));
    await tester.pumpAndSettle();
    expect(repo.updated!['thumbnail_url'], isNull);
    expect(repo.updated!['banner_url'], isNull);
    expect(repo.updated!['max_guests'], 0);
    expect(repo.deletedOrgs, [7]);
  });

  testWidgets('removing a group with data can be cancelled', (tester) async {
    await _open(tester, _FormRepo(), event: _event(maxGuests: 2));

    await tester.tap(_key('event-remove-guests'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();
    expect(_key('event-group-guests'), findsOneWidget);
  });

  testWidgets('closing at the start counts as no custom registration dates',
      (tester) async {
    final repo = _FormRepo();
    await _open(tester, repo, event: _event(registrationClosesAt: _start));

    expect(_key('event-group-registrationDates'), findsNothing);
    await tester.tap(_key('event-form-save'));
    await tester.pumpAndSettle();
    expect(repo.updated!['registration_closes_at'], repo.updated!['start_datetime']);
    expect(repo.updated!['registration_opens_at'], isNull);
  });

  testWidgets('a custom closing time shows its group and is kept', (tester) async {
    final repo = _FormRepo();
    final closes = _start.subtract(const Duration(days: 2));
    await _open(tester, repo, event: _event(registrationClosesAt: closes));

    expect(_key('event-group-registrationDates'), findsOneWidget);
    await tester.tap(_key('event-form-save'));
    await tester.pumpAndSettle();
    expect(repo.updated!['registration_closes_at'], isNot(repo.updated!['start_datetime']));
    expect(DateTime.parse(repo.updated!['registration_closes_at'] as String).toUtc(), closes);
  });

  testWidgets('closing with no changes closes straight away', (tester) async {
    final result = await _open(tester, _FormRepo(), event: _event());
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Edit event'), findsNothing);
    expect(result, [false]);
  });

  testWidgets('closing with unsaved changes asks first', (tester) async {
    final result = await _open(tester, _FormRepo(), event: _event());
    await tester.enterText(_field('Event Title *'), 'Bangalore Breakfast, November');
    await tester.pump();

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard your changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Edit event'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(_key('event-form-discard'));
    await tester.pumpAndSettle();
    expect(find.text('Edit event'), findsNothing);
    expect(result, [false]);
  });

  testWidgets('a published event can be saved without a description',
      (tester) async {
    final repo = _FormRepo();
    final published = AppEvent(
      eventId: 43,
      slug: 'published',
      title: 'Published meet',
      status: 'published',
      startDatetime: _start,
      endDatetime: _start.add(const Duration(hours: 2)),
      timezone: 'Asia/Kolkata',
      isVirtual: true,
      virtualUrl: 'https://meet.example.com/x',
      capacity: 50,
      registrationStatus: 'open',
      registeredCount: 0,
    );
    await _open(tester, repo, event: published);
    expect(_field('Description (optional)'), findsOneWidget);
    await tester.tap(_key('event-form-save'));
    await tester.pumpAndSettle();
    expect(repo.updated, isNotNull);
    expect(repo.updated!['description'], isNull);
  });

  testWidgets('a missing field is refused and nothing is saved', (tester) async {
    final repo = _FormRepo();
    await _open(tester, repo);
    // No title, no capacity.
    await tester.tap(_key('event-form-save'));
    await tester.pumpAndSettle();
    expect(find.text('Event Title is required'), findsOneWidget);
    expect(repo.created, isNull);
  });

  // The event's link (/e/<slug>): editable in a draft, fixed once published.
  testWidgets('a draft link can be changed and is saved tidied', (tester) async {
    final repo = _FormRepo();
    await _open(tester, repo, event: _event());
    expect(find.textContaining('/e/breakfast'), findsOneWidget);
    await tester.tap(_key('event-link-change'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('event-link'), 'Bangalore Breakfast Oct 2026');
    await tester.pumpAndSettle();
    await tester.tap(_key('event-form-save'));
    await tester.pumpAndSettle();
    expect(repo.updated!['slug'], 'bangalore-breakfast-oct-2026');
  });

  testWidgets('the description says Markdown can be used', (tester) async {
    await _open(tester, _FormRepo());
    expect(find.textContaining('**bold**, ## headings'), findsOneWidget);
  });

  testWidgets('an unchanged link is not sent', (tester) async {
    final repo = _FormRepo();
    await _open(tester, repo, event: _event());
    await tester.tap(_key('event-form-save'));
    await tester.pumpAndSettle();
    expect(repo.updated, isNotNull);
    expect(repo.updated!.containsKey('slug'), isFalse);
  });

  testWidgets('a bad link is refused and nothing is saved', (tester) async {
    final repo = _FormRepo();
    await _open(tester, repo, event: _event());
    await tester.tap(_key('event-link-change'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('event-link'), 'ab');
    await tester.tap(_key('event-form-save'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 3 letters or numbers'), findsOneWidget);
    expect(repo.updated, isNull);
  });

  testWidgets('a published event\'s link is fixed', (tester) async {
    final repo = _FormRepo();
    final published = AppEvent(
      eventId: 44,
      slug: 'nitkonnect-2027',
      title: 'NITKonnect 2027',
      status: 'published',
      publishedAt: DateTime(2026, 10, 1),
      startDatetime: _start,
      endDatetime: _start.add(const Duration(hours: 2)),
      timezone: 'Asia/Kolkata',
      isVirtual: true,
      virtualUrl: 'https://meet.example.com/x',
      capacity: 50,
      registrationStatus: 'open',
      registeredCount: 0,
    );
    await _open(tester, repo, event: published);
    expect(find.textContaining('/e/nitkonnect-2027'), findsOneWidget);
    expect(find.textContaining('can\'t change once the event is published'), findsOneWidget);
    expect(_key('event-link-change'), findsNothing);
    await tester.tap(_key('event-form-save'));
    await tester.pumpAndSettle();
    expect(repo.updated!.containsKey('slug'), isFalse);
  });

  group('Branding (B6)', () {
    testWidgets('an event without branding saves no branding fields', (tester) async {
      final repo = _FormRepo();
      await _open(tester, repo, event: _event());
      expect(_key('event-add-branding'), findsOneWidget);
      await tester.tap(_key('event-form-save'));
      await tester.pumpAndSettle();
      expect(repo.updated, isNotNull);
      for (final key in ['brand_logo_url', 'brand_logo_dark_url', 'brand_accent']) {
        expect(repo.updated!.containsKey(key), isFalse, reason: key);
      }
    });

    testWidgets('added and saved; any old colour is cleared', (tester) async {
      final repo = _FormRepo();
      await _open(tester, repo, event: _event());
      await tester.tap(_key('event-add-branding'));
      await tester.pumpAndSettle();
      expect(_key('event-group-branding'), findsOneWidget);
      expect(find.text('Page colour'), findsNothing);

      await tester.enterText(_field('Logo URL'), '/brand/nitkonnect/logo.png');
      await tester.tap(_key('event-form-save'));
      await tester.pumpAndSettle();
      final data = repo.updated!;
      expect(data['brand_logo_url'], '/brand/nitkonnect/logo.png');
      expect(data['brand_logo_dark_url'], isNull);
      expect(data.containsKey('brand_accent'), isTrue);
      expect(data['brand_accent'], isNull);
    });
  });

  group('Edit event layout', () {
    testWidgets('the + buttons come before the groups', (tester) async {
      await _open(tester, _FormRepo(), event: _event(thumbnailUrl: 'https://x/t.png'));
      final plus = tester.getTopLeft(_key('event-add-agenda')).dy;
      final images = tester.getTopLeft(_key('event-group-images')).dy;
      expect(plus, lessThan(images));
    });

    testWidgets('a long list starts folded to one line; Show opens it', (tester) async {
      final repo = _FormRepo()
        ..details = {
          'speakers': [
            for (var i = 1; i <= 6; i++)
              {'person_id': i, 'fullname': 'Speaker $i', 'title': 'CTO', 'organisation': 'Acme'},
          ],
          'sessions': [],
          'fees': [],
        };
      await _open(tester, repo, event: _event());
      expect(find.text('6 speakers'), findsOneWidget);
      expect(find.text('Speaker 1'), findsNothing);

      await tester.tap(_key('event-fold-speakers'));
      await tester.pumpAndSettle();
      expect(find.text('Speaker 1'), findsOneWidget);
      expect(find.text('6 speakers'), findsNothing);
    });

    testWidgets('a short list shows as before', (tester) async {
      final repo = _FormRepo()
        ..details = {
          'speakers': [
            {'person_id': 1, 'fullname': 'Asha Rao', 'title': 'Panelist', 'organisation': 'NITK'},
          ],
          'sessions': [],
          'fees': [],
        };
      await _open(tester, repo, event: _event());
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(_key('event-fold-speakers'), findsNothing);
    });
  });
}
