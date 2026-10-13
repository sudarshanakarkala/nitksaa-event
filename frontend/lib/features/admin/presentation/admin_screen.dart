import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/page_insets.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/domain/admin_access.dart';
import '../../auth/services/auth_controller.dart';
import '../admin_tabs.dart';
import 'admin_actions_tab.dart';
import 'admin_audit_tab.dart';
import 'admin_dashboard_tab.dart';
import 'admin_events_tab.dart';
import 'admin_payments_tab.dart';
import 'admin_registrations_tab.dart';
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
    final p = context.palette;

    // Website AdminPage: a sticky zone (page header, then the tab row with
    // a bottom border) and the tab's content scrolling beneath it, both in
    // the same 1520px container as the site header.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.border)),
          ),
          child: AdminContainer(
            child: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PageHeader(eyebrow: 'NITKSAA Events', title: 'Admin'),
                  const SizedBox(height: 16),
                  _AdminTabBar(tabs: tabs, selected: widget.tab),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: _content(widget.tab)),
      ],
    );
  }

  Widget _content(AdminTab tab) {
    switch (tab) {
      case AdminTab.events:
        return const AdminEventsTab();
      case AdminTab.roles:
        return const RolesTab();
      case AdminTab.registrations:
        return const AdminRegistrationsTab();
      case AdminTab.dashboard:
        return const AdminDashboardTab();
      case AdminTab.payments:
        return const AdminPaymentsTab();
      case AdminTab.actions:
        return const AdminActionsTab();
      case AdminTab.audit:
        return const AdminAuditTab();
    }
  }
}

/// The website's `.container`, lined up with the site header (content
/// starts under the NITKSAA logo; see [PageInsets]).
class AdminContainer extends StatelessWidget {
  const AdminContainer({super.key, required this.child});

  final Widget child;

  /// Padding for a scroll view that fills the width (so its scrollbar sits
  /// at the window edge, as on the website) but keeps its content in the
  /// header's column. Website `.mgmt-content`: 28px top, 60px bottom.
  static EdgeInsets scrollPadding(
    BuildContext context,
    double width, {
    double top = 28,
    double bottom = 60,
  }) {
    final h = PageInsets.horizontal(context, width);
    return EdgeInsets.fromLTRB(h.left, top, h.right, bottom);
  }

  @override
  Widget build(BuildContext context) =>
      PageContainer(child: SizedBox(width: double.infinity, child: child));
}

/// Website `.adm-tab-group` of `.tab-btn`s: small bordered buttons 6px
/// apart; the active one gold on a faint gold fill.
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
            if (i > 0) const SizedBox(width: 6),
            _TabButton(tab: tabs[i], active: tabs[i] == selected),
          ],
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.tab, required this.active});

  final AdminTab tab;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? p.primary.withValues(alpha: 0.06) : p.surfaceSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: active ? p.primary.withValues(alpha: 0.4) : p.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: active ? null : () => context.go(tab.path),
          hoverColor: p.surfaceHover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              tab.label,
              style: AppTextStyles.labelMedium.copyWith(
                fontSize: 12.8,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                color: active ? p.primary : p.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
