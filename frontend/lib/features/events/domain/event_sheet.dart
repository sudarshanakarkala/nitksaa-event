import 'package:dio/dio.dart';

/// An event's Google Sheet: what the server says about it.
///
/// While a sheet is linked, it is the only source of the event's speakers,
/// agenda, sponsors and partners: the form shows them read-only and Refresh
/// reads and saves them in one step (`POST …/sheet/refresh`).

/// Where to start a sheet, and whom to share it with (`GET /admin/sheets/info`).
class SheetInfo {
  const SheetInfo({required this.shareWith, required this.templates});

  final String shareWith;

  /// Name and "Make a copy" link, e.g. ('Blank', 'https://docs.google.com/…/copy').
  final List<({String name, String url})> templates;

  factory SheetInfo.fromJson(Map<String, dynamic> json) => SheetInfo(
        shareWith: json['share_with'] as String? ?? '',
        templates: [
          for (final t in (json['templates'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>())
            (name: t['name'] as String? ?? '', url: t['url'] as String? ?? ''),
        ],
      );
}

/// How many of each the sheet holds.
class SheetSummary {
  const SheetSummary({this.sessions = 0, this.speakers = 0, this.sponsors = 0, this.partners = 0});

  final int sessions;
  final int speakers;
  final int sponsors;
  final int partners;

  factory SheetSummary.fromJson(Map<String, dynamic>? json) {
    int n(String key) => (json?[key] as num?)?.toInt() ?? 0;
    return SheetSummary(
      sessions: n('sessions'),
      speakers: n('speakers'),
      sponsors: n('sponsors'),
      partners: n('partners'),
    );
  }

  /// "40 sessions, 83 speakers, 15 sponsors" (nothing for a zero).
  String describe() {
    String count(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final parts = [
      if (sessions > 0) count(sessions, 'session', 'sessions'),
      if (speakers > 0) count(speakers, 'speaker', 'speakers'),
      if (sponsors > 0) count(sponsors, 'sponsor', 'sponsors'),
      if (partners > 0) count(partners, 'partner', 'partners'),
    ];
    return parts.isEmpty ? 'nothing yet' : parts.join(', ');
  }
}

/// One change the sheet's Event tab makes to the event, e.g.
/// ('Title', 'Alumni Meetup', 'NITKonnect 2026').
typedef SheetChange = ({String field, String from, String to});

/// What a Refresh saved, or, when [needsConfirm], what it would change to the
/// event (nothing saved yet: ask, then Refresh again with confirm).
class SheetRefresh {
  const SheetRefresh({
    required this.url,
    this.readAt,
    required this.summary,
    this.warnings = const [],
    this.needsConfirm = false,
    this.changes = const [],
  });

  final String url;
  final DateTime? readAt;
  final SheetSummary summary;
  final List<String> warnings;
  final bool needsConfirm;
  final List<SheetChange> changes;

  factory SheetRefresh.fromJson(Map<String, dynamic> json) => SheetRefresh(
        url: json['url'] as String? ?? '',
        readAt: DateTime.tryParse(json['read_at'] as String? ?? '')?.toLocal(),
        summary: SheetSummary.fromJson(json['summary'] as Map<String, dynamic>?),
        warnings: [for (final w in json['warnings'] as List<dynamic>? ?? const []) '$w'],
        needsConfirm: json['needs_confirm'] == true,
        changes: [
          for (final c in (json['changes'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>())
            (field: '${c['field'] ?? ''}', from: '${c['from'] ?? ''}', to: '${c['to'] ?? ''}'),
        ],
      );
}

/// Events → Import: the Event tab as the create form's fields.
class SheetPreview {
  const SheetPreview({required this.url, required this.event, required this.summary, this.warnings = const []});

  final String url;

  /// The create form's fields: title, start and end ("yyyy-MM-dd HH:mm" in
  /// [timezone]), is_full_day, is_virtual, location_text, capacity, … (see
  /// sheet_parser._parse_event on the server).
  final Map<String, dynamic> event;
  final SheetSummary summary;
  final List<String> warnings;

  factory SheetPreview.fromJson(Map<String, dynamic> json) => SheetPreview(
        url: json['url'] as String? ?? '',
        event: (json['event'] as Map<String, dynamic>?) ?? const {},
        summary: SheetSummary.fromJson(json['summary'] as Map<String, dynamic>?),
        warnings: [for (final w in json['warnings'] as List<dynamic>? ?? const []) '$w'],
      );
}

/// Why a sheet couldn't be read or saved, in words for the person: either
/// one [message] (not shared, wrong link…) or the sheet's [errors], each
/// naming its tab and row. Nothing was changed.
class SheetProblem implements Exception {
  const SheetProblem(this.message, {this.errors = const []});

  final String message;
  final List<String> errors;

  @override
  String toString() => errors.isEmpty ? message : '$message\n${errors.join('\n')}';

  /// The server's 422 (or another failure) as a [SheetProblem].
  static SheetProblem from(Object error) {
    if (error is SheetProblem) return error;
    if (error is DioException) {
      final data = error.response?.data;
      final detail = data is Map ? data['detail'] : null;
      if (detail is Map) {
        final errors = [for (final e in detail['errors'] as List<dynamic>? ?? const []) '$e'];
        if (errors.isNotEmpty) {
          return SheetProblem(
            errors.length == 1 ? 'The sheet has a problem to fix:' : 'The sheet has ${errors.length} problems to fix:',
            errors: errors,
          );
        }
        final message = detail['message'];
        if (message is String && message.isNotEmpty) return SheetProblem(message);
      }
      if (detail == 'sheet_linked') {
        return const SheetProblem('These come from the linked Google Sheet. Change them in the sheet, then press Refresh.');
      }
      final status = error.response?.statusCode;
      if (status == 403) return const SheetProblem("You don't have access to this event.");
      if (status == null) return const SheetProblem("Couldn't reach the server. Check your connection and try again.");
    }
    return const SheetProblem("Couldn't read the sheet. Try again in a minute.");
  }
}

/// "20 Oct, 12:41" for "read …".
String sheetReadTime(DateTime when) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${when.day} ${months[when.month - 1]}, ${two(when.hour)}:${two(when.minute)}';
}
