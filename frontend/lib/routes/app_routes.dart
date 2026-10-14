abstract class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String myEvents = '/my-events';
  /// Old Manage Events page; redirects to [adminEvents].
  static const String manageEvents = '/manage-events';
  static const String admin = '/admin';
  static const String adminTab = '/admin/:tab';
  static const String adminEvents = '/admin/events';
  static const String adminRegistrations = '/admin/registrations';
  /// Old per-event registrations page; redirects to [adminRegistrations].
  static const String eventRegistrations = '/admin/events/:id/registrations';
  static const String developer = '/developer';
  static const String eventDetail = '/events/:id';
  static const String checkout = '/events/:id/checkout';

  /// Opened from an entry pass QR; see `CheckInScreen`.
  static const String checkIn = '/checkin/:eventId/:token';
  static const String checkInPrefix = '/checkin/';

  // Website-style public pages (UI alignment).
  static const String privacy = '/privacy';
  static const String terms = '/terms';
  static const String refund = '/refund';
  static const String disclaimer = '/disclaimer';
  static const String feedback = '/feedback';

  static const Set<String> publicPages = {
    privacy,
    terms,
    refund,
    disclaimer,
    feedback,
  };
}