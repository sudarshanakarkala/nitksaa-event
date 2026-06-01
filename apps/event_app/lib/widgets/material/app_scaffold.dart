import 'package:flutter/material.dart';
import 'package:nitksaa_event/apps/event_app/lib/theme/app_colors.dart';

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
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color backgroundColor = isDark ? AppColors.darkBackground : AppColors.lightBackground;

    return Scaffold(
      key: scaffoldMessengerKey,
      backgroundColor: backgroundColor,
      appBar: appBar ?? AppBar(
        title: const Text(''),
        backgroundColor: backgroundColor,
        elevation: 0,
      ),
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
