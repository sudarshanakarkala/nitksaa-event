import 'package:hive_flutter/hive_flutter.dart';

/// Remembers the page to come back to after signing in, on this device.
///
/// Used by the check-in page: a volunteer who scans a QR while signed out
/// signs in (often with an emailed link that opens a new tab) and lands back
/// on that person's check-in page instead of the Events list. Kept in the
/// `app_settings` box (see `EmailLinkStore`), so it survives the new tab.
/// Used once, and forgotten after 30 minutes.
abstract class ReturnAfterSignIn {
  static const _boxName = 'app_settings';
  static const _pathKey = 'returnAfterSignIn';
  static const _atKey = 'returnAfterSignInAt';
  static const _keepFor = Duration(minutes: 30);

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen(_boxName) ? Hive.box<dynamic>(_boxName) : null;

  static void save(String path) {
    try {
      _box?.put(_pathKey, path);
      _box?.put(_atKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Not remembered: after sign-in the person lands on Events.
    }
  }

  /// The remembered page, if any and still fresh; forgets it either way.
  static String? take() {
    final box = _box;
    if (box == null) return null;
    final path = box.get(_pathKey);
    final at = box.get(_atKey);
    try {
      box.delete(_pathKey);
      box.delete(_atKey);
    } catch (_) {}
    if (path is! String || path.isEmpty || at is! int) return null;
    final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at));
    return age <= _keepFor ? path : null;
  }
}
