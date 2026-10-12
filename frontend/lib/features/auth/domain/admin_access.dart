/// The signed-in person's admin rights, from the backend's `access` block
/// on `/auth/firebase` and `/auth/me` (admin revamp step 1).
///
/// The backend works these out on every request, and the app refreshes them
/// from `/auth/me` at startup, so a role change applies at the next app load
/// without signing in again. The backend still enforces every permission;
/// this only decides what the app shows.
class AdminAccess {
  const AdminAccess({
    this.isAdmin = false,
    this.isEventCreator = false,
    this.platformRoles = const [],
    this.adminEventIds = const [],
  });

  /// No admin rights.
  static const none = AdminAccess();

  /// Payment roles that can see payments without being an overall admin.
  static const _paymentRoles = {'finance_operator', 'auditor', 'support'};

  /// Overall admin: everything, all events.
  final bool isAdmin;

  /// May create events (always true for an overall admin).
  final bool isEventCreator;

  /// platform_admin / finance_operator / auditor / support.
  final List<String> platformRoles;

  /// Events this person administers. Empty for an overall admin, who has
  /// every event.
  final List<int> adminEventIds;

  /// Shows the Admin badge and may open `/admin`.
  bool get isAnyAdmin => isAdmin || isEventCreator || adminEventIds.isNotEmpty;

  /// Shows the Admin badge and may open `/admin`: any admin, or someone
  /// with only a payment role (who sees just the Payments tab).
  bool get hasAdminArea => isAnyAdmin || canSeePayments;

  /// May open the Payments tab (scoped by the backend).
  bool get canSeePayments =>
      isAdmin ||
      platformRoles.any(_paymentRoles.contains) ||
      adminEventIds.isNotEmpty;

  /// Overall admin, or an admin of [eventId].
  bool canAdminEvent(int eventId) => isAdmin || adminEventIds.contains(eventId);

  factory AdminAccess.fromJson(Object? json) {
    if (json is! Map) return none;
    return AdminAccess(
      isAdmin: json['is_admin'] == true,
      isEventCreator: json['is_event_creator'] == true,
      platformRoles: _list(json['platform_roles'])
          .map((e) => e.toString())
          .toList(growable: false),
      adminEventIds: _list(json['admin_event_ids'])
          .map((e) => e is int ? e : int.tryParse(e.toString()))
          .whereType<int>()
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'is_admin': isAdmin,
        'is_event_creator': isEventCreator,
        'platform_roles': platformRoles,
        'admin_event_ids': adminEventIds,
      };

  static List<dynamic> _list(Object? value) =>
      value is List ? value : const [];
}
