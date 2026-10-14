// QR check-in page: event admins check people in with one tap; anyone else
// only sees that it's an entry pass.

import 'package:dio/dio.dart';
import 'package:event_app/features/auth/domain/admin_access.dart';
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/checkin/check_in_scanner_screen.dart';
import 'package:event_app/features/checkin/check_in_screen.dart';
import 'package:event_app/features/checkin/data/check_in_api.dart';
import 'package:event_app/features/events/presentation/widgets/entry_pass_qr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../events/support/auth_isolation_fakes.dart';

const _eventId = 42;
const _token = 'tok-abc';

class _FakeCheckInApi extends CheckInApi {
  _FakeCheckInApi(this.pass) : super(dio: Dio());

  EntryPassCheck pass;
  int checkIns = 0;

  @override
  Future<EntryPassCheck> verify({
    required int eventId,
    required String qrToken,
    required String accessToken,
  }) async =>
      pass;

  @override
  Future<CheckInDone> checkIn({
    required int eventId,
    required String qrToken,
    required String accessToken,
  }) async {
    checkIns++;
    return const CheckInDone(checkinId: 1, registrationId: 1);
  }
}

const _ready = EntryPassCheck(
  valid: true,
  alreadyCheckedIn: false,
  message: 'ready_to_checkin',
  fullName: 'Asha Rao',
  registrationStatus: 'registered',
);

Future<_FakeCheckInApi> _open(
  WidgetTester tester, {
  required FakeAuthController auth,
  EntryPassCheck pass = _ready,
}) async {
  final api = _FakeCheckInApi(pass);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth),
        checkInApiProvider.overrideWithValue(api),
      ],
      child: const MaterialApp(
        home: CheckInScreen(eventId: _eventId, qrToken: _token),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('signed out: an entry pass, with a sign-in for volunteers',
      (tester) async {
    final api = await _open(tester, auth: FakeAuthController()..restore(null));

    expect(find.text('This is an entry pass'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Check in'), findsNothing);
    expect(api.checkIns, 0);
  });

  testWidgets('signed in but not an admin of the event: no check-in',
      (tester) async {
    final auth = FakeAuthController()
      ..logIn(sessionA.copyWith(access: const AdminAccess(adminEventIds: [7])));
    await _open(tester, auth: auth);

    expect(find.text('This is an entry pass'), findsOneWidget);
    expect(find.text('Check in'), findsNothing);
    expect(find.text('Asha Rao'), findsNothing);
  });

  testWidgets("the event's admin sees who it is and checks them in",
      (tester) async {
    final auth = FakeAuthController()
      ..logIn(sessionA.copyWith(
          access: const AdminAccess(adminEventIds: [_eventId])));
    final api = await _open(tester, auth: auth);

    expect(find.text('Asha Rao'), findsOneWidget);
    await tester.tap(find.text('Check in'));
    await tester.pumpAndSettle();

    expect(api.checkIns, 1);
    expect(find.text('Checked in'), findsOneWidget);
  });

  testWidgets('already checked in: says so, no button',
      (tester) async {
    final auth = FakeAuthController()
      ..logIn(sessionA.copyWith(access: const AdminAccess(isAdmin: true)));
    await _open(
      tester,
      auth: auth,
      pass: const EntryPassCheck(
        valid: true,
        alreadyCheckedIn: true,
        message: 'already_checked_in',
        fullName: 'Asha Rao',
      ),
    );
    expect(find.text('Already checked in'), findsOneWidget);
    expect(find.text('Check in'), findsNothing);
  });

  test('the QR holds a check-in link for this event and person', () {
    expect(entryPassUrl(_eventId, _token), endsWith('/#/checkin/42/tok-abc'));
  });

  test('the scanner reads the event and token back out of the QR', () {
    final pass = parseEntryPass(entryPassUrl(_eventId, 'Ab_9-xY'));
    expect(pass?.eventId, _eventId);
    expect(pass?.token, 'Ab_9-xY');
    expect(parseEntryPass('https://nitksaa-events-beta.web.app/#/checkin/7/tok')?.eventId, 7);
    expect(parseEntryPass('NITKSAA-2026-000123'), isNull); // an old badge number
    expect(parseEntryPass('https://example.com/'), isNull);
  });
}
