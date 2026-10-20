import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logger/app_logger.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/page_insets.dart';
import '../../../shared/widgets/phone_chrome.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/domain/admin_access.dart';
import '../../auth/services/auth_controller.dart';
import '../../events/data/events_repository.dart';
import '../admin_tabs.dart';
import 'admin_actions_tab.dart';
import 'admin_audit_tab.dart';
import 'admin_check_in_tab.dart';
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
  bool _landingChecked = false;

  @override
  void initState() {
    super.initState();
    // Pick up role changes made since sign-in (e.g. in the Roles tab).
    Future.microtask(
      () => ref.read(authControllerProvider.notifier).refreshSession(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_landingChecked) return;
    _landingChecked = true;
    final fromAdmin = GoRouterState.of(context).uri.query == AdminTab.landingQuery;
    if (fromAdmin && widget.tab == AdminTab.landing) Future.microtask(_smartLanding);
  }

  /// Plain `/admin` opens Actions. On an event day (an event you admin is on,
  /// or starts within a few hours) it moves on to Check-in for that event,
  /// so volunteers at the door land straight on it.
  Future<void> _smartLanding() async {
    final session = ref.read(authControllerProvider).session;
    final access = session?.access ?? AdminAccess.none;
    if (session == null || !AdminTab.checkIn.visibleTo(access)) return;
    try {
      final events = await ref.read(eventsRepositoryProvider).getAllAdminEvents(session.accessToken);
      final today = eventOnNow(events, DateTime.now());
      // Only if they're still on Actions (they may have moved on meanwhile).
      if (!mounted || today == null || widget.tab != AdminTab.landing) return;
      context.go('${AdminTab.checkIn.path}?event=${today.eventId}');
    } catch (error) {
      // Stay on Actions; Check-in is one tap away.
      AppLogger.warning('Admin: event-day check failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final access = auth.session?.access ?? AdminAccess.none;
    final tabs = AdminTab.visibleTabs(access);
    final p = context.palette;
    // Phones and short laptop windows: the shorter title.
    final phone = PhoneChrome.isPhone(context) || PhoneChrome.isShort(context);

    // Website AdminPage: a sticky zone (page header, then the tab row with
    // a bottom border) and the tab's content scrolling beneath it, both in
    // the same 1520px container as the site header. Phones: a shorter
    // title.
    final header = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: AdminContainer(
        child: Padding(
          padding: EdgeInsets.only(top: phone ? 10 : 16, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (phone)
                const PageHeader(title: 'Admin', dense: true)
              else
                const PageHeader(eyebrow: 'NITKSAA Events', title: 'Admin'),
              SizedBox(height: phone ? 10 : 16),
              _AdminTabBar(tabs: tabs, selected: widget.tab),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
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
      case AdminTab.checkIn:
        return const AdminCheckInTab();
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
    // Phones: the tabs used away from a desk; the rest under "More". With
    // nothing (or only one tab) to put there, every tab shows.
    var shown = tabs;
    var more = const <AdminTab>[];
    if (MediaQuery.sizeOf(context).width < 600) {
      final phone = tabs.where(AdminTab.phoneTabs.contains).toList();
      final rest = tabs.where((t) => !AdminTab.phoneTabs.contains(t)).toList();
      if (phone.isNotEmpty && rest.length > 1) {
        shown = phone;
        more = rest;
      }
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _TabButton(tab: shown[i], active: shown[i] == selected),
          ],
          if (more.isNotEmpty) ...[
            const SizedBox(width: 6),
            _MoreButton(tabs: more, selected: selected),
          ],
        ],
      ),
    );
  }
}

/// "More ▾" on phones: the tabs that don't fit. Shows the open tab's name
/// while one of them is open.
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.tabs, required this.selected});

  final List<AdminTab> tabs;
  final AdminTab selected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final active = tabs.contains(selected);
    final color = active ? p.primary : p.textSecondary;
    return PopupMenuButton<AdminTab>(
      tooltip: 'More tabs',
      onSelected: (tab) => context.go(tab.path),
      itemBuilder: (_) => [
        for (final t in tabs)
          PopupMenuItem(
            value: t,
            child: Text(
              t.label,
              style: TextStyle(
                color: t == selected ? p.primary : null,
                fontWeight: t == selected ? FontWeight.w600 : null,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          color: active ? p.primary.withValues(alpha: 0.06) : p.surfaceSubtle,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? p.primary.withValues(alpha: 0.4) : p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              active ? selected.label : 'More',
              style: AppTextStyles.labelMedium.copyWith(
                fontSize: 12.8,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                color: color,
              ),
            ),
            Icon(Icons.expand_more, size: 16, color: color),
          ],
        ),
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
