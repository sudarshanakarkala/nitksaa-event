import 'dart:typed_data';

/// Screenshots and short recordings on the feedback form.
///
/// The limits match the server (`backend/app/api/feedback.py`): up to 3
/// files, 15 MB in total, images and videos only. The server checks again,
/// from the files' own bytes.
const maxFeedbackAttachments = 3;
const maxFeedbackAttachmentBytes = 15 * 1024 * 1024;

const attachmentTooManyMessage = 'You can attach up to 3 files.';
const attachmentTooLargeMessage = 'Files can be up to 15 MB in total.';
const attachmentTypeMessage =
    'Only images and videos (PNG, JPG, WebP, GIF, HEIC, MP4, WebM, MOV).';
const attachmentUnreadableMessage =
    'That file couldn\'t be read. Please try another.';

const _extensions = {
  'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic', 'heif', //
  'mp4', 'm4v', 'webm', 'mov',
};

const _mimeTypes = {
  'image/png', 'image/jpeg', 'image/webp', 'image/gif', 'image/heic',
  'image/heif', 'video/mp4', 'video/webm', 'video/quicktime', //
};

/// A file the person chose, before it is read.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.mimeType,
    required this.size,
    required this.read,
  });

  final String name;
  final String mimeType;
  final int size;
  final Future<Uint8List> Function() read;
}

/// A file read and ready to send.
class FeedbackAttachment {
  const FeedbackAttachment({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;

  int get size => bytes.length;
  bool get isVideo =>
      mimeType.startsWith('video/') ||
      const {'mp4', 'm4v', 'webm', 'mov'}.contains(_extension(name));
}

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Whether the file looks like an allowed image or video, by its name or
/// the type the browser gave it.
bool isAllowedAttachmentType(String name, String mimeType) =>
    _extensions.contains(_extension(name)) ||
    _mimeTypes.contains(mimeType.toLowerCase());

/// The outcome of checking newly picked files against the ones already
/// attached: the files that fit, in order, and a message about the first
/// one that didn't (null if all fit).
class AttachmentCheck {
  const AttachmentCheck(this.accepted, this.message);

  final List<PickedFile> accepted;
  final String? message;
}

AttachmentCheck checkPickedFiles(
  List<FeedbackAttachment> current,
  List<PickedFile> picked,
) {
  final accepted = <PickedFile>[];
  var count = current.length;
  var total = current.fold<int>(0, (sum, a) => sum + a.size);
  String? message;
  for (final file in picked) {
    String? problem;
    if (!isAllowedAttachmentType(file.name, file.mimeType)) {
      problem = attachmentTypeMessage;
    } else if (count >= maxFeedbackAttachments) {
      problem = attachmentTooManyMessage;
    } else if (total + file.size > maxFeedbackAttachmentBytes) {
      problem = attachmentTooLargeMessage;
    }
    if (problem != null) {
      message ??= problem;
      continue;
    }
    accepted.add(file);
    count++;
    total += file.size;
  }
  return AttachmentCheck(accepted, message);
}

/// "820 KB", "4.2 MB".
String formatFileSize(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  final kb = (bytes / 1024).round();
  return '${kb < 1 ? 1 : kb} KB';
}
