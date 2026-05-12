import 'package:go_router/go_router.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/developer/presentation/developer_diagnostics_screen.dart';
import '../features/foundation/presentation/foundation_ready_screen.dart';
import '../features/home/presentation/home_placeholder_screen.dart';
import 'app_routes.dart';

abstract class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
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
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomePlaceholderScreen(),
      ),
      GoRoute(
        path: AppRoutes.developer,
        name: 'developer',
        builder: (context, state) => const DeveloperDiagnosticsScreen(),
      ),
    ],
  );
}
