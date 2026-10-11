import 'package:flutter/foundation.dart';

/// Build switch for the NITiKa panel. Off by default: with it off the shell
/// gets no assistant and no code path calls NITiKa.
///
/// `--dart-define=NITIKA_ENABLED=true`
const nitikaEnabled = bool.fromEnvironment('NITIKA_ENABLED');

/// The events backend, resolved as in `events_repository.dart`. The panel
/// calls the backend's `/api/v1/nitika/chat`, never NITiKa itself.
String get nitikaBackendBaseUrl {
  const configured = String.fromEnvironment('BACKEND_BASE_URL');
  const devConfigured = String.fromEnvironment('DEV_BACKEND_BASE_URL');
  if (configured.isNotEmpty) return configured;
  if (devConfigured.isNotEmpty) return devConfigured;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://127.0.0.1:8000';
}
