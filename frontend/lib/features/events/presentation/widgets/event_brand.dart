/// An event's own branding: its logos, for light and dark
/// backgrounds. The logo (and the event's banner) carry the brand; pages
/// keep the site's colours (decided 19 Oct). Off unless set: [EventBrand.of]
/// is null for an event without logos, and it then looks exactly as before.
library;

import 'package:flutter/material.dart';

import '../../domain/event.dart';

class EventBrand {
  const EventBrand({this.logoUrl, this.logoDarkUrl});

  /// For light backgrounds.
  final String? logoUrl;

  /// For dark backgrounds (e.g. a white logo).
  final String? logoDarkUrl;

  /// [event]'s branding, or null when it has none.
  static EventBrand? of(AppEvent event) {
    final logo = _clean(event.brandLogoUrl);
    final logoDark = _clean(event.brandLogoDarkUrl);
    if (logo == null && logoDark == null) return null;
    return EventBrand(logoUrl: logo, logoDarkUrl: logoDark);
  }

  /// The logo for this mode: the dark one on dark backgrounds, falling
  /// back to the other when only one is set.
  String? logoFor(Brightness brightness) =>
      brightness == Brightness.dark ? (logoDarkUrl ?? logoUrl) : (logoUrl ?? logoDarkUrl);

  static String? _clean(String? url) {
    final u = url?.trim() ?? '';
    return u.isEmpty ? null : u;
  }
}
