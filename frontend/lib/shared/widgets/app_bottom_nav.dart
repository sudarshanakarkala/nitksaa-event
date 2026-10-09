import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../routes/app_routes.dart';
import '../../features/auth/services/auth_controller.dart';
import '../../theme/app_palette.dart';

/// A shared bottom navigation bar used across all main screens.
/// Shows different items based on user authentication status and permissions.
/// On web screens with width >= 900, this returns null (sidebar is used instead).
class AppBottomNav extends ConsumerWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
  });

  /// The index of the currently active tab.
  final int currentIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWebScreen = MediaQuery.of(context).size.width >= 900;

    // On wide web screens, the sidebar handles navigation instead
    if (isWebScreen) return const SizedBox.shrink();

    final auth = ref.watch(authControllerProvider);
    final isAdmin = auth.session?.userType?.toLowerCase() == 'admin';

    // Build destinations based on user permissions
    final destinations = <NavigationDestination>[];
    final destinationRoutes = <String>[];

    // Events - always visible
    destinations.add(const NavigationDestination(
      icon: Icon(Icons.calendar_month_outlined),
      selectedIcon: Icon(Icons.calendar_month),
      label: 'Events',
    ));
    destinationRoutes.add(AppRoutes.home);

    // My Events - visible when authenticated
    if (auth.isAuthenticated) {
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.bookmark_border),
        selectedIcon: Icon(Icons.bookmark),
        label: 'My Events',
      ));
      destinationRoutes.add(AppRoutes.myEvents);
    }

    // Manage Events - visible only for admin users
    if (auth.isAuthenticated && isAdmin) {
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.admin_panel_settings_outlined),
        selectedIcon: Icon(Icons.admin_panel_settings),
        label: 'Manage',
      ));
      destinationRoutes.add(AppRoutes.manageEvents);
    }

    // If no destinations, return empty
    if (destinations.isEmpty) return const SizedBox.shrink();

    // NavigationBar requires at least 2 destinations.
    // When unauthenticated, show a simple bar with Events + login prompt.
    if (destinations.length < 2) {
      return SafeArea(
        top: false,
        child: SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSingleNavItem(
                context: context,
                icon: Icons.calendar_month_outlined,
                selectedIcon: Icons.calendar_month,
                label: 'Events',
                isActive: currentIndex == 0,
                onTap: () => context.go(AppRoutes.home),
              ),
              _buildSingleNavItem(
                context: context,
                icon: Icons.login_outlined,
                selectedIcon: Icons.login,
                label: 'Login',
                isActive: false,
                onTap: () => context.go(AppRoutes.login),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: NavigationBar(
        selectedIndex: currentIndex.clamp(0, destinations.length - 1),
        onDestinationSelected: (index) {
          final route = destinationRoutes[index];
          if (route != GoRouterState.of(context).uri.toString()) {
            context.go(route);
          }
        },
        destinations: destinations,
      ),
    );
  }

  Widget _buildSingleNavItem({
    required BuildContext context,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final color = isActive
        ? context.palette.primary
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isActive ? selectedIcon : icon, color: color, size: 16),
              const SizedBox(height: 1),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 9, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}