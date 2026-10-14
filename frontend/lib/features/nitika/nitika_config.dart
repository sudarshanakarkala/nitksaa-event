/// The events backend, resolved as in `events_repository.dart`. The panel
/// calls the backend's `/api/v1/nitika/chat`, never NITiKa itself.
String get nitikaBackendBaseUrl {
  const configured = String.fromEnvironment('BACKEND_BASE_URL');
  const devConfigured = String.fromEnvironment('DEV_BACKEND_BASE_URL');
  if (configured.isNotEmpty) return configured;
  if (devConfigured.isNotEmpty) return devConfigured;
  return 'http://127.0.0.1:8000';
}
