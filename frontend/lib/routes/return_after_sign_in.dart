import 'package:hive_flutter/hive_flutter.dart';

/// Remembers the page to come back to after signing in, on this device.
///
/// Used by the check-in page: a volunteer who scans a QR while signed out
/// signs in (often with an emailed link that opens a new tab) and lands back
/// on that person's check-in page instead of the Events list. Kept in the
/// `app_settings` box (see `EmailLinkStore`), so it survives the new tab.
/// Used once, and forgotten after 30 minutes.
///
/// Also used by the route guard for every page that needs sign-in
/// (ISSUE-021). A copy is kept in memory too, for when the box isn't open.
abstract class ReturnAfterSignIn {
  static const _boxName = 'app_settings';
  static const _pathKey = 'returnAfterSignIn';
  static const _atKey = 'returnAfterSignInAt';
  static const _keepFor = Duration(minutes: 30);

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen(_boxName) ? Hive.box<dynamic>(_boxName) : null;

  static String? _memoryPath;
  static int? _memoryAt;

  static void save(String path) {
    _memoryPath = path;
    _memoryAt = DateTime.now().millisecondsSinceEpoch;
    try {
      _box?.put(_pathKey, path);
      _box?.put(_atKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Kept in memory only: lost if sign-in finishes in a new tab.
    }
  }

  /// The remembered page, if any and still fresh; forgets it either way.
  static String? take() {
    final box = _box;
    final stored = box?.get(_pathKey);
    final path = stored ?? _memoryPath;
    final at = stored != null ? box?.get(_atKey) : _memoryAt;
    _memoryPath = null;
    _memoryAt = null;
    try {
      box?.delete(_pathKey);
      box?.delete(_atKey);
    } catch (_) {}
    if (path is! String || path.isEmpty || at is! int) return null;
    final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at));
    return age <= _keepFor ? path : null;
  }
}
