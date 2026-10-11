// apiErrorMessage turns a failed API call into a message an admin can act
// on, instead of showing `DioException [bad response]: …` on screen.

import 'package:dio/dio.dart';
import 'package:event_app/core/errors/api_error_message.dart';
import 'package:flutter_test/flutter_test.dart';

final _request = RequestOptions(path: '/x');

DioException _badResponse(int status, Object? data) => DioException(
      requestOptions: _request,
      response: Response<Object?>(
        requestOptions: _request,
        statusCode: status,
        data: data,
      ),
      type: DioExceptionType.badResponse,
    );

void main() {
  group('apiErrorMessage', () {
    test('missing publish fields become a labelled list', () {
      final error = _badResponse(422, {
        'detail': 'missing_fields_for_publish: capacity, description, virtual_url',
      });
      expect(
        apiErrorMessage(error, action: 'publish the event'),
        "Can't publish yet. Please fill in: Capacity, Description, Meeting URL.",
      );
    });

    test('a single missing field', () {
      final error = _badResponse(422, {'detail': 'missing_fields_for_publish: capacity'});
      expect(
        apiErrorMessage(error, action: 'publish the event'),
        "Can't publish yet. Please fill in: Capacity.",
      );
    });

    test('an unknown missing field key is humanised', () {
      final error = _badResponse(422, {'detail': 'missing_fields_for_publish: banner_url'});
      expect(
        apiErrorMessage(error, action: 'publish the event'),
        "Can't publish yet. Please fill in: Banner url.",
      );
    });

    test('a plain string detail has underscores replaced', () {
      final error = _badResponse(409, {
        'detail': 'invalid_status_transition_published_to_published',
      });
      expect(
        apiErrorMessage(error, action: 'publish the event'),
        'Could not publish the event: invalid status transition published to published.',
      );
    });

    test('a FastAPI validation list names the field', () {
      final error = _badResponse(422, {
        'detail': [
          {
            'loc': ['body', 'capacity'],
            'msg': 'Input should be greater than 0',
            'type': 'greater_than',
          },
        ],
      });
      expect(
        apiErrorMessage(error, action: 'save the event'),
        'Could not save the event: Capacity: Input should be greater than 0.',
      );
    });

    test('a FastAPI validation list is capped at three items', () {
      final item = {
        'loc': ['body', 'title'],
        'msg': 'Field required',
      };
      final error = _badResponse(422, {
        'detail': [item, item, item, item],
      });
      expect(
        apiErrorMessage(error, action: 'save the event'),
        'Could not save the event: Title: Field required; Title: Field required; '
        'Title: Field required.',
      );
    });

    test('an {errors: [...]} detail is joined', () {
      final error = _badResponse(400, {
        'detail': {
          'errors': ['Ticket price is required', 'Currency must be INR'],
        },
      });
      expect(
        apiErrorMessage(error, action: 'save the event'),
        'Could not save the event: Ticket price is required; Currency must be INR.',
      );
    });

    test('no detail falls back to the HTTP status', () {
      final error = _badResponse(500, '<html>Internal Server Error</html>');
      expect(
        apiErrorMessage(error, action: 'delete the event'),
        'Could not delete the event (HTTP 500). Please try again.',
      );
    });

    test('an empty detail falls back to the HTTP status', () {
      final error = _badResponse(404, {'detail': ''});
      expect(
        apiErrorMessage(error, action: 'load events'),
        'Could not load events (HTTP 404). Please try again.',
      );
    });

    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
      DioExceptionType.badCertificate,
    ]) {
      test('$type is a connection message', () {
        final error = DioException(requestOptions: _request, type: type);
        expect(
          apiErrorMessage(error, action: 'load events'),
          'Could not reach the server. Check your connection and try again.',
        );
      });
    }

    test('an unknown Dio error with no response has no status', () {
      final error = DioException(requestOptions: _request, type: DioExceptionType.unknown);
      expect(
        apiErrorMessage(error, action: 'load registrations'),
        'Could not load registrations. Please try again.',
      );
    });

    test('a non-Dio error is generic and hides its text', () {
      final message = apiErrorMessage(
        StateError('secret internals'),
        action: 'unpublish the event',
      );
      expect(message, 'Could not unpublish the event. Please try again.');
      expect(message, isNot(contains('secret')));
    });
  });
}
