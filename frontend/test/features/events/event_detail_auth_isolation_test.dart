// Regression tests for ISSUE-001: after logout -> login as another user in the
// same app session, the event screen showed the previous user's eligibility,
// registration, badge and profile.

import 'dart:async';

import 'package:event_app/features/auth/domain/auth_session.dart';
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/events/data/events_repository.dart';
import 'package:event_app/features/events/presentation/providers/event_detail_provider.dart';
import 'package:event_app/features/events/presentation/screens/event_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_isolation_fakes.dart';

/// A provider container wired to the fakes. [openEvent] adds the listener a
/// mounted event screen would hold, and [states] records everything that
/// screen would have rendered.
class Harness {
  Harness({FakeEventsRepository? backend}) : backend = backend ?? buildBackend() {
    container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth),
        eventsRepositoryProvider.overrideWithValue(this.backend),
      ],
    );
    addTearDown(container.dispose);
  }

  final auth = FakeAuthController();
  final FakeEventsRepository backend;
  late final ProviderContainer container;
  final states = <EventDetailState>[];
  ProviderSubscription<EventDetailState>? _subscription;

  void openEvent() {
    _subscription = container.listen(
      eventDetailProvider(eventX),
      (_, next) => states.add(next),
      fireImmediately: true,
    );
  }

  void closeEvent() {
    _subscription?.close();
    _subscription = null;
  }

  EventDetailState get state => container.read(eventDetailProvider(eventX));

  EventDetailNotifier get notifier =>
      container.read(eventDetailProvider(eventX).notifier);

  Future<EventDetailState> settled() async {
    await pumpEventQueue();
    return state;
  }

  /// Logout followed by another login, with no restart in between.
  Future<void> switchTo(AuthSession session) async {
    await auth.signOut();
    auth.logIn(session);
  }
}

/// Whether a state holds anything that was fetched for user A.
bool holdsDataOfA(EventDetailState state) {
  return state.myRegistration?['registration_id'] == registrationIdA ||
      state.myRegistration?['registration_number'] == registrationNumberA ||
      state.alumniProfile?['fullname'] == sessionA.fullname ||
      state.alumniProfile?['email'] == sessionA.email ||
      state.alumniProfile?['phone'] == phoneA ||
      state.eligibilityStatus == 'already_registered';
}

const _eligible = {
  'eligibility_status': 'eligible',
  'message': 'You can register for this event.',
};

void main() {
  group('ISSUE-001: user switch on the same event id', () {
    test("Test A: user B does not inherit user A's registration", () async {
      final h = Harness()
        ..auth.logIn(sessionA)
        ..openEvent();
      final asA = await h.settled();
      expect(asA.myRegistration?['registration_number'], registrationNumberA);

      await h.switchTo(sessionB);
      final asB = await h.settled();

      expect(asB.isLoading, isFalse);
      expect(asB.event?.eventId, eventX);
      expect(asB.myRegistration, isNull);
    });

    test("Test B: user A's alumni profile is dropped when B is refused "
        'with 403 alumni_only', () async {
      final h = Harness()
        ..auth.logIn(sessionA)
        ..openEvent();
      final asA = await h.settled();
      expect(asA.alumniProfile?['email'], sessionA.email);
      expect(asA.alumniProfile?['phone'], phoneA);

      await h.switchTo(sessionB);
      final asB = await h.settled();

      expect(asB.alumniProfile, isNull);
      expect(
        h.backend.calls,
        contains((endpoint: 'alumni-me', token: tokenB)),
      );
    });

    test("Test C: user B's eligibility replaces user A's", () async {
      final backend = buildBackend();
      backend.accounts[tokenA]!
        ..registration = null
        ..eligibility = _eligible;
      final h = Harness(backend: backend)
        ..auth.logIn(sessionA)
        ..openEvent();
      final asA = await h.settled();
      expect(asA.eligibilityStatus, 'eligible');
      expect(asA.eligibilityMessage, _eligible['message']);

      await h.switchTo(sessionB);
      final asB = await h.settled();

      expect(asB.eligibilityStatus, 'ineligible');
      expect(asB.eligibilityMessage, ineligibleMessageB);
    });

    test("Test D: the same event id is rebuilt and reloaded with user B's "
        'token', () async {
      final h = Harness()
        ..auth.logIn(sessionA)
        ..openEvent();
      await h.settled();
      final notifierA = h.notifier;
      h.backend.calls.clear();

      await h.switchTo(sessionB);
      await h.settled();

      expect(notifierA.mounted, isFalse);
      expect(identical(h.notifier, notifierA), isFalse);
      expect(h.backend.userScopedCalls, [
        (endpoint: 'eligibility', token: tokenB),
        (endpoint: 'my-registration', token: tokenB),
        (endpoint: 'alumni-me', token: tokenB),
      ]);
    });

    test('logout alone discards user-scoped state and keeps the public '
        'event', () async {
      final h = Harness()
        ..auth.logIn(sessionA)
        ..openEvent();
      await h.settled();
      h.backend.calls.clear();

      await h.auth.signOut();
      final signedOut = await h.settled();

      expect(signedOut.event?.eventId, eventX);
      expect(signedOut.eligibilityStatus, isNull);
      expect(signedOut.eligibilityMessage, isNull);
      expect(signedOut.myRegistration, isNull);
      expect(signedOut.alumniProfile, isNull);
      expect(h.backend.userScopedCalls, isEmpty);
    });

    test("nothing rendered after logout carries user A's data", () async {
      final h = Harness()
        ..auth.logIn(sessionA)
        ..openEvent();
      await h.settled();
      expect(h.states.any(holdsDataOfA), isTrue);
      h.states.clear();

      await h.switchTo(sessionB);
      await h.settled();

      expect(h.states, isNotEmpty);
      expect(h.states.where(holdsDataOfA), isEmpty);
    });

    test('a response for user A that arrives after the switch is '
        'dropped', () async {
      final h = Harness();
      final release = h.backend.heldMyRegistration[tokenA] = Completer<void>();
      h
        ..auth.logIn(sessionA)
        ..openEvent();
      await pumpEventQueue();
      expect(h.backend.count('my-registration'), 1);
      expect(h.state.isLoading, isTrue);

      await h.switchTo(sessionB);
      await h.settled();
      h.states.clear();
      release.complete();
      final asB = await h.settled();

      expect(asB.eligibilityStatus, 'ineligible');
      expect(asB.myRegistration, isNull);
      expect(asB.alumniProfile, isNull);
      expect(h.states.where(holdsDataOfA), isEmpty);
    });

    test("Test E: checkout cannot reuse user A's registration id", () async {
      final backend = buildBackend(registrationStatusA: 'payment_pending');
      backend.accounts[tokenB]!.eligibility = _eligible;
      final h = Harness(backend: backend)
        ..auth.logIn(sessionA)
        ..openEvent();
      final asA = await h.settled();
      // What checkout would reuse while A is signed in.
      expect(asA.myRegistration?['registration_id'], registrationIdA);
      final notifierA = h.notifier;

      await h.switchTo(sessionB);
      await h.settled();

      // The reads CheckoutScreen._confirmRegistration makes before paying.
      expect(h.state.myRegistration, isNull);
      expect(await h.notifier.register(eventX, ''), isTrue);
      final registrationIdB = h.state.myRegistration?['registration_id'];
      expect(registrationIdB, isNotNull);
      expect(registrationIdB, isNot(registrationIdA));
      expect(h.backend.calls.last, (endpoint: 'register', token: tokenB));

      // A notifier captured while A was signed in can no longer act.
      expect(await notifierA.register(eventX, ''), isFalse);
      expect(h.backend.count('register'), 1);
    });
  });

  group('ISSUE-001: session restore and same-user behaviour', () {
    test("Test F: a restored session loads that user's own data", () async {
      final h = Harness()
        ..auth.restore(sessionA)
        ..openEvent();
      final restored = await h.settled();

      expect(restored.isLoading, isFalse);
      expect(restored.eligibilityStatus, 'already_registered');
      expect(
        restored.myRegistration?['registration_number'],
        registrationNumberA,
      );
      expect(restored.alumniProfile?['email'], sessionA.email);
      expect(h.backend.userScopedCalls.map((c) => c.token).toSet(), {tokenA});
    });

    test('Test F: a restore that finishes after the screen opened still '
        'loads the user', () async {
      final h = Harness()..openEvent();
      final whileChecking = await h.settled();
      expect(whileChecking.event?.eventId, eventX);
      expect(whileChecking.myRegistration, isNull);
      expect(h.backend.userScopedCalls, isEmpty);

      h.auth.restore(sessionA);
      final restored = await h.settled();

      expect(
        restored.myRegistration?['registration_number'],
        registrationNumberA,
      );
    });

    test('auth notifications that do not change the session keep the loaded '
        'state', () async {
      final h = Harness()
        ..auth.logIn(sessionA)
        ..openEvent();
      await h.settled();
      final notifier = h.notifier;
      final callsBefore = h.backend.calls.length;

      h.auth.notifyWithoutChange();
      final after = await h.settled();

      expect(identical(h.notifier, notifier), isTrue);
      expect(h.backend.calls.length, callsBefore);
      expect(after.myRegistration?['registration_number'], registrationNumberA);
    });

    test('the same user signing back in sees their own data again', () async {
      const tokenA2 = 'token-A2';
      final backend = buildBackend();
      backend.accounts[tokenA2] = backend.accounts[tokenA]!;
      final h = Harness(backend: backend)
        ..auth.logIn(sessionA)
        ..openEvent();
      await h.settled();
      h.backend.calls.clear();

      await h.switchTo(sessionA.copyWith(accessToken: tokenA2));
      final again = await h.settled();

      expect(
        again.myRegistration?['registration_number'],
        registrationNumberA,
      );
      expect(again.alumniProfile?['email'], sessionA.email);
      expect(h.backend.userScopedCalls.map((c) => c.token).toSet(), {tokenA2});
    });

    test('leaving the event drops its state and reopening refetches', () async {
      final h = Harness()
        ..auth.logIn(sessionA)
        ..openEvent();
      await h.settled();
      final first = h.notifier;

      h.closeEvent();
      await pumpEventQueue();
      expect(first.mounted, isFalse);
      h.backend.calls.clear();

      h.openEvent();
      final reopened = await h.settled();

      expect(h.backend.count('my-registration'), 1);
      expect(
        reopened.myRegistration?['registration_number'],
        registrationNumberA,
      );
    });
  });

  group('ISSUE-001: null clears stale state', () {
    const loaded = EventDetailState(
      eligibilityStatus: 'eligible',
      eligibilityMessage: 'You can register for this event.',
      myRegistration: {'registration_id': registrationIdA},
      alumniProfile: {'email': 'alice@example.com'},
    );

    test('copyWith(null) clears each user-scoped field', () {
      final cleared = loaded.copyWith(
        eligibilityStatus: null,
        eligibilityMessage: null,
        myRegistration: null,
        alumniProfile: null,
      );

      expect(cleared.eligibilityStatus, isNull);
      expect(cleared.eligibilityMessage, isNull);
      expect(cleared.myRegistration, isNull);
      expect(cleared.alumniProfile, isNull);
    });

    test('copyWith keeps the fields it is not given', () {
      final kept = loaded.copyWith(isLoading: true);

      expect(kept.eligibilityStatus, loaded.eligibilityStatus);
      expect(kept.eligibilityMessage, loaded.eligibilityMessage);
      expect(kept.myRegistration, loaded.myRegistration);
      expect(kept.alumniProfile, loaded.alumniProfile);
    });

    test('a later empty or failed result clears what an earlier fetch '
        'stored', () async {
      final backend = buildBackend();
      final notifier = EventDetailNotifier(backend, tokenA);
      addTearDown(notifier.dispose);
      await notifier.fetchEventDetails(eventX);
      expect(holdsDataOfA(notifier.state), isTrue);

      backend.accounts[tokenA]!
        ..eligibility = null // the call fails
        ..registration = null // 404
        ..alumniProfile = null; // 403 alumni_only
      await notifier.fetchEventDetails(eventX);

      final refreshed = notifier.state;
      expect(refreshed.isLoading, isFalse);
      expect(refreshed.event?.eventId, eventX);
      expect(refreshed.eligibilityStatus, isNull);
      expect(refreshed.eligibilityMessage, isNull);
      expect(refreshed.myRegistration, isNull);
      expect(refreshed.alumniProfile, isNull);
    });
  });

  group('ISSUE-001: EventDetailScreen', () {
    Future<void> pumpEventScreen(
      WidgetTester tester,
      FakeAuthController auth,
      FakeEventsRepository backend,
    ) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith((ref) => auth),
            eventsRepositoryProvider.overrideWithValue(backend),
          ],
          child: const MaterialApp(home: EventDetailScreen(eventId: eventX)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets("stops showing user A's badge once user B signs in, with no "
        'reload', (tester) async {
      final auth = FakeAuthController()..logIn(sessionA);
      await pumpEventScreen(tester, auth, buildBackend());
      expect(find.text('Registered Successfully'), findsOneWidget);
      expect(find.text('Badge #: $registrationNumberA'), findsOneWidget);

      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Registered Successfully'), findsNothing);
      expect(find.textContaining(registrationNumberA), findsNothing);

      auth.logIn(sessionB);
      await tester.pumpAndSettle();

      expect(find.text('Registered Successfully'), findsNothing);
      expect(find.textContaining(registrationNumberA), findsNothing);
      expect(find.text(ineligibleMessageB), findsOneWidget);
    });

    testWidgets('registration form is prefilled for user B, not user A', (
      tester,
    ) async {
      final backend = buildBackend();
      backend.accounts[tokenA]!
        ..registration = null
        ..eligibility = _eligible;
      backend.accounts[tokenB]!.eligibility = _eligible;
      final auth = FakeAuthController()..logIn(sessionA);
      await pumpEventScreen(tester, auth, backend);

      await auth.signOut();
      auth.logIn(sessionB);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Register'));
      await tester.pumpAndSettle();

      expect(find.text('Register for Event'), findsOneWidget);
      expect(find.text(sessionB.fullname!), findsOneWidget);
      expect(find.text(sessionB.email!), findsOneWidget);
      expect(find.text(sessionA.fullname!), findsNothing);
      expect(find.text(sessionA.email!), findsNothing);
      expect(find.text(phoneA), findsNothing);
    });
  });
}
