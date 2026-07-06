import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/constants/game_constants.dart';
import 'core/l10n/app_strings.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/notification_service.dart';
import 'core/theme/game_theme.dart';
import 'features/auth/notifiers/auth_notifier.dart';
import 'features/auth/screens/auth_screen.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/habits/catalog/habit_plans.dart' show reminderTimeProvider;
import 'features/focus/screens/focus_screen.dart';
import 'features/grid/screens/grid_screen.dart';
import 'features/grid/screens/monthly_heatmap_screen.dart';
import 'features/intention/screens/intention_screen.dart';
import 'features/matrix/screens/matrix_screen.dart';
import 'features/night_review/screens/night_review_screen.dart';
import 'features/premium/screens/premium_screen.dart';
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
  // Seed guestModeProvider from Hive so a returning guest with intact local
  // data lands back on their grid instead of being bounced to the auth
  // screen (the provider's own default is always `false` in memory).
  final persistedGuestMode = await loadPersistedGuestMode();
  runApp(ProviderScope(
    overrides: [guestModeProvider.overrideWith((ref) => persistedGuestMode)],
    child: const GrowDailyApp(),
  ));
}

class GrowDailyApp extends ConsumerStatefulWidget {
  const GrowDailyApp({super.key});

  @override
  ConsumerState<GrowDailyApp> createState() => _GrowDailyAppState();
}

class _GrowDailyAppState extends ConsumerState<GrowDailyApp> {
  ProviderSubscription<TimeOfDay?>? _reminderSub;

  @override
  void initState() {
    super.initState();
    // Re-arm the daily reminder on cold start. Android clears exact-alarm
    // schedules on device reboot, so this makes sure a previously-set
    // reminder survives a restart even without a boot-completed receiver.
    // `fireImmediately` needs listenManual (not the build-scoped ref.listen),
    // since it has to run once as soon as the persisted value loads, not
    // only on a future change.
    _reminderSub = ref.listenManual(reminderTimeProvider, (previous, next) {
      if (next != null) {
        NotificationService.instance
            .scheduleDailyReminder(hour: next.hour, minute: next.minute);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _reminderSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'GrowDaily',
      debugShowCheckedModeBanner: false,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.light,
      darkTheme: GameTheme.dark,
      themeMode: themeMode,
      locale: locale,
      initialRoute: '/',
      routes: {
        '/': (_) => const _AuthGate(),
        '/dashboard': (_) => const DashboardScreen(),
        '/grid': (_) => const GridScreen(),
        '/heatmap': (_) => const MonthlyHeatmapScreen(),
        '/focus': (_) => const FocusScreen(),
        '/matrix': (_) => const MatrixScreen(),
        '/intention': (_) => const IntentionScreen(),
        '/night-review': (_) => const NightReviewScreen(),
        '/premium': (_) => const PremiumScreen(),
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
    if (isGuest) return const GridScreen();
    final auth = ref.watch(authStateProvider);
    return auth.when(
      data: (user) => user != null ? const GridScreen() : const AuthScreen(),
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
    final s = S.of(context);
    return Scaffold(
      backgroundColor: gp.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.grid_view_rounded,
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
            const SizedBox(height: 6),
            Text(
              s.tagline,
              style: TextStyle(
                fontSize: 13,
                color: gp.textSec,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
