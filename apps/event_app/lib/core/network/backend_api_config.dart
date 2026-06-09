import 'package:flutter/foundation.dart';

abstract class BackendApiConfig {
  static const String _configured = String.fromEnvironment('BACKEND_BASE_URL');
  static const String _devConfigured = String.fromEnvironment(
    'DEV_BACKEND_BASE_URL',
  );

  static String get baseUrl {
    if (_configured.isNotEmpty) return _configured;
    if (_devConfigured.isNotEmpty) return _devConfigured;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }
}
