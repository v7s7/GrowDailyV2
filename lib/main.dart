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
import 'features/language/screens/language_picker_screen.dart';
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
  final persistedLocale = await loadPersistedLocale();
  final persistedThemeMode = await loadPersistedThemeMode();
  // Also applies the preset's colors to GameColors immediately, so the
  // very first frame already renders in the right preset.
  final persistedThemePreset = await loadPersistedThemePreset();
  runApp(ProviderScope(
    overrides: [
      guestModeProvider.overrideWith((ref) => persistedGuestMode),
      ...localeProviderOverrides(persistedLocale),
      if (persistedThemeMode != null)
        themeModeProvider.overrideWith((ref) => ThemeModeNotifier(persistedThemeMode)),
      if (persistedThemePreset != null)
        themePresetProvider.overrideWith((ref) => ThemePresetNotifier(persistedThemePreset)),
    ],
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
    // Not read directly below — GameTheme.light/dark pull live from
    // GameColors, which `themePresetProvider.notifier.set()` mutates in
    // place. Watching here is what makes that mutation actually trigger a
    // rebuild (and thus a fresh MaterialApp theme) across the whole app.
    ref.watch(themePresetProvider);

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
        '/': (_) => const _LanguageGate(),
        '/heatmap': (_) => const MonthlyHeatmapScreen(),
        '/intention': (_) => const IntentionScreen(),
        '/night-review': (_) => const NightReviewScreen(),
        '/premium': (_) => const PremiumScreen(),
        '/auth': (_) => const AuthScreen(),
        // Focus is still available as a normal pushed screen, while Matrix is
        // restored as the bottom-nav peer tab below.
        '/focus': (_) => const FocusScreen(),
      },
      onGenerateRoute: (settings) {
        // The bottom nav bar's four tabs are peers, not a hierarchy, so
        // switching between them shouldn't play a "pushing a new screen"
        // transition. Other apps (Instagram, Spotify, WhatsApp, ...) swap
        // bottom-tab content instantly — everything else still gets the
        // normal platform push/pop animation via the `routes` map above.
        final WidgetBuilder? builder = switch (settings.name) {
          '/dashboard' => (_) => const DashboardScreen(),
          '/grid' => (_) => const GridScreen(),
          '/matrix' => (_) => const MatrixScreen(),
          '/profile' => (_) => const ProfileScreen(),
          _ => null,
        };
        if (builder == null) return null;
        return PageRouteBuilder(
          settings: settings,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, _, __) => builder(context),
        );
      },
    );
  }
}

/// Shown once per device, before auth: picks a language on first launch,
/// then hands off to [_AuthGate]. Crossfades rather than snapping straight
/// to the auth/grid screen once a language is chosen.
class _LanguageGate extends ConsumerWidget {
  const _LanguageGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = ref.watch(languageChosenProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: chosen
          ? const _AuthGate(key: ValueKey('auth-gate'))
          : const LanguagePickerScreen(key: ValueKey('language-picker')),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate({super.key});

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
            Icon(Icons.grid_view_rounded,
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
