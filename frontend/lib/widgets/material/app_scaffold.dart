import 'package:flutter/material.dart';
import 'package:event_app/theme/app_palette.dart';

class AppScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final bool extendBodyBehindAppBar;
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  const AppScaffold({
    Key? key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.extendBodyBehindAppBar = false,
    this.scaffoldMessengerKey,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = context.palette.background;

    return Scaffold(
      key: scaffoldMessengerKey,
      backgroundColor: backgroundColor,
      // If appBar is provided, use it; otherwise no app bar (e.g., splash screen)
      appBar: appBar,
      body: SafeArea(
        child: body ?? const SizedBox.shrink(),
      ),
      floatingActionButton: floatingActionButton,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
    );
  }

  /// Helper to show a snackbar consistently.
  static void showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
