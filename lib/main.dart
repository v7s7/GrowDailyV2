import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/constants/game_constants.dart';
import 'core/extensions/datetime_ext.dart';
import 'core/l10n/app_strings.dart';
import 'core/providers/app_guide_provider.dart';
import 'core/providers/get_started_checklist_provider.dart';
import 'core/providers/home_tab_provider.dart'
    show requestedHomeTabProvider, requestedMatrixQuickAddProvider;
import 'core/providers/onboarding_provider.dart';
import 'core/providers/room_finale_seen_provider.dart';
import 'core/providers/weekly_recap_collapsed_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/analytics_service.dart';
import 'core/services/app_badge_service.dart';
import 'core/services/home_widget_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/purchase_service.dart';
import 'core/theme/game_theme.dart';
import 'features/auth/notifiers/auth_notifier.dart';
import 'features/auth/screens/auth_screen.dart';
import 'features/dashboard/notifiers/dashboard_notifier.dart';
import 'features/habits/catalog/habit_plans.dart' show reminderTimeProvider;
import 'features/habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitCatalog, IslamicHabitTemplate;
import 'features/habits/models/habit_cue.dart';
import 'features/insights/insights_screen.dart';
import 'features/habits/models/habit_model.dart' show GoalType, ReductionType;
import 'features/habits/notifiers/custom_habits_notifier.dart'
    show customHabitsProvider, habitListProvider, habitsStillLoadingProvider;
import 'features/grid/models/square_state.dart' show SquareState;
import 'features/grid/notifiers/weekly_grid_notifier.dart'
    show WeeklyGridState, isQuitAutoCleanEligible, weeklyGridProvider;
import 'features/grid/screens/grid_journal_screen.dart';
import 'features/grid/screens/monthly_heatmap_screen.dart';
import 'features/language/screens/language_picker_screen.dart';
import 'features/matrix/models/matrix_task.dart' show MatrixQuadrant;
import 'features/matrix/notifiers/matrix_notifier.dart'
    show MatrixState, isMatrixQuickAddLink, matrixProvider;
import 'features/matrix/widgets/voice_note_player.dart'
    show GlobalVoiceNotePlayerOverlay;
import 'features/night_review/screens/night_review_screen.dart';
import 'features/onboarding/screens/app_guide_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/premium/notifiers/premium_notifier.dart';
import 'features/premium/screens/premium_screen.dart';
import 'features/profile/screens/help_support_screen.dart';
import 'features/profile/screens/profile_screen.dart' show SettingsScreen;
import 'features/rooms/notifiers/rooms_notifier.dart'
    show
        RoomRaceSnapshot,
        myRoomRaceSnapshotProvider,
        pendingJoinCodeProvider,
        pendingOpenRoomCodeProvider,
        parseRoomJoinLink,
        roomBoostedReward,
        syncRoomToday,
        // _resyncMyRooms (didChangeAppLifecycleState) - keeps this account's
        // own room progress fresh for everyone else without needing anyone to
        // open the Rooms tab. See that method's doc comment.
        myRoomCodesProvider,
        roomProvider,
        roomsControllerProvider;
import 'features/rooms/screens/room_detail_screen.dart';
import 'features/rooms/screens/rooms_hub_screen.dart';
import 'features/rooms/widgets/room_finale_announcer.dart';
import 'features/rooms/widgets/join_room_sheet.dart' show showJoinRoomSheet;
import 'features/settings/models/notification_settings.dart';
import 'shared/widgets/home_shell.dart';
import 'features/settings/notifiers/notification_settings_notifier.dart'
    show notificationSettingsProvider;
import 'features/settings/screens/notification_settings_screen.dart';
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
  // Everything below is wrapped in runZonedGuarded rather than left as a
  // plain `Future<void> main() async {...}` body — see the crash-reporting
  // block a few lines in for why: its own onError (below) is the final
  // backstop of the three-layer setup that block describes, catching
  // anything that reaches neither FlutterError.onError nor
  // PlatformDispatcher.instance.onError (a fire-and-forget Future nobody
  // ever awaited or attached a catchError to, for instance).
  await runZonedGuarded(() async {
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

    // Crash reporting: three layers, matching Firebase's own documented
    // Flutter setup, since no single one of them catches everything on its
    // own.
    //   - FlutterError.onError catches errors *inside* the Flutter
    //     framework itself (a widget build/layout/paint error) —
    //     recordFlutterFatalError is Crashlytics' own recommended handler,
    //     not a custom one, so it also forwards to whatever default
    //     handling FlutterError.onError already did (red screen in debug).
    //   - PlatformDispatcher.instance.onError catches everything else in
    //     this isolate that isn't already inside a try/catch — a bad
    //     `late` field, a failed cast, a plugin's platform-channel error —
    //     including cases Flutter's own error zone doesn't see.
    //   - runZonedGuarded's own onError, at the bottom of this function,
    //     is the final backstop: a fire-and-forget Future nobody ever
    //     awaited or attached a catchError to surfaces here instead of
    //     vanishing as an "Unhandled exception" in the console with zero
    //     record anywhere — the actual gap this whole change closes (see
    //     the empty `catch (_) {}` blocks this same pass fixed in
    //     dashboard_notifier.dart for the same underlying problem).
    // Collection disabled for local `flutter run` debug sessions
    // (kDebugMode) so a developer's own hot-reload/dev-loop errors don't
    // pollute the real dashboard — every real distribution path
    // (TestFlight via RELEASE.md's `flutter build ipa`) is a release build
    // regardless, so this never silences a build anyone outside the dev
    // machine will ever run.
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    await NotificationService.instance.init();
    await HomeWidgetService.instance.init();
    // Configures the RevenueCat SDK with the production API key (see
    // PurchaseService's doc comment). Safe to call unconditionally even if
    // it were ever unset — [PurchaseService.configure] never throws.
    await PurchaseService.instance.configure();
    // Seed guestModeProvider from Hive so a returning guest with intact local
    // data lands back on their grid instead of being bounced to the auth
    // screen (the provider's own default is always `false` in memory).
    final persistedGuestMode = await loadPersistedGuestMode();
    final persistedLocale = await loadPersistedLocale();
    final persistedOnboardingSeen = await loadPersistedOnboardingSeen();
    final persistedGetStartedDismissed = await loadPersistedGetStartedDismissed();
    final persistedAppGuideRoomsSeen = await loadPersistedAppGuideRoomsSeen();
    final persistedRoomFinaleSeen = await loadPersistedRoomFinaleSeen();
    final persistedAppGuideBadgeSeen = await loadPersistedAppGuideBadgeSeen();
    final persistedRecapCollapsed = await loadPersistedWeeklyRecapCollapsed();
    final persistedThemeMode = await loadPersistedThemeMode();
    // Also applies the preset's colors to GameColors immediately, so the
    // very first frame already renders in the right preset.
    final persistedThemePreset = await loadPersistedThemePreset();
    // Also applies the font to GameTextStyles immediately, so the very first
    // frame already renders in the right typeface instead of flashing the
    // default and then swapping.
    final persistedFont = await loadPersistedFont();
    runApp(ProviderScope(
      overrides: [
        guestModeProvider.overrideWith((ref) => persistedGuestMode),
        ...localeProviderOverrides(persistedLocale),
        onboardingSeenProvider.overrideWith((ref) => persistedOnboardingSeen),
        getStartedDismissedProvider.overrideWith((ref) => persistedGetStartedDismissed),
        appGuideRoomsSeenProvider.overrideWith((ref) => persistedAppGuideRoomsSeen),
        roomFinaleSeenProvider.overrideWith((ref) => persistedRoomFinaleSeen),
        appGuideBadgeSeenProvider.overrideWith((ref) => persistedAppGuideBadgeSeen),
        weeklyRecapCollapsedProvider.overrideWith((ref) => persistedRecapCollapsed),
        if (persistedThemeMode != null)
          themeModeProvider.overrideWith((ref) => ThemeModeNotifier(persistedThemeMode)),
        if (persistedThemePreset != null)
          themePresetProvider.overrideWith((ref) => ThemePresetNotifier(persistedThemePreset)),
        if (persistedFont != null)
          appFontProvider.overrideWith((ref) => AppFontNotifier(persistedFont)),
      ],
      child: const GrowDailyApp(),
    ));
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
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
  ProviderSubscription<NotificationSettings>? _notificationSettingsSub;
  ProviderSubscription<WeeklyGridState>? _gridSub;
  ProviderSubscription<AsyncValue<User?>>? _authSub;
  ProviderSubscription<RoomRaceSnapshot?>? _roomRaceSub;
  ProviderSubscription<MatrixState>? _matrixWidgetSub;
  StreamSubscription<Uri>? _linkSub;
  final _appLinks = AppLinks();

  // Lets notification body-taps navigate without a BuildContext of their
  // own — see _handleNotificationBodyTap. Attached to MaterialApp below.
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // So didChangeAppLifecycleState below actually fires — see its doc
    // comment for why: draining whatever the widget's Mark Done button
    // queued while the app was closed.
    WidgetsBinding.instance.addObserver(this);

    // Routes a tapped room-finish push to the right room - the actual
    // navigation happens through pendingOpenRoomCodeProvider (see
    // _OnboardingOrGrid's listener), same "hand it to something that can
    // safely navigate" indirection NotificationService.onAction already
    // uses for a tapped local-notification action. Set unconditionally,
    // not just for signed-in users - harmless either way, since a push
    // only ever reaches a device that registered a token in the first
    // place (see PushNotificationService.registerForUser).
    PushNotificationService.instance.onOpenRoom = (code) {
      ref.read(pendingOpenRoomCodeProvider.notifier).state = code;
    };

    // Once sign-in resolves — including "already signed in" on a warm
    // boot — pull each of these settings' account-level value, if the
    // account has one (see ThemeModeNotifier.pullFromAccount's doc
    // comment), and tie RevenueCat's App User ID to this Firebase account
    // (see PurchaseService.logIn's doc comment). `fireImmediately: true`
    // is load-bearing here, not decoration: this used to be a plain
    // `ref.listen` inside build(), which only fires on a *change* to
    // authStateProvider - for anyone already signed in when the widget
    // first builds (i.e. every user after their first session), that
    // "already signed in" state was never a change from this listener's
    // point of view, so it silently never fired at all. In practice that
    // meant PurchaseService.logIn(uid) never ran for a returning signed-in
    // user, so their RevenueCat identity stayed anonymous forever instead
    // of linking to their account - exactly what surfaced as every
    // customer in the RevenueCat dashboard showing as $RCAnonymousID
    // instead of a real Firebase uid. `listenManual` + `fireImmediately`
    // is the same fix already used for every other listener in this
    // method (see _reminderSub etc. below) - this one just hadn't gotten
    // it.
    _authSub = ref.listenManual(authStateProvider, (previous, next) {
      final uid = next.asData?.value?.uid;
      // Ties analytics to the real account instead of leaving every
      // session anonymous, same as PurchaseService.logIn below for
      // RevenueCat's identity — see AnalyticsService.setUserId's doc
      // comment.
      AnalyticsService.instance.setUserId(uid);
      // Same idea for crash reports — a crash correlated to a real uid
      // (rather than an anonymous device) is the difference between
      // "something broke for someone" and "I can look up this exact
      // account's data to reproduce it." Cleared to '' on sign-out rather
      // than left stale, same as this block's detachAccount() calls below.
      FirebaseCrashlytics.instance.setUserIdentifier(uid ?? '');
      if (uid != null) {
        ref.read(themeModeProvider.notifier).pullFromAccount(uid);
        ref.read(themePresetProvider.notifier).pullFromAccount(uid);
        ref.read(appFontProvider.notifier).pullFromAccount(uid);
        ref.read(reminderTimeProvider.notifier).pullFromAccount(uid);
        ref.read(notificationSettingsProvider.notifier).pullFromAccount(uid);
        _syncAmbientAccountFacts(uid);
        // Keeps this device's FCM token mirrored to this account for the
        // room-finish push (see PushNotificationService's own doc comment)
        // - a no-op token-wise if nothing's changed since the last sync,
        // same as every other call in this branch.
        PushNotificationService.instance.registerForUser(uid);
        // Apply this identity's CustomerInfo the moment it's back, instead
        // of letting PremiumNotifier's own constructor-time refresh() race
        // it — see PurchaseService.logIn's doc comment for the cold-start
        // "shows not Premium for a moment" flash this closes. `mounted` is
        // a real guard here (unlike the synchronous calls above): this
        // fires after a network round trip, so the app could in principle
        // have torn this widget down before it lands.
        PurchaseService.instance.logIn(uid).then((info) {
          if (info != null && mounted) {
            ref.read(premiumProvider.notifier).applyCustomerInfo(info);
          }
        });
      } else {
        ref.read(themeModeProvider.notifier).detachAccount();
        ref.read(themePresetProvider.notifier).detachAccount();
        ref.read(appFontProvider.notifier).detachAccount();
        ref.read(reminderTimeProvider.notifier).detachAccount();
        ref.read(notificationSettingsProvider.notifier).detachAccount();
        PurchaseService.instance.logOut();
        // Drops this device's own token doc so a shared/reset device stops
        // being a room-finish push target for the account that just left it.
        PushNotificationService.instance.clearForSignOut();
      }
    }, fireImmediately: true);

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
    _processPendingWidgetTaskCompletions();

    // Catch a growdaily://join/CODE link that cold-launched the app, and
    // keep listening for one arriving while the app's already running (a
    // friend's invite tapped while GrowDaily is backgrounded, say).
    // Instantiated here, early in initState, per app_links' own guidance,
    // so a cold-start link is never missed. See _OnboardingOrGrid's
    // listener for where the code this stores actually gets acted on - not
    // here, since it isn't safe to navigate yet this early (the language/
    // auth/onboarding gates haven't resolved).
    _initDeepLinks();

    // Re-arm the daily reminder on cold start. Android clears exact-alarm
    // schedules on device reboot, so this makes sure a previously-set
    // reminder survives a restart even without a boot-completed receiver.
    // `fireImmediately` needs listenManual (not the build-scoped ref.listen),
    // since it has to run once as soon as the persisted value loads, not
    // only on a future change. The actual scheduling decision — including
    // respecting NotificationSettings.masterEnabled — lives in
    // _recomputeNotifications, since flipping the master switch has to
    // reach this too, not just a reminderTimeProvider change.
    _reminderSub = ref.listenManual(
      reminderTimeProvider,
      (previous, next) => _recomputeNotifications(),
      fireImmediately: true,
    );

    // Resolve every habit's cue (fixed clock time or a prayer) into a real
    // reminder — see NotificationService.scheduleSmartReminders. Re-runs on
    // cold start and any time the habit list changes (added/edited/removed,
    // cue changed).
    _habitRemindersSub = ref.listenManual(
      habitListProvider,
      (previous, next) {
        _recomputeNotifications();
        // Also one of _maybeAutoCleanQuitYesterday's three triggers (with
        // the dashboard and grid listeners below) — it gates on BOTH the
        // habit list and dashboard state being loaded, and which of those
        // finishes last isn't deterministic, so every input's listener has
        // to give it a chance to run or a load-order race could skip the
        // pass for the whole session.
        _maybeAutoCleanQuitYesterday();
      },
      fireImmediately: true,
    );

    // Same recompute, triggered by a completion/streak change instead of a
    // habit-list change — this is what cancels today's reminder for a habit
    // the moment it's marked done, and what keeps the streak-risk nudge's
    // "still pending" count current. Also still owns the home screen/Lock
    // Screen widget + app badge sync it always has.
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
      _recomputeNotifications();
      _maybeAutoCleanQuitYesterday(); // see _habitRemindersSub's comment
    }, fireImmediately: true);

    // Every toggle/time/location in Settings > Notifications funnels
    // through here too — e.g. turning quiet hours on has to reach already-
    // scheduled reminders, not just future ones.
    _notificationSettingsSub = ref.listenManual(
      notificationSettingsProvider,
      (previous, next) => _recomputeNotifications(),
      fireImmediately: true,
    );

    // Grid square changes need their own recompute trigger: the quit-habit
    // slip/undo-slip paths can change today's resolution state without any
    // dashboardProvider change at all (logging a slip when nothing was
    // completed yet only touches the Grid — uncompleteHabit no-ops), and
    // tonight's quit check-in has to notice either way. Also doubles as
    // the auto-clean pass's trigger once grid/dashboard data finishes
    // loading — see _maybeAutoCleanQuitYesterday.
    _gridSub = ref.listenManual(weeklyGridProvider, (previous, next) {
      _recomputeNotifications();
      _maybeAutoCleanQuitYesterday();
    }, fireImmediately: true);

    // Keeps the widget's opt-in Room Race face current — see
    // rooms_notifier.dart's myRoomRaceSnapshotProvider for how "the one
    // room" to show and its ranking get picked. fireImmediately so a cold
    // start with an already-live room doesn't leave the widget on stale
    // data (or its placeholder) until something in Rooms happens to change.
    _roomRaceSub = ref.listenManual(myRoomRaceSnapshotProvider,
        (previous, next) {
      HomeWidgetService.instance.updateRoomRaceData(
        hasRoom: next != null,
        roomName: next?.roomName ?? '',
        isLive: next?.isLive ?? false,
        daysRemaining: next?.daysRemaining ?? 0,
        rows: [
          for (final r in next?.rows ?? const [])
            (
              name: r.name,
              rank: r.rank,
              percent: r.percent,
              isMe: r.isMe,
              uid: r.uid,
              daysDone: r.daysDone,
              daysTotal: r.daysTotal,
              heatmap: r.heatmap,
            ),
        ],
      );
    }, fireImmediately: true);

    // Keeps the Matrix widget's task list current — see HomeWidgetService.
    // updateMatrixWidgetData's doc comment for why this pushes every open
    // task, sorted, rather than a pre-capped handful: the Swift side decides
    // how many rows a given widget size actually has room to draw.
    // fireImmediately so a cold start with tasks already on the board
    // doesn't leave the widget on stale data (or its placeholder) until the
    // very first edit.
    _matrixWidgetSub = ref.listenManual(matrixProvider, (previous, next) {
      final now = DateTime.now();
      final open = next.tasks.where((t) => !t.isDone).toList()
        ..sort((a, b) {
          final byQuadrant = _matrixQuadrantRank(a.quadrant)
              .compareTo(_matrixQuadrantRank(b.quadrant));
          return byQuadrant != 0 ? byQuadrant : a.order.compareTo(b.order);
        });
      HomeWidgetService.instance.updateMatrixWidgetData([
        for (final t in open)
          (
            id: t.id,
            title: t.title,
            quadrant: t.quadrant.name,
            isDone: t.isDone,
            isFav: t.isFav,
            // Same "overdue" definition as MatrixNotifier's
            // latestMissedTaskReminder (reminder set, in the past, task
            // still open) — deliberately NOT gated on the notifications
            // master switch the way that one is, since this just marks the
            // task as late, it doesn't fire anything.
            //
            // Keyed off the *last* reminder, not the first: a task warned
            // about at 3:00, 3:30 and 4:00 isn't late at 3:15 just because
            // the first nudge has been and gone — two more are still
            // coming. See MatrixTask.lastReminderAt.
            isLate: t.lastReminderAt != null &&
                !t.lastReminderAt!.isAfter(now),
          ),
      ]);
    }, fireImmediately: true);
  }

  /// Do First → Schedule → Delegate → Eliminate, the same triage order the
  /// in-app board itself reads top to bottom — see [_matrixWidgetSub]. A
  /// widget only has room for a handful of rows, so this decides which open
  /// tasks are worth those rows when there are more open tasks than space
  /// to show them.
  int _matrixQuadrantRank(MatrixQuadrant q) => switch (q) {
        MatrixQuadrant.doFirst => 0,
        MatrixQuadrant.schedule => 1,
        MatrixQuadrant.delegate => 2,
        MatrixQuadrant.eliminate => 3,
      };

  // Once-per-app-day guard for _maybeAutoCleanQuitYesterday — in-memory
  // only on purpose: autoCleanQuitDay is idempotent (only ever writes over
  // an untouched square), so re-running after a cold start costs one day-
  // doc read and changes nothing that's already settled.
  String? _lastQuitAutoCleanKey;

  /// Settles *yesterday's* record for quit habits that were never answered:
  /// an untouched square counts as clean — see
  /// WeeklyGridNotifier.autoCleanQuitDay for the write rules (visual green
  /// only, no rewards) and isQuitAutoCleanEligible for which habits
  /// qualify. Runs at most once per app-day, and only after the habit list
  /// and dashboard state have genuinely loaded — the eligibility rule
  /// reads habitLastCompletedDate, which is empty mid-load, and burning
  /// the once-a-day guard on unloaded data would skip the real pass
  /// entirely. Only yesterday, never every missed day since last open:
  /// yesterday evening's check-in asked and got silence, which is a fair
  /// "clean"; assuming a whole untracked week was clean would be inventing
  /// history.
  void _maybeAutoCleanQuitYesterday() {
    final todayKey = DateTime.now().effectiveDay.toDateKey();
    if (_lastQuitAutoCleanKey == todayKey) return;
    final dash = ref.read(dashboardProvider);
    if (dash.isLoading || ref.read(habitsStillLoadingProvider)) return;
    _lastQuitAutoCleanKey = todayKey;

    final yesterday =
        DateTime.now().effectiveDay.subtract(const Duration(days: 1));
    final ids = [
      for (final h in ref.read(habitListProvider))
        if (isQuitAutoCleanEligible(
          isQuit: h.goalType == GoalType.quit,
          isSingleTap: h.frequencyTarget == 1,
          wasScheduled: h.isScheduledFor(yesterday),
          hasEverCompleted: dash.habitLastCompletedDate.containsKey(h.id),
        ))
          h.id,
    ];
    ref
        .read(weeklyGridProvider.notifier)
        .autoCleanQuitDay(ids, yesterday)
        .ignore();
  }

  /// The one place that turns "habits + today's completions + streaks +
  /// Matrix's urgent-task count + notification settings" into actual
  /// scheduled notifications. Deliberately re-reads everything fresh via
  /// `ref.read` on every call rather than trusting whichever provider's
  /// listener happened to trigger it — cheap (a handful of in-memory list
  /// scans) and means every trigger path (habit list, dashboard, settings,
  /// or a plain app resume — see didChangeAppLifecycleState) produces the
  /// exact same result instead of four subtly different code paths.
  void _recomputeNotifications() {
    final settings = ref.read(notificationSettingsProvider);
    final isAr = ref.read(localeProvider).languageCode == 'ar';

    final reminderTime = ref.read(reminderTimeProvider);
    if (reminderTime != null && settings.masterEnabled) {
      NotificationService.instance.scheduleDailyReminder(
        hour: reminderTime.hour,
        minute: reminderTime.minute,
        isAr: isAr,
      );
    } else {
      NotificationService.instance.cancelDailyReminder();
    }

    final dash = ref.read(dashboardProvider);
    final today = DateTime.now().effectiveDay;
    final todayHabits = ref
        .read(habitListProvider)
        .where((h) => h.isScheduledFor(today))
        .toList();

    final reminders = <HabitReminderInput>[];
    var pendingCount = 0;
    for (final habit in todayHabits) {
      final done = dash.isCompleted(habit.id, habit.frequencyTarget);
      if (!done) pendingCount++;
      final cue = HabitCue.fromStoredValue(habit.cueAfter);
      reminders.add((
        id: habit.id,
        name: habit.localName(isAr),
        clockTime: cue.clockTime,
        prayerKey: cue.prayerKey,
        streak: dash.habitStreak(habit.id),
        isDoneToday: done,
        reminderOffsetMinutes: habit.reminderOffsetMinutes,
        ignoreQuietHours: habit.ignoreQuietHours,
      ));
    }
    NotificationService.instance
        .scheduleSmartReminders(reminders, settings, isAr: isAr);

    // "Do First" = urgent + important, the one Matrix quadrant that's a
    // reasonable proxy for "actually time-sensitive" without the app having
    // real per-task due times yet (MatrixTask has no due-date field today).
    // Read fresh here rather than from a dedicated Matrix listener: this
    // only ever feeds one line of the evening nudge, so it just needs to be
    // current by the time that fires, not instantly reactive to every
    // Matrix edit.
    final urgentMatrixCount = ref
        .read(matrixProvider)
        .tasks
        .where((t) => t.quadrant == MatrixQuadrant.doFirst && !t.isDone)
        .length;
    NotificationService.instance.scheduleStreakRiskCheck(
      settings: settings,
      streak: dash.streak,
      pendingHabitCount: pendingCount,
      urgentMatrixCount: urgentMatrixCount,
      isAr: isAr,
    );

    // Matrix task reminders previously only resynced once, at cold start/
    // sign-in — every other reminder type above already gets re-derived on
    // every call to this method (including a plain resume, see
    // didChangeAppLifecycleState), so a Matrix reminder that silently
    // failed to schedule earlier (e.g. notification permission was off,
    // then granted later from system Settings) had no chance to self-heal
    // short of the user manually re-touching that exact task. See
    // MatrixNotifier.resyncReminders' own doc comment.
    ref.read(matrixProvider.notifier).resyncReminders();

    // Quit habits resolve in the evening, not (only) at a cue time — their
    // success is the absence of something, so the day gets settled by an
    // evening check-in instead of relying on the user remembering to tap
    // (see NotificationService.scheduleQuitCheckIns). Resolved = affirmed
    // on-track (completed) or logged as a slip (today's square already
    // red). Same single-tap-only rule as HabitCard's slip link. Reading
    // the grid fresh here can transiently miss a slip while the grid is
    // still loading or showing a past week — the _gridSub recompute
    // corrects that the moment the real data lands.
    final grid = ref.read(weeklyGridProvider);
    final quitCheckIns = <QuitCheckInInput>[
      for (final habit in todayHabits)
        if (habit.goalType == GoalType.quit && habit.frequencyTarget == 1)
          (
            id: habit.id,
            name: habit.localName(isAr),
            isLimit: habit.reductionType == ReductionType.limit,
            isResolvedToday:
                dash.isCompleted(habit.id, habit.frequencyTarget) ||
                    grid.squareFor(habit.id, today) == SquareState.failed,
          ),
    ];
    NotificationService.instance
        .scheduleQuitCheckIns(quitCheckIns, settings, isAr: isAr);

    // Weekly digest content ("N of 7 days colored") comes straight off the
    // same grid read above — only recomputed (and rescheduled) once that
    // grid is actually showing the current week and done loading; a stale
    // or mid-load read would either undercount or briefly show 0, so this
    // cycle just leaves the previous schedule alone and lets the next
    // recompute (moments later, once the real data lands) correct it —
    // same eventually-consistent pattern as the quit check-ins above.
    if (grid.isCurrentWeek && !grid.isLoading) {
      final greenDaysThisWeek = grid.days
          .where((d) => (grid.states[d.toDateKey()] ?? const {})
              .values
              .any((s) => s.isGreen))
          .length;
      NotificationService.instance.scheduleWeeklyDigest(
        settings: settings,
        greenDays: greenDaysThisWeek,
        streak: dash.streak,
        isAr: isAr,
      );
    }

    NotificationService.instance.celebrationsEnabled =
        settings.masterEnabled && settings.celebrationsEnabled;
    // Same reactive hand-off as the flag above: the celebration
    // notifications fired from DashboardNotifier have no BuildContext to
    // read the locale from. See NotificationService.isArabic.
    NotificationService.instance.isArabic = isAr;

    _syncBadge();
  }

  /// Called whenever the app returns to the foreground — in particular,
  /// this is what actually credits a habit someone marked done from the
  /// widget while the app was closed or backgrounded (see
  /// _processPendingWidgetCompletions), and what picks up account fields
  /// (gold, premium status, ...) changed from outside the app — e.g. by
  /// hand in the Firebase console while testing — since those notifiers
  /// otherwise only ever load once, at construction, and would just keep
  /// showing whatever they last saw until a full restart.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _processPendingWidgetCompletions();
      _processPendingWidgetTaskCompletions();
      ref.read(dashboardProvider.notifier).refresh();
      ref.read(premiumProvider.notifier).refresh();
      // The Grid's visible week is otherwise only computed once, at
      // construction — leaving the app open/backgrounded across the day
      // cutoff (see DateTimeGameExt.effectiveDay), and especially across a
      // Saturday grid-week boundary, would keep showing the old week until
      // a full restart without this.
      ref.read(weeklyGridProvider.notifier).refresh();
      // Local notifications can only ever be scheduled one occurrence
      // ahead (see NotificationService's class doc comment) — re-running
      // this on every resume, not just on explicit state changes, is what
      // keeps reminders self-healing for a day-cutoff rollover or a
      // yesterday-completed habit that happened while the app was closed.
      _recomputeNotifications();
      // Same self-healing idea for the ambient facts the room-finish push
      // Cloud Function reads (see _syncAmbientAccountFacts) — a trip across
      // time zones mid-session should be reflected by the next resume, not
      // require a fresh sign-in.
      final uid = ref.read(authStateProvider).asData?.value?.uid;
      if (uid != null) {
        _syncAmbientAccountFacts(uid);
        // Same self-healing idea as _syncAmbientAccountFacts right above -
        // catches a token that rotated while this device was backgrounded
        // (registerForUser's onTokenRefresh listener already catches one
        // that rotates while the app is actually running).
        PushNotificationService.instance.registerForUser(uid);
        _resyncMyRooms();
      }
    }
  }

  /// Pushes this account's own room progress up for every room it's in, on
  /// every resume.
  ///
  /// Why this has to exist: a room's leaderboard is assembled from each
  /// participant's OWN doc, and only that person's device may write it -
  /// nobody can compute a teammate's progress, because nobody else is
  /// allowed to read their habit history (see firestore.rules). So a
  /// teammate's row is only ever as fresh as the last time THEIR app synced.
  ///
  /// Before this, the only full resync ran when someone actually opened a
  /// room's detail screen, plus a per-tap fast path for habits already
  /// linked to a live room. That left an obvious hole: finish your habits,
  /// never open the Rooms tab, and everyone else keeps seeing you on zero -
  /// which reads as "the room is broken" rather than "her phone hasn't
  /// spoken to the server yet". Syncing on resume closes it without anyone
  /// needing to visit the room at all.
  ///
  /// Fire-and-forget and deliberately unawaited: it's a background freshening
  /// nothing on screen is waiting for, and a failure just means the next
  /// resume tries again.
  void _resyncMyRooms() {
    final codes = ref.read(myRoomCodesProvider).valueOrNull;
    if (codes == null || codes.isEmpty) return;
    final controller = ref.read(roomsControllerProvider);
    for (final code in codes) {
      final room = ref.read(roomProvider(code)).valueOrNull;
      // Skipped for a room that hasn't started or has already finished -
      // syncLinkedHabitsProgress would no-op on the first anyway, and the
      // second can't gain new progress.
      if (room == null || !room.hasStarted || room.isEnded) continue;
      controller.syncLinkedHabitsProgress(room).ignore();
    }
  }

  /// Best-effort mirror of two small device facts to `users/{uid}` that
  /// only exist for a server (never read anywhere else client-side): the
  /// active locale, and this device's current UTC offset in minutes. Both
  /// are for functions/index.js's room-finish push trigger, which has no
  /// other way to know which language a recipient reads or what "quiet
  /// hours" means in their local clock — see NotificationSettings.
  /// roomActivityEnabled's doc comment for the feature this feeds. A
  /// plain int offset (not a full IANA timezone id) is a deliberate
  /// simplification: good enough for a soft courtesy check like quiet
  /// hours, at the cost of being off by an hour during the couple of weeks
  /// a year DST transitions don't line up with the recipient's — an
  /// acceptable trade for not needing a timezone database in the function.
  /// Never awaited by its caller and never throws outward — a failed or
  /// offline write here just leaves the function's copy stale until the
  /// next successful sync, exactly like every other pullFromAccount-
  /// adjacent call in this listener.
  void _syncAmbientAccountFacts(String uid) {
    final locale = ref.read(localeProvider).languageCode;
    final tzOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    unawaited(FirebaseFirestore.instance.collection('users').doc(uid).set({
      'locale': locale,
      'tzOffsetMinutes': tzOffsetMinutes,
    }, SetOptions(merge: true)).catchError((_) {}));
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

  /// Same idea as [_processPendingWidgetCompletions], for the Matrix
  /// widget's checkmark instead of a habit's — see MarkTaskDoneIntent in
  /// GrowDailyWidget.swift. Guards on the task still being open before
  /// toggling: MatrixNotifier.toggle is a plain flip (not an idempotent
  /// "mark done"), so without this guard, a task the user already finished
  /// in-app before this queue drained would get silently un-done instead of
  /// safely no-op'd — the exact double-credit-shaped bug
  /// takePendingCompletions' habit path avoids by calling a real "mark
  /// done" action instead of a toggle. A missing id (task deleted before
  /// this drained) is skipped the same way.
  Future<void> _processPendingWidgetTaskCompletions() async {
    final ids = await HomeWidgetService.instance.takePendingTaskCompletions();
    if (ids.isEmpty) return;
    final tasks = ref.read(matrixProvider).tasks;
    final notifier = ref.read(matrixProvider.notifier);
    for (final id in ids) {
      final matches = tasks.where((t) => t.id == id);
      if (matches.isNotEmpty && !matches.first.isDone) {
        notifier.toggle(id);
      }
    }
  }

  /// Reads whatever link cold-launched the app (if any), then subscribes
  /// for further ones - both paths just hand off to [_handleDeepLink]. See
  /// _OnboardingOrGrid for where a stashed room code turns into navigation,
  /// and MatrixScreen's own ref.listen for where the Matrix quick-add flag
  /// does. Wrapped in try/catch since the initial-link platform channel can
  /// throw before the native side is fully ready on some launches - the
  /// live stream subscribed to right after still catches anything real, so
  /// a failure here is never fatal to deep linking as a whole, just to that
  /// one cold-start link.
  Future<void> _initDeepLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleDeepLink(initial);
    } catch (_) {
      // Ignored - see doc comment above.
    }
    _linkSub =
        _appLinks.uriLinkStream.listen(_handleDeepLink, onError: (_) {});
  }

  /// Every `growdaily://...` link this app currently recognizes, in one
  /// place — a room invite (see [parseRoomJoinLink]) or the Matrix widget's
  /// "+" button (see [isMatrixQuickAddLink]). A link matching neither is
  /// just ignored, same as before this was split out of [_initDeepLinks]:
  /// some other feature, or the OS itself, can hand this app a link for a
  /// reason unrelated to either of these, and that's fine.
  void _handleDeepLink(Uri uri) {
    final code = parseRoomJoinLink(uri);
    if (code != null) {
      ref.read(pendingJoinCodeProvider.notifier).state = code;
      return;
    }
    if (isMatrixQuickAddLink(uri)) {
      ref.read(requestedHomeTabProvider.notifier).state = 2;
      ref.read(requestedMatrixQuickAddProvider.notifier).state = true;
    }
  }

  /// Today's scheduled habits vs. how many are already complete, plus the
  /// per-habit list itself — the one computation both the widgets and the
  /// app icon badge are built from, kept in one place so they can't quietly
  /// drift apart.
  _TodayHabitStats _todayHabitStats() {
    final today = DateTime.now().effectiveDay;
    final scheduled =
        ref.read(habitListProvider).where((h) => h.isScheduledFor(today));
    final dash = ref.read(dashboardProvider);
    final isAr = ref.read(localeProvider).languageCode == 'ar';
    var completed = 0;
    final habits = <({String id, String name, bool done})>[];
    for (final h in scheduled) {
      final done = dash.isCompleted(h.id, h.frequencyTarget);
      if (done) completed++;
      habits.add((id: h.id, name: h.localName(isAr), done: done));
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
  /// [habitId] is the notification's payload (see
  /// NotificationService.scheduleSmartReminders) — never set on a bundled
  /// "N habits ready" notification, so this correctly no-ops on a tap
  /// there instead of trying to resolve a habit that isn't specified.
  Future<void> _handleNotificationAction(
      String actionId, String? habitId) async {
    // A plain body tap (no action button) carries an empty actionId — that
    // used to just open the app wherever it last was. Now it lands where
    // the notification actually points: see _handleNotificationBodyTap.
    if (actionId.isEmpty) {
      _handleNotificationBodyTap(habitId);
      return;
    }
    if (habitId == null || habitId.isEmpty) return;
    final habit = _resolveHabit(habitId);
    if (habit == null) return;
    final isAr = ref.read(localeProvider).languageCode == 'ar';

    if (actionId == NotificationService.actionSnooze) {
      NotificationService.instance
          .snoozeHabitReminder(habitId, habit.localName(isAr), isAr: isAr);
      return;
    }
    if (actionId == NotificationService.actionSlipped) {
      // The quit check-in's "Slipped" button — mirrors DashboardScreen.
      // _slipHabit exactly: reverse any same-day reward first
      // (uncompleteHabit no-ops safely when nothing was completed today),
      // then mirror the red square, which is also what flips HabitCard
      // into its slipped-today state.
      await ref.read(dashboardProvider.notifier).uncompleteHabit(
            habitId: habit.id,
            // Mirrors the completion's boost — see roomBoostedReward.
            xpReward: roomBoostedReward(ref, habit.id, habit.xpReward),
            goldReward: roomBoostedReward(ref, habit.id, habit.goldReward),
            category: habit.category.name,
          );
      final today = DateTime.now().effectiveDay;
      ref.read(weeklyGridProvider.notifier).markResultFromHabit(
          habit.id, today, SquareState.failed);
      // A notification action is a third way to change today's square,
      // alongside Grid and Today — see syncRoomToday's doc comment for why
      // every one of them has to call this.
      syncRoomToday(ref, habit.id, today);
      return;
    }
    // The quit check-in's "On Track" button affirms the day through the
    // exact same canonical path as Mark Done — a clean/within-limit day
    // IS this habit's completion (identical to tapping HabitCard's pill).
    if (actionId == NotificationService.actionMarkDone ||
        actionId == NotificationService.actionStayedClean) {
      // Mirrors DashboardScreen._completeHabit exactly: completeHabit grants
      // the one canonical reward for this habit-day, then — only if that
      // was a single-tap habit finishing just now — the Grid square is
      // mirrored to green too, same as tapping it from Today's Habits would.
      final dashState = ref.read(dashboardProvider);
      final todayHabits = ref
          .read(habitListProvider)
          .where((h) => h.isScheduledFor(DateTime.now().effectiveDay))
          .map((h) => (id: h.id, frequencyTarget: h.frequencyTarget));
      final justFinishedSingleTap =
          await ref.read(dashboardProvider.notifier).completeHabit(
                habitId: habit.id,
                // 2x while a linked room is live — see roomBoostedReward.
                xpReward: roomBoostedReward(ref, habit.id, habit.xpReward),
                goldReward:
                    roomBoostedReward(ref, habit.id, habit.goldReward),
                frequencyTarget: habit.frequencyTarget,
                allHabitsDoneAfter: willCompleteAllHabitsToday(
                  state: dashState,
                  todayHabits: todayHabits,
                  habitId: habit.id,
                  frequencyTarget: habit.frequencyTarget,
                ),
                category: habit.category.name,
                habitName: habit.localName(isAr),
              );
      if (justFinishedSingleTap) {
        final today = DateTime.now().effectiveDay;
        ref
            .read(weeklyGridProvider.notifier)
            .markCompleteFromHabit(habit.id, today);
        syncRoomToday(ref, habit.id, today);
      }
    }
  }

  /// Routes a notification's plain body tap to where its action lives: a
  /// daily reminder, streak-risk nudge, habit reminder or quit check-in all
  /// open the Grid — the app's home, where the habit's own row and squares
  /// are; a Matrix task reminder opens the Tasks tab. Anything unrecognized
  /// just opens the app, same as before.
  ///
  /// These used to open `/dashboard`, the standalone Today screen. That
  /// screen was reachable by no other route in the entire app — not a tab,
  /// not a link from anywhere — so tapping a reminder dropped someone onto a
  /// screen they had never seen and could not get back to on purpose. It's
  /// gone now; everything it did for a habit, the Grid row does.
  void _handleNotificationBodyTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final String route;
    if (payload == NotificationService.openTodayPayload ||
        _resolveHabit(payload) != null) {
      route = '/grid';
    } else if (ref.read(matrixProvider).tasks.any((t) => t.id == payload)) {
      route = '/matrix';
    } else {
      return;
    }
    final nav = _navKey.currentState;
    if (nav != null) {
      nav.pushNamed(route);
      return;
    }
    // Cold launch replay can arrive before MaterialApp has built its
    // navigator (NotificationService.onAction flushes the pending tap the
    // moment it's assigned, in initState) — defer one frame and try again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navKey.currentState?.pushNamed(route);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminderSub?.close();
    _habitRemindersSub?.close();
    _widgetSub?.close();
    _notificationSettingsSub?.close();
    _gridSub?.close();
    _authSub?.close();
    _roomRaceSub?.close();
    _matrixWidgetSub?.close();
    _linkSub?.cancel();
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
    // Same trick for the typeface: GameTextStyles pulls live from a static
    // field that `appFontProvider.notifier.set()` mutates in place, so this
    // watch is what turns that mutation into an actual rebuild.
    ref.watch(appFontProvider);

    return MaterialApp(
      title: 'Grow Daily',
      navigatorKey: _navKey,
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
      // Mounts the floating voice-note player once, above the Navigator
      // entirely, instead of inside GameNavBar (see
      // GlobalVoiceNotePlayerOverlay's doc comment for why that's the fix
      // for it going invisible behind modal sheets / pushed full-screen
      // routes like TaskDetailSheet and QuadrantExpandedScreen). `child` is
      // the fully-built Navigator — whatever route or modal is currently on
      // top of it — so stacking the overlay after it here guarantees the
      // player paints above literally everything else in the app.
      //
      // The transparent Material around that Stack is the app-wide safety
      // net for the "yellow double-underlined text" bug. MaterialApp hands
      // WidgetsApp a fallback `_errorTextStyle` (red 48px monospace,
      // double yellow underline) as the root DefaultTextStyle, and
      // WidgetsApp installs it *above* this builder — so anything rendered
      // without a Material/Scaffold above it inherits that decoration.
      // Explicit color/fontSize on a Text override the red and the size but
      // never the decoration, which is why the symptom shows up as bare
      // yellow lines under otherwise correct-looking text. It is not
      // debug-only either: MaterialApp passes _errorTextStyle
      // unconditionally, so it ships to users.
      //
      // Wrapping here fixes it once for everything below: the Navigator
      // (hence every route, dialog, and showGeneralDialog page) and the
      // overlay siblings stacked next to it. `MaterialType.transparency`
      // paints nothing — no color, no elevation, no clip — it only supplies
      // the DefaultTextStyle that was missing. Individual widgets that can
      // render outside a Material still wrap themselves too (see
      // VoiceNotePlayer, HabitMilestoneCelebration, the LongPressDraggable
      // feedbacks); this is the backstop, not a replacement for those.
      builder: (context, child) => Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            if (child != null) child,
            const GlobalVoiceNotePlayerOverlay(),
          ],
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const _LanguageGate(),
        '/heatmap': (_) => const MonthlyHeatmapScreen(),
        '/night-review': (_) => const NightReviewScreen(),
        '/grid-journal': (_) => const GridJournalScreen(),
        '/insights': (_) => const InsightsScreen(),
        '/premium': (_) => const PremiumScreen(),
        '/auth': (_) => const AuthScreen(),
        '/notification-settings': (_) => const NotificationSettingsScreen(),
        '/help-support': (_) => const HelpSupportScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/app-guide': (_) => const AppGuideScreen(),
      },
      onGenerateRoute: (settings) {
        // The bottom nav bar's tabs are peers, not a hierarchy, so
        // switching between them shouldn't play a "pushing a new screen"
        // transition. All three tab routes resolve to the same HomeShell
        // (a swipeable PageView) at different starting pages — see
        // HomeShell's doc comment — so an old pushReplacementNamed call
        // from anywhere in the app still lands exactly where it expects.
        final WidgetBuilder? builder = switch (settings.name) {
          // '/dashboard' deliberately absent: the standalone Today screen it
          // pointed at is gone (see _handleNotificationBodyTap). A stale
          // payload naming it now falls through to null below and simply
          // opens the app, which is the right outcome for a route that no
          // longer describes anywhere.
          '/grid' => (_) => const HomeShell(initialIndex: 0),
          '/profile' => (_) => const HomeShell(initialIndex: 1),
          '/matrix' => (_) => const HomeShell(initialIndex: 2),
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
    // A growdaily://join/CODE link (see main.dart's AppLinks wiring above)
    // may have arrived before this widget ever existed - cold start, or
    // while the language/auth/onboarding gates above this one were still
    // showing. This is the first point it's safe to act on it: every gate
    // is behind the user, and there's a real BuildContext to navigate from.
    // Consumed exactly once (reset to null immediately) so backing out of
    // Rooms afterward can never re-trigger it.
    ref.listen(pendingJoinCodeProvider, (previous, code) {
      if (code == null) return;
      ref.read(pendingJoinCodeProvider.notifier).state = null;
      final isGuest = ref.read(guestModeProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) return;
        // Guests can't join a room (Rooms needs an account - see
        // RoomsHubScreen's own guest gate); land them on that same
        // explanation screen instead of a Join sheet whose Join button
        // would just fail silently with nobody signed in.
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RoomsHubScreen()),
        );
        if (isGuest || !context.mounted) return;
        final joinedCode =
            await showJoinRoomSheet(context, ref, initialCode: code);
        if (joinedCode != null && context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => RoomDetailScreen(code: joinedCode)),
          );
        }
      });
    });

    // A tapped room-finish push notification (see
    // PushNotificationService.onOpenRoom, wired below in _MyAppState) may
    // similarly have arrived before this widget existed - same guard, same
    // "first safe point to navigate" reasoning as pendingJoinCodeProvider
    // right above, just straight to the room itself with no join sheet in
    // between (see pendingOpenRoomCodeProvider's own doc comment for why).
    ref.listen(pendingOpenRoomCodeProvider, (previous, code) {
      if (code == null) return;
      ref.read(pendingOpenRoomCodeProvider.notifier).state = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => RoomDetailScreen(code: code)));
      });
    });

    // App Guide is NOT auto-opened for a new user any more.
    //
    // Finishing onboarding used to push the whole App Guide screen on top of
    // the Grid half a second after arriving — so a first-time user reached
    // their new board and immediately had a four-lesson guide land over it,
    // with a dimming spotlight and the Get Started checklist waiting
    // underneath. Four teaching surfaces before a single tap, which is what
    // made starting the app feel like work.
    //
    // The guide keeps doing the job its own doc comment describes: a
    // replayable reference you open from Settings when you actually want it.
    // Discovery is handled by the "new" dot on that Settings row
    // (appGuideBadgeSeenProvider), which is a nudge rather than an
    // interruption. The first run itself is taught by one thing now — the
    // Get Started checklist on the Grid.

    // Announces any room that finished while the app was closed, once, on
    // the next open — see RoomFinaleAnnouncer for why this is state-driven
    // rather than a scheduled notification. Wrapped here rather than inside
    // HomeShell so it survives the crossfade below without remounting (and
    // re-asking) every time onboarding flips.
    return RoomFinaleAnnouncer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: seen
            ? const HomeShell(key: ValueKey('home'))
            : const OnboardingScreen(key: ValueKey('onboarding')),
      ),
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
              'Grow Daily',
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
