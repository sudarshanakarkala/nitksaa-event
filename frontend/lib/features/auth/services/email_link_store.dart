import 'package:hive_flutter/hive_flutter.dart';

/// Remembers which email a sign-in link was sent to, so the link can be
/// completed when it is opened on this device (Firebase needs the email).
///
/// Uses the `app_settings` box that main.dart opens at startup. If storage
/// is unavailable, nothing is remembered and the login screen asks for the
/// email instead.
abstract class EmailLinkStore {
  static const _boxName = 'app_settings';
  static const _key = 'emailForSignIn';

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen(_boxName) ? Hive.box<dynamic>(_boxName) : null;

  static String? load() {
    final value = _box?.get(_key);
    return value is String && value.isNotEmpty ? value : null;
  }

  static Future<void> save(String email) async {
    try {
      await _box?.put(_key, email);
    } catch (_) {
      // Not remembered: the login screen will ask for the email.
    }
  }

  static Future<void> clear() async {
    try {
      await _box?.delete(_key);
    } catch (_) {}
  }
}
