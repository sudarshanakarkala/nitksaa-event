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
  await ThemeNotifier.openStorage();
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
      title: 'NITKSAA Events',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: AppRouter.router,
    );
  }
}
