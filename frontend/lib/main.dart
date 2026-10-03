import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/app_state.dart';
import 'core/logger/app_logger.dart';
import 'features/auth/services/auth_controller.dart';
import 'firebase_options.dart';
import 'routes/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppLogger.info('Starting NITKSAA Event App...');

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    AppState.firebaseInitialized = true;
    AppLogger.info('Firebase initialized: ${Firebase.app().name}');
  } catch (e, st) {
    AppLogger.error('Firebase initialization failed', e, st);
  }

  await Hive.initFlutter();
  AppLogger.info('Hive initialized');

  await AuthController.instance.initialize();
  AppLogger.info('Auth controller initialized');

  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    return MaterialApp.router(
      title: 'NITKSAA Event',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: AppRouter.router,
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            // Global theme toggle button - positioned just above bottom nav on mobile
            Positioned(
              bottom: MediaQuery.of(context).size.width >= 900
                  ? MediaQuery.of(context).padding.bottom + 16
                  : MediaQuery.of(context).padding.bottom + 80,
              right: 16,
              child: SafeArea(
                child: Consumer(
                  builder: (context, innerRef, _) {
                    final mode = innerRef.watch(themeProvider);
                    final isDark = mode == ThemeMode.dark || (mode == ThemeMode.system && MediaQuery.of(context).platformBrightness == Brightness.dark);
                    return Material(
                      color: Colors.transparent,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark 
                              ? Colors.grey[900]?.withOpacity(0.85) 
                              : Colors.white.withOpacity(0.85),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? Colors.white24 : Colors.black12,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: Icon(
                            isDark ? Icons.light_mode : Icons.dark_mode, 
                            color: isDark ? Colors.amberAccent : Colors.indigo,
                          ),
                          onPressed: () => innerRef.read(themeProvider.notifier).toggleTheme(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
