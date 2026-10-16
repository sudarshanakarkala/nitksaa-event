// Attachments on the feedback form (FEEDBACK_ATTACHMENTS.md).
//
// - The form's own checks: allowed types, up to 3 files, 15 MB in total.
// - Attach shows each file with its name and size; ✕ removes it.
// - The files go to the API, with "Sending… n%" while they upload.
// - A server refusal of the files is shown in plain words, not as the
//   "please email us" box, and the files stay on the form.
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:event_app/features/auth/services/auth_controller.dart';
import 'package:event_app/features/feedback/data/attachment_picker.dart';
import 'package:event_app/features/feedback/data/feedback_api.dart';
import 'package:event_app/features/feedback/data/feedback_attachment.dart';
import 'package:event_app/features/feedback/feedback_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../events/support/auth_isolation_fakes.dart';

const _mb = 1024 * 1024;

PickedFile _picked(String name, String mimeType, int size) => PickedFile(
      name: name,
      mimeType: mimeType,
      size: size,
      read: () async => Uint8List(size),
    );

FeedbackAttachment _attached(String name, int size) =>
    FeedbackAttachment(name: name, mimeType: 'image/png', bytes: Uint8List(size));

class _FakePicker implements AttachmentPicker {
  List<PickedFile> next = const [];

  @override
  Future<List<PickedFile>> pick() async => next;
}

class _Sent {
  _Sent(this.message, this.attachments);
  final String message;
  final List<FeedbackAttachment> attachments;
}

class _FakeApi extends FeedbackApi {
  final sent = <_Sent>[];

  /// When set, submit waits for it (to see the progress) or throws it.
  Completer<void>? pending;
  Object? error;

  @override
  Future<void> submit({
    required String accessToken,
    required String area,
    required String category,
    required String message,
    List<FeedbackAttachment> attachments = const [],
    void Function(int sent, int total)? onSendProgress,
  }) async {
    sent.add(_Sent(message, attachments));
    onSendProgress?.call(50, 100);
    if (pending != null) await pending!.future;
    if (error != null) throw error!;
  }
}

DioException _refusal(int status, String detail) {
  final options = RequestOptions(path: '/api/v1/feedback');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: options,
      statusCode: status,
      data: {'detail': detail},
    ),
  );
}

Future<void> _open(WidgetTester tester, _FakeApi api, _FakePicker picker) async {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = FakeAuthController()..logIn(sessionA);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authControllerProvider.overrideWith((ref) => auth)],
      child: MaterialApp(home: FeedbackScreen(api: api, picker: picker)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'The QR badge does not show.');
  await tester.pump();
}

final _attach = find.byKey(const ValueKey('feedback-attach'));
final _fileMessage = find.byKey(const ValueKey('feedback-file-message'));

Future<void> _pick(WidgetTester tester, _FakePicker picker, List<PickedFile> files) async {
  picker.next = files;
  await tester.tap(_attach);
  await tester.pumpAndSettle();
}

void main() {
  group('checkPickedFiles', () {
    test('accepts images and videos by name or type', () {
      final check = checkPickedFiles([], [
        _picked('shot.PNG', '', 100),
        _picked('clip', 'video/quicktime', 100),
        _picked('IMG_0001.heic', '', 100),
      ]);
      expect(check.accepted, hasLength(3));
      expect(check.message, isNull);
    });

    test('refuses other types', () {
      final check = checkPickedFiles([], [_picked('report.pdf', 'application/pdf', 10)]);
      expect(check.accepted, isEmpty);
      expect(check.message, attachmentTypeMessage);
    });

    test('takes up to 3 files in all', () {
      final check = checkPickedFiles(
        [_attached('a.png', 10), _attached('b.png', 10)],
        [_picked('c.png', 'image/png', 10), _picked('d.png', 'image/png', 10)],
      );
      expect(check.accepted.map((f) => f.name), ['c.png']);
      expect(check.message, attachmentTooManyMessage);
    });

    test('takes up to 15 MB in total', () {
      final check = checkPickedFiles(
        [_attached('a.png', 10 * _mb)],
        [
          _picked('big.mp4', 'video/mp4', 6 * _mb),
          _picked('small.png', 'image/png', 5 * _mb),
        ],
      );
      expect(check.accepted.map((f) => f.name), ['small.png']);
      expect(check.message, attachmentTooLargeMessage);
    });

    test('formatFileSize', () {
      expect(formatFileSize(10), '1 KB');
      expect(formatFileSize(820 * 1024), '820 KB');
      expect(formatFileSize((4.2 * _mb).round()), '4.2 MB');
    });
  });

  testWidgets('attach shows the file with its size, and ✕ removes it',
      (tester) async {
    final api = _FakeApi();
    final picker = _FakePicker();
    await _open(tester, api, picker);

    expect(find.text('Attach screenshots or a video'), findsOneWidget);
    await _pick(tester, picker, [_picked('screenshot.png', 'image/png', 820 * 1024)]);
    expect(find.text('screenshot.png'), findsOneWidget);
    expect(find.text('820 KB'), findsOneWidget);
    expect(find.text('Attach another file'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove screenshot.png'));
    await tester.pumpAndSettle();
    expect(find.text('screenshot.png'), findsNothing);
  });

  testWidgets('a wrong type or too much is refused before sending',
      (tester) async {
    final api = _FakeApi();
    final picker = _FakePicker();
    await _open(tester, api, picker);

    await _pick(tester, picker, [_picked('report.pdf', 'application/pdf', 1000)]);
    expect(find.text('report.pdf'), findsNothing);
    expect(tester.widget<Text>(_fileMessage).data, attachmentTypeMessage);

    await _pick(tester, picker, [_picked('long.mov', 'video/quicktime', 16 * _mb)]);
    expect(find.text('long.mov'), findsNothing);
    expect(tester.widget<Text>(_fileMessage).data, attachmentTooLargeMessage);
    expect(api.sent, isEmpty);
  });

  testWidgets('the Attach button goes once 3 files are attached', (tester) async {
    final picker = _FakePicker();
    await _open(tester, _FakeApi(), picker);
    await _pick(tester, picker, [
      for (final n in ['a', 'b', 'c']) _picked('$n.png', 'image/png', 1000),
    ]);
    expect(_attach, findsNothing);
  });

  testWidgets('files are sent, with the upload progress', (tester) async {
    final api = _FakeApi()..pending = Completer<void>();
    final picker = _FakePicker();
    await _open(tester, api, picker);
    await _pick(tester, picker, [_picked('screenshot.png', 'image/png', 2000)]);

    await tester.tap(find.text('Send feedback'));
    await tester.pump();
    expect(find.text('Sending… 50%'), findsOneWidget);
    expect(api.sent.single.message, 'The QR badge does not show.');
    expect(api.sent.single.attachments.single.name, 'screenshot.png');
    expect(api.sent.single.attachments.single.bytes, hasLength(2000));

    api.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Thanks — feedback received'), findsOneWidget);
  });

  testWidgets('a server refusal of the files is shown plainly; files stay',
      (tester) async {
    final api = _FakeApi()..error = _refusal(400, 'attachment_type_not_allowed');
    final picker = _FakePicker();
    await _open(tester, api, picker);
    await _pick(tester, picker, [_picked('screenshot.png', 'image/png', 2000)]);

    await tester.tap(find.text('Send feedback'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(_fileMessage).data,
      'Only images and videos (PNG, JPG, WebP, GIF, HEIC, MP4, WebM, MOV).',
    );
    expect(find.textContaining('please email us'), findsNothing);
    expect(find.text('screenshot.png'), findsOneWidget);
  });

  testWidgets('a request too big for the server reads as the size limit',
      (tester) async {
    final api = _FakeApi()..error = _refusal(413, '');
    final picker = _FakePicker();
    await _open(tester, api, picker);
    await _pick(tester, picker, [_picked('clip.mp4', 'video/mp4', 2000)]);

    await tester.tap(find.text('Send feedback'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_fileMessage).data, attachmentTooLargeMessage);
  });

  testWidgets('a failed send keeps the files for Try again', (tester) async {
    final api = _FakeApi()..error = _refusal(502, 'feedback_send_failed');
    final picker = _FakePicker();
    await _open(tester, api, picker);
    await _pick(tester, picker, [_picked('screenshot.png', 'image/png', 2000)]);

    await tester.tap(find.text('Send feedback'));
    await tester.pumpAndSettle();
    expect(find.textContaining('please email us'), findsOneWidget);
    expect(find.text('screenshot.png'), findsOneWidget);
  });
}
