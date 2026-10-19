// Event branding (B6).
//
// - Off unless set: no branding, no EventBrand.
// - The page colour is #RRGGBB; the page's colours come from it: a dark
//   page gets light text, a light page dark text, cards a shade lighter
//   or darker.
// - The logo for the mode: the dark one on dark backgrounds.
// - The card: a branded event without a thumbnail shows its logo, not its
//   wide banner; other events are unchanged.
import 'package:event_app/features/events/domain/event.dart';
import 'package:event_app/features/events/presentation/widgets/event_brand.dart';
import 'package:event_app/features/events/presentation/widgets/event_card.dart';
import 'package:event_app/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppEvent _event({String? accent, String? logo, String? logoDark, String? banner}) => AppEvent(
      eventId: 7,
      slug: 'nitkonnect-2027',
      title: 'NITKonnect 2027',
      status: 'published',
      startDatetime: DateTime(2027, 2, 13, 8),
      timezone: 'Asia/Kolkata',
      isVirtual: false,
      registrationStatus: 'open',
      registeredCount: 0,
      bannerUrl: banner,
      brandAccent: accent,
      brandLogoUrl: logo,
      brandLogoDarkUrl: logoDark,
    );

Finder _networkImage(String url) => find.byWidgetPredicate(
      (w) => w is Image && w.image is NetworkImage && (w.image as NetworkImage).url == url,
    );

void main() {
  group('EventBrand', () {
    test('none set: no branding', () {
      expect(EventBrand.of(_event()), isNull);
      expect(EventBrand.of(_event(logo: '  ')), isNull);
    });

    test('the accent is #RRGGBB', () {
      expect(EventBrand.parseAccent('#FEEF00'), const Color(0xFFFEEF00));
      expect(EventBrand.parseAccent('#feef00'), const Color(0xFFFEEF00));
      for (final bad in ['FEEF00', '#FFF', 'yellow', '', null]) {
        expect(EventBrand.parseAccent(bad), isNull, reason: '$bad');
      }
    });

    test('a deep purple page: light text, lighter cards', () {
      const purple = Color(0xFF2A1A4F);
      final p = EventBrand.pagePalette(purple);
      expect(p.canvas, purple);
      expect(p.background, purple);
      expect(p.textPrimary, AppPalette.dark.textPrimary);
      expect(p.card.computeLuminance(), greaterThan(purple.computeLuminance()));
      expect(EventBrand.pageTheme(purple).brightness, Brightness.dark);
    });

    test('a light page: dark text, darker cards', () {
      const lilac = Color(0xFFF3EEFF);
      final p = EventBrand.pagePalette(lilac);
      expect(p.textPrimary, AppPalette.light.textPrimary);
      expect(p.card.computeLuminance(), lessThan(lilac.computeLuminance()));
      expect(EventBrand.pageTheme(lilac).brightness, Brightness.light);
    });

    test('the logo for the mode', () {
      final both = EventBrand.of(_event(logo: 'l.png', logoDark: 'd.png'))!;
      expect(both.logoFor(Brightness.light), 'l.png');
      expect(both.logoFor(Brightness.dark), 'd.png');
      final one = EventBrand.of(_event(logo: 'l.png'))!;
      expect(one.logoFor(Brightness.dark), 'l.png');
    });
  });

  group('Event card', () {
    Future<void> showCard(WidgetTester tester, AppEvent event, {Brightness mode = Brightness.dark}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: mode),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: EventCard.height,
                child: EventCard.forEvent(event, onView: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a branded event without a thumbnail shows its logo, not the banner', (tester) async {
      await showCard(
        tester,
        _event(accent: '#2A1A4F', logo: 'l.png', logoDark: 'd.png', banner: 'banner.png'),
      );
      expect(_networkImage('banner.png'), findsNothing);
      expect(_networkImage('d.png'), findsOneWidget);
    });

    testWidgets('light mode uses the light logo', (tester) async {
      await showCard(
        tester,
        _event(logo: 'l.png', logoDark: 'd.png', banner: 'banner.png'),
        mode: Brightness.light,
      );
      expect(_networkImage('l.png'), findsOneWidget);
    });

    testWidgets('without branding, the banner as before', (tester) async {
      await showCard(tester, _event(banner: 'banner.png'));
      expect(_networkImage('banner.png'), findsOneWidget);
    });
  });
}
