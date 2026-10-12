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

  group('applyGrid', () {
    final columns = <GridColumn<AdminRegistration>>[
      GridColumn(id: 'number', label: 'No.', kind: ColumnKind.text, value: (r) => r.registrationNumber),
      GridColumn(id: 'name', label: 'Name', kind: ColumnKind.text, value: (r) => r.displayName),
      GridColumn(id: 'batch', label: 'Batch', kind: ColumnKind.category, value: (r) => r.batchYear),
      GridColumn(id: 'branch', label: 'Branch', kind: ColumnKind.category, value: (r) => r.branch),
      GridColumn(id: 'email', label: 'Email', kind: ColumnKind.text, value: (r) => r.email),
      GridColumn(id: 'phone', label: 'Phone', kind: ColumnKind.text, value: (r) => r.phone),
      GridColumn(id: 'registered', label: 'Registered', kind: ColumnKind.date, value: (r) => r.registeredAt),
    ];
    final rows = [
      _reg(1, name: 'charlie', email: 'c@example.com', phone: '+91 98450 11111', batch: 1998, branch: 'CSE'),
      _reg(2, name: 'Alice', email: 'a@example.com', batch: 2005, branch: 'ECE'),
      _reg(3, name: null, email: 'bob@example.com', batch: null, branch: 'ECE'),
    ];

    List<int> ids(List<AdminRegistration> r) => [for (final x in r) x.registrationId];

    test('search matches name, email, phone or registration number', () {
      expect(ids(applyGrid(rows, columns, search: 'ALICE')), [2]);
      expect(ids(applyGrid(rows, columns, search: 'bob@')), [3]);
      expect(ids(applyGrid(rows, columns, search: '98450')), [1]);
      expect(ids(applyGrid(rows, columns, search: 'reg-3')), [3]);
      expect(ids(applyGrid(rows, columns, search: '  ')), [1, 2, 3]);
    });

    test('column filters combine with each other and the search', () {
      expect(
        ids(applyGrid(rows, columns, filters: {'branch': const ColumnFilter(values: {'ECE'})})),
        [2, 3],
      );
      expect(
        ids(applyGrid(rows, columns, filters: {
          'branch': const ColumnFilter(values: {'ECE'}),
          'batch': const ColumnFilter(values: {'2005'}),
        })),
        [2],
      );
      expect(
        ids(applyGrid(rows, columns, filters: {'batch': const ColumnFilter(values: {''})})),
        [3],
      );
      expect(
        ids(applyGrid(rows, columns, filters: {'name': const ColumnFilter(query: 'li')})),
        [1, 2],
      );
      expect(
        ids(applyGrid(rows, columns, search: 'charlie', filters: {'branch': const ColumnFilter(values: {'ECE'})})),
        isEmpty,
      );
    });

    test('every column sorts; text ignores case and blanks go last', () {
      expect(ids(applyGrid(rows, columns, sortId: 'name', ascending: true)), [2, 3, 1]);
      expect(ids(applyGrid(rows, columns, sortId: 'batch', ascending: true)), [1, 2, 3]);
      expect(ids(applyGrid(rows, columns, sortId: 'batch', ascending: false)), [2, 1, 3]);
      expect(ids(applyGrid(rows, columns, sortId: 'phone', ascending: true)), [1, 2, 3]);
      expect(ids(applyGrid(rows, columns, sortId: 'registered', ascending: false)), [3, 2, 1]);
      expect(ids(applyGrid(rows, columns, sortId: 'branch', ascending: true)), [1, 2, 3]);
    });

    test('does not change the list it is given', () {
      applyGrid(rows, columns, sortId: 'name', ascending: true);
      expect(ids(rows), [1, 2, 3]);
    });

    test('tick-list values come from the rows, in sort order, blank included', () {
      expect(distinctValues(rows, columns[2]), ['1998', '2005', '']);
      expect(distinctValues(rows, columns[3]), ['CSE', 'ECE']);
    });

    test('a year range keeps batches inside it and drops blanks', () {
      expect(
        ids(applyGrid(rows, columns, filters: {'batch': const ColumnFilter(from: 1990, to: 1999)})),
        [1],
      );
      expect(
        ids(applyGrid(rows, columns, filters: {'batch': const ColumnFilter(from: 2000)})),
        [2],
      );
      expect(
        ids(applyGrid(rows, columns, filters: {'batch': const ColumnFilter(to: 2010)})),
        [1, 2],
      );
    });

    test('decades come from the batch years present', () {
      expect(decadesOf([1998, 2005, null, 2009, 1971]), [1970, 1990, 2000]);
    });

    test('a person without a name shows their email', () {
      expect(rows[2].displayName, 'bob@example.com');
    });
  });

  test('confirmation-email statuses read as plain words', () {
    expect(confirmationEmailLabel('sent'), 'Sent');
    expect(confirmationEmailLabel('failed'), 'Failed');
    expect(confirmationEmailLabel('pending'), 'Pending');
    expect(confirmationEmailLabel(null), '');
    expect(confirmationEmailLabel('not_required'), 'Not required');
  });
}
