import 'dart:async';

import 'package:dio/dio.dart';
import 'package:event_app/features/events/domain/public_event_detail.dart';
import 'package:event_app/features/events/presentation/event_detail_screen.dart';
import 'package:event_app/features/events/services/public_event_detail_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows loading then physical detail and speaker empty state', (
    tester,
  ) async {
    final completer = Completer<PublicEventDetail>();
    await tester.pumpWidget(
      _app(
        EventDetailScreen(
          eventId: 6,
          eventService: _CallbackDetailService((_) => completer.future),
        ),
      ),
    );
    expect(find.text('Loading event'), findsOneWidget);

    completer.complete(_physicalEvent);
    await tester.pumpAndSettle();

    expect(find.text('Innovation Summit'), findsOneWidget);
    expect(find.text('In-person'), findsOneWidget);
    expect(find.text('Chennai Convention Centre'), findsOneWidget);
    expect(find.text('Capacity'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
    expect(find.text('Registered Count'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Registration Status'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Asia/Kolkata'), findsOneWidget);
    expect(find.text('Speakers will be announced soon.'), findsOneWidget);
    expect(find.textContaining('meet.google'), findsNothing);
  });

  testWidgets('shows virtual Online detail and speaker list', (tester) async {
    await tester.pumpWidget(
      _app(
        EventDetailScreen(
          eventId: 7,
          eventService: _CallbackDetailService((_) async => _virtualEvent),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Virtual Alumni Forum'), findsOneWidget);
    expect(find.text('Virtual'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Ada Alumni'), findsOneWidget);
    expect(find.text('CTO'), findsOneWidget);
    expect(find.textContaining('meet.google'), findsNothing);
  });

  testWidgets('unauthenticated Register requests login', (tester) async {
    var loginRequested = false;
    await tester.pumpWidget(
      _app(
        EventDetailScreen(
          eventId: 6,
          eventService: _CallbackDetailService((_) async => _physicalEvent),
          isAuthenticated: () => false,
          onLoginRequired: () => loginRequested = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Register'));
    await tester.tap(find.text('Register'));
    expect(loginRequested, isTrue);
  });

  testWidgets('authenticated Register shows Week 3 message', (tester) async {
    await tester.pumpWidget(
      _app(
        EventDetailScreen(
          eventId: 6,
          eventService: _CallbackDetailService((_) async => _physicalEvent),
          isAuthenticated: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Register'));
    await tester.tap(find.text('Register'));
    await tester.pump();
    expect(
      find.text('Registration will be available in Week 3.'),
      findsOneWidget,
    );
  });

  testWidgets('shows error, retries, and then loads event', (tester) async {
    var fail = true;
    final service = _CallbackDetailService((_) async {
      if (fail) throw Exception('network error');
      return _physicalEvent;
    });
    await tester.pumpWidget(
      _app(EventDetailScreen(eventId: 6, eventService: service)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load event'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Innovation Summit'), findsOneWidget);
  });

  testWidgets('shows not found state for a 404', (tester) async {
    final options = RequestOptions(path: '/api/v1/events/public/999');
    await tester.pumpWidget(
      _app(
        EventDetailScreen(
          eventId: 999,
          eventService: _CallbackDetailService(
            (_) async => throw DioException(
              requestOptions: options,
              response: Response<void>(
                requestOptions: options,
                statusCode: 404,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Event not found'), findsOneWidget);
    expect(
      find.text('This event is unavailable or no longer published.'),
      findsOneWidget,
    );
  });
}

Widget _app(Widget child) => MaterialApp(home: child);

class _CallbackDetailService implements PublicEventDetailService {
  _CallbackDetailService(this.callback);

  final Future<PublicEventDetail> Function(int eventId) callback;

  @override
  Future<PublicEventDetail> getEvent(int eventId) => callback(eventId);
}

final _physicalEvent = PublicEventDetail(
  eventId: 6,
  slug: 'innovation-summit',
  title: 'Innovation Summit',
  tagline: 'Build the future',
  description: 'A summit for NITK alumni.',
  status: 'published',
  startDateTime: DateTime.utc(2026, 6, 19, 11),
  endDateTime: DateTime.utc(2026, 6, 19, 13),
  timezone: 'Asia/Kolkata',
  locationText: 'Chennai Convention Centre',
  isVirtual: false,
  capacity: 200,
  registeredCount: 4,
  registrationStatus: 'open',
);

final _virtualEvent = PublicEventDetail(
  eventId: 7,
  slug: 'virtual-alumni-forum',
  title: 'Virtual Alumni Forum',
  description: 'An online alumni forum.',
  status: 'published',
  startDateTime: DateTime.utc(2026, 6, 20, 11),
  endDateTime: DateTime.utc(2026, 6, 20, 12),
  timezone: 'UTC',
  isVirtual: true,
  capacity: 100,
  registeredCount: 10,
  registrationStatus: 'open',
  speakers: const [PublicEventSpeaker(name: 'Ada Alumni', title: 'CTO')],
);
