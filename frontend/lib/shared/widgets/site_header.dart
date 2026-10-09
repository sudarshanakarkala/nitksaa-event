import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/services/auth_controller.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/theme_provider.dart';
import 'nav_items.dart';

/// Top bar matching the association website's navbar
/// (website: components/core/Navbar.jsx, styles/navbar.css).
///
/// Brand and nav links on the left; theme toggle and account on the right.
/// Below [navBreakpoint] the links move into a menu ([SiteNavDrawer]),
/// opened from the menu button, which needs a Scaffold with that endDrawer.
class SiteHeader extends ConsumerWidget {
  const SiteHeader({super.key, this.showThemeToggle = true});

  /// The header toggle is the app's only theme switch.
  final bool showThemeToggle;

  static const double height = 68;
  static const double compactHeight = 56;
  static const double maxContentWidth = 1520;
  static const double navBreakpoint = 900;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;
    final wide = width >= navBreakpoint;
    final location = GoRouterState.of(context).uri.path;
    final items = visibleNavItems(ref.watch(authControllerProvider));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: p.background.withValues(alpha: 0.96),
      child: Container(
        height: compact ? compactHeight : height,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.border)),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxContentWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 40),
              child: Row(
                children: [
                  _Brand(compact: compact, isDark: isDark),
                  if (wide) ...[
                    const SizedBox(width: 40),
                    for (final item in items)
                      _NavLink(
                        item: item,
                        active: isNavItemActive(item, location),
                      ),
                  ],
                  const Spacer(),
                  if (showThemeToggle) ...[
                    _HeaderIconButton(
                      tooltip: isDark ? 'Light mode' : 'Dark mode',
                      icon: isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      onPressed: () =>
                          ref.read(themeProvider.notifier).toggleTheme(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const _AccountButton(),
                  if (!wide) ...[
                    const SizedBox(width: 8),
                    _HeaderIconButton(
                      tooltip: 'Menu',
                      icon: Icons.menu,
                      onPressed: () => Scaffold.of(context).openEndDrawer(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.compact, required this.isDark});

  final bool compact;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    // Gold artwork on dark, navy on light (NITKSAA Events logo set).
    final tone = isDark ? 'dark' : 'light';
    final emblem = isDark ? 'gold' : 'navy';

    return Semantics(
      button: true,
      label: 'NITKSAA Events home',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => context.go(AppRoutes.home),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          // Wide: the logo carries the "NITKSAA Events" wordmark itself.
          child: compact
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/images/nitksaa-emblem-$emblem.png', height: 32),
                    const SizedBox(width: 10),
                    Text(
                      'NITKSAA Events',
                      style: AppTextStyles.titleLarge.copyWith(
                        fontSize: 17,
                        color: p.textPrimary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                )
              : Image.asset('assets/images/nitksaa-events-logo-on-$tone.png', height: 48),
        ),
      ),
    );
  }
}

/// 34×34 square icon button with border, like the website's nav icons.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 34,
        height: 34,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: p.surfaceSubtle,
            foregroundColor: p.textSecondary,
            side: BorderSide(color: p.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ).copyWith(
            foregroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.hovered)
                    ? p.primary
                    : p.textSecondary),
          ),
          child: Icon(icon, size: 16),
        ),
      ),
    );
  }
}

class _AccountButton extends ConsumerWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final auth = ref.watch(authControllerProvider);

    if (!auth.isAuthenticated) {
      return OutlinedButton(
        onPressed: () => context.go(AppRoutes.login),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          minimumSize: const Size(0, 34),
        ),
        child: const Text('Sign in'),
      );
    }

    final name = (auth.session?.fullname ?? '').trim();
    final initials = name
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();

    return PopupMenuButton<String>(
      tooltip: name.isEmpty ? 'Account' : name,
      offset: const Offset(0, 44),
      onSelected: (value) async {
        if (value == 'my-events') {
          context.go(AppRoutes.myEvents);
        } else if (value == 'sign-out') {
          await ref.read(authControllerProvider.notifier).signOut();
          if (context.mounted) context.go(AppRoutes.login);
        }
      },
      itemBuilder: (context) => [
        if (name.isNotEmpty)
          PopupMenuItem<String>(
            enabled: false,
            child: Text(
              name,
              style: AppTextStyles.titleSmall.copyWith(color: p.textPrimary),
            ),
          ),
        const PopupMenuItem<String>(value: 'my-events', child: Text('My Events')),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'sign-out', child: Text('Sign out')),
      ],
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Website avatar gradient (same in both themes).
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.darkNavLight, AppColors.darkNavMuted],
          ),
          border: Border.all(
            color: p.primary.withValues(alpha: 0.55),
            width: 1.5,
          ),
        ),
        child: initials.isEmpty
            ? const Icon(Icons.person_outline, size: 16, color: Colors.white)
            : Text(
                initials,
                style: AppTextStyles.labelSmall.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

/// Header nav link: muted text, gold when hovered or active, with a gold
/// underline on the active page (website navbar).
class _NavLink extends StatefulWidget {
  const _NavLink({required this.item, required this.active});

  final NavItem item;
  final bool active;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = widget.active || _hover ? p.primary : p.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.active ? null : () => context.go(widget.item.route),
        child: Container(
          // Full header height, so the underline sits on its bottom edge.
          height: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: widget.active ? p.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            widget.item.label,
            style: AppTextStyles.labelLarge.copyWith(
              color: color,
              fontWeight: widget.active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Phone/tablet menu with the same items as the header links.
class SiteNavDrawer extends ConsumerWidget {
  const SiteNavDrawer({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final items = visibleNavItems(ref.watch(authControllerProvider));
    return Drawer(
      backgroundColor: p.surface,
      width: 280,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              child: Text(
                'MENU',
                style: AppTextStyles.eyebrow.copyWith(color: p.primary),
              ),
            ),
            for (final item in items)
              _DrawerItem(item: item, active: isNavItemActive(item, location)),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({required this.item, required this.active});

  final NavItem item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = active ? p.primary : p.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        tileColor: active ? p.surfaceHover : null,
        leading: Icon(item.icon, color: color, size: 20),
        title: Text(
          item.label,
          style: AppTextStyles.labelLarge.copyWith(
            color: active ? p.primary : p.textPrimary,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        onTap: () {
          Navigator.of(context).pop();
          if (!active) context.go(item.route);
        },
      ),
    );
  }
}
