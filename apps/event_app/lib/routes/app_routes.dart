abstract class AppRoutes {
  static const String root = '/';
  static const String foundation = '/foundation';
  static const String splash = '/splash';
  static const String login = '/login';
  static const String events = '/events';
  static String eventDetail(int eventId) => '$events/$eventId';
  static String registerForEvent(int eventId) => '$events/$eventId/register';
  static const String registrationConfirmation = '/registration/confirmation';
  static const String myRegistrations = '/my-registrations';
  static const String home = '/home';
  static const String developer = '/developer';
}
