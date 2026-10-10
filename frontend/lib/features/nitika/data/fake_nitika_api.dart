import '../domain/nitika_models.dart';
import 'nitika_api.dart';

/// Canned replies for checking the panel's layout without a backend. Debug
/// builds only (`NITIKA_FAKE`); a release build never constructs it.
///
/// Type "table", "sql", "long", "error", "timeout", "denied", "limit",
/// "budget" or "expired" to see each shape; anything else gets an answer
/// with links.
class FakeNitikaApi implements NitikaApi {
  @override
  Future<NitikaReply> chat({
    required String accessToken,
    required String message,
    required List<ChatTurn> history,
    required String locale,
    required NitikaPageContext context,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final text = message.toLowerCase();
    const id = 'fake-request-id';

    NitikaError fail(int status, String code, [String? message, int? retry]) =>
        NitikaError.fromResponse(status, {
          'error': {
            'code': code,
            'message': ?message,
            'request_id': id,
            'retry_after_seconds': ?retry,
          },
        });

    if (text.contains('error')) throw fail(502, 'model_failure');
    if (text.contains('timeout')) throw fail(504, 'timeout');
    if (text.contains('denied')) {
      throw fail(403, 'scope_denied', "That event isn't one you manage.");
    }
    if (text.contains('limit')) throw fail(429, 'user_rate_limited', null, 900);
    if (text.contains('budget')) throw fail(429, 'monthly_budget_reached');
    if (text.contains('expired')) throw fail(401, 'unauthorized');

    if (text.contains('table') || text.contains('sql') || text.contains('long')) {
      final rows = text.contains('long') ? 200 : 24;
      return NitikaReply(
        mode: text.contains('sql') ? 'sql' : 'assistant',
        answer: text.contains('sql')
            ? null
            : '**$rows attendees** for the Mumbai gala, '
                  '${rows - 3} checked in.',
        requestId: id,
        table: NitikaTable(
          columns: const ['Name', 'Email', 'Status', 'Checked in', 'Notes'],
          rows: [
            for (var i = 1; i <= rows; i++)
              [
                'Attendee $i',
                'attendee$i@example.com',
                'confirmed',
                i % 8 != 0,
                i == 2 ? 'A very long note that will not fit in its cell' : null,
              ],
          ],
          rowCount: rows,
          truncated: text.contains('long'),
        ),
      );
    }

    return NitikaReply(
      answer:
          'Here is what is coming up:\n\n'
          '- **Pune Alumni Meet**, 18 Oct, registration open\n'
          '- **Mumbai Gala**, 2 Nov, ₹499 (the final amount is shown at '
          'checkout)\n\n'
          'Your registrations are in **My Events**.',
      links: const [
        NitikaLink(label: 'Pune Alumni Meet', path: '/events/1'),
        NitikaLink(label: 'Mumbai Gala', path: '/events/13'),
        NitikaLink(label: 'My Events', path: '/my-events'),
        NitikaLink(label: 'Outside link', path: 'https://example.com'),
      ],
      intent: 'list_events',
      requestId: id,
    );
  }
}
