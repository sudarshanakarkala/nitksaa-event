import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/logger/app_logger.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../routes/app_routes.dart';
import '../../../theme/app_palette.dart';
import '../../auth/services/auth_controller.dart';
import '../../../widgets/shared/shared_screen.dart';

class HomePlaceholderScreen extends StatefulWidget {
  const HomePlaceholderScreen({super.key});

  @override
  State<HomePlaceholderScreen> createState() => _HomePlaceholderScreenState();
}

class _HomePlaceholderScreenState extends State<HomePlaceholderScreen> {
  Future<void> _signOut() async {
    AppLogger.info('User signing out');
    await AuthController.instance.signOut();
    if (mounted) context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SharedScreen(
      appBar: AppBar(
        title: const Text('NITKSAA Event'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Sign Out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: context.palette.success,
            ),
            const SizedBox(height: 20),
            Text('NITKSAA Event Home', style: textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Authentication Successful',
              style: textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 40),
            AppSecondaryButton(
              label: 'Sign Out',
              icon: Icons.logout_outlined,
              onPressed: _signOut,
            ),
          ],
        ),
      ),
    );
  }
}
