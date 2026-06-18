import 'dart:async';

import 'package:event_app/features/events/domain/public_event.dart';
import 'package:event_app/features/events/presentation/event_list_screen.dart';
import 'package:event_app/features/events/services/public_event_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('shows loading then upcoming physical and virtual event cards', (
    tester,
  ) async {
    final completer = Completer<List<PublicEvent>>();
    final service = _FakePublicEventService(
      responses: {
        EventPeriod.upcoming: () => completer.future,
        EventPeriod.past: () async => [],
      },
    );

    await tester.pumpWidget(_app(service));
    expect(find.text('Loading events'), findsOneWidget);

    completer.complete([_physicalEvent, _virtualEvent]);
    await tester.pumpAndSettle();

    expect(find.text('Chapter Meetup'), findsOneWidget);
    expect(find.text('In-person'), findsOneWidget);
    expect(find.text('Mangaluru'), findsOneWidget);
    expect(find.text('Capacity: 4 / 30'), findsOneWidget);
    expect(find.text('Registration: Open'), findsOneWidget);
    expect(find.text('Virtual Town Hall'), findsOneWidget);
    expect(find.text('Virtual'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Capacity: Unlimited'), findsOneWidget);
    expect(find.text('Registration: Full'), findsOneWidget);
    expect(find.textContaining('join.example'), findsNothing);

    await tester.tap(find.text('Chapter Meetup'));
    await tester.pumpAndSettle();
    expect(find.text('Detail event 1'), findsOneWidget);
  });

  testWidgets('loads the past tab only when selected', (tester) async {
    final service = _FakePublicEventService(
      responses: {
        EventPeriod.upcoming: () async => [_physicalEvent],
        EventPeriod.past: () async => [_pastEvent],
      },
    );

    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    expect(service.calls, [EventPeriod.upcoming]);

    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();

    expect(service.calls, [EventPeriod.upcoming, EventPeriod.past]);
    expect(find.text('Past Reunion'), findsOneWidget);
    expect(find.text('Registration: Closed'), findsOneWidget);
  });

  testWidgets('shows error with retry and then empty state', (tester) async {
    var shouldFail = true;
    final service = _FakePublicEventService(
      responses: {
        EventPeriod.upcoming: () async {
          if (shouldFail) throw Exception('network failed');
          return [];
        },
        EventPeriod.past: () async => [],
      },
    );

    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load events'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    shouldFail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('No upcoming events'), findsOneWidget);
    expect(find.text('Pull down to refresh.'), findsOneWidget);
  });
}

Widget _app(PublicEventService service) {
  final router = GoRouter(
    initialLocation: '/events',
    routes: [
      GoRoute(
        path: '/events',
        builder: (context, index) => EventListScreen(eventService: service),
      ),
      GoRoute(
        path: '/events/:eventId',
        builder: (_, state) => Scaffold(
          body: Text('Detail event ${state.pathParameters['eventId']}'),
        ),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

class _FakePublicEventService implements PublicEventService {
  _FakePublicEventService({required this.responses});

  final Map<EventPeriod, Future<List<PublicEvent>> Function()> responses;
  final List<EventPeriod> calls = [];

  @override
  Future<List<PublicEvent>> listEvents(EventPeriod period) {
    calls.add(period);
    return responses[period]!();
  }
}

final _physicalEvent = PublicEvent(
  eventId: 1,
  slug: 'chapter-meetup',
  title: 'Chapter Meetup',
  status: 'published',
  startDateTime: DateTime.utc(2026, 6, 12, 9),
  endDateTime: DateTime.utc(2026, 6, 12, 11),
  timezone: 'UTC',
  locationText: 'Mangaluru',
  isVirtual: false,
  capacity: 30,
  registeredCount: 4,
  registrationStatus: 'open',
);

final _virtualEvent = PublicEvent(
  eventId: 2,
  slug: 'virtual-town-hall',
  title: 'Virtual Town Hall',
  status: 'published',
  startDateTime: DateTime.utc(2026, 7, 1, 14),
  endDateTime: DateTime.utc(2026, 7, 1, 15),
  timezone: 'UTC',
  isVirtual: true,
  registeredCount: 50,
  registrationStatus: 'full',
);

final _pastEvent = PublicEvent(
  eventId: 3,
  slug: 'past-reunion',
  title: 'Past Reunion',
  status: 'published',
  startDateTime: DateTime.utc(2025, 12, 1, 10),
  endDateTime: DateTime.utc(2025, 12, 1, 12),
  timezone: 'UTC',
  locationText: 'Surathkal',
  isVirtual: false,
  capacity: 100,
  registeredCount: 80,
  registrationStatus: 'closed',
);
