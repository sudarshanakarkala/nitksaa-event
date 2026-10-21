// Event branding.
//
// - Off unless set: no branding, no EventBrand.
// - The logo for the mode: the dark one on dark backgrounds.
// - The card: a branded event without a thumbnail shows its logo, not its
//   wide banner; other events are unchanged.
// - Images from other sites still show (the browser's own image as a fallback).
import 'package:event_app/features/events/domain/event.dart';
import 'package:event_app/features/events/presentation/widgets/event_brand.dart';
import 'package:event_app/features/events/presentation/widgets/event_card.dart';
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
    test('none set: no branding; a colour alone is not branding', () {
      expect(EventBrand.of(_event()), isNull);
      expect(EventBrand.of(_event(logo: '  ')), isNull);
      expect(EventBrand.of(_event(accent: '#2A1A4F')), isNull);
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
        _event(logo: 'l.png', logoDark: 'd.png', banner: 'banner.png'),
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

    testWidgets('logos and banners from other sites still show', (tester) async {
      for (final event in [
        _event(logo: 'https://other.site/l.png'),
        _event(banner: 'https://other.site/banner.png'),
      ]) {
        await showCard(tester, event);
        final images = tester.widgetList<Image>(find.byType(Image)).where((i) => i.image is NetworkImage);
        expect(images, isNotEmpty);
        for (final image in images) {
          expect((image.image as NetworkImage).webHtmlElementStrategy, WebHtmlElementStrategy.fallback);
        }
      }
    });
  });
}
