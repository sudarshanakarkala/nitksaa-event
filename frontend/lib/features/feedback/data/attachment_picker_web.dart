import 'dart:async';
import 'dart:js_interop';

import 'feedback_attachment.dart';

@JS('document.createElement')
external _Input _createInput(JSString tag);

@JS('document.body.appendChild')
external void _appendToBody(JSObject element);

extension type _Input._(JSObject _) implements JSObject {
  external set type(JSString value);
  external set accept(JSString value);
  external set multiple(bool value);
  external _FileList? get files;
  external _Style get style;
  external void click();
  external void remove();
  external void addEventListener(JSString type, JSFunction listener);
}

extension type _Style._(JSObject _) implements JSObject {
  external set display(JSString value);
}

extension type _FileList._(JSObject _) implements JSObject {
  external int get length;
  external _File? item(int index);
}

extension type _File._(JSObject _) implements JSObject {
  external JSString get name;
  external JSString get type;
  external double get size;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

Future<List<PickedFile>> pickFiles() {
  final done = Completer<List<PickedFile>>();
  final input = _createInput('input'.toJS)
    ..type = 'file'.toJS
    ..accept = 'image/*,video/*,.heic,.heif'.toJS
    ..multiple = true;
  // Kept in the page while open: some phone browsers only report the
  // choice for an input that is in the document.
  input.style.display = 'none'.toJS;
  _appendToBody(input);

  void finish(List<PickedFile> files) {
    if (done.isCompleted) return;
    input.remove();
    done.complete(files);
  }

  input.addEventListener(
    'change'.toJS,
    ((JSAny? _) {
      final list = input.files;
      final files = <PickedFile>[];
      for (var i = 0; i < (list?.length ?? 0); i++) {
        final file = list!.item(i);
        if (file == null) continue;
        files.add(PickedFile(
          name: file.name.toDart,
          mimeType: file.type.toDart,
          size: file.size.toInt(),
          read: () async =>
              (await file.arrayBuffer().toDart).toDart.asUint8List(),
        ));
      }
      finish(files);
    }).toJS,
  );
  // Closing the chooser without a choice (browsers that report it).
  input.addEventListener('cancel'.toJS, ((JSAny? _) => finish(const [])).toJS);

  input.click();
  return done.future;
}
