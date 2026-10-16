import 'dart:js_interop';

/// `new Date(ms)`, for its `toLocaleString`.
@JS('Date')
extension type _JSDate._(JSObject _) implements JSObject {
  external factory _JSDate(JSNumber milliseconds);
  external JSString toLocaleString(JSString locale, JSObject options);
}

final _wallTime = RegExp(r'^(\d{2})/(\d{2})/(\d{4}), (\d{2}):(\d{2}):(\d{2})$');

/// The browser's timezone data: the wall clock in [zone] at [instant],
/// less the UTC time. Null when the browser doesn't know [zone].
int? utcOffsetMinutes(DateTime instant, String zone) {
  final utc = instant.toUtc();
  final String text;
  try {
    text = _JSDate(utc.millisecondsSinceEpoch.toJS)
        .toLocaleString(
          'en-US'.toJS,
          {
            'timeZone': zone,
            'hourCycle': 'h23',
            'year': 'numeric',
            'month': '2-digit',
            'day': '2-digit',
            'hour': '2-digit',
            'minute': '2-digit',
            'second': '2-digit',
          }.jsify()! as JSObject,
        )
        .toDart;
  } catch (_) {
    return null; // RangeError: unknown timezone.
  }
  final m = _wallTime.firstMatch(text.replaceAll(' ', ' '));
  if (m == null) return null;
  int part(int i) => int.parse(m.group(i)!);
  final wall = DateTime.utc(
    part(3), part(1), part(2), part(4) % 24, part(5), part(6),
  );
  final whole = DateTime.utc(
    utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second,
  );
  return wall.difference(whole).inMinutes;
}
