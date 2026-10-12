// Admin → Registrations: the API client (paging, the three lists, the CSV
// export) on a real Dio whose transport is a fake backend, and the search,
// filter and sort rules the tab applies.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:event_app/features/admin/data/registrations_api.dart';
import 'package:event_app/features/admin/domain/registration_filters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers each request from [routes] (path → handler) and records it.
class _FakeBackend implements HttpClientAdapter {
  _FakeBackend(this.routes);

  final Map<String, ResponseBody Function(RequestOptions)> routes;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final handler = routes[options.path];
    if (handler == null) return _json({'detail': 'not_found'}, status: 404);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Map<String, dynamic> _attendee(int id, {String? name, int? batch, String? branch}) => {
      'registration_id': id,
      'registration_number': 'REG-$id',
      'fullname_snapshot': name ?? 'Person $id',
      'email_snapshot': 'person$id@example.com',
      'phone_snapshot': '+91 90000 0000$id',
      'batch_year_snapshot': batch,
      'branch_snapshot': branch,
      'registered_at': '2026-10-0${id % 9 + 1}T10:00:00Z',
      'status': 'registered',
      'confirmation_email_status': 'sent',
    };

RegistrationsApi _api(_FakeBackend backend) {
  final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))..httpClientAdapter = backend;
  return RegistrationsApi(dio: dio);
}

AdminRegistration _reg(
  int id, {
  String? name,
  String? email,
  String? phone,
  int? batch,
  String? branch,
  DateTime? registeredAt,
  DateTime? cancelledAt,
}) =>
    AdminRegistration(
      registrationId: id,
      eventId: 1,
      status: cancelledAt == null ? 'registered' : 'cancelled',
      registeredAt: registeredAt ?? DateTime(2026, 10, id),
      registrationNumber: 'REG-$id',
      fullname: name,
      email: email,
      phone: phone,
      batchYear: batch,
      branch: branch,
      cancelledAt: cancelledAt,
    );

void main() {
  group('RegistrationsApi', () {
    test('loads every page of registered people, the cancelled list and check-ins', () async {
      final backend = _FakeBackend({
        '/api/v1/admin/events/7/attendees': (o) {
          final page = o.queryParameters['page'] as int;
          // 3 people over two pages.
          final rows = page == 1
              ? [_attendee(1, batch: 2001, branch: 'CSE'), _attendee(2)]
              : [_attendee(3)];
          return _json({'attendees': rows, 'total': 3, 'page': page, 'per_page': 2});
        },
        '/api/v1/admin/events/7/registrations': (o) => _json({
              'registrations': [
                {
                  'registration_id': 9,
                  'registration_number': 'REG-9',
                  'fullname_snapshot': 'Gone Person',
                  'email_snapshot': 'gone@example.com',
                  'status': 'cancelled',
                  'registered_at': '2026-09-01T10:00:00Z',
                  'cancelled_at': '2026-09-05T10:00:00Z',
                },
              ],
              'total': 1,
              'page': 1,
              'per_page': 200,
            }),
        '/api/v1/admin/events/7/check-ins': (o) => _json([
              {
                'checkin_id': 1,
                'event_id': 7,
                'registration_id': 1,
                'session_id': null,
                'checked_in_at': '2026-10-20T09:00:00Z',
                'checked_in_by': 'uid',
                'result': 'success',
              },
            ]),
      });

      final data = await _api(backend).loadEvent(accessToken: 't', eventId: 7);

      expect(data.registered.map((r) => r.registrationId), [1, 2, 3]);
      expect(data.registered.first.batchYear, 2001);
      expect(data.registered.first.branch, 'CSE');
      expect(data.registered.first.phone, isNotNull);
      expect(data.registered.first.confirmationEmailStatus, 'sent');
      expect(data.registered.every((r) => r.eventId == 7), isTrue);

      expect(data.cancelled.single.isCancelled, isTrue);
      expect(data.cancelled.single.cancelledAt, isNotNull);

      expect(data.checkIns.single.registrationId, 1);
      expect(data.checkIns.single.sessionId, isNull);

      final cancelledRequest = backend.requests.firstWhere(
        (r) => r.path.endsWith('/registrations'),
      );
      expect(cancelledRequest.queryParameters['status'], 'cancelled');
      expect(
        backend.requests.every((r) => r.headers['Authorization'] == 'Bearer t'),
        isTrue,
      );
    });

    test('export returns the server CSV bytes unchanged', () async {
      final csv = utf8.encode('﻿registration_number,fullname_snapshot\nREG-1,Asha\n');
      final backend = _FakeBackend({
        '/api/v1/admin/events/7/attendees/export': (o) => ResponseBody.fromBytes(
              csv,
              200,
              headers: {
                Headers.contentTypeHeader: ['text/csv; charset=utf-8'],
              },
            ),
      });

      final bytes = await _api(backend).exportCsv(accessToken: 't', eventId: 7);

      expect(bytes, csv);
    });

    test('a refusal surfaces as an error for the tab to explain', () async {
      final backend = _FakeBackend({
        '/api/v1/admin/events/8/attendees': (o) => _json({'detail': 'event_admin_required'}, status: 403),
        '/api/v1/admin/events/8/registrations': (o) => _json({'detail': 'event_admin_required'}, status: 403),
        '/api/v1/admin/events/8/check-ins': (o) => _json({'detail': 'event_admin_required'}, status: 403),
      });

      await expectLater(
        _api(backend).loadEvent(accessToken: 't', eventId: 8),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('RegistrationFilters', () {
    final rows = [
      _reg(1, name: 'Asha Rao', email: 'asha@example.com', phone: '+91 98450 11111', batch: 1998, branch: 'CSE'),
      _reg(2, name: 'Vikram Shenoy', email: 'vik@example.com', batch: 2005, branch: 'ECE'),
      _reg(3, name: null, email: 'noname@example.com', batch: 1998, branch: 'ECE'),
    ];

    test('search matches name, email, phone or registration number', () {
      expect(const RegistrationFilters(query: 'asha').apply(rows).single.registrationId, 1);
      expect(const RegistrationFilters(query: 'VIK@').apply(rows).single.registrationId, 2);
      expect(const RegistrationFilters(query: '98450').apply(rows).single.registrationId, 1);
      expect(const RegistrationFilters(query: 'reg-3').apply(rows).single.registrationId, 3);
      expect(const RegistrationFilters(query: '  ').apply(rows), hasLength(3));
    });

    test('batch and branch combine with the search', () {
      expect(const RegistrationFilters(batchYear: 1998).apply(rows).map((r) => r.registrationId), [1, 3]);
      expect(
        const RegistrationFilters(batchYear: 1998, branch: 'ECE').apply(rows).single.registrationId,
        3,
      );
      expect(const RegistrationFilters(query: 'asha', branch: 'ECE').apply(rows), isEmpty);
      expect(const RegistrationFilters().isEmpty, isTrue);
      expect(const RegistrationFilters(branch: 'CSE').isEmpty, isFalse);
    });

    test('filter choices come from the loaded rows', () {
      expect(batchYearsIn(rows), [2005, 1998]);
      expect(branchesIn(rows), ['CSE', 'ECE']);
    });

    test('a person without a name shows their email', () {
      expect(rows[2].displayName, 'noname@example.com');
    });
  });

  group('sortRegistrations', () {
    final rows = [
      _reg(1, name: 'charlie', batch: 2001, cancelledAt: DateTime(2026, 9, 3)),
      _reg(2, name: 'Alice', batch: null, cancelledAt: DateTime(2026, 9, 1)),
      _reg(3, name: 'bob', batch: 1999, cancelledAt: null),
    ];

    test('names sort A–Z ignoring case', () {
      final sorted = sortRegistrations(rows, RegistrationSort.name, ascending: true);
      expect(sorted.map((r) => r.fullname), ['Alice', 'bob', 'charlie']);
    });

    test('newest registration first when descending', () {
      final sorted = sortRegistrations(rows, RegistrationSort.registeredAt, ascending: false);
      expect(sorted.map((r) => r.registrationId), [3, 2, 1]);
    });

    test('missing values go last either way', () {
      final up = sortRegistrations(rows, RegistrationSort.batch, ascending: true);
      final down = sortRegistrations(rows, RegistrationSort.batch, ascending: false);
      expect(up.map((r) => r.registrationId), [3, 1, 2]);
      expect(down.map((r) => r.registrationId), [1, 3, 2]);

      final cancelled = sortRegistrations(rows, RegistrationSort.cancelledAt, ascending: true);
      expect(cancelled.last.registrationId, 3);
    });

    test('does not change the list it is given', () {
      sortRegistrations(rows, RegistrationSort.name, ascending: true);
      expect(rows.map((r) => r.registrationId), [1, 2, 3]);
    });
  });

  test('confirmation-email statuses read as plain words', () {
    expect(confirmationEmailLabel('sent'), 'Sent');
    expect(confirmationEmailLabel('failed'), 'Failed');
    expect(confirmationEmailLabel('pending'), 'Pending');
    expect(confirmationEmailLabel(null), '—');
    expect(confirmationEmailLabel('not_required'), 'Not required');
  });
}
