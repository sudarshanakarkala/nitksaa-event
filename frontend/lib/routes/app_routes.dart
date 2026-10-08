abstract class AppRoutes {
  static const String foundation = '/foundation';
  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String myEvents = '/my-events';
  static const String manageEvents = '/manage-events';
  static const String eventRegistrations = '/admin/events/:id/registrations';
  static const String developer = '/developer';
  static const String eventDetail = '/events/:id';
  static const String checkout = '/events/:id/checkout';

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