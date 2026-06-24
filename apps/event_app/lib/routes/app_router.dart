import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/auth/services/auth_controller.dart';
import '../features/developer/presentation/developer_diagnostics_screen.dart';
import '../features/events/presentation/event_detail_screen.dart';
import '../features/events/presentation/event_list_screen.dart';
import '../features/foundation/presentation/foundation_ready_screen.dart';
import '../features/home/presentation/home_placeholder_screen.dart';
import '../features/registration/domain/registration.dart';
import '../features/registration/presentation/confirmation_screen.dart';
import '../features/registration/presentation/my_registrations_screen.dart';
import '../features/registration/presentation/register_screen.dart';
import 'app_routes.dart';
import 'route_guards.dart';

abstract class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.root,
    debugLogDiagnostics: false,
    refreshListenable: AuthController.instance,
    redirect: RouteGuards.redirect,
    routes: [
      GoRoute(
        path: AppRoutes.root,
        builder: (context, state) => const SplashScreen(),
      ),
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
      GoRoute(
        path: AppRoutes.events,
        builder: (context, state) => const EventListScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.events}/:eventId',
        builder: (context, state) {
          final eventId = int.tryParse(state.pathParameters['eventId'] ?? '');
          return EventDetailScreen(eventId: eventId ?? -1);
        },
      ),
      GoRoute(
        path: '${AppRoutes.events}/:eventId/register',
        builder: (context, state) {
          final eventId = int.tryParse(state.pathParameters['eventId'] ?? '');
          final rawTitle = state.uri.queryParameters['title'] ?? '';
          final eventTitle = rawTitle.isNotEmpty
              ? Uri.decodeComponent(rawTitle)
              : 'Event Registration';
          return RegisterScreen(
            eventId: eventId ?? -1,
            eventTitle: eventTitle,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.registrationConfirmation,
        builder: (context, state) {
          final registration = state.extra as Registration?;
          if (registration == null) {
            return const _MissingRegistrationFallback();
          }
          return ConfirmationScreen(registration: registration);
        },
      ),
      GoRoute(
        path: AppRoutes.myRegistrations,
        builder: (context, state) => const MyRegistrationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomePlaceholderScreen(),
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

class _MissingRegistrationFallback extends StatelessWidget {
  const _MissingRegistrationFallback();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Registration data unavailable.')),
    );
  }
}
