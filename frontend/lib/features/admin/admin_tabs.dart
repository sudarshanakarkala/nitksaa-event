import '../auth/domain/admin_access.dart';

/// The `/admin` tabs, in display order (website Admin page pattern).
enum AdminTab {
  actions('actions', 'Actions'),
  dashboard('dashboard', 'Dashboard'),
  events('events', 'Events'),
  registrations('registrations', 'Registrations'),
  payments('payments', 'Payments'),
  audit('audit', 'Audit'),
  roles('roles', 'Roles');

  const AdminTab(this.slug, this.label);

  /// Path segment: `/admin/<slug>`.
  final String slug;
  final String label;

  String get path => '/admin/$slug';

  /// Who sees the tab. The backend scopes the data inside each tab.
  bool visibleTo(AdminAccess access) {
    // Payment roles alone open Payments only.
    if (this == AdminTab.payments) return access.canSeePayments;
    if (!access.isAnyAdmin) return false;
    switch (this) {
      case AdminTab.payments:
        return access.canSeePayments;
      case AdminTab.roles:
        return access.isAdmin;
      case AdminTab.actions:
      case AdminTab.dashboard:
      case AdminTab.events:
      case AdminTab.registrations:
      case AdminTab.audit:
        return true;
    }
  }

  static AdminTab? fromSlug(String? slug) {
    for (final tab in AdminTab.values) {
      if (tab.slug == slug) return tab;
    }
    return null;
  }

  /// Where `/admin` lands: what needs attention (website pattern). People
  /// without it (finance only) land on their first visible tab.
  static const AdminTab landing = AdminTab.actions;

  static List<AdminTab> visibleTabs(AdminAccess access) =>
      AdminTab.values.where((t) => t.visibleTo(access)).toList();
}
