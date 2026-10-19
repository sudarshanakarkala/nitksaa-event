/// An event's own branding (B6): logos for light and dark backgrounds and
/// a page colour. Off unless set: [EventBrand.of] is null for an event
/// without branding, and it then looks exactly as before.
///
/// The page colour (stored as `brand_accent`) is the event page's
/// background in both light and dark mode; [pagePalette] derives its
/// cards, borders and text from it. Only the event page uses it: the site
/// header and footer, the registration pop-up, checkout and every other
/// page keep the site's colours.
library;

import 'package:flutter/material.dart';

import '../../../../theme/app_palette.dart';
import '../../../../theme/app_theme.dart';
import '../../domain/event.dart';

class EventBrand {
  const EventBrand({this.accent, this.logoUrl, this.logoDarkUrl});

  /// The event page's colour (`brand_accent`).
  final Color? accent;

  /// For light backgrounds.
  final String? logoUrl;

  /// For dark backgrounds (e.g. a white logo).
  final String? logoDarkUrl;

  /// [event]'s branding, or null when it has none.
  static EventBrand? of(AppEvent event) {
    final accent = parseAccent(event.brandAccent);
    final logo = _clean(event.brandLogoUrl);
    final logoDark = _clean(event.brandLogoDarkUrl);
    if (accent == null && logo == null && logoDark == null) return null;
    return EventBrand(accent: accent, logoUrl: logo, logoDarkUrl: logoDark);
  }

  /// The logo for this mode: the dark one on dark backgrounds, falling
  /// back to the other when only one is set.
  String? logoFor(Brightness brightness) =>
      brightness == Brightness.dark ? (logoDarkUrl ?? logoUrl) : (logoUrl ?? logoDarkUrl);

  /// `#RRGGBB` as a colour; null when empty or not in that form.
  static Color? parseAccent(String? hex) {
    final h = hex?.trim() ?? '';
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(h)) return null;
    return Color(int.parse(h.substring(1), radix: 16) | 0xFF000000);
  }

  /// The event page's colours over [page]: the page itself, slightly
  /// lighter cards and surfaces, borders, and text that reads on it. A dark
  /// page gets light text (from the dark palette), a light one dark text.
  static AppPalette pagePalette(Color page) {
    final dark = page.computeLuminance() < 0.3;
    final base = dark ? AppPalette.dark : AppPalette.light;
    final towards = dark ? Colors.white : Colors.black;
    Color step(double t) => Color.lerp(page, towards, t)!;
    return base.copyWith(
      canvas: page,
      background: page,
      surface: step(0.05),
      surfaceSubtle: step(0.03),
      surfaceHover: step(0.09),
      card: step(0.07),
      border: step(0.18),
      borderHover: step(0.26),
      textSecondary: Color.lerp(towards, page, 0.25),
      textMuted: Color.lerp(towards, page, 0.42),
    );
  }

  /// The theme for an event page in [page] colour, whatever the site's
  /// mode.
  static ThemeData pageTheme(Color page) {
    final palette = pagePalette(page);
    final brightness = page.computeLuminance() < 0.3 ? Brightness.dark : Brightness.light;
    return AppTheme.forPalette(palette, brightness);
  }

  static String? _clean(String? url) {
    final u = url?.trim() ?? '';
    return u.isEmpty ? null : u;
  }
}
