import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/logger/app_logger.dart';
import '../../../../routes/app_routes.dart';
import '../../../../shared/widgets/emblem_ring.dart';
import '../../../../theme/app_palette.dart';
import '../../../../theme/app_text_styles.dart';
import '../../services/auth_controller.dart';

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
      AppLogger.info('Splash screen completed. Navigating to home.');
      context.go(AppRoutes.home);
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
    final p = context.palette;
    final Color bgColor = p.background;
    final Color textColor = p.textPrimary;
    final Color secondaryTextColor = p.textSecondary;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'NITKSAA',
                    style: TextStyle(
                      fontFamily: AppTextStyles.serif,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: p.primary,
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
                  const EmblemRing(size: 80),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(p.primary),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Connecting…',
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIOSSplash() {
    final p = context.palette;
    final Color bgColor = p.background;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'NITKSAA',
                style: TextStyle(
                  fontFamily: AppTextStyles.serif,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: p.primary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'EVENT PLATFORM · ALPHA',
                style: TextStyle(
                  fontSize: 11,
                  color: p.textSecondary,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 28),
              const EmblemRing(size: 68),
              const SizedBox(height: 28),
              CupertinoActivityIndicator(
                radius: 13,
                color: p.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Connecting…',
                style: TextStyle(
                  fontSize: 10,
                  color: p.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAndroidSplash() {
    final p = context.palette;
    final Color bgColor = p.background;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'NITKSAA',
                style: TextStyle(
                  fontFamily: AppTextStyles.serif,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: p.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'EVENT PLATFORM · ALPHA',
                style: TextStyle(
                  fontSize: 11,
                  color: p.textSecondary,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 28),
              const EmblemRing(size: 64),
              const SizedBox(height: 28),
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(p.primary),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Connecting…',
                style: TextStyle(
                  fontSize: 10,
                  color: p.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
