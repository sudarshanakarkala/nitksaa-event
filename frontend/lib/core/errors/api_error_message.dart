import 'package:dio/dio.dart';

/// Labels for backend field keys, as the admin sees them in the event form.
const _fieldLabels = <String, String>{
  'title': 'Title',
  'description': 'Description',
  'start_datetime': 'Start date/time',
  'end_datetime': 'End date/time',
  'timezone': 'Timezone',
  'capacity': 'Capacity',
  'location_text': 'Location',
  'virtual_url': 'Meeting URL',
};

const _missingFieldsPrefix = 'missing_fields_for_publish:';

/// A user-facing message for a failed API call.
///
/// [action] is a short phrase such as 'publish the event'. The message never
/// contains `error.toString()` or a stack trace; log the raw error separately.
String apiErrorMessage(Object error, {required String action}) {
  if (error is! DioException) {
    return 'Could not $action. Please try again.';
  }

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
    case DioExceptionType.connectionError:
    case DioExceptionType.badCertificate:
      return 'Could not reach the server. Check your connection and try again.';
    case DioExceptionType.badResponse:
      final fromDetail = _messageFromDetail(error.response?.data, action);
      if (fromDetail != null) return fromDetail;
      break;
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      break;
  }

  final status = error.response?.statusCode;
  final httpPart = status != null ? ' (HTTP $status)' : '';
  return 'Could not $action$httpPart. Please try again.';
}

String? _messageFromDetail(Object? data, String action) {
  if (data is! Map) return null;
  final detail = data['detail'];

  if (detail is String) {
    final text = detail.trim();
    if (text.isEmpty) return null;
    if (text.startsWith(_missingFieldsPrefix)) {
      final labels = text
          .substring(_missingFieldsPrefix.length)
          .split(',')
          .map((key) => key.trim())
          .where((key) => key.isNotEmpty)
          .map(fieldLabel)
          .toList();
      if (labels.isNotEmpty) {
        return "Can't publish yet. Please fill in: ${labels.join(', ')}.";
      }
    }
    return 'Could not $action: ${text.replaceAll('_', ' ')}.';
  }

  if (detail is List) {
    final parts = detail.take(3).map(_validationItem).whereType<String>().toList();
    if (parts.isEmpty) return null;
    return 'Could not $action: ${parts.join('; ')}.';
  }

  if (detail is Map && detail['errors'] is List) {
    final errors = (detail['errors'] as List)
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    if (errors.isEmpty) return null;
    return 'Could not $action: ${errors.join('; ')}.';
  }

  return null;
}

/// One FastAPI validation item, e.g. `Capacity: Input should be greater than 0`.
String? _validationItem(Object? item) {
  if (item is! Map) return null;
  final msg = item['msg']?.toString().trim() ?? '';
  if (msg.isEmpty) return null;
  final loc = item['loc'];
  if (loc is List && loc.isNotEmpty) {
    // Skip the leading 'body' / 'query' / 'path' segment.
    final field = loc.last;
    if (field is String && !const {'body', 'query', 'path'}.contains(field)) {
      return '${fieldLabel(field)}: $msg';
    }
  }
  return msg;
}

/// The form label for a backend field key; unknown keys get `_` → space and
/// a capital first letter.
String fieldLabel(String key) {
  final known = _fieldLabels[key];
  if (known != null) return known;
  final spaced = key.replaceAll('_', ' ').trim();
  if (spaced.isEmpty) return key;
  return spaced[0].toUpperCase() + spaced.substring(1);
}
