import 'package:hive_flutter/hive_flutter.dart';

import '../domain/auth_session.dart';

class AuthSessionStore {
  static const _boxName = 'auth_session';
  static const _sessionKey = 'backend_session';

  Box<dynamic>? _box;

  Future<void> initialize() async {
    _box ??= await Hive.openBox<dynamic>(_boxName);
  }

  Future<AuthSession?> load() async {
    await initialize();
    final raw = _box?.get(_sessionKey);
    if (raw is Map) {
      final session = AuthSession.fromStoredMap(raw);
      return session.isValid ? session : null;
    }
    return null;
  }

  Future<void> save(AuthSession session) async {
    await initialize();
    await _box?.put(_sessionKey, session.toStoredMap());
  }

  Future<void> clear() async {
    await initialize();
    await _box?.delete(_sessionKey);
  }
}
