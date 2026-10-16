// The Create/Edit Event form must not save an event the backend can't
// publish. These are the rules behind the check in _save(); they mirror
// _validate_for_publish in the backend.

import 'package:event_app/features/events/domain/event_publish_requirements.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _missing({
  String title = 'Alumni Meetup',
  String startDate = '2026-11-01',
  String endDate = '2026-11-01',
  String timezone = 'Asia/Kolkata',
  String capacity = '50',
  bool isVirtual = false,
  String location = 'NITK Surathkal',
  String virtualUrl = '',
}) =>
    missingPublishFields(
      title: title,
      startDate: startDate,
      endDate: endDate,
      timezone: timezone,
      capacity: capacity,
      isVirtual: isVirtual,
      location: location,
      virtualUrl: virtualUrl,
    );

void main() {
  group('parseCapacity / validateCapacity', () {
    test('a positive whole number is valid', () {
      expect(parseCapacity('50'), 50);
      expect(parseCapacity(' 1 '), 1);
      expect(validateCapacity('1000'), isNull);
    });

    for (final bad in ['', '   ', '0', '-5', 'abc', '2.5']) {
      test('"$bad" is not a capacity', () {
        expect(parseCapacity(bad), isNull);
        expect(validateCapacity(bad), capacityErrorText);
      });
    }

    test('null is not a capacity', () {
      expect(validateCapacity(null), capacityErrorText);
    });
  });

  group('missingPublishFields', () {
    test('a complete in-person event has nothing missing', () {
      expect(_missing(), isEmpty);
    });

    test('a complete virtual event has nothing missing', () {
      expect(
        _missing(isVirtual: true, location: '', virtualUrl: 'https://zoom.us/j/1'),
        isEmpty,
      );
    });

    test('everything filled in except capacity: Capacity is missing', () {
      expect(_missing(capacity: ''), ['Capacity']);
    });

    test('capacity 0 or text counts as missing', () {
      expect(_missing(capacity: '0'), ['Capacity']);
      expect(_missing(capacity: 'abc'), ['Capacity']);
    });

    test('an event saved before the fix, with no capacity, is blocked', () {
      // The form prefills capacity with '' when event.capacity is null.
      expect(_missing(capacity: ''), contains('Capacity'));
    });

    test('in person needs a location, not a meeting URL', () {
      expect(_missing(location: ''), ['Location']);
    });

    test('virtual needs a meeting URL, not a location', () {
      expect(_missing(isVirtual: true, location: '', virtualUrl: ' '), ['Meeting URL']);
    });

    test('several missing fields are listed in form order', () {
      expect(
        _missing(title: '', timezone: '', capacity: ''),
        ['Title', 'Timezone', 'Capacity'],
      );
    });

    test('blank dates are missing', () {
      expect(_missing(startDate: '', endDate: ''), ['Start date', 'End date']);
    });
  });
}
