// Readable event links (/e/<slug>): tidying what's typed, the same rules as
// the server, and the link built from the app's own address.
import 'package:event_app/features/events/domain/event_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('typed links are tidied', () {
    expect(tidySlug('Bangalore Breakfast Oct 2026'), 'bangalore-breakfast-oct-2026');
    expect(tidySlug('NITKonnect_2027!'), 'nitkonnect-2027');
    expect(tidySlug('a  --  b'), 'a-b');
    expect(tidySlug('-lead'), 'lead');
    // A trailing hyphen stays while typing: the next word follows.
    expect(tidySlug('bangalore-'), 'bangalore-');
  });

  test('link rules match the server', () {
    expect(slugProblem('bangalore-breakfast-oct-2026'), isNull);
    expect(slugProblem('abc'), isNull);
    expect(slugProblem('ab'), isNotNull);
    expect(slugProblem('x' * 61), isNotNull);
    expect(slugProblem('ends-'), isNotNull);
    expect(slugProblem('two--hyphens'), isNotNull);
    expect(slugProblem('Capitals'), isNotNull);
  });

  test('the link has no # (the app moves it under #/ as it starts)', () {
    expect(eventLinkUrl('nitkonnect-2027'), endsWith('/e/nitkonnect-2027'));
    expect(eventLinkUrl('nitkonnect-2027'), isNot(contains('#')));
  });
}
