import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_tabs.dart';
import '../features/auth/domain/admin_access.dart';
import '../features/auth/services/auth_controller.dart';
import 'app_routes.dart';
import 'return_after_sign_in.dart';

abstract class RouteGuards {
  static String? redirect(BuildContext context, GoRouterState state) =>
      redirectFor(AuthController.instance, state.uri);

  /// The page opened (or refreshed) while sign-in was still being checked.
  /// The splash goes there once it is done ([afterSplash]).
  static String? _requested;

  /// [redirect], for [auth] at [uri].
  @visibleForTesting
  static String? redirectFor(AuthController auth, Uri uri) {
    final location = uri.path;

    final isSplash = location == AppRoutes.splash;
    final isLogin = location == AppRoutes.login;
    final isDeveloper = location == AppRoutes.developer;
    // Pages that need sign-in: My Events, an event's page and its checkout.
    final isProtected =
        location == AppRoutes.myEvents || location.startsWith('/events/');

    if (isDeveloper && !kDebugMode) return AppRoutes.login;

    // Policy and feedback pages open directly, even while sign-in is still
    // being checked, so links and page refreshes land on the right page.
    if (AppRoutes.publicPages.contains(location)) return null;
    // An entry pass link (often opened by a phone camera, from a cold start)
    // stays on its page; the page waits for sign-in itself.
    if (location.startsWith(AppRoutes.checkInPrefix)) return null;

    if (auth.isChecking) {
      if (isSplash) return null;
      // Remembered, so a page refresh comes back to the same page.
      _requested = uri.toString();
      return AppRoutes.splash;
    }

    if (location == AppRoutes.admin || location.startsWith('${AppRoutes.admin}/')) {
      return _adminRedirect(auth, uri);
    }

    if (auth.isAuthenticated) {
      // Just signed in: back to the page that asked for it, else Events.
      if (isLogin) return ReturnAfterSignIn.take() ?? AppRoutes.home;
      return null;
    }

    if (isProtected) return _signInFirst(uri);
    if (isSplash) return null;
    if (isLogin || isDeveloper) return null;

    return null;
  }

  /// Where the splash goes once sign-in has been checked: the page that was
  /// opened or refreshed, else the page that asked for sign-in (e.g. a
  /// check-in link, then an emailed sign-in link opened in a new tab), else
  /// Events.
  static String afterSplash(AuthController auth) {
    final requested = _requested;
    _requested = null;
    final back = auth.isAuthenticated ? ReturnAfterSignIn.take() : null;
    return requested ?? back ?? AppRoutes.home;
  }

  /// To sign-in, and back to [uri] afterwards.
  static String _signInFirst(Uri uri) {
    ReturnAfterSignIn.save(uri.toString());
    return AppRoutes.login;
  }

  /// `/admin…`: signed-out people go to sign-in (and back), non-admins to a
  /// page that says Admin is not for them. `/admin` and tabs the person
  /// can't see go to their landing tab.
  static String? _adminRedirect(AuthController auth, Uri uri) {
    if (!auth.isAuthenticated) return _signInFirst(uri);
    final access = auth.session?.access ?? AdminAccess.none;
    if (!access.hasAdminArea) return AppRoutes.notAdmin;

    final segments = uri.pathSegments;
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
