import 'package:flutter/material.dart';
import 'package:nitksaa_event/apps/event_app/lib/theme/app_colors.dart';
import 'package:nitksaa_event/apps/event_app/lib/theme/app_text_styles.dart';

class AppSecondaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final bool isLoading;

  const AppSecondaryButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color background = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final Color border = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;
    final Color textColor = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    return OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: background,
        side: BorderSide(color: border, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      child: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              label,
              style: AppTextStyles.labelLarge.copyWith(color: textColor),
            ),
    );
  }
}
