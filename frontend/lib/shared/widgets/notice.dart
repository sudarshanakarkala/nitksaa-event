import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';

/// What a notice is about. Decides its colour, icon and how long it stays.
enum NoticeKind { info, success, warning, error }

/// Shows a short message at the bottom of the screen: the one way the app
/// tells people something happened. Every screen uses this, so notices look
/// and behave the same everywhere.
///
/// - colour and icon by [kind]: green success, yellow warning, red error,
///   blue information;
/// - errors stay until closed (they're the ones people must not miss);
///   warnings stay 8 seconds, the rest 4; all can be closed with ×;
/// - a new notice replaces the one showing.
///
/// [action] adds a button (e.g. "View refund"); [persist] keeps the notice
/// up until it is closed, whatever its kind.
void showNotice(
  BuildContext context,
  String message, {
  NoticeKind kind = NoticeKind.info,
  SnackBarAction? action,
  bool? persist,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final p = context.palette;
  final tone = switch (kind) {
    NoticeKind.success => p.success,
    NoticeKind.warning => p.warning,
    NoticeKind.error => p.error,
    NoticeKind.info => p.info,
  };
  final icon = switch (kind) {
    NoticeKind.success => Icons.check_circle_outline,
    NoticeKind.warning => Icons.warning_amber_rounded,
    NoticeKind.error => Icons.error_outline,
    NoticeKind.info => Icons.info_outline,
  };
  final stays = persist ?? kind == NoticeKind.error;
  final width = MediaQuery.sizeOf(context).width;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        // On wide screens a centred card, not a thin strip across the page.
        width: width > 720 ? 560 : null,
        backgroundColor: p.tinted(tone, 0.28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: tone.withValues(alpha: 0.7), width: 1.2),
        ),
        elevation: 6,
        showCloseIcon: true,
        closeIconColor: p.textSecondary,
        action: action,
        persist: stays,
        duration: stays
            ? const Duration(days: 1)
            : Duration(seconds: kind == NoticeKind.warning ? 8 : 4),
        content: Row(
          children: [
            Icon(icon, color: tone, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
}
