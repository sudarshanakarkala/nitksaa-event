import 'package:flutter/material.dart';
import 'package:event_app/theme/app_palette.dart';
import 'package:event_app/theme/app_text_styles.dart';

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
    final p = context.palette;
    final Color background = p.surfaceSubtle;
    final Color border = p.primary;
    final Color textColor = p.primary;

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
