import 'package:flutter/material.dart';

/// NITKSAA palette, matching the association website
/// (nitksaa-website: frontend/src/styles/tokens.css).
///
/// Dark is the default theme. Light uses the website's cream palette.
/// New code should read colours from the theme (`Theme.of(context)` or
/// `context.palette` from app_palette.dart) rather than from here directly.
abstract class AppColors {
  // ── Brand (same in both themes) ───────────────────────────────────────
  static const Color navy = Color(0xFF0F2744);
  static const Color gold = Color(0xFFC9A84C);
  static const Color goldLight = Color(0xFFE2C97E);
  static const Color goldDim = Color(0xFF8A6E2F);

  // ── Dark (default) ────────────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF09192E); // --navy-deep
  static const Color darkCanvas = Color(0xFF070F1C); // --bg-canvas
  static const Color darkSurface = Color(0xFF162F52); // --navy-mid (panels, dialogs)
  static const Color darkSurfaceSubtle = Color(0x0AFFFFFF); // --surface (4% white)
  static const Color darkSurfaceHover = Color(0x12FFFFFF); // --surface-hover (7% white)
  static const Color darkCard = Color(0x8C0F2744); // --bg-card-alumni (navy @ 55%)
  static const Color darkNavLight = Color(0xFF1E3F6E); // --navy-light
  static const Color darkNavMuted = Color(0xFF2A5298); // --navy-muted
  static const Color darkPrimary = gold;
  static const Color darkPrimaryHover = goldLight;
  static const Color darkOnPrimary = darkBackground;
  static const Color darkText = Color(0xFFF0E6C8); // --text-primary
  static const Color darkSecondary = Color(0xFF9DB4D0); // --text-secondary
  static const Color darkMuted = Color(0xFF5A7A9A); // --text-muted
  static const Color darkBorder = Color(0x2EC9A84C); // gold @ 18%
  static const Color darkBorderHover = Color(0x73C9A84C); // gold @ 45%
  static const Color darkOverlay = Color(0xE0050E1C); // --bg-overlay
  static const Color darkSuccess = Color(0xFF6EE7B7);
  static const Color darkWarning = Color(0xFFFCD34D);
  static const Color darkError = Color(0xFFF87171);
  static const Color darkInfo = Color(0xFF93C5FD);

  // ── Light (website cream) ─────────────────────────────────────────────
  static const Color lightBackground = Color(0xFFF5F0E6); // --navy-deep (light)
  static const Color lightCanvas = Color(0xFFE8E2D4); // --bg-canvas (light)
  static const Color lightSurface = Color(0xFFEDE8D8); // --navy-mid (light)
  static const Color lightSurfaceSubtle = Color(0x0A000000); // 4% black
  static const Color lightSurfaceHover = Color(0x12000000); // 7% black
  static const Color lightCard = Color(0xA6FFFFFF); // white @ 65%
  static const Color lightNavLight = Color(0xFFDDD5C3);
  static const Color lightNavMuted = Color(0xFF4A6090);
  static const Color lightPrimary = Color(0xFF8A6010); // gold, darkened for cream
  static const Color lightPrimaryHover = Color(0xFFA07520);
  static const Color lightOnPrimary = lightBackground;
  static const Color lightText = Color(0xFF1C2B3A);
  static const Color lightSecondary = Color(0xFF4A6278);
  static const Color lightMuted = Color(0xFF7A8898);
  static const Color lightBorder = Color(0x38A07828); // rgba(160,120,40,.22)
  static const Color lightBorderHover = Color(0x80A07828); // rgba(160,120,40,.50)
  static const Color lightOverlay = Color(0x8C0A1428);
  static const Color lightSuccess = Color(0xFF166534);
  static const Color lightWarning = Color(0xFF92400E);
  static const Color lightError = Color(0xFF991B1B);
  static const Color lightInfo = Color(0xFF1E3A8A);
}
