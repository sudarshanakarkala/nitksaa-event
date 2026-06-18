import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/services/auth_controller.dart';
import 'app_routes.dart';

abstract class RouteGuards {
  static String? redirect(BuildContext context, GoRouterState state) {
    final auth = AuthController.instance;
    final location = state.uri.path;

    final isRoot = location == AppRoutes.root;
    final isSplash = location == AppRoutes.splash;
    final isLogin = location == AppRoutes.login;
    final isEvents = location == AppRoutes.events ||
        location.startsWith('${AppRoutes.events}/');
    final isFoundation = location == AppRoutes.foundation;
    final isDeveloper = location == AppRoutes.developer;
    final isProtected = location == AppRoutes.home;

    if (isDeveloper && !kDebugMode) return AppRoutes.login;

    if (auth.isChecking) {
      return (isRoot || isSplash || isEvents) ? null : AppRoutes.root;
    }

    if (isDeveloper) {
      if (!auth.isAuthenticated) return AppRoutes.login;
      return auth.canAccessDeveloperDiagnostics ? null : AppRoutes.home;
    }

    if (auth.isAuthenticated) {
      if (isLogin || isSplash) return AppRoutes.home;
      return null;
    }

    if (isProtected) return AppRoutes.login;
    if (isRoot || isSplash || isLogin || isEvents || isFoundation) {
      return null;
    }

    return null;
  }
}
