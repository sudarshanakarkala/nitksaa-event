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

const _sessionExpired = 'Your session has expired. Please sign in again.';
const _paymentUnconfirmed =
    'We couldn\'t confirm this payment. Please check the event page in a few '
    'minutes before paying again.';
const _paymentServiceDown =
    'The payment service isn\'t responding. Please try again in a few minutes.';
const _notPayable =
    'This registration can\'t be paid for now. Please refresh the event page.';

/// Backend codes with their own plain-words message.
const _codeMessages = <String, String>{
  'name_required': 'Please enter your name.',
  'phone_required': 'Please enter a phone number we can reach you on.',
  'phone_invalid': 'Please enter a valid phone number.',
  'not_enough_seats':
      'There aren\'t enough seats left for everyone. Remove a guest to continue.',
  'event_full': 'The event is full.',
  'too_many_guests': 'This event allows fewer guests. Remove a guest to continue.',
  'guest_name_required': 'Please enter a name for each guest.',
  // Registering (registration_service.py).
  'already_registered': 'You\'re already registered for this event.',
  'registration_closed': 'Registration for this event has closed.',
  'registration_not_open_yet': 'Registration for this event hasn\'t opened yet.',
  'event_not_published': 'This event isn\'t open for registration.',
  'event_not_found': 'We couldn\'t find this event.',
  'payment_not_configured':
      'Payment isn\'t set up for this event yet. Please try again later.',
  'registration_not_found':
      'We couldn\'t find this registration. Please refresh and try again.',
  // Paying (payment_service.py).
  'payment_attempt_active':
      'A payment for this registration is already in progress. Please wait a '
          'few minutes and try again.',
  'payment_order_creation_conflict':
      'A payment for this registration is already being set up. Please wait a '
          'moment and try again.',
  'payment_verification_in_progress':
      'We\'re confirming your payment. Please check the event page in a few '
          'minutes.',
  'payment_already_completed': 'This registration is already paid for.',
  'seat_hold_expired':
      'The time to pay for your seat ran out. Please register again.',
  'payment_order_expired':
      'This payment has expired. Please start again from the event page.',
  'registration_not_payable': _notPayable,
  'payment_order_not_payable': _notPayable,
  'payment_gateway_error': _paymentServiceDown,
  'payment_gateway_unavailable': _paymentServiceDown,
  'checkout_signature_invalid': _paymentUnconfirmed,
  'checkout_order_mismatch': _paymentUnconfirmed,
  'checkout_amount_mismatch': _paymentUnconfirmed,
  // Signed-in session (middleware/auth.py; FastAPI's own for no token).
  'invalid_or_expired_token': _sessionExpired,
  'invalid_token': _sessionExpired,
  'firebase_token_expired': _sessionExpired,
  'invalid_firebase_token': _sessionExpired,
  'Not authenticated': _sessionExpired,
  'account_suspended':
      'Your account is currently suspended. Please contact support if you '
          'believe this is an error.',
};

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
    final known = _codeMessages[text];
    if (known != null) return known;
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
