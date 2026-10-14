// Typed dates in the date filter's From / To boxes.

import 'package:event_app/shared/widgets/filter_controls.dart';
import 'package:flutter_test/flutter_test.dart';

final _today = DateTime(2026, 10, 14);

void main() {
  test('day first, with or without a year', () {
    expect(parseFilterDate('15 Nov', _today), DateTime(2026, 11, 15));
    expect(parseFilterDate('15 november', _today), DateTime(2026, 11, 15));
    expect(parseFilterDate('15nov', _today), DateTime(2026, 11, 15));
    expect(parseFilterDate('15/11', _today), DateTime(2026, 11, 15));
    expect(parseFilterDate('15-11-27', _today), DateTime(2027, 11, 15));
    expect(parseFilterDate('15 Nov 2025', _today), DateTime(2025, 11, 15));
    expect(parseFilterDate('15/11/2025', _today), DateTime(2025, 11, 15));
  });

  test('no year: the next one on or after today', () {
    expect(parseFilterDate('14 Oct', _today), DateTime(2026, 10, 14));
    expect(parseFilterDate('1 Oct', _today), DateTime(2027, 10, 1));
    expect(parseFilterDate('5 Jan', _today), DateTime(2027, 1, 5));
  });

  test('not a date', () {
    for (final t in ['', 'soon', '31 Feb 2026', '32/1', '15/13', 'Nov 15']) {
      expect(parseFilterDate(t, _today), isNull, reason: t);
    }
  });

  test('looking back: no year means the latest one on or before today', () {
    expect(parseFilterDate('14 Oct', _today, past: true), DateTime(2026, 10, 14));
    expect(parseFilterDate('3 Nov', _today, past: true), DateTime(2025, 11, 3));
    expect(parseFilterDate('1/10', _today, past: true), DateTime(2026, 10, 1));
    expect(parseFilterDate('3 Nov 2026', _today, past: true), DateTime(2026, 11, 3));
  });
}
