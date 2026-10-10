// Guard for ISSUE-004: nothing in the app can send the old
// `DELETE /api/v1/events/{event_id}/my-registration` again. It reads the
// source files, so it runs on the VM only.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A Dio `delete` call whose path is `…/my-registration`, on one line or
/// wrapped, with or without type arguments.
final _deleteCall = RegExp(r"\.delete\b[^;(]*\(\s*'[^']*my-registration");

/// The same request written out, as in an endpoint list or a comment.
final _deleteWording = RegExp(r'DELETE[^\n]{0,80}my-registration');

void main() {
  final sources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();

  test('lib/ is being read', () {
    expect(sources.length, greaterThan(20));
  });

  test('Test B: no file in lib/ sends or names DELETE …/my-registration', () {
    final offenders = [
      for (final file in sources)
        if (file.readAsStringSync() case final source
            when _deleteCall.hasMatch(source) ||
                _deleteWording.hasMatch(source) ||
                source.contains('cancelMyRegistration'))
          file.path,
    ];
    expect(offenders, isEmpty);
  });

  test('Test A: the repository cancels through POST '
      '/registrations/{id}/cancel with an idempotency key', () {
    final repository = File(
      'lib/features/events/data/events_repository.dart',
    ).readAsStringSync();
    final call = RegExp(
      r"_dio\.post<[^;]*'/api/v1/registrations/\$registrationId/cancel',\s*"
      r"data: \{'idempotency_key': idempotencyKey\}",
    );
    expect(call.hasMatch(repository), isTrue);
  });
}
