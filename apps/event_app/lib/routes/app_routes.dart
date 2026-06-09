abstract class AppRoutes {
  static const String root = '/';
  static const String foundation = '/foundation';
  static const String splash = '/splash';
  static const String login = '/login';
  static const String events = '/events';
  static String eventDetail(int eventId) => '$events/$eventId';
  static const String home = '/home';
  static const String developer = '/developer';
}
