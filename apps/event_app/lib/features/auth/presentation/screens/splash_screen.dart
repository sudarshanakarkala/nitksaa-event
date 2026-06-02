import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/logger/app_logger.dart';
import '../../../../routes/app_routes.dart';
import '../../services/auth_controller.dart';
import '../../services/firebase_auth_service.dart';
import '../../../../../widgets/shared/info_screen.dart';
import '../../../../../widgets/shared/shared_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _navigate());
  }

  void _navigate() {
    if (!mounted) return;
    final auth = AuthController.instance;
    if (auth.isChecking || auth.isAuthenticating) {
      Future<void>.delayed(const Duration(milliseconds: 150), _navigate);
      return;
    }
    if (auth.isAuthenticated) {
      AppLogger.info('Backend session authenticated. Navigating to home.');
      context.go(AppRoutes.home);
    } else {
      AppLogger.info('No valid backend session. Navigating to login.');
      context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SharedScreen(
      body: InfoScreen(
        icon: Icons.account_balance_outlined,
        title: 'NITKSAA Event',
        subtitle: 'NIT Karnataka Alumni Association',
        showLoading: true,
      ),
    );
  }
}
