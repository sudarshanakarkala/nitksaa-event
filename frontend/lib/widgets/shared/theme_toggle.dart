import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A reusable widget that toggles between light and dark theme.
///
/// Works for both Material and Cupertino designs. In Material it renders an
/// [IconButton]; in Cupertino it renders a [CupertinoButton] with the same
/// behaviour.
class ThemeToggle extends ConsumerWidget {
  const ThemeToggle({Key? key, required this.onToggle}) : super(key: key);

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final icon = isDark ? Icons.light_mode : Icons.dark_mode;
    final tooltip = isDark ? 'Light mode' : 'Dark mode';

    // Choose widget based on the current platform style.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onToggle,
        child: Icon(icon),
      );
    }
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onToggle,
    );
  }
}
