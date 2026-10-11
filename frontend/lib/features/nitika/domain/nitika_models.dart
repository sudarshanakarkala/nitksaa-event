/// NITiKa's chat contract, as passed through by the events backend
/// (service design §3). Parsing is tolerant: unknown fields are ignored and
/// missing ones fall back to empty values.
library;

enum ChatRole { user, assistant }

/// One turn of history sent with a message.
class ChatTurn {
  const ChatTurn({required this.role, required this.text});

  final ChatRole role;
  final String text;

  Map<String, dynamic> toJson() => {'role': role.name, 'text': text};
}

/// Where the user is, so "this event" can be resolved.
class NitikaPageContext {
  const NitikaPageContext({required this.page, this.eventId});

  /// The event id from `/events/:id`, `/events/:id/checkout` and
  /// `/admin/events/:id/registrations`; null on every other page.
  factory NitikaPageContext.fromLocation(String location) {
    for (final pattern in _eventPages) {
      final match = pattern.firstMatch(location);
      if (match != null) {
        return NitikaPageContext(
          page: location,
          eventId: int.tryParse(match.group(1)!),
        );
      }
    }
    return NitikaPageContext(page: location);
  }

  static final _eventPages = [
    RegExp(r'^/events/(\d+)(?:/checkout)?/?$'),
    RegExp(r'^/admin/events/(\d+)/registrations/?$'),
  ];

  final String page;
  final int? eventId;

  Map<String, dynamic> toJson() => {
    'page': page,
    if (eventId != null) 'event_id': eventId,
  };
}

class NitikaLink {
  const NitikaLink({required this.label, required this.path});

  final String label;
  final String path;

  static NitikaLink? tryParse(Object? json) {
    if (json is! Map) return null;
    final label = json['label']?.toString() ?? '';
    final path = json['path']?.toString() ?? '';
    if (label.isEmpty || path.isEmpty) return null;
    return NitikaLink(label: label, path: path);
  }
}

class NitikaTable {
  const NitikaTable({
    required this.columns,
    required this.rows,
    required this.rowCount,
    required this.truncated,
  });

  final List<String> columns;

  /// Cells are as sent: strings, numbers, booleans or null.
  final List<List<Object?>> rows;
  final int rowCount;
  final bool truncated;

  static NitikaTable? tryParse(Object? json) {
    if (json is! Map) return null;
    final columns = (json['columns'] is List)
        ? [for (final c in json['columns'] as List) c?.toString() ?? '']
        : <String>[];
    final rows = (json['rows'] is List)
        ? [
            for (final r in json['rows'] as List)
              if (r is List) List<Object?>.from(r),
          ]
        : <List<Object?>>[];
    if (columns.isEmpty && rows.isEmpty) return null;
    return NitikaTable(
      columns: columns,
      rows: rows,
      rowCount: _int(json['row_count']) ?? rows.length,
      truncated: json['truncated'] == true,
    );
  }
}

class NitikaReply {
  const NitikaReply({
    this.answer,
    this.table,
    this.links = const [],
    this.intent,
    this.mode = 'assistant',
    this.requestId,
    this.truncated = false,
  });

  /// Limited markdown (bold and lists), or null for a table-only reply.
  final String? answer;
  final NitikaTable? table;
  final List<NitikaLink> links;
  final String? intent;

  /// `assistant`, or `sql` for an admin's SQL query.
  final String mode;
  final String? requestId;
  final bool truncated;

  bool get isSql => mode == 'sql';

  factory NitikaReply.fromJson(Map<String, dynamic> json) {
    final answer = json['answer']?.toString();
    return NitikaReply(
      answer: (answer == null || answer.trim().isEmpty) ? null : answer,
      table: NitikaTable.tryParse(json['table']),
      links: (json['links'] is List)
          ? [
              for (final l in json['links'] as List)
                ?NitikaLink.tryParse(l),
            ]
          : const [],
      intent: json['intent']?.toString(),
      mode: json['mode']?.toString() ?? 'assistant',
      requestId: json['request_id']?.toString(),
      truncated: json['truncated'] == true,
    );
  }
}

/// What went wrong, as the panel tells it apart (plan §6).
enum NitikaErrorKind {
  /// 401: the app session has expired.
  sessionExpired,

  /// 403 `scope_denied`: the service's message is shown.
  scopeDenied,

  /// 404: NITiKa isn't configured on the backend.
  unavailable,

  /// 429 `user_rate_limited`.
  rateLimited,

  /// 429 `monthly_budget_reached`.
  budgetReached,

  /// 502, 503, other server errors, or no connection.
  failed,

  /// 504, or no answer before the client's own deadline.
  timeout,

  /// 400 and other client errors.
  invalid,
}

class NitikaError implements Exception {
  const NitikaError(
    this.kind, {
    this.code,
    this.message,
    this.requestId,
    this.retryAt,
  });

  final NitikaErrorKind kind;
  final String? code;

  /// The service's message, safe to show.
  final String? message;
  final String? requestId;

  /// When a rate-limited user may send again (from `retry_after_seconds`).
  final DateTime? retryAt;

  /// Errors that a resend may fix.
  bool get canRetry =>
      kind == NitikaErrorKind.failed || kind == NitikaErrorKind.timeout;

  /// Maps an HTTP status and body (NITiKa's `{error: {...}}`, or the
  /// backend's own `{detail: ...}`) to an error.
  factory NitikaError.fromResponse(int? status, Object? body) {
    final error = (body is Map && body['error'] is Map)
        ? body['error'] as Map
        : const {};
    final code = error['code']?.toString();
    var message = error['message']?.toString();
    if (message == null && body is Map && body['detail'] is String) {
      message = body['detail'] as String;
    }
    final requestId = error['request_id']?.toString();
    final retrySeconds = _int(error['retry_after_seconds']);

    final NitikaErrorKind kind;
    if (status == 401) {
      kind = NitikaErrorKind.sessionExpired;
    } else if (status == 403) {
      kind = NitikaErrorKind.scopeDenied;
    } else if (status == 404) {
      kind = NitikaErrorKind.unavailable;
    } else if (status == 429) {
      kind = code == 'monthly_budget_reached'
          ? NitikaErrorKind.budgetReached
          : NitikaErrorKind.rateLimited;
    } else if (status == 504) {
      kind = NitikaErrorKind.timeout;
    } else if (status != null && status >= 400 && status < 500) {
      kind = NitikaErrorKind.invalid;
    } else {
      kind = NitikaErrorKind.failed;
    }

    return NitikaError(
      kind,
      code: code,
      message: message,
      requestId: requestId,
      retryAt: retrySeconds == null
          ? null
          : DateTime.now().add(Duration(seconds: retrySeconds)),
    );
  }

  @override
  String toString() => 'NitikaError($kind, $code)';
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
