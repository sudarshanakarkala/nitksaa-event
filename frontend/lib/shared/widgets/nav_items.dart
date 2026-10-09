import 'package:flutter/material.dart';

import '../../features/auth/services/auth_controller.dart';
import '../../routes/app_routes.dart';

/// App navigation: the header links on wide screens and the menu on phones.
class NavItem {
  const NavItem({
    required this.label,
    required this.route,
    required this.icon,
    this.signedInOnly = false,
    this.adminOnly = false,
  });

  final String label;
  final String route;
  final IconData icon;
  final bool signedInOnly;
  final bool adminOnly;
}

// Website pattern: "My ..." is a filter on the list page and "Manage" is
// an admin button there, not a nav link. My Events is also in the account
// menu.
const List<NavItem> navItems = [
  NavItem(label: 'Events', route: AppRoutes.home, icon: Icons.calendar_month_outlined),
];

List<NavItem> visibleNavItems(AuthController auth) {
  final isAdmin = auth.session?.userType.toLowerCase() == 'admin';
  return navItems.where((item) {
    if (item.adminOnly) return auth.isAuthenticated && isAdmin;
    if (item.signedInOnly) return auth.isAuthenticated;
    return true;
  }).toList();
}

/// Whether [item] is the section the [location] belongs to.
bool isNavItemActive(NavItem item, String location) {
  switch (item.route) {
    case AppRoutes.home:
      // The whole Events section: list, detail, checkout, my events, manage.
      return location == AppRoutes.home ||
          location.startsWith('/events/') ||
          location.startsWith(AppRoutes.myEvents) ||
          location.startsWith(AppRoutes.manageEvents) ||
          location.startsWith('/admin/');
    case AppRoutes.manageEvents:
      return location.startsWith(AppRoutes.manageEvents) ||
          location.startsWith('/admin/');
    default:
      return location.startsWith(item.route);
  }
}
