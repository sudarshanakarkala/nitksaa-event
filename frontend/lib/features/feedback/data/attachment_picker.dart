/// Opens the browser's own file chooser for the feedback form.
///
/// Images and videos, several at once. On phones the chooser also offers the
/// camera and the photo library. Off the web (tests) it returns no files.
library;

import 'attachment_picker_platform.dart' as platform;
import 'feedback_attachment.dart';

class AttachmentPicker {
  const AttachmentPicker();

  /// The files chosen, or an empty list if the chooser was closed. Call it
  /// straight from a tap, or the browser may block the chooser.
  Future<List<PickedFile>> pick() => platform.pickFiles();
}
