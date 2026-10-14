import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_tabs.dart';
import '../features/auth/domain/admin_access.dart';
import '../features/auth/services/auth_controller.dart';
import 'app_routes.dart';
import 'return_after_sign_in.dart';

abstract class RouteGuards {
  static String? redirect(BuildContext context, GoRouterState state) {
    final auth = AuthController.instance;
    final location = state.uri.path;

    final isSplash = location == AppRoutes.splash;
    final isLogin = location == AppRoutes.login;
    final isDeveloper = location == AppRoutes.developer;
    final isProtected = location.startsWith('/events/');

    if (isDeveloper && !kDebugMode) return AppRoutes.login;

    // Policy and feedback pages open directly, even while sign-in is still
    // being checked, so links and page refreshes land on the right page.
    if (AppRoutes.publicPages.contains(location)) return null;
    // An entry pass link (often opened by a phone camera, from a cold start)
    // stays on its page; the page waits for sign-in itself.
    if (location.startsWith(AppRoutes.checkInPrefix)) return null;

    if (auth.isChecking) {
      return isSplash ? null : AppRoutes.splash;
    }

    if (location == AppRoutes.admin || location.startsWith('${AppRoutes.admin}/')) {
      return _adminRedirect(auth, location);
    }

    if (auth.isAuthenticated) {
      // Just signed in: back to the page that asked for it, else Events.
      if (isLogin) return ReturnAfterSignIn.take() ?? AppRoutes.home;
      return null;
    }

    if (isProtected) return AppRoutes.login;
    if (isSplash) return null;
    if (isLogin || isDeveloper) return null;

    return null;
  }

  /// `/admin…`: signed-out people go to login, non-admins to Events.
  /// `/admin` and tabs the person can't see go to their landing tab.
  static String? _adminRedirect(AuthController auth, String location) {
    if (!auth.isAuthenticated) return AppRoutes.login;
    final access = auth.session?.access ?? AdminAccess.none;
    if (!access.hasAdminArea) return AppRoutes.home;

    final segments = Uri.parse(location).pathSegments;
    // Deeper admin pages, e.g. /admin/events/:id/registrations.
    if (segments.length > 2) return null;

    final tab = segments.length == 2 ? AdminTab.fromSlug(segments[1]) : null;
    if (tab != null && tab.visibleTo(access)) return null;

    final visible = AdminTab.visibleTabs(access);
    if (visible.contains(AdminTab.landing)) {
      // Plain /admin: the page may move on to Check-in on an event day.
      return segments.length < 2
          ? '${AdminTab.landing.path}?${AdminTab.landingQuery}'
          : AdminTab.landing.path;
    }
    return visible.first.path;
  }
}
