import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/constants/game_constants.dart';
import 'core/l10n/app_strings.dart';
import 'core/providers/onboarding_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/app_badge_service.dart';
import 'core/services/home_widget_service.dart';
import 'core/services/notification_service.dart';
import 'core/theme/game_theme.dart';
import 'features/auth/notifiers/auth_notifier.dart';
import 'features/auth/screens/auth_screen.dart';
import 'features/dashboard/notifiers/dashboard_notifier.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/habits/catalog/habit_plans.dart' show reminderTimeProvider;
import 'features/habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitCatalog, IslamicHabitTemplate;
import 'features/habits/models/habit_cue.dart';
import 'features/habits/notifiers/custom_habits_notifier.dart'
    show customHabitsProvider, habitListProvider;
import 'features/focus/screens/focus_screen.dart';
import 'features/grid/notifiers/weekly_grid_notifier.dart'
    show weeklyGridProvider;
import 'features/grid/screens/grid_screen.dart';
import 'features/grid/screens/monthly_heatmap_screen.dart';
import 'features/language/screens/language_picker_screen.dart';
import 'features/matrix/screens/matrix_screen.dart';
import 'features/night_review/screens/night_review_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/premium/screens/premium_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'firebase_options.dart';

/// Today's scheduled habits vs. how many are already complete, plus the
/// per-habit rows the large widget and the app icon badge are both built
/// from — kept as one shape so those two can't quietly drift apart.
typedef _TodayHabitStats = ({
  int completed,
  int total,
  List<({String id, String name, bool done})> habits,
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp]);
  }
  SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  // Both supported locales, always — not just whichever one MaterialApp
  // resolves to. Grid's dual-language day headers format dates in en AND
  // ar regardless of the app's active language, and intl throws
  // LocaleDataException on an uninitialized locale, so both must be ready
  // before any screen can render.
  await initializeDateFormatting('en');
  await initializeDateFormatting('ar');
  await Hive.initFlutter();
  await Future.wait([
    Hive.openBox(GameConstants.boxSettings),
    Hive.openBox(GameConstants.boxDailyLogs),
    Hive.openBox(GameConstants.boxHabits),
  ]);
  await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.init();
  await HomeWidgetService.instance.init();
  // Seed guestModeProvider from Hive so a returning guest with intact local
  // data lands back on their grid instead of being bounced to the auth
  // screen (the provider's own default is always `false` in memory).
  final persistedGuestMode = await loadPersistedGuestMode();
  final persistedLocale = await loadPersistedLocale();
  final persistedOnboardingSeen = await loadPersistedOnboardingSeen();
  final persistedThemeMode = await loadPersistedThemeMode();
  // Also applies the preset's colors to GameColors immediately, so the
  // very first frame already renders in the right preset.
  final persistedThemePreset = await loadPersistedThemePreset();
  runApp(ProviderScope(
    overrides: [
      guestModeProvider.overrideWith((ref) => persistedGuestMode),
      ...localeProviderOverrides(persistedLocale),
      onboardingSeenProvider.overrideWith((ref) => persistedOnboardingSeen),
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

class _GrowDailyAppState extends ConsumerState<GrowDailyApp>
    with WidgetsBindingObserver {
  ProviderSubscription<TimeOfDay?>? _reminderSub;
  ProviderSubscription<List<IslamicHabitTemplate>>? _habitRemindersSub;
  ProviderSubscription<DashboardState>? _widgetSub;

  @override
  void initState() {
    super.initState();
    // So didChangeAppLifecycleState below actually fires — see its doc
    // comment for why: draining whatever the widget's Mark Done button
    // queued while the app was closed.
    WidgetsBinding.instance.addObserver(this);

    // Wire Mark Done / Snooze notification taps to the exact same
    // completion path the UI itself uses — see NotificationService's
    // "Actionable notifications" doc comment for why this deliberately only
    // ever runs through the live app rather than a background isolate.
    // Assigning this also flushes any tap that already arrived (e.g. the
    // app was cold-launched by tapping an action) — see NotificationService
    // .onAction.
    NotificationService.instance.onAction = _handleNotificationAction;

    // Catch anything the widget queued between the last time the app was
    // open and this cold start (see _processPendingWidgetCompletions).
    _processPendingWidgetCompletions();

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

    // Give each habit with a fixed clock-time cue its own real reminder
    // (see NotificationService.scheduleHabitReminders) instead of every
    // habit sharing the one generic ping above. Re-runs on cold start and
    // any time a habit is added/edited/removed or its cue changes.
    _habitRemindersSub = ref.listenManual(habitListProvider, (previous, next) {
      final dash = ref.read(dashboardProvider);
      final reminders =
          <({String id, String name, TimeOfDay time, int streak})>[];
      for (final habit in next) {
        final time = HabitCue.fromStoredValue(habit.cueAfter).clockTime;
        if (time != null) {
          reminders.add((
            id: habit.id,
            name: habit.name,
            time: time,
            streak: dash.habitStreak(habit.id),
          ));
        }
      }
      NotificationService.instance.scheduleHabitReminders(reminders);
      _syncBadge();
    }, fireImmediately: true);

    // Keep the home screen + Lock Screen widgets current — no-ops safely
    // until the native widget extension exists (see ios/WIDGET_SETUP.md).
    _widgetSub = ref.listenManual(dashboardProvider, (previous, next) {
      final stats = _todayHabitStats();
      HomeWidgetService.instance.updateWidgetData(
        streak: next.streak,
        level: next.level,
        gold: next.gold,
        completedToday: stats.completed,
        totalToday: stats.total,
        todayHabits: stats.habits,
        dailyGreenCounts: next.dailyGreenCounts,
      );
      _syncBadge(stats);
    }, fireImmediately: true);
  }

  /// Called whenever the app returns to the foreground — in particular,
  /// this is what actually credits a habit someone marked done from the
  /// widget while the app was closed or backgrounded (see
  /// _processPendingWidgetCompletions).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _processPendingWidgetCompletions();
    }
  }

  /// Drains habit ids the large widget's Mark Done button queued (see the
  /// AppIntent in WIDGET_SETUP.md) and runs each through the exact same
  /// completeHabit + grid-mirror path as a real in-app tap — reusing
  /// _handleNotificationAction, which already does exactly that. The widget
  /// itself shows a tapped habit as done the instant it's tapped (its
  /// AppIntent flips its own cached copy of today's habits before this is
  /// ever read); this is what makes that tap *count* — XP, streak, gold —
  /// which can only safely happen through the app's real, live state.
  Future<void> _processPendingWidgetCompletions() async {
    final ids = await HomeWidgetService.instance.takePendingCompletions();
    for (final id in ids) {
      await _handleNotificationAction(NotificationService.actionMarkDone, id);
    }
    if (ids.isNotEmpty) _syncBadge();
  }

  /// Today's scheduled habits vs. how many are already complete, plus the
  /// per-habit list itself — the one computation both the widgets and the
  /// app icon badge are built from, kept in one place so they can't quietly
  /// drift apart.
  _TodayHabitStats _todayHabitStats() {
    final today = DateTime.now();
    final scheduled =
        ref.read(habitListProvider).where((h) => h.isScheduledFor(today));
    final dash = ref.read(dashboardProvider);
    var completed = 0;
    final habits = <({String id, String name, bool done})>[];
    for (final h in scheduled) {
      final done = dash.isCompleted(h.id, h.frequencyTarget);
      if (done) completed++;
      habits.add((id: h.id, name: h.name, done: done));
    }
    return (completed: completed, total: habits.length, habits: habits);
  }

  /// However many of today's scheduled habits are still incomplete.
  /// flutter_local_notifications has no standalone "set the badge" call
  /// (see AppBadgeService's doc comment), so this is the one place that
  /// decides what the app icon badge should say right now. [stats] is
  /// optional so callers that already computed it (the widget listener
  /// above) don't do the same habit-list scan twice.
  void _syncBadge([_TodayHabitStats? stats]) {
    final s = stats ?? _todayHabitStats();
    AppBadgeService.instance.setCount(s.total - s.completed);
  }

  /// Resolves a habit id the same way the Dashboard's own completion-toast
  /// listener does (built-in catalog first, then custom habits) — except
  /// this returns null on a genuine miss instead of falling back to some
  /// other habit, since this feeds an action that *mutates* state
  /// (completing a habit), not just a display label.
  IslamicHabitTemplate? _resolveHabit(String habitId) {
    final builtin = IslamicHabitCatalog.findById(habitId);
    if (builtin != null) return builtin;
    for (final h in ref.read(customHabitsProvider)) {
      if (h.id == habitId) return h;
    }
    return null;
  }

  /// Handles a Mark Done / Snooze tap on a habit reminder notification —
  /// wired up as NotificationService.instance.onAction in initState above.
  /// [habitId] is the notification's payload (see scheduleHabitReminders).
  Future<void> _handleNotificationAction(
      String actionId, String? habitId) async {
    if (habitId == null || habitId.isEmpty) return;
    final habit = _resolveHabit(habitId);
    if (habit == null) return;

    if (actionId == NotificationService.actionSnooze) {
      NotificationService.instance.snoozeHabitReminder(habitId, habit.name);
      return;
    }
    if (actionId == NotificationService.actionMarkDone) {
      // Mirrors DashboardScreen._completeHabit exactly: completeHabit grants
      // the one canonical reward for this habit-day, then — only if that
      // was a single-tap habit finishing just now — the Grid square is
      // mirrored to green too, same as tapping it from Today's Habits would.
      final justFinishedSingleTap =
          await ref.read(dashboardProvider.notifier).completeHabit(
                habitId: habit.id,
                xpReward: habit.xpReward,
                goldReward: habit.goldReward,
                frequencyTarget: habit.frequencyTarget,
                category: habit.category.name,
                habitName: habit.name,
              );
      if (justFinishedSingleTap) {
        ref
            .read(weeklyGridProvider.notifier)
            .markCompleteFromHabit(habit.id, DateTime.now());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminderSub?.close();
    _habitRemindersSub?.close();
    _widgetSub?.close();
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
    if (isGuest) return const _OnboardingOrGrid();
    final auth = ref.watch(authStateProvider);
    return auth.when(
      data: (user) =>
          user != null ? const _OnboardingOrGrid() : const AuthScreen(),
      loading: () => const _SplashScreen(),
      error: (_, __) => const AuthScreen(),
    );
  }
}

/// Once someone's authenticated (or in guest mode), one more gate before the
/// real app: the first-run walkthrough, shown exactly once per device. See
/// [onboardingSeenProvider] — finishing or skipping it flips that flag, which
/// is what actually reveals the Grid; this widget just reacts to it.
class _OnboardingOrGrid extends ConsumerWidget {
  const _OnboardingOrGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(onboardingSeenProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: seen
          ? const GridScreen(key: ValueKey('grid'))
          : const OnboardingScreen(key: ValueKey('onboarding')),
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
