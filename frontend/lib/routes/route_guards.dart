import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/services/auth_controller.dart';
import 'app_routes.dart';

abstract class RouteGuards {
  static String? redirect(BuildContext context, GoRouterState state) {
    final auth = AuthController.instance;
    final location = state.uri.path;

    final isSplash = location == AppRoutes.splash;
    final isLogin = location == AppRoutes.login;
    final isFoundation = location == AppRoutes.foundation;
    final isDeveloper = location == AppRoutes.developer;
    final isProtected = location.startsWith('/events/');

    if (isDeveloper && !kDebugMode) return AppRoutes.login;

    // Policy and feedback pages open directly, even while sign-in is still
    // being checked, so links and page refreshes land on the right page.
    if (AppRoutes.publicPages.contains(location)) return null;

    if (auth.isChecking) {
      return isSplash ? null : AppRoutes.splash;
    }

    if (auth.isAuthenticated) {
      if (isLogin) return AppRoutes.home;
      return null;
    }

    if (isProtected) return AppRoutes.login;
    if (isSplash) return null;
    if (isLogin || isFoundation || isDeveloper) return null;

    return null;
  }
}
