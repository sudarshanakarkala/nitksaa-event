import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/data/actions_api.dart';
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
/// Brand and nav links on the left; NITiKa, theme toggle and account on the
/// right. Below [navBreakpoint] the links move into a menu
/// ([SiteNavDrawer]), opened from the menu button, which needs a Scaffold
/// with that endDrawer.
class SiteHeader extends ConsumerWidget {
  const SiteHeader({
    super.key,
    this.showThemeToggle = true,
    this.onAssistant,
    this.assistantOpen = false,
  });

  /// The header toggle is the app's only theme switch.
  final bool showThemeToggle;

  /// Opens or collapses NITiKa (website: the navbar's chat button). No
  /// button when null.
  final VoidCallback? onAssistant;

  /// Gold while the NITiKa rail is open, like the website's active button.
  final bool assistantOpen;

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
    final auth = ref.watch(authControllerProvider);
    final items = visibleNavItems(auth);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gap = compact ? 6.0 : 8.0;
    // Website Admin badge: shield, only for people with admin rights, with
    // the count of things that need attention (Actions tab).
    final showAdmin =
        auth.isAuthenticated && (auth.session?.access.hasAdminArea ?? false);
    final onAdminPage = location == AppRoutes.admin ||
        location.startsWith('${AppRoutes.admin}/');

    return Material(
      // Website --bg-nav: background at 92% (dark) / 95% (light).
      color: p.background.withValues(alpha: isDark ? 0.92 : 0.95),
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
                  if (wide)
                    _Brand(compact: compact, isDark: isDark)
                  else
                    // Narrow: the brand gives way to the actions.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _Brand(compact: compact, isDark: isDark),
                      ),
                    ),
                  if (wide) ...[
                    const SizedBox(width: 32),
                    for (final item in items) ...[
                      _NavLink(
                        item: item,
                        active: isNavItemActive(item, location),
                      ),
                      const SizedBox(width: 4),
                    ],
                    const Spacer(),
                  ],
                  if (showAdmin) ...[
                    _AdminButton(active: onAdminPage),
                    SizedBox(width: gap),
                  ],
                  if (onAssistant != null) ...[
                    _HeaderIconButton(
                      tooltip: 'NITiKa',
                      icon: Icons.chat_bubble_outline,
                      active: assistantOpen,
                      onPressed: onAssistant!,
                    ),
                    SizedBox(width: gap),
                  ],
                  if (showThemeToggle) ...[
                    _HeaderIconButton(
                      tooltip: isDark ? 'Light mode' : 'Dark mode',
                      icon: isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      onPressed: () =>
                          ref.read(themeProvider.notifier).toggleTheme(),
                    ),
                    SizedBox(width: gap),
                  ],
                  const _AccountButton(),
                  if (!wide) ...[
                    SizedBox(width: gap),
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
                    Flexible(
                      child: Text(
                        'NITKSAA Events',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleLarge.copyWith(
                          fontSize: 17,
                          color: p.textPrimary,
                          letterSpacing: 0.3,
                        ),
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

/// The Admin shield with the website's gold count badge: how many things
/// need attention (Actions tab), hidden at zero. Fetched on load and again
/// whenever the window regains focus; admin changes refresh it too
/// (refreshEventLists).
class _AdminButton extends ConsumerStatefulWidget {
  const _AdminButton({required this.active});

  final bool active;

  @override
  ConsumerState<_AdminButton> createState() => _AdminButtonState();
}

class _AdminButtonState extends ConsumerState<_AdminButton> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // On the web, "resumed" is the window or tab getting focus back.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(pendingCountProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final count = ref.watch(pendingCountProvider).valueOrNull?.total ?? 0;
    final label = count > 99 ? '99+' : '$count';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _HeaderIconButton(
          tooltip: count > 0 ? 'Admin · $count need attention' : 'Admin',
          icon: Icons.shield_outlined,
          active: widget.active,
          onPressed: () => context.go(AppRoutes.admin),
        ),
        if (count > 0)
          Positioned(
            top: -6,
            right: -6,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.primary,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  label,
                  style: AppTextStyles.labelSmall.copyWith(
                    fontSize: 10.9,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    letterSpacing: 0,
                    color: p.onPrimary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 34×34 square icon button with border, like the website's nav icons.
/// [active] is the website's `.nav-icon-btn--active`: gold on a faint gold
/// fill.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

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
            backgroundColor: active
                ? p.primary.withValues(alpha: 0.10)
                : p.surfaceSubtle,
            foregroundColor: p.textSecondary,
            side: BorderSide(
              color: active ? p.primary.withValues(alpha: 0.40) : p.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ).copyWith(
            foregroundColor: WidgetStateProperty.resolveWith((states) =>
                active || states.contains(WidgetState.hovered)
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
          // Your registrations, cancelled ones and refunds included. The
          // Events page keeps "Registered by me" as a quick filter.
          context.go(AppRoutes.myEvents);
        } else if (value == 'sign-out') {
          // To Events, from any page (ISSUE-021). Moved there first, so the
          // page left behind isn't remembered as one to return to.
          final auth = ref.read(authControllerProvider.notifier);
          context.go(AppRoutes.home);
          await auth.signOut();
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

/// Header nav link, website `.nav-link`: secondary text in a small pill;
/// hover lifts the text and fills the pill; the active page is gold on a
/// faint gold pill.
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
    final color = widget.active
        ? p.primary
        : (_hover ? p.textPrimary : p.textSecondary);
    final fill = widget.active
        ? p.primary.withValues(alpha: 0.08)
        : (_hover ? p.surfaceSubtle : Colors.transparent);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.active ? null : () => context.go(widget.item.route),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.item.label,
            style: AppTextStyles.labelLarge.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
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
