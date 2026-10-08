import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// App theme mode. Defaults to dark (like the website) and remembers the
/// user's choice on this device.
class ThemeNotifier extends Notifier<ThemeMode> {
  static const _boxName = 'app_settings';
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    _loadSaved();
    return ThemeMode.dark;
  }

  void setTheme(ThemeMode mode) {
    state = mode;
    _save(mode);
  }

  void toggleTheme() {
    setTheme(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  Future<void> _loadSaved() async {
    try {
      final box = await Hive.openBox<dynamic>(_boxName);
      final saved = box.get(_key);
      final mode = switch (saved) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        'dark' => ThemeMode.dark,
        _ => null,
      };
      if (mode != null && mode != state) state = mode;
    } catch (_) {
      // Storage unavailable (e.g. private browsing): keep the default.
    }
  }

  Future<void> _save(ThemeMode mode) async {
    try {
      final box = await Hive.openBox<dynamic>(_boxName);
      await box.put(_key, mode.name);
    } catch (_) {
      // Ignore: the choice just won't be remembered.
    }
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(
  ThemeNotifier.new,
);
