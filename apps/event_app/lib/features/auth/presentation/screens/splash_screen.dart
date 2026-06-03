import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/app_widgets.dart';
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
  late final DateTime _startTime;

  @override
  void initState() {
    super.initState();
    AppLogger.info('SplashScreen: Initializing.');
    _startTime = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _navigate());
  }

  void _navigate() {
    AppLogger.info('SplashScreen: Running navigation check.');
    if (!mounted) return;
    final auth = AuthController.instance;
    if (auth.isChecking || auth.isAuthenticating) {
      Future<void>.delayed(const Duration(milliseconds: 150), _navigate);
      return;
    }

    final elapsed = DateTime.now().difference(_startTime);
    final remaining = const Duration(milliseconds: 1500) - elapsed;
    if (remaining.isNegative) {
      if (auth.isAuthenticated) {
        AppLogger.info('Backend session authenticated. Navigating to home.');
        context.go(AppRoutes.home);
      } else {
        AppLogger.info('No valid backend session. Navigating to login.');
        context.go(AppRoutes.login);
      }
    } else {
      Future<void>.delayed(remaining, _navigate);
    }
  }



@override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebSplash();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _buildIOSSplash();
    } else {
      return _buildAndroidSplash();
    }
  }

  Widget _buildWebSplash() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF0B0D10) : const Color(0xFFF7F8FA);
    final Color textColor = isDark ? const Color(0xFFF5F7FA) : const Color(0xFF0E1117);
    final Color secondaryTextColor = isDark ? const Color(0xFF9AA3B2) : const Color(0xFF4A5260);

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'NITKSAA',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFC9952A),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'EVENT PLATFORM · ALPHA',
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryTextColor,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC9952A).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.calendar_today_outlined,
                    size: 36,
                    color: Color(0xFFC9952A),
                  ),
                ),
                const SizedBox(height: 32),
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC9952A)),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Connecting…',
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIOSSplash() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF0A0A0C) : const Color(0xFF000000);

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'NITKSAA',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Color(0xFFC9952A),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'EVENT PLATFORM · ALPHA',
              style: TextStyle(
                fontSize: 11,
                color: Color(0x99FFFFFF), // 60% opacity
                letterSpacing: 1.0,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFC9952A).withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.calendar_today_outlined,
                size: 32,
                color: Color(0xFFC9952A),
              ),
            ),
            const SizedBox(height: 28),
            const CupertinoActivityIndicator(
              radius: 13,
              color: Color(0xFFC9952A),
            ),
            const SizedBox(height: 12),
            const Text(
              'Connecting…',
              style: TextStyle(
                fontSize: 10,
                color: Color(0x66FFFFFF), // 40% opacity
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAndroidSplash() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF060B14) : const Color(0xFF0D1B3E);

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'NITKSAA',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: Color(0xFFC9952A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'EVENT PLATFORM · ALPHA',
              style: TextStyle(
                fontSize: 11,
                color: Color(0x80FFFFFF), // 50% opacity
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFC9952A).withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.calendar_today_outlined,
                size: 28,
                color: Color(0xFFC9952A),
              ),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC9952A)),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Connecting…',
              style: TextStyle(
                fontSize: 10,
                color: Color(0x4DFFFFFF), // 30% opacity
              ),
            ),
          ],
        ),
      ),
    );
  }
}
