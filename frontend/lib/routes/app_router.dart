import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/developer/presentation/developer_diagnostics_screen.dart';
import '../features/foundation/presentation/foundation_ready_screen.dart';
import '../features/events/presentation/screens/event_list_screen.dart';
import '../features/events/presentation/screens/event_detail_screen.dart';
import '../features/events/presentation/screens/checkout_screen.dart';
import '../features/events/presentation/screens/manage_events_screen.dart';
import '../features/events/presentation/screens/event_registrations_screen.dart';
import '../features/events/presentation/screens/my_events_screen.dart';
import '../features/auth/services/auth_controller.dart';
import '../features/feedback/feedback_screen.dart';
import '../features/nitika/nitika_config.dart';
import '../features/nitika/presentation/nitika_panel.dart';
import '../features/policies/policy_screen.dart';
import '../shared/widgets/app_shell.dart';
import 'app_routes.dart';
import 'route_guards.dart';

abstract class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    refreshListenable: AuthController.instance,
    redirect: RouteGuards.redirect,
    routes: [
      GoRoute(
        path: AppRoutes.foundation,
        builder: (context, state) => const FoundationReadyScreen(),
      ),
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      // Attendee pages share one shell: header, sidebar / bottom nav, footer.
      ShellRoute(
        builder: (context, state, child) => Consumer(
          builder: (context, ref, _) => AppShell(
            location: state.uri.path,
            assistant: nitikaAssistant(
              enabled: nitikaEnabled,
              signedIn: nitikaEnabled &&
                  ref.watch(authControllerProvider).isAuthenticated,
              location: state.uri.path,
            ),
            child: child,
          ),
        ),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const EventListScreen(),
          ),
          GoRoute(
            path: AppRoutes.myEvents,
            builder: (context, state) => const MyEventsScreen(),
          ),
          GoRoute(
            path: AppRoutes.manageEvents,
            builder: (context, state) => const ManageEventsScreen(),
          ),
          GoRoute(
            path: AppRoutes.eventRegistrations,
            builder: (context, state) {
              final idStr = state.pathParameters['id'] ?? '';
              final eventId = int.tryParse(idStr) ?? 0;
              return EventRegistrationsScreen(eventId: eventId);
            },
          ),
          GoRoute(
            path: AppRoutes.eventDetail,
            builder: (context, state) {
              final idStr = state.pathParameters['id'] ?? '';
              final eventId = int.tryParse(idStr) ?? 0;
              return EventDetailScreen(eventId: eventId);
            },
          ),
          GoRoute(
            path: AppRoutes.checkout,
            builder: (context, state) {
              final idStr = state.pathParameters['id'] ?? '';
              final eventId = int.tryParse(idStr) ?? 0;
              final notes = state.uri.queryParameters['notes'] ?? '';
              return CheckoutScreen(eventId: eventId, notes: notes);
            },
          ),
          GoRoute(
            path: AppRoutes.privacy,
            builder: (context, state) => const PolicyScreen(policy: Policy.privacy),
          ),
          GoRoute(
            path: AppRoutes.terms,
            builder: (context, state) => const PolicyScreen(policy: Policy.terms),
          ),
          GoRoute(
            path: AppRoutes.refund,
            builder: (context, state) => const PolicyScreen(policy: Policy.refund),
          ),
          GoRoute(
            path: AppRoutes.disclaimer,
            builder: (context, state) => const PolicyScreen(policy: Policy.disclaimer),
          ),
          GoRoute(
            path: AppRoutes.feedback,
            builder: (context, state) => const FeedbackScreen(),
          ),
        ],
      ),
      if (kDebugMode)
        GoRoute(
          path: AppRoutes.developer,
          name: 'developer',
          builder: (context, state) => const DeveloperDiagnosticsScreen(),
        ),
    ],
  );
}