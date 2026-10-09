import 'package:flutter/material.dart';

import '../../features/auth/services/auth_controller.dart';
import '../../routes/app_routes.dart';

/// App navigation: the header links on wide screens and the menu on phones.
/// Same items and visibility rules as the old sidebar.
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

const List<NavItem> navItems = [
  NavItem(label: 'Events', route: AppRoutes.home, icon: Icons.calendar_month_outlined),
  NavItem(
    label: 'My Events',
    route: AppRoutes.myEvents,
    icon: Icons.bookmark_border,
    signedInOnly: true,
  ),
  NavItem(
    label: 'Manage Events',
    route: AppRoutes.manageEvents,
    icon: Icons.admin_panel_settings_outlined,
    adminOnly: true,
  ),
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
      return location == AppRoutes.home || location.startsWith('/events/');
    case AppRoutes.manageEvents:
      return location.startsWith(AppRoutes.manageEvents) ||
          location.startsWith('/admin/');
    default:
      return location.startsWith(item.route);
  }
}
