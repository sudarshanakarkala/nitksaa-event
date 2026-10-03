import 'package:flutter/material.dart';
import 'package:event_app/theme/app_colors.dart';
import 'package:event_app/theme/app_text_styles.dart';

class AppPrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool isLoading;
  final bool isDisabled;

  const AppPrimaryButton({
    Key? key,
    required this.onPressed,
    required this.child,
    this.isLoading = false,
    this.isDisabled = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool effectiveDisabled = isDisabled || isLoading || onPressed == null;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color backgroundColor = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;
    final Color onBackgroundColor = isDark ? AppColors.darkOnPrimary : AppColors.lightOnPrimary;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: effectiveDisabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: onBackgroundColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
              )
            : DefaultTextStyle(
                style: AppTextStyles.labelLarge,
                child: child,
              ),
      ),
    );
  }
}
