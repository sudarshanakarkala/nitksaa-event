import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/services/auth_controller.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/theme_provider.dart';

/// Top bar matching the association website's navbar
/// (website: components/core/Navbar.jsx, styles/navbar.css).
///
/// Brand on the left; theme toggle and account on the right.
/// Navigation items stay in the sidebar / bottom nav.
class SiteHeader extends ConsumerWidget {
  const SiteHeader({super.key, this.showThemeToggle = true});

  /// The header toggle is the app's only theme switch.
  final bool showThemeToggle;

  static const double height = 68;
  static const double compactHeight = 56;
  static const double maxContentWidth = 1520;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;
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

    // Website: logo is drawn white in dark mode, as-is in light mode.
    Widget tint(Widget child) => isDark
        ? ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.white.withValues(alpha: 0.9),
              BlendMode.srcIn,
            ),
            child: child,
          )
        : child;

    final logo = compact
        ? tint(Image.asset('assets/images/nitksaa-emblem.png', height: 32))
        : tint(Image.asset('assets/images/nitksaa-logo.png', height: 34));

    return Semantics(
      button: true,
      label: 'NITKSAA Events home',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => context.go(AppRoutes.home),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              logo,
              const SizedBox(width: 12),
              Text(
                compact ? 'NITKSAA Events' : 'Events',
                style: AppTextStyles.titleLarge.copyWith(
                  fontSize: 17,
                  color: p.textPrimary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
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
