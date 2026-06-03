import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/constants/game_constants.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/notification_service.dart';
import 'core/theme/game_theme.dart';
import 'features/auth/notifiers/auth_notifier.dart';
import 'features/auth/screens/auth_screen.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/focus/screens/focus_screen.dart';
import 'features/matrix/screens/matrix_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp]);
  }
  SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  await Hive.initFlutter();
  await Future.wait([
    Hive.openBox(GameConstants.boxSettings),
    Hive.openBox(GameConstants.boxDailyLogs),
    Hive.openBox(GameConstants.boxHabits),
  ]);
  await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.init();
  runApp(const ProviderScope(child: GrowDailyApp()));
}

class GrowDailyApp extends ConsumerWidget {
  const GrowDailyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'GrowDaily',
      debugShowCheckedModeBanner: false,
      theme: GameTheme.light,
      darkTheme: GameTheme.dark,
      themeMode: themeMode,
      initialRoute: '/',
      routes: {
        '/': (_) => const _AuthGate(),
        '/dashboard': (_) => const DashboardScreen(),
        '/focus': (_) => const FocusScreen(),
        '/matrix': (_) => const MatrixScreen(),
        '/profile': (_) => const ProfileScreen(),
        '/auth': (_) => const AuthScreen(),
      },
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGuest = ref.watch(guestModeProvider);
    if (isGuest) return const DashboardScreen();
    final auth = ref.watch(authStateProvider);
    return auth.when(
      data: (user) =>
          user != null ? const DashboardScreen() : const AuthScreen(),
      loading: () => const _SplashScreen(),
      error: (_, __) => const AuthScreen(),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Scaffold(
      backgroundColor: gp.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.trending_up_rounded,
                size: 48, color: GameColors.gold),
            const SizedBox(height: 16),
            Text(
              'GrowDaily',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
