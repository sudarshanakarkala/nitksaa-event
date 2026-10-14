/// Shared date and money formats (`UI_PATTERNS.md` → Dates and money).
///
/// - Full date and time: `13 Oct 2026, 10:29 AM` ([formatDateTime]).
/// - Short, in tables: `13 Oct, 10:29 AM` ([formatShortDateTime]).
/// - Money: ₹ with Indian digit grouping, paise only when there are any
///   (`₹1,800`, `₹1,23,456.50`) ([formatMoney]).
library;

const monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// `13 Oct 2026`.
String formatDate(DateTime d) => '${d.day} ${monthNames[d.month - 1]} ${d.year}';

/// `13 Oct`.
String formatShortDate(DateTime d) => '${d.day} ${monthNames[d.month - 1]}';

/// `10:29 AM`.
String formatTime(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${d.hour >= 12 ? 'PM' : 'AM'}';
}

/// `10:29 AM – 12:00 PM`, or just the start when there's no end.
String formatTimeRange(DateTime start, DateTime? end) =>
    end == null ? formatTime(start) : '${formatTime(start)} – ${formatTime(end)}';

/// `13 Oct 2026, 10:29 AM`.
String formatDateTime(DateTime d) => '${formatDate(d)}, ${formatTime(d)}';

/// `13 Oct, 10:29 AM`: short enough for a table; the year is in the
/// details window.
String formatShortDateTime(DateTime d) => '${formatShortDate(d)}, ${formatTime(d)}';

/// ₹ with Indian digit grouping (`₹1,23,456`); paise only when there are
/// any (`₹123.45`), unless [wholeRupees] rounds them away (Dashboard tiles).
String formatMoney(num amount, {bool wholeRupees = false}) {
  final negative = amount < 0;
  final abs = amount.abs();
  var whole = wholeRupees ? abs.round() : abs.truncate();
  var paise = wholeRupees ? 0 : ((abs - whole) * 100).round();
  if (paise == 100) {
    whole += 1;
    paise = 0;
  }
  final digits = whole.toString();
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    grouped = '${groups.join(',')},$last3';
  }
  final pa = paise == 0 ? '' : '.${paise.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}₹$grouped$pa';
}
