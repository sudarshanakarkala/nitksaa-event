import '../data/registrations_api.dart';
import '../../../shared/format.dart';

export '../../../shared/format.dart' show formatDate, formatDateTime;

/// The three lists in the Registrations tab.
enum RegistrationView {
  registered('Registered'),
  cancelled('Cancelled'),
  checkIns('Check-ins');

  const RegistrationView(this.label);
  final String label;
}

/// How a column filters: text columns match what you type, category
/// columns offer a tick-list of their values, dates and numbers only sort.
enum ColumnKind { text, category, date, number }

/// One column of an admin table: what it shows, how it sorts and filters.
class GridColumn<T> {
  const GridColumn({
    required this.id,
    required this.label,
    required this.kind,
    required this.value,
    String Function(T row)? text,
    this.width,
  }) : _text = text;

  final String id;
  final String label;
  final ColumnKind kind;

  /// A set width for the table, for columns whose cells aren't plain text
  /// (badges, buttons). Null: sized to the text.
  final double? width;

  /// The sort value: a String, num or DateTime, or null when there's none.
  final Object? Function(T row) value;
  final String Function(T row)? _text;

  /// What the cell shows, and what filters match against ('' when empty).
  String text(T row) {
    final custom = _text;
    if (custom != null) return custom(row);
    final v = value(row);
    if (v == null) return '';
    if (v is DateTime) return formatDateTime(v);
    return v.toString();
  }

  bool get filterable => kind == ColumnKind.text || kind == ColumnKind.category;
}

/// A column's filter: typed text, ticked values (the cells'
/// [GridColumn.text]; '' stands for blank) and/or a number range
/// ([from]–[to], inclusive; either end may be open).
class ColumnFilter {
  const ColumnFilter({this.query = '', this.values = const {}, this.from, this.to});

  final String query;
  final Set<String> values;
  final num? from;
  final num? to;

  bool get isActive =>
      query.trim().isNotEmpty || values.isNotEmpty || from != null || to != null;

  bool matches(String cell, [Object? value]) {
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty && !cell.toLowerCase().contains(q)) return false;
    if (values.isNotEmpty && !values.contains(cell)) return false;
    if (from != null || to != null) {
      if (value is! num) return false;
      if (from != null && value < from!) return false;
      if (to != null && value > to!) return false;
    }
    return true;
  }
}

/// Rows matching the search box (any text or category column contains it)
/// and every active column filter, sorted by [sortId].
List<T> applyGrid<T>(
  List<T> rows,
  List<GridColumn<T>> columns, {
  String search = '',
  Map<String, ColumnFilter> filters = const {},
  String? sortId,
  bool ascending = true,
}) {
  final q = search.trim().toLowerCase();
  final searchable = columns.where((c) => c.filterable).toList();
  final active = [
    for (final c in columns)
      if (filters[c.id]?.isActive ?? false) (c, filters[c.id]!),
  ];

  final kept = <T>[
    for (final row in rows)
      if ((q.isEmpty || searchable.any((c) => c.text(row).toLowerCase().contains(q))) &&
          active.every((f) => f.$2.matches(f.$1.text(row), f.$1.value(row))))
        row,
  ];

  GridColumn<T>? sortColumn;
  for (final c in columns) {
    if (c.id == sortId) sortColumn = c;
  }
  if (sortColumn == null) return kept;
  final by = sortColumn;

  // Sort with the original position as tie-break, so equal rows keep their
  // order (Dart's sort isn't stable).
  final indexed = [for (var i = 0; i < kept.length; i++) (i, kept[i])];
  indexed.sort((a, b) {
    final result = compareCells(by.value(a.$2), by.value(b.$2), ascending: ascending);
    return result != 0 ? result : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Compares two sort values; empty values go last either way, and text
/// ignores case.
int compareCells(Object? a, Object? b, {required bool ascending}) {
  final aEmpty = a == null || (a is String && a.trim().isEmpty);
  final bEmpty = b == null || (b is String && b.trim().isEmpty);
  if (aEmpty && bEmpty) return 0;
  if (aEmpty) return 1;
  if (bEmpty) return -1;
  final int result;
  if (a is String && b is String) {
    result = a.toLowerCase().compareTo(b.toLowerCase());
  } else if (a is Comparable && b is Comparable) {
    result = a.compareTo(b);
  } else {
    result = a.toString().compareTo(b.toString());
  }
  return ascending ? result : -result;
}

/// The distinct cell texts in [column], in its sort order, for a tick-list
/// filter. A blank cell is ''.
List<String> distinctValues<T>(List<T> rows, GridColumn<T> column) {
  final seen = <String, Object?>{};
  for (final row in rows) {
    seen.putIfAbsent(column.text(row), () => column.value(row));
  }
  final entries = seen.entries.toList()
    ..sort((a, b) => compareCells(a.value, b.value, ascending: true));
  return [for (final e in entries) e.key];
}

/// Decades (1990, 2000 …) the years in [years] fall in, oldest first.
List<int> decadesOf(Iterable<int?> years) {
  final decades = years.whereType<int>().map((y) => y - y % 10).toSet().toList()..sort();
  return decades;
}

/// A check-in with the person it belongs to (null if their registration
/// isn't in the loaded lists).
class CheckInEntry {
  const CheckInEntry(this.checkIn, this.person);

  final AdminCheckIn checkIn;
  final AdminRegistration? person;
}

/// Plain words for the confirmation-email status the backend stores.
String confirmationEmailLabel(String? raw) {
  final status = raw?.trim() ?? '';
  switch (status) {
    case 'sent':
      return 'Sent';
    case 'failed':
      return 'Failed';
    case 'pending':
    case 'queued':
      return 'Pending';
    case 'skipped':
      return 'Not sent';
    case '':
      return '';
    default:
      return status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
  }
}

// formatDate / formatDateTime now live in shared/format.dart (exported above).
