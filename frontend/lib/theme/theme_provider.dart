import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// App theme mode. Defaults to dark (like the website) and remembers the
/// user's choice on this device.
///
/// The settings box is opened once at startup ([openStorage], called from
/// main.dart). If it isn't open (e.g. in widget tests, or storage is
/// unavailable), the theme falls back to dark and the choice simply isn't
/// remembered. This notifier never opens Hive itself.
class ThemeNotifier extends Notifier<ThemeMode> {
  static const boxName = 'app_settings';
  static const _key = 'theme_mode';

  /// Opens the settings box. Call once after `Hive.initFlutter()`.
  static Future<void> openStorage() async {
    try {
      await Hive.openBox<dynamic>(boxName);
    } catch (_) {
      // Storage unavailable (e.g. private browsing): run without it.
    }
  }

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen(boxName) ? Hive.box<dynamic>(boxName) : null;

  @override
  ThemeMode build() {
    return switch (_box?.get(_key)) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  void setTheme(ThemeMode mode) {
    state = mode;
    try {
      _box?.put(_key, mode.name);
    } catch (_) {
      // Ignore: the choice just won't be remembered.
    }
  }

  void toggleTheme() {
    setTheme(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(
  ThemeNotifier.new,
);
