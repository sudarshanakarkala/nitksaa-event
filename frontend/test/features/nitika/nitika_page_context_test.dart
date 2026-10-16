import 'package:event_app/features/nitika/domain/nitika_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NitikaPageContext at(String location) => NitikaPageContext.fromLocation(location);

  test('event page and checkout give the event', () {
    expect(at('/events/82').eventId, 82);
    expect(at('/events/82/checkout').eventId, 82);
    expect(at('/events/82').isEventPage, isTrue);
  });

  test('admin Registrations and Check-in give the event chosen in ?event=', () {
    final regs = at('/admin/registrations?event=82&q=joshi');
    expect(regs.eventId, 82);
    expect(regs.page, '/admin/registrations'); // the query never reaches NITiKa
    expect(regs.isEventPage, isFalse);
    expect(at('/admin/checkin?event=115').eventId, 115);
  });

  test('no event on admin tabs without one, or on other pages', () {
    expect(at('/admin/registrations').eventId, isNull);
    expect(at('/admin/registrations?event=abc').eventId, isNull);
    expect(at('/admin/payments?event=82').eventId, isNull);
    expect(at('/home').eventId, isNull);
    expect(at('/my-events').toJson(), {'page': '/my-events'});
  });

  test('sends page and event id', () {
    expect(at('/admin/checkin?event=7').toJson(), {'page': '/admin/checkin', 'event_id': 7});
  });
}
