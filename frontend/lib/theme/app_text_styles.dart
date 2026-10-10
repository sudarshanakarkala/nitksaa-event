import 'package:flutter/material.dart';

/// Type scale matching the association website.
///
/// Headings use Crimson Pro (serif); everything else uses DM Sans.
/// Both are bundled in assets/fonts/ (see pubspec.yaml). Colours come from
/// the theme, so these styles carry no colour.
abstract class AppTextStyles {
  static const String serif = 'CrimsonPro';
  static const String sans = 'DMSans';

  // ── Headings (serif) ──────────────────────────────────────────────────
  /// Page heading, website `.dash-heading` (2.2rem).
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: serif,
    fontSize: 35,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// Login title (1.75rem).
  static const TextStyle headlineMedium = TextStyle(
    fontFamily: serif,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// Detail title (1.35rem).
  static const TextStyle headlineSmall = TextStyle(
    fontFamily: serif,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  /// Modal / section title (1.25rem).
  static const TextStyle titleLarge = TextStyle(
    fontFamily: serif,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  // ── Sans ──────────────────────────────────────────────────────────────
  static const TextStyle titleMedium = TextStyle(
    fontFamily: sans,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle titleSmall = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: sans,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.65,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: sans,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// Buttons and nav links.
  static const TextStyle labelLarge = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
  );

  /// Form field labels: small uppercase, website `label`.
  static const TextStyle labelMedium = TextStyle(
    fontFamily: sans,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.0,
  );

  /// Badges, footer, captions.
  static const TextStyle labelSmall = TextStyle(
    fontFamily: sans,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );

  /// Gold eyebrow above page titles (`.dash-eyebrow`). Use uppercase text.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: sans,
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.6,
  );
}
