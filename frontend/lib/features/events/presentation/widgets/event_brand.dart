/// An event's own branding (B6): logos for light and dark backgrounds and
/// one accent colour. Off unless set: [EventBrand.of] is null for an event
/// without branding, and it then looks exactly as before.
///
/// The accent tints fills (bands, pills, the card's empty banner). Used as
/// text or an icon it must stay readable on the background it sits on in
/// both modes; [readableOn] falls back to the theme's colour when it isn't
/// (Konnect yellow on a light page).
library;

import 'package:flutter/material.dart';

import '../../domain/event.dart';

class EventBrand {
  const EventBrand({this.accent, this.logoUrl, this.logoDarkUrl});

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

  /// [color] when it reads clearly on [background] (contrast 3:1, enough
  /// for bold or large text and icons); otherwise [fallback].
  static Color readableOn(Color color, Color background, Color fallback) =>
      contrast(color, background) >= 3 ? color : fallback;

  /// WCAG contrast ratio, 1 to 21.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Black or white, whichever reads better on [fill] (text on an accent).
  static Color onFill(Color fill) =>
      contrast(Colors.black, fill) >= contrast(Colors.white, fill) ? Colors.black : Colors.white;

  static String? _clean(String? url) {
    final u = url?.trim() ?? '';
    return u.isEmpty ? null : u;
  }
}
