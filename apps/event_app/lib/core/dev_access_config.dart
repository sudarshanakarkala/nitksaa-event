import 'package:flutter/foundation.dart';

import '../features/auth/domain/auth_session.dart';

abstract class DevAccessConfig {
  static const diagnosticsEmail = String.fromEnvironment(
    'DEV_DIAGNOSTICS_EMAIL',
  );
  static const diagnosticsPassword = String.fromEnvironment(
    'DEV_DIAGNOSTICS_PASSWORD',
  );

  static bool get isConfigured => diagnosticsEmail.trim().isNotEmpty;

  static bool canAccessDiagnostics(AuthSession? session) {
    if (!kDebugMode || !isConfigured) return false;
    final sessionEmail = session?.email?.trim().toLowerCase();
    return sessionEmail == diagnosticsEmail.trim().toLowerCase();
  }
}
