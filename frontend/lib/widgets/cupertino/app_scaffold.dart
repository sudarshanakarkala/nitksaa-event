import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // for ScaffoldMessenger fallback
import 'package:event_app/theme/app_palette.dart';

class AppScaffoldCupertino extends StatelessWidget {
  final ObstructingPreferredSizeWidget? navigationBar;
  final Widget? child;
  final bool extendBodyBehindAppBar;
  const AppScaffoldCupertino({
    Key? key,
    this.navigationBar,
    this.child,
    this.extendBodyBehindAppBar = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color background = context.palette.background;
    return CupertinoPageScaffold(
      navigationBar: navigationBar ?? const CupertinoNavigationBar(),
      backgroundColor: background,
      child: SafeArea(
        top: !extendBodyBehindAppBar,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }

  /// Show a snackbar‑like message on iOS using a fallback dialog.
  static void showSnackBar(BuildContext context, String message) {
    // Use ScaffoldMessenger if a Material Scaffold is ancestor, otherwise CupertinoAlertDialog.
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } else {
      showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Notice'),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
  }
}
