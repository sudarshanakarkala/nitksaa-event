import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_text_styles.dart';

/// Light and dark themes matching the association website.
///
/// Component styles follow website/frontend/src/styles/global.css:
/// buttons radius 6, cards radius 12, gold-tinted borders, gold focus.
abstract class AppTheme {
  static ThemeData get light => _build(AppPalette.light, Brightness.light);
  static ThemeData get dark => _build(AppPalette.dark, Brightness.dark);

  static const double radiusSm = 6;
  static const double radiusMd = 12;
  static const double radiusLg = 20;

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: p.primary,
      brightness: brightness,
    ).copyWith(
      primary: p.primary,
      onPrimary: p.onPrimary,
      primaryContainer: p.primary.withValues(alpha: 0.14),
      onPrimaryContainer: p.primary,
      secondary: p.textSecondary,
      onSecondary: p.background,
      tertiary: p.info,
      error: p.error,
      onError: p.background,
      errorContainer: p.error.withValues(alpha: 0.10),
      onErrorContainer: p.error,
      surface: p.background,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceContainerLowest: p.canvas,
      surfaceContainerLow: Color.alphaBlend(p.surfaceSubtle, p.background),
      surfaceContainer: Color.alphaBlend(p.surfaceHover, p.background),
      surfaceContainerHigh: p.surface,
      surfaceContainerHighest: p.surface,
      outline: p.borderHover,
      outlineVariant: p.border,
      scrim: p.overlay,
      inverseSurface: p.textPrimary,
      onInverseSurface: p.background,
      inversePrimary: p.primaryHover,
      surfaceTint: Colors.transparent,
    );

    final textTheme = const TextTheme(
      headlineLarge: AppTextStyles.headlineLarge,
      headlineMedium: AppTextStyles.headlineMedium,
      headlineSmall: AppTextStyles.headlineSmall,
      titleLarge: AppTextStyles.titleLarge,
      titleMedium: AppTextStyles.titleMedium,
      titleSmall: AppTextStyles.titleSmall,
      bodyLarge: AppTextStyles.bodyLarge,
      bodyMedium: AppTextStyles.bodyMedium,
      bodySmall: AppTextStyles.bodySmall,
      labelLarge: AppTextStyles.labelLarge,
      labelMedium: AppTextStyles.labelMedium,
      labelSmall: AppTextStyles.labelSmall,
    ).apply(
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
    );

    final smallShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusSm),
    );
    final mediumShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMd),
      side: BorderSide(color: p.border),
    );

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: color, width: width),
        );

    final primaryButtonStyle = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return p.primary.withValues(alpha: 0.4);
        }
        if (states.contains(WidgetState.hovered)) return p.primaryHover;
        return p.primary;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return p.onPrimary.withValues(alpha: 0.7);
        }
        return p.onPrimary;
      }),
      overlayColor: WidgetStatePropertyAll(p.onPrimary.withValues(alpha: 0.08)),
      elevation: const WidgetStatePropertyAll(0),
      shape: WidgetStatePropertyAll(smallShape),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      ),
      textStyle: const WidgetStatePropertyAll(AppTextStyles.labelLarge),
    );

    final ghostButtonStyle = ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return p.textSecondary.withValues(alpha: 0.4);
        }
        if (states.contains(WidgetState.hovered)) return p.textPrimary;
        return p.textSecondary;
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) return p.surfaceSubtle;
        return Colors.transparent;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return BorderSide(color: p.border.withValues(alpha: 0.4));
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return BorderSide(color: p.borderHover);
        }
        return BorderSide(color: p.border);
      }),
      overlayColor: WidgetStatePropertyAll(p.textPrimary.withValues(alpha: 0.04)),
      shape: WidgetStatePropertyAll(smallShape),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      ),
      textStyle: const WidgetStatePropertyAll(AppTextStyles.labelLarge),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: AppTextStyles.sans,
      textTheme: textTheme,
      // iOS layouts (also used by Safari on iPhone) default to Apple's system
      // font, which web builds don't have; use the website fonts there too.
      cupertinoOverrideTheme: CupertinoThemeData(
        primaryColor: p.primary,
        textTheme: CupertinoTextThemeData(
          primaryColor: p.primary,
          textStyle: TextStyle(
            fontFamily: AppTextStyles.sans,
            fontSize: 17,
            color: p.textPrimary,
          ),
          actionTextStyle: TextStyle(
            fontFamily: AppTextStyles.sans,
            fontSize: 17,
            color: p.primary,
          ),
          navTitleTextStyle: TextStyle(
            fontFamily: AppTextStyles.sans,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
          navLargeTitleTextStyle: TextStyle(
            fontFamily: AppTextStyles.serif,
            fontSize: 34,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
          tabLabelTextStyle: TextStyle(
            fontFamily: AppTextStyles.sans,
            fontSize: 10,
            color: p.textMuted,
          ),
        ),
      ),
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      dividerColor: p.border,
      hoverColor: p.surfaceHover,
      focusColor: p.primary.withValues(alpha: 0.12),
      splashColor: p.primary.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
      extensions: <ThemeExtension<dynamic>>[p],
      appBarTheme: AppBarTheme(
        backgroundColor: p.canvas,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: AppTextStyles.titleLarge.copyWith(color: p.textPrimary),
        shape: Border(bottom: BorderSide(color: p.border)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: primaryButtonStyle),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButtonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: ghostButtonStyle),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(p.primary),
          overlayColor: WidgetStatePropertyAll(p.primary.withValues(alpha: 0.08)),
          shape: WidgetStatePropertyAll(smallShape),
          textStyle: const WidgetStatePropertyAll(AppTextStyles.labelLarge),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return p.primary;
            return p.textSecondary;
          }),
          shape: WidgetStatePropertyAll(smallShape),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceSubtle,
        hoverColor: p.surfaceHover,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: inputBorder(p.border),
        enabledBorder: inputBorder(p.border),
        focusedBorder: inputBorder(p.primary),
        disabledBorder: inputBorder(p.border.withValues(alpha: 0.5)),
        errorBorder: inputBorder(p.error),
        focusedErrorBorder: inputBorder(p.error),
        labelStyle: AppTextStyles.bodyMedium.copyWith(color: p.textMuted),
        floatingLabelStyle: AppTextStyles.bodyMedium.copyWith(color: p.primary),
        hintStyle: AppTextStyles.bodyMedium.copyWith(color: p.textMuted),
        helperStyle: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
        errorStyle: AppTextStyles.bodySmall.copyWith(color: p.error),
        prefixIconColor: p.textMuted,
        suffixIconColor: p.textMuted,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.primary,
        selectionColor: p.primary.withValues(alpha: 0.3),
        selectionHandleColor: p.primary,
      ),
      cardTheme: CardThemeData(
        color: p.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: mediumShape,
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        barrierColor: p.overlay,
        shape: mediumShape,
        titleTextStyle: AppTextStyles.titleLarge.copyWith(color: p.textPrimary),
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: p.overlay,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusMd)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: mediumShape,
        textStyle: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceSubtle,
        selectedColor: p.primary.withValues(alpha: 0.12),
        disabledColor: p.surfaceSubtle,
        side: BorderSide(color: p.border),
        shape: const StadiumBorder(),
        labelStyle: AppTextStyles.labelSmall.copyWith(color: p.textSecondary),
        secondaryLabelStyle: AppTextStyles.labelSmall.copyWith(color: p.primary),
        checkmarkColor: p.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surface,
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(color: p.textPrimary),
        actionTextColor: p.primary,
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          side: BorderSide(color: p.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.border,
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.primary;
          return p.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return p.primary.withValues(alpha: 0.2);
          }
          return p.surfaceSubtle;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return p.primary.withValues(alpha: 0.5);
          }
          return p.border;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(p.onPrimary),
        side: BorderSide(color: p.borderHover),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.primary;
          return p.textMuted;
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.primary,
        unselectedLabelColor: p.textMuted,
        indicatorColor: p.primary,
        dividerColor: p.border,
        labelStyle: AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: AppTextStyles.labelLarge,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.canvas,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.primary.withValues(alpha: 0.12),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: p.primary);
          }
          return IconThemeData(color: p.textMuted);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final base = AppTextStyles.labelSmall;
          if (states.contains(WidgetState.selected)) {
            return base.copyWith(color: p.primary);
          }
          return base.copyWith(color: p.textMuted);
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.canvas,
        selectedItemColor: p.primary,
        unselectedItemColor: p.textMuted,
        elevation: 0,
        selectedLabelStyle: AppTextStyles.labelSmall,
        unselectedLabelStyle: AppTextStyles.labelSmall,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        selectedColor: p.primary,
        selectedTileColor: p.primary.withValues(alpha: 0.08),
        shape: smallShape,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(radiusSm),
          border: Border.all(color: p.border),
        ),
        textStyle: AppTextStyles.bodySmall.copyWith(color: p.textPrimary),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.border),
        radius: const Radius.circular(3),
        thickness: const WidgetStatePropertyAll(6),
      ),
    );
  }
}
