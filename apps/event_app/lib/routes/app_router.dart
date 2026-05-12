import 'package:go_router/go_router.dart';
import '../features/developer/presentation/developer_diagnostics_screen.dart';
import '../features/foundation/presentation/foundation_ready_screen.dart';
import 'app_routes.dart';

abstract class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const FoundationReadyScreen(),
      ),
      GoRoute(
        path: AppRoutes.developer,
        name: 'developer',
        builder: (context, state) => const DeveloperDiagnosticsScreen(),
      ),
    ],
  );
}
