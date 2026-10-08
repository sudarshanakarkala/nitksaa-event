import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Named colours for the app, one set per theme.
///
/// Use these instead of hard-coded `Color(0x…)` values:
///
/// ```dart
/// final p = context.palette;
/// Container(color: p.card, child: Text('Hi', style: TextStyle(color: p.textPrimary)));
/// ```
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.canvas,
    required this.background,
    required this.surface,
    required this.surfaceSubtle,
    required this.surfaceHover,
    required this.card,
    required this.primary,
    required this.primaryHover,
    required this.onPrimary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.borderHover,
    required this.overlay,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
  });

  /// Page canvas behind sticky headers and detail pages.
  final Color canvas;

  /// Main scaffold background.
  final Color background;

  /// Raised panels: dialogs, menus, sheets.
  final Color surface;

  /// Very light fill for inputs, chips and cards on the background.
  final Color surfaceSubtle;
  final Color surfaceHover;

  /// List / entity card fill.
  final Color card;

  /// Gold accent: primary buttons, active nav, links.
  final Color primary;
  final Color primaryHover;
  final Color onPrimary;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color border;
  final Color borderHover;
  final Color overlay;

  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  static const dark = AppPalette(
    canvas: AppColors.darkCanvas,
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceSubtle: AppColors.darkSurfaceSubtle,
    surfaceHover: AppColors.darkSurfaceHover,
    card: AppColors.darkCard,
    primary: AppColors.darkPrimary,
    primaryHover: AppColors.darkPrimaryHover,
    onPrimary: AppColors.darkOnPrimary,
    textPrimary: AppColors.darkText,
    textSecondary: AppColors.darkSecondary,
    textMuted: AppColors.darkMuted,
    border: AppColors.darkBorder,
    borderHover: AppColors.darkBorderHover,
    overlay: AppColors.darkOverlay,
    success: AppColors.darkSuccess,
    warning: AppColors.darkWarning,
    error: AppColors.darkError,
    info: AppColors.darkInfo,
  );

  static const light = AppPalette(
    canvas: AppColors.lightCanvas,
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceSubtle: AppColors.lightSurfaceSubtle,
    surfaceHover: AppColors.lightSurfaceHover,
    card: AppColors.lightCard,
    primary: AppColors.lightPrimary,
    primaryHover: AppColors.lightPrimaryHover,
    onPrimary: AppColors.lightOnPrimary,
    textPrimary: AppColors.lightText,
    textSecondary: AppColors.lightSecondary,
    textMuted: AppColors.lightMuted,
    border: AppColors.lightBorder,
    borderHover: AppColors.lightBorderHover,
    overlay: AppColors.lightOverlay,
    success: AppColors.lightSuccess,
    warning: AppColors.lightWarning,
    error: AppColors.lightError,
    info: AppColors.lightInfo,
  );

  @override
  AppPalette copyWith({
    Color? canvas,
    Color? background,
    Color? surface,
    Color? surfaceSubtle,
    Color? surfaceHover,
    Color? card,
    Color? primary,
    Color? primaryHover,
    Color? onPrimary,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
    Color? borderHover,
    Color? overlay,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
  }) {
    return AppPalette(
      canvas: canvas ?? this.canvas,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      card: card ?? this.card,
      primary: primary ?? this.primary,
      primaryHover: primaryHover ?? this.primaryHover,
      onPrimary: onPrimary ?? this.onPrimary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      borderHover: borderHover ?? this.borderHover,
      overlay: overlay ?? this.overlay,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      canvas: l(canvas, other.canvas),
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceSubtle: l(surfaceSubtle, other.surfaceSubtle),
      surfaceHover: l(surfaceHover, other.surfaceHover),
      card: l(card, other.card),
      primary: l(primary, other.primary),
      primaryHover: l(primaryHover, other.primaryHover),
      onPrimary: l(onPrimary, other.onPrimary),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      border: l(border, other.border),
      borderHover: l(borderHover, other.borderHover),
      overlay: l(overlay, other.overlay),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      error: l(error, other.error),
      info: l(info, other.info),
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// The current theme's [AppPalette]. Falls back to dark if not registered.
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}
