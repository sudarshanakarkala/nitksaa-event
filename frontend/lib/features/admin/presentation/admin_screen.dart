import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/list_page.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/domain/admin_access.dart';
import '../../auth/services/auth_controller.dart';
import '../../events/presentation/screens/manage_events_screen.dart';
import '../admin_tabs.dart';
import 'roles_tab.dart';

/// `/admin/<tab>`: the one admin area, modelled on the website's Admin page
/// (eyebrow, serif title, gold rule, pill tabs).
///
/// RouteGuards only lets people with admin rights in, and only to tabs they
/// can see. The backend scopes every tab's data.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key, required this.tab});

  final AdminTab tab;

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  @override
  void initState() {
    super.initState();
    // Pick up role changes made since sign-in (e.g. in the Roles tab).
    Future.microtask(
      () => ref.read(authControllerProvider.notifier).refreshSession(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final access = auth.session?.access ?? AdminAccess.none;
    final tabs = AdminTab.visibleTabs(access);
    final side = ListPage.sidePadding(context);
    final compact = MediaQuery.sizeOf(context).width < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(side, compact ? 20 : 28, side, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(eyebrow: 'NITKSAA Events', title: 'Admin'),
              const SizedBox(height: 20),
              _AdminTabBar(tabs: tabs, selected: widget.tab),
            ],
          ),
        ),
        Expanded(child: _content(widget.tab)),
      ],
    );
  }

  Widget _content(AdminTab tab) {
    switch (tab) {
      case AdminTab.events:
        // The existing Manage Events screen until step 5 rebuilds this tab.
        return const ManageEventsScreen();
      case AdminTab.roles:
        return const RolesTab();
      case AdminTab.registrations:
        return const _ComingSoon(
          note: 'Until then, open an event\'s registrations from the Events tab.',
        );
      case AdminTab.actions:
      case AdminTab.dashboard:
      case AdminTab.payments:
      case AdminTab.audit:
        return const _ComingSoon();
    }
  }
}

/// Website `.tab-btn` pills: bordered, the active one gold.
class _AdminTabBar extends StatelessWidget {
  const _AdminTabBar({required this.tabs, required this.selected});

  final List<AdminTab> tabs;
  final AdminTab selected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _TabPill(tab: tabs[i], active: tabs[i] == selected),
          ],
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({required this.tab, required this.active});

  final AdminTab tab;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? p.primary : p.surfaceSubtle,
        shape: StadiumBorder(
          side: BorderSide(color: active ? p.primary : p.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: active ? null : () => context.go(tab.path),
          hoverColor: p.surfaceHover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              tab.label,
              style: AppTextStyles.labelLarge.copyWith(
                color: active ? p.onPrimary : p.textSecondary,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder for tabs that arrive in later steps.
class _ComingSoon extends StatelessWidget {
  const _ComingSoon({this.note});

  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction_outlined, size: 40, color: p.textMuted),
              const SizedBox(height: 12),
              Text(
                'Coming in the next update',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMedium.copyWith(color: p.textPrimary),
              ),
              if (note != null) ...[
                const SizedBox(height: 8),
                Text(
                  note!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
