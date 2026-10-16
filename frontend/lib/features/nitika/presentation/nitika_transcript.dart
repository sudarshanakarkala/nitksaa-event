import '../domain/nitika_models.dart';
import 'nitika_controller.dart';

/// The conversation as plain text, for an overall admin to save while
/// training or debugging NITiKa. Each reply carries its request id, so it
/// can be found in NITiKa's server logs.
String nitikaTranscript(
  List<NitikaMessage> messages, {
  required DateTime savedAt,
  String? savedBy,
}) {
  final out = StringBuffer()
    ..writeln('NITiKa chat, ${_dateTime(savedAt)}')
    ..writeln('Saved by: ${savedBy ?? '(unknown)'} (overall admin)');

  for (final m in messages) {
    out.writeln();
    switch (m.kind) {
      case NitikaMessageKind.user:
        out.writeln('You: ${m.text ?? ''}');
      case NitikaMessageKind.reply:
        _reply(out, m.reply!);
      case NitikaMessageKind.error:
        final e = m.error!;
        final what = e.message ?? e.code ?? e.kind.name;
        out.writeln('NITiKa: Error: $what${_id(e.requestId)}');
    }
  }
  return out.toString();
}

/// "nitika-chat-2026-10-16-1405".
String nitikaTranscriptName(DateTime savedAt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'nitika-chat-${savedAt.year}-${two(savedAt.month)}-${two(savedAt.day)}'
      '-${two(savedAt.hour)}${two(savedAt.minute)}';
}

void _reply(StringBuffer out, NitikaReply r) {
  final sql = r.isSql ? ' (SQL)' : '';
  final answer = r.answer?.trim();
  out.writeln('NITiKa$sql: ${answer ?? ''}${_id(r.requestId)}');

  final table = r.table;
  if (table != null) {
    final shown = table.rows.length;
    final more = table.truncated || table.rowCount > shown
        ? ', showing $shown of ${table.rowCount}'
        : '';
    out.writeln('  (table, ${table.rowCount} rows$more)');
    out.writeln('  ${table.columns.join('\t')}');
    for (final row in table.rows) {
      out.writeln('  ${row.map((c) => c?.toString() ?? '').join('\t')}');
    }
  }
  if (r.links.isNotEmpty) {
    out.writeln('  Links: ${r.links.map((l) => '${l.label} → ${l.path}').join(', ')}');
  }
  if (r.truncated) out.writeln('  (answer cut short)');
}

String _id(String? requestId) =>
    (requestId == null || requestId.isEmpty) ? '' : '   [request id: $requestId]';

String _dateTime(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} ${d.year}, ${two(d.hour)}:${two(d.minute)}';
}
