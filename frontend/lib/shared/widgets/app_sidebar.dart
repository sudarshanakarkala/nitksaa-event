import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../routes/app_routes.dart';
import '../../features/auth/services/auth_controller.dart';
import '../../theme/app_palette.dart';

enum SidebarItemPermission {
  all, // Visible to everyone
  authenticated, // Visible only when logged in
  admin, // Visible only to admin users
}

class SidebarMenuItem {
  const SidebarMenuItem({
    required this.icon,
    required this.label,
    required this.route,
    this.permission = SidebarItemPermission.all,
    this.showWhenCollapsed = false,
  });

  final IconData icon;
  final String label;
  final String route;
  final SidebarItemPermission permission;
  final bool showWhenCollapsed;
}

class AppSidebar extends ConsumerStatefulWidget {
  const AppSidebar({
    super.key,
    this.initialCollapsed = false,
    this.onCollapsedChanged,
  });

  final bool initialCollapsed;
  final ValueChanged<bool>? onCollapsedChanged;

  static final List<SidebarMenuItem> _allMenuItems = [
    SidebarMenuItem(
      icon: Icons.calendar_month,
      label: 'Events',
      route: AppRoutes.home,
      permission: SidebarItemPermission.all,
      showWhenCollapsed: true,
    ),
    SidebarMenuItem(
      icon: Icons.bookmark,
      label: 'My Events',
      route: AppRoutes.myEvents,
      permission: SidebarItemPermission.authenticated,
      showWhenCollapsed: true,
    ),
    SidebarMenuItem(
      icon: Icons.verified_user_outlined,
      label: 'Volunteer',
      route: '/volunteer', // Placeholder route
      permission: SidebarItemPermission.authenticated,
    ),
    SidebarMenuItem(
      icon: Icons.admin_panel_settings_outlined,
      label: 'Manage Events',
      route: AppRoutes.manageEvents,
      permission: SidebarItemPermission.admin,
    ),
    SidebarMenuItem(
      icon: Icons.more_horiz,
      label: 'More',
      route: '/more', // Placeholder route
      permission: SidebarItemPermission.authenticated,
    ),
  ];

  @override
  ConsumerState<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends ConsumerState<AppSidebar> {
  late bool _isCollapsed;

  @override
  void initState() {
    super.initState();
    _isCollapsed = widget.initialCollapsed;
  }

  void _toggleCollapsed() {
    setState(() {
      _isCollapsed = !_isCollapsed;
    });
    widget.onCollapsedChanged?.call(_isCollapsed);
  }

  bool _hasPermission(SidebarItemPermission permission) {
    final auth = ref.read(authControllerProvider);
    switch (permission) {
      case SidebarItemPermission.all:
        return true;
      case SidebarItemPermission.authenticated:
        return auth.isAuthenticated;
      case SidebarItemPermission.admin:
        final userType = auth.session?.userType?.toLowerCase();
        return auth.isAuthenticated && userType == 'admin';
    }
  }

  List<SidebarMenuItem> _getVisibleMenuItems() {
    final currentRoute = GoRouterState.of(context).uri.toString();
    
    return AppSidebar._allMenuItems.where((item) {
      if (!_hasPermission(item.permission)) return false;
      
      // Hide Manage Events if not admin
      if (item.route == AppRoutes.manageEvents) {
        final userType = ref.read(authControllerProvider).session?.userType?.toLowerCase();
        return userType == 'admin';
      }
      
      return true;
    }).toList();
  }

  bool _isItemActive(String route) {
    final currentRoute = GoRouterState.of(context).uri.toString();
    final baseRoute = currentRoute.split('?').first;
    
    if (route == AppRoutes.home) {
      return baseRoute == AppRoutes.home || baseRoute == '/';
    }
    
    return baseRoute == route || baseRoute.startsWith('$route?');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final p = context.palette;
    final menuItems = _getVisibleMenuItems();
    final sidebarWidth = _isCollapsed ? 72.0 : 240.0;

    final activeBg = p.surfaceHover;
    final activeText = p.primary;
    final inactiveText = p.textSecondary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: p.background,
        border: Border(
          right: BorderSide(
            color: p.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with logo and collapse button
          Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  _isCollapsed ? 8 : 24,
                  24,
                  _isCollapsed ? 32 : 16,
                  24,
              ),
              child: SizedBox(
                width: _isCollapsed ? 20 : sidebarWidth - 40,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      color: p.primary,
                      size: _isCollapsed ? 20 : 24,
                    ),
                    if (!_isCollapsed) ...[
                      const SizedBox(width: 8),
                      Text(
                        'NITKSAA',
                        style: TextStyle(
                          fontFamily: 'Fraunces',
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: p.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 24,
              bottom: 24,
              child: GestureDetector(
                onTap: _toggleCollapsed,
                child: Tooltip(
                  message: _isCollapsed ? 'Expand' : 'Collapse',
                  child: Icon(
                    _isCollapsed ? Icons.chevron_right : Icons.chevron_left,
                    size: 18,
                    color: inactiveText,
                  ),
                ),
              ),
            ),
          ],
        ),

          const SizedBox(height: 16),

          // Menu items
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(
                horizontal: _isCollapsed ? 8 : 12,
              ),
              itemCount: menuItems.length,
              itemBuilder: (context, index) {
                final item = menuItems[index];
                final isActive = _isItemActive(item.route);

                return Container(
                  margin: const EdgeInsets.only(bottom: 6.0),
                  decoration: BoxDecoration(
                    color: isActive ? activeBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Tooltip(
                    message: _isCollapsed ? item.label : '',
                    child: ListTile(
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: _isCollapsed ? 8 : 12,
                        vertical: 4,
                      ),
                      leading: Icon(
                        item.icon,
                        size: 20,
                        color: isActive ? activeText : inactiveText,
                      ),
                      title: _isCollapsed
                          ? null
                          : Text(
                              item.label,
                              style: TextStyle(
                                color: isActive ? activeText : inactiveText,
                                fontSize: 13,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                      onTap: () {
                        if (isActive) return;
                        context.go(item.route);
                      },
                    ),
                  ),
                );
              },
            ),
          ),

          // User profile section at bottom
          if (auth.isAuthenticated) ...[
            const Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.fromLTRB(
                _isCollapsed ? 8 : 12,
                8,
                _isCollapsed ? 8 : 12,
                8,
              ),
              child: _isCollapsed
                  ? Tooltip(
                      message: auth.session?.fullname ?? 'User',
                      child: CircleAvatar(
                        backgroundColor: p.primary,
                        radius: 18,
                        child: Text(
                          (auth.session?.fullname ?? 'U').substring(0, 1).toUpperCase(),
                          style: TextStyle(
                            color: p.onPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: p.primary,
                          radius: 18,
                          child: Text(
                            (auth.session?.fullname ?? 'U').substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              color: p.onPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                auth.session?.fullname ?? 'Alumni User',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                auth.session?.userType ?? 'Member',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            // Logout button
            Padding(
              padding: EdgeInsets.fromLTRB(
                _isCollapsed ? 8 : 12,
                0,
                _isCollapsed ? 8 : 12,
                16,
              ),
              child: _isCollapsed
                  ? Tooltip(
                      message: 'Logout',
                      child: IconButton(
                        icon: const Icon(Icons.logout, size: 20),
                        color: inactiveText,
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Logout'),
                              content: const Text('Are you sure you want to logout?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Logout'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true && mounted) {
                            await ref.read(authControllerProvider.notifier).signOut();
                            if (mounted) {
                              context.go(AppRoutes.login);
                            }
                          }
                        },
                      ),
                    )
                  : ListTile(
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: _isCollapsed ? 8 : 12,
                        vertical: 4,
                      ),
                      leading: Icon(
                        Icons.logout,
                        size: 20,
                        color: p.error,
                      ),
                      title: Text(
                        'Logout',
                        style: TextStyle(
                          color: p.error,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Logout'),
                            content: const Text('Are you sure you want to logout?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Logout'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && mounted) {
                          await ref.read(authControllerProvider.notifier).signOut();
                          if (mounted) {
                            context.go(AppRoutes.login);
                          }
                        }
                      },
                    ),
            ),
          ] else ...[
            // Login button for unauthenticated users
            const Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.fromLTRB(
                _isCollapsed ? 8 : 12,
                8,
                _isCollapsed ? 8 : 12,
                16,
              ),
              child: _isCollapsed
                  ? Tooltip(
                      message: 'Login',
                      child: IconButton(
                        icon: const Icon(Icons.login, size: 20),
                        color: p.primary,
                        onPressed: () {
                          context.go(AppRoutes.login);
                        },
                      ),
                    )
                  : ListTile(
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: _isCollapsed ? 8 : 12,
                        vertical: 4,
                      ),
                      leading: Icon(
                        Icons.login,
                        size: 20,
                        color: p.primary,
                      ),
                      title: Text(
                        'Login',
                        style: TextStyle(
                          color: p.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        context.go(AppRoutes.login);
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}