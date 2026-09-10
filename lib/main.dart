import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
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
import 'core/providers/nav_badges_setting_provider.dart';
import 'core/providers/nav_bar_hint_provider.dart';
import 'core/providers/nav_layout_provider.dart';
import 'core/providers/first_run_offer_provider.dart';
import 'core/providers/onboarding_provider.dart';
import 'core/providers/room_finale_seen_provider.dart';
import 'core/providers/weekly_recap_collapsed_provider.dart';
import 'core/providers/room_rows_view_provider.dart';
import 'core/providers/room_cards_collapse_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/bahrain_prayer_table.dart';
import 'core/services/analytics_service.dart';
import 'core/services/app_badge_service.dart';
import 'core/services/home_widget_service.dart';
import 'core/services/notification_action_queue.dart';
import 'core/services/notification_service.dart';
import 'core/services/push_notification_service.dart';
import 'shared/widgets/app_logo.dart';
import 'shared/widgets/overlay_notice.dart';
import 'core/services/purchase_service.dart';
import 'core/theme/game_theme.dart';
import 'core/services/local_store_service.dart';
import 'features/auth/notifiers/auth_notifier.dart';
import 'features/auth/notifiers/guest_reconnect_provider.dart';
import 'features/auth/widgets/guest_reconnect_prompt.dart';
import 'core/constants/deep_links.dart';
import 'features/auth/screens/auth_screen.dart';
import 'features/auth/screens/set_new_password_screen.dart';
import 'features/dashboard/notifiers/dashboard_notifier.dart';
import 'features/habits/catalog/habit_plans.dart'
    show reminderTimeProvider, activeCatalogProvider;
import 'features/habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitCatalog, IslamicHabitTemplate;
import 'features/habits/models/habit_cue.dart';
import 'features/insights/insights_screen.dart';
import 'features/habits/models/habit_model.dart'
    show GoalType, HabitFrequencyType, ReductionType;
import 'features/habits/notifiers/custom_habits_notifier.dart'
    show
        allHabitsEverProvider,
        canAddHabits,
        customHabitsProvider,
        habitListProvider,
        habitsStillLoadingProvider,
        pausedHabitsProvider;
import 'features/habits/notifiers/habit_resume_notifier.dart'
    show habitResumeScheduleProvider;
import 'features/grid/models/square_state.dart' show SquareState;
import 'features/grid/notifiers/square_audit.dart'
    show kSquareSourceNotification;
import 'features/grid/notifiers/weekly_grid_notifier.dart'
    show
        WeeklyGridState,
        isQuitAutoCleanEligible,
        weeklyGridProvider,
        willCompleteAllSquaresOn;
import 'features/grid/screens/grid_journal_screen.dart';
import 'features/grid/screens/monthly_heatmap_screen.dart';
import 'features/matrix/models/matrix_task.dart' show MatrixQuadrant;
import 'features/matrix/notifiers/matrix_notifier.dart'
    show MatrixState, isMatrixQuickAddLink, matrixProvider;
import 'features/matrix/widgets/voice_note_player.dart'
    show GlobalVoiceNotePlayerOverlay;
import 'features/night_review/notifiers/night_review_notifier.dart';
import 'features/night_review/screens/night_review_screen.dart';
import 'features/onboarding/screens/app_guide_screen.dart';
import 'features/tasbih/tasbih_screen.dart';
import 'features/onboarding/screens/first_run_offer_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/premium/notifiers/premium_notifier.dart';
import 'features/premium/screens/premium_screen.dart';
import 'features/profile/screens/help_support_screen.dart';
import 'features/profile/screens/profile_screen.dart' show SettingsScreen;
import 'features/settings/screens/nav_bar_settings_screen.dart';
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
import 'shared/widgets/app_snackbar.dart';

/// Today's scheduled habits vs. how many are already complete, plus the
/// per-habit rows the large widget and the app icon badge are both built
/// from — kept as one shape so those two can't quietly drift apart.
typedef _TodayHabitStats = ({
  int completed,
  int total,
  List<({String id, String name, bool done, int count, int perDay})> habits,
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
    // Crashlytics has no web implementation: the first call into it threw
    // and took the whole boot down before the first frame (the web build
    // sat on its splash forever, 2026-09-09). On the web, errors go to the
    // console and the app carries on.
    if (!kIsWeb) {
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } else {
      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('[web] uncaught: $error\n$stack');
        return true;
      };
      // A widget error in a release build paints a plain grey box and, on
      // the web, says nothing anywhere. Say it in the console, where the
      // only crash reporter the web has can read it.
      FlutterError.onError = (details) {
        debugPrint('[web] flutter error: ${details.exceptionAsString()}\n'
            '${details.stack}');
      };
      ErrorWidget.builder = (details) => Material(
            color: const Color(0xFFFEFAF0),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                details.exceptionAsString(),
                style: const TextStyle(color: Color(0xFFB00020), fontSize: 13),
              ),
            ),
          );
    }

    // The persisted language is read BEFORE the notification service starts,
    // so its one-time category registration (the iOS action buttons under a
    // reminder, «تمت» / «تأجيل ساعة») is made in that language, rather than
    // in English first and corrected a few awaits later. That gap used to be
    // harmless, because this function only ever ran with the app coming to
    // the foreground. A background notification action now launches this
    // same main() with the app closed, and iOS may suspend the process
    // before the correction runs, which left the NEXT reminder's buttons in
    // English on an Arabic account (seen live on 2026-09-06). applyLocale on
    // a fresh process is init() in the right language; see that method.
    final persistedLocale = await loadPersistedLocale();
    final persistedLanguageChosen = await loadPersistedLanguageChosen();
    // Nothing stored means a fresh install, and until now that meant English
    // no matter what the phone itself is set to: the app read the device
    // locale nowhere, so the language picker was the only code path in the
    // whole app that could produce Arabic. An Arabic phone now opens in
    // Arabic — the notification categories registered a few lines down
    // included, which is the part a later correction cannot fix on a process
    // iOS may suspend. See resolveInitialLocale for the matching rules.
    final bootLocale = persistedLocale ??
        resolveInitialLocale(
            WidgetsBinding.instance.platformDispatcher.locales);
    await NotificationService.instance
        .applyLocale(bootLocale.languageCode == 'ar');
    // The password-reset email is rendered by FIREBASE, from its own
    // templates, in whatever language this says. Left unset it falls back to
    // the console's default language, which is English, so someone who asked
    // for a reset from an Arabic screen got an English email with an English
    // sender name. Set at boot, before anything can request one, and kept in
    // step by the locale listener in _AuthGate.
    FirebaseAuth.instance.setLanguageCode(bootLocale.languageCode);
    // After NotificationService, which is what initialises the timezone
    // database this table converts through. Preloaded here so the one
    // synchronous prayer-time caller (AddHabitSheet's live cue preview)
    // can reach it — see BahrainPrayerTable.ensureLoaded.
    //
    // On the web the notification service steps aside entirely, so the
    // database it would have loaded is loaded here instead: the prayer table
    // asks for Asia/Bahrain by name and throws without it.
    if (kIsWeb) tz_data.initializeTimeZones();
    await BahrainPrayerTable.ensureLoaded();
    // Neither the home widget nor the store exists on the web; both plugins
    // are native-only and their first channel call would throw here.
    if (!kIsWeb) {
      await HomeWidgetService.instance.init();
      // Configures the RevenueCat SDK with the production API key (see
      // PurchaseService's doc comment). Safe to call unconditionally even if
      // it were ever unset — [PurchaseService.configure] never throws.
      await PurchaseService.instance.configure();
    }
    // Seed guestModeProvider from Hive so a returning guest with intact local
    // data lands back on their grid instead of being bounced to the auth
    // screen (the provider's own default is always `false` in memory).
    final persistedGuestMode = await loadPersistedGuestMode();
    // Delete guest data whose grace period has run out.
    //
    // Boot is the only place this can run: the sweep clears the daily box,
    // which a live guest session reads and writes continuously, so it has
    // to happen before any notifier has loaded from it. Passing the
    // just-read flag rather than letting the sweep look it up keeps the
    // veto honest at exactly this moment (see sweepDiscardedGuestData).
    await LocalStoreService.sweepDiscardedGuestData(
      now: DateTime.now(),
      inGuestMode: persistedGuestMode,
    );
    // The same language, for the headless engine that handles a notification
    // action tapped with the app closed (see HomeWidgetService.saveLocale).
    // bootLocale was resolved above, before the notification service
    // registered its buttons.
    await HomeWidgetService.instance
        .saveLocale(bootLocale.languageCode == 'ar');
    final persistedOnboardingSeen = await loadPersistedOnboardingSeen();
    final persistedGetStartedDismissed = await loadPersistedGetStartedDismissed();
    final persistedAppGuideRoomsSeen = await loadPersistedAppGuideRoomsSeen();
    final persistedRoomFinaleSeen = await loadPersistedRoomFinaleSeen();
    final persistedAppGuideBadgeSeen = await loadPersistedAppGuideBadgeSeen();
    final persistedRecapCollapsed = await loadPersistedWeeklyRecapCollapsed();
    final persistedRoomRowsCompact = await loadPersistedRoomRowsCompact();
    final persistedRoomTodayCollapsed = await loadPersistedRoomTodayCollapsed();
    final persistedRoomPlanCollapsed = await loadPersistedRoomPlanCollapsed();
    // Whether this device has already been asked "want to see how it works?".
    // See resolveFirstRunOfferAsked for why this derives from the onboarding
    // flag rather than defaulting, and for the test that covers it.
    final persistedFirstRunOfferAsked =
        await resolveFirstRunOfferAsked(onboardingSeen: persistedOnboardingSeen);
    // The entitlement this device last saw. Restored alongside every other
    // boot-time setting so a paying customer's first frame is already the
    // paid one, instead of flashing the free UI (locked history, muted
    // strips, an upgrade banner) until a RevenueCat round trip lands - or
    // staying free indefinitely when that round trip cannot complete at all.
    // See [loadPersistedPremium] for why a local cache is safe here and a
    // Firestore field is not.
    final persistedPremium = await loadPersistedPremium();
    final persistedPremiumUid = await loadPersistedPremiumUid();
    // Starts the new-install trial clock on the very first boot and reads
    // it back on every later one — see loadOrStartTrial. Loaded here so
    // premiumAccessProvider answers correctly from the first frame.
    final trialStart = await loadOrStartTrial();
    final persistedThemeMode = await loadPersistedThemeMode();
    // Also applies the preset's colors to GameColors immediately, so the
    // very first frame already renders in the right preset.
    final persistedThemePreset = await loadPersistedThemePreset();
    final persistedSavedColours = await loadPersistedSavedColours();
    // Also applies the font to GameTextStyles immediately, so the very first
    // frame already renders in the right typeface instead of flashing the
    // default and then swapping.
    final persistedFont = await loadPersistedFont();
    // The bottom bar's tabs, so the first frame draws the bar this account
    // arranged instead of three tabs that then jump to five.
    final persistedNavTabs = await loadPersistedNavTabs();
    final persistedNavBarHintSeen = await loadPersistedNavBarHintSeen();
    final persistedNavBadgesEnabled = await loadPersistedNavBadgesEnabled();
    runApp(ProviderScope(
      overrides: [
        guestModeProvider.overrideWith((ref) => persistedGuestMode),
        ...localeProviderOverrides(
          locale: bootLocale,
          chosen: persistedLanguageChosen,
        ),
        onboardingSeenProvider.overrideWith((ref) => persistedOnboardingSeen),
        getStartedDismissedProvider.overrideWith((ref) => persistedGetStartedDismissed),
        appGuideRoomsSeenProvider.overrideWith((ref) => persistedAppGuideRoomsSeen),
        roomFinaleSeenProvider.overrideWith((ref) => persistedRoomFinaleSeen),
        appGuideBadgeSeenProvider.overrideWith((ref) => persistedAppGuideBadgeSeen),
        weeklyRecapCollapsedProvider.overrideWith((ref) => persistedRecapCollapsed),
        roomRowsCompactProvider.overrideWith((ref) => persistedRoomRowsCompact),
        roomTodayCollapsedProvider.overrideWith((ref) => persistedRoomTodayCollapsed),
        roomPlanCollapsedProvider.overrideWith((ref) => persistedRoomPlanCollapsed),
        firstRunOfferAskedProvider.overrideWith((ref) => persistedFirstRunOfferAsked),
        premiumProvider.overrideWith((ref) => PremiumNotifier(
              initial: persistedPremium,
              cachedUid: persistedPremiumUid,
            )),
        trialStartProvider.overrideWithValue(trialStart),
        if (persistedThemeMode != null)
          themeModeProvider.overrideWith((ref) => ThemeModeNotifier(persistedThemeMode)),
        if (persistedThemePreset != null)
          themePresetProvider.overrideWith((ref) => ThemePresetNotifier(persistedThemePreset)),
          savedThemeColoursProvider.overrideWith(
              (ref) => SavedThemeColoursNotifier(persistedSavedColours)),
        if (persistedFont != null)
          appFontProvider.overrideWith((ref) => AppFontNotifier(persistedFont)),
        if (persistedNavTabs != null)
          navLayoutProvider
              .overrideWith((ref) => NavLayoutNotifier(persistedNavTabs)),
        navBarHintSeenProvider.overrideWith((ref) => persistedNavBarHintSeen),
        navBadgesEnabledProvider.overrideWith(
            (ref) => NavBadgesSettingNotifier(persistedNavBadgesEnabled)),
      ],
      child: const GrowDailyApp(),
    ));
  }, (error, stack) {
    // Crashlytics has no web plugin: forwarding to it on the web threw a
    // MissingPluginException out of the error handler itself, which both
    // hid the original error and took the app down. The console is the
    // crash reporter there.
    if (kIsWeb) {
      debugPrint('[web] zone error: $error\n$stack');
      return;
    }
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
  ProviderSubscription<Locale>? _localeSub;
  ProviderSubscription<List<IslamicHabitTemplate>>? _habitRemindersSub;
  ProviderSubscription<DashboardState>? _widgetSub;
  ProviderSubscription<NotificationSettings>? _notificationSettingsSub;
  ProviderSubscription<WeeklyGridState>? _gridSub;

  /// Two subscriptions, because the streak gap can only be judged once the
  /// dashboard AND the habit list have both settled and either may land
  /// second. See _watchForDeferredStreakGap.
  final List<ProviderSubscription<Object?>> _streakGapSubs = [];
  ProviderSubscription<AsyncValue<User?>>? _authSub;
  ProviderSubscription<String?>? _passwordDroppedSub;
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
    _watchForDeferredStreakGap();
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
    // A room push that lands while the app is OPEN is shown inside the app,
    // as a tappable notice over whatever screen is up, instead of a system
    // banner on top of the app (Aziz, 2026-09-08: a banner about the app
    // you are already in is noise; a small card that opens the room is
    // useful). Same indirection as onOpenRoom: the service has no context,
    // this has the navigator. Falls back to the banner before the first
    // frame.
    PushNotificationService.instance.onForegroundRoomPush =
        (title, body, code) {
      final ctx = _navKey.currentContext;
      if (ctx == null) {
        NotificationService.instance
            .showForegroundRoomPush(title: title, body: body);
        return;
      }
      showOverlayNotice(
        ctx,
        '$title\n$body',
        icon: Icons.groups_rounded,
        onTap: code == null
            ? null
            : () =>
                ref.read(pendingOpenRoomCodeProvider.notifier).state = code,
      );
    };
    // Start listening NOW, with both callbacks above already assigned.
    //
    // This used to happen inside PushNotificationService
    // .requestPermissionAndInit, whose only call site is RoomsHubScreen, so
    // nothing was listening until the person opened the Rooms tab — and a
    // room-finish push that arrived before they ever did was drawn by the
    // system (the Cloud Function sends a `notification` block), shown in the
    // tray, tapped, and handled by nobody. Especially visible on Android,
    // where the FCM SDK always draws it.
    //
    // Attaching a stream listener needs no permission and no account, so it
    // belongs at startup; only the PROMPT still waits for Rooms to mean
    // something. Order matters: onOpenRoom above must already be set, or a
    // tap that cold-launched the app resolves against null and is lost.
    unawaited(PushNotificationService.instance.attachListeners());

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
    // A Google or Apple sign-in that cost this account its password, which
    // Firebase does silently to any password account whose address was never
    // verified. AuthNotifier._repairDroppedPassword is what notices; this is
    // what puts the offer on screen. Pushed over whatever the sign-in landed
    // on, for the same reason the reset screen is: one job and a way out.
    _passwordDroppedSub =
        ref.listenManual<String?>(passwordDroppedProvider, (_, email) {
      if (email == null || email.isEmpty) return;
      // Consumed here, so a rebuild cannot show it twice.
      ref.read(passwordDroppedProvider.notifier).state = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = _navKey.currentState;
        if (!mounted || nav == null) return;
        nav.push(MaterialPageRoute<void>(
          builder: (_) => SetNewPasswordScreen.addToAccount(email: email),
        ));
      });
    });
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
      // No Crashlytics on the web; this was the call that took the web build
      // down on its first frame (MissingPluginException, Crashlytics#
      // setUserIdentifier) once the boot-time guards were in place.
      if (!kIsWeb) FirebaseCrashlytics.instance.setUserIdentifier(uid ?? '');
      if (uid != null) {
        ref.read(themeModeProvider.notifier).pullFromAccount(uid);
        ref.read(themePresetProvider.notifier).pullFromAccount(uid);
        ref.read(appFontProvider.notifier).pullFromAccount(uid);
        ref.read(reminderTimeProvider.notifier).pullFromAccount(uid);
        ref.read(notificationSettingsProvider.notifier).pullFromAccount(uid);
        ref.read(navLayoutProvider.notifier).pullFromAccount(uid);
        ref.read(navBadgesEnabledProvider.notifier).pullFromAccount(uid);
        _hydrateLocaleFromAccount(uid);
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
        // Bind the restored entitlement to the account that actually signed
        // in, well before the network call below can answer. If this
        // device's cache belonged to someone else, this is what drops it,
        // rather than showing one person's subscription to the next person
        // who signs in.
        //
        // Deferred by a microtask, and it has to be. This listener is
        // registered with fireImmediately, so on a cold start it runs inside
        // initState while the root ProviderScope above is still MOUNTING.
        // Reading premiumProvider there is what creates the notifier, and
        // creating a provider during the scope's own first build marks that
        // scope dirty mid-build: '!_dirty' fails and the app opens on a red
        // screen instead of the grid. Every other premium touch in this file
        // is already async for the same reason (see the logIn().then below),
        // which is why this was the only one that tripped it.
        //
        // A microtask still lands orders of magnitude before any network
        // round trip, so nothing about the "drop a stale entitlement fast"
        // guarantee is weakened.
        Future.microtask(() {
          if (!mounted) return;
          ref.read(premiumProvider.notifier).bindAccount(uid);
        });
        PurchaseService.instance.logIn(uid).then((info) {
          if (info != null && mounted) {
            ref.read(premiumProvider.notifier).applyCustomerInfo(info);
          }
        });
      } else if (next.hasValue && previous?.valueOrNull != null) {
        // ── Only a RESOLVED sign-out counts ───────────────────────────
        //
        // `uid == null` is two different states wearing one face:
        // genuinely signed out (AsyncData(null)) and "Firebase Auth has
        // not answered yet" (AsyncLoading, which is what fireImmediately
        // hands us on EVERY cold start). An auth network blip adds a
        // third, AsyncError. All three have a null asData.
        //
        // Without this guard the branch below ran at every launch, before
        // auth had resolved, and detachAccount() wiped the entitlement
        // restored from disk moments earlier along with its cache. That
        // defeated the whole point of caching it: the app was right again
        // only once RevenueCat answered over the network, which is exactly
        // the round trip the cache exists to remove. Offline, it never
        // came back at all.
        //
        // hasValue alone is NOT the whole test, though: AsyncData(null) is
        // also the RESTING state of every guest launch — Firebase's first
        // emission on a signed-out device is null. That ran this branch on
        // every guest cold start, re-wiping the guest's own persisted
        // entitlement (guests never bindAccount, so their premium lives
        // under uid == null) and calling Purchases.logOut() for an
        // anonymous user each launch. Hence the `previous` check: only a
        // transition FROM a real signed-in user is a sign-out. Riverpod's
        // AsyncLoading preserves the prior value via copyWithPrevious, so
        // a sign-out landing mid-refresh still qualifies; a guest launch's
        // previous is loading-with-nothing-behind-it and is skipped.
        ref.read(themeModeProvider.notifier).detachAccount();
        ref.read(themePresetProvider.notifier).detachAccount();
        ref.read(savedThemeColoursProvider.notifier).detachAccount();
        ref.read(appFontProvider.notifier).detachAccount();
        ref.read(reminderTimeProvider.notifier).detachAccount();
        ref.read(notificationSettingsProvider.notifier).detachAccount();
        ref.read(navLayoutProvider.notifier).detachAccount();
        ref.read(navBadgesEnabledProvider.notifier).detachAccount();
        PurchaseService.instance.logOut();
        // Clears the cached entitlement with it. Without this the signed-out
        // device would keep answering "Premium" from disk on the next cold
        // start, for an account that is no longer signed in. Deferred for
        // the same mounting reason as bindAccount above.
        Future.microtask(() {
          if (!mounted) return;
          ref.read(premiumProvider.notifier).detachAccount();
          // A registration that rolled back (register()'s profile-doc write
          // failed and the auth user was deleted) resolves as this same
          // signed-out transition, with the auth screen's pre-await arming
          // of justRegisteredProvider still standing — its own disarm sits
          // behind an `if (!mounted)` that the rollback's dispose already
          // tripped. Left armed, the NEXT sign-in that has any legitimate
          // offer would get the post-registration modal it never earned.
          // Same microtask deferral as the premium calls above, and for the
          // same red-screen reason.
          ref.read(justRegisteredProvider.notifier).state = false;
        });
        // Drops this device's own token doc so a shared/reset device stops
        // being a room-finish push target for the account that just left it.
        PushNotificationService.instance.clearForSignOut();
      }
    }, fireImmediately: true);

    // Wire the notification taps that reach the LIVE app to the exact same
    // completion path the UI itself uses: a body tap, and on Android the
    // Mark Done / Snooze buttons (which open the app there). On iOS the
    // buttons are background actions handled in a headless engine and
    // queued for _processPendingNotificationActions instead; see
    // NotificationService's "Actionable notifications" doc comment.
    // Assigning this also flushes any tap that already arrived (e.g. the
    // app was cold-launched by tapping an action); see NotificationService
    // .onAction.
    NotificationService.instance.onAction = _handleNotificationAction;

    // Catch anything the widget queued between the last time the app was
    // open and this cold start (see _processPendingWidgetCompletions), and
    // any notification action tapped while the app was closed (see
    // _processPendingNotificationActions).
    _processPendingWidgetCompletions();
    _processPendingWidgetTaskCompletions();
    _processPendingNotificationActions();

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

    // Language change re-bakes every scheduled notification's copy. The
    // title/body are rendered AT SCHEDULE TIME from the isAr flag, so
    // without this a mid-session switch left the daily reminder, habit
    // reminders, nudges and check-ins in the previous language until some
    // unrelated trigger or the next resume happened to recompute. No
    // fireImmediately: the subscriptions above already cover cold start.
    _localeSub = ref.listenManual(
      localeProvider,
      (previous, next) {
        // The copy below is re-baked by the recompute; the iOS action
        // buttons are not, because they live on a category registered once
        // per process rather than on each notification.
        NotificationService.instance
            .applyLocale(next.languageCode == 'ar')
            .ignore();
        // The background action handler has no locale provider to read, so
        // the language it snoozes in is whatever this last wrote.
        HomeWidgetService.instance
            .saveLocale(next.languageCode == 'ar')
            .ignore();
        // Same reason as the boot call in main(): this is the language
        // Firebase's own emails come out in, and someone who switches to
        // Arabic and then asks for a reset should not get an English one.
        FirebaseAuth.instance.setLanguageCode(next.languageCode);
        _recomputeNotifications();
      },
    );

    // Resolve every habit's cue (fixed clock time or a prayer) into a real
    // reminder — see NotificationService.scheduleSmartReminders. Re-runs on
    // cold start and any time the habit list changes (added/edited/removed,
    // cue changed).
    _habitRemindersSub = ref.listenManual(
      habitListProvider,
      (previous, next) {
        _recomputeNotifications();
        // Booked returns are checked from here for the same reason the
        // quit-clean below is: this listener is the one that fires once the
        // habit list has actually loaded, which auto-resume cannot run
        // without.
        _maybeAutoResumeDueHabits().ignore();
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
      // Done TODAY, not "done and still in state": the board keeps a
      // completed task visible until the midnight archive sweep, and that
      // sweep only runs on load — an app sitting open past midnight still
      // holds yesterday's dones, which must not fill today's ring. A null
      // completedAt (legacy docs) counts as today rather than vanishing.
      final doneToday = next.tasks
          .where((t) =>
              t.isDone &&
              (t.completedAt == null || t.completedAt!.isSameDayAs(now)))
          .length;
      HomeWidgetService.instance.updateMatrixWidgetData(
        doneTodayCount: doneToday,
        [
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

  // Once-per-app-day guard for the "board is full, could not auto-resume"
  // snackbar. The blocked branch keeps the habit paused and its booking armed
  // and returns, so without this it re-shows on every habit-list settle. Only
  // the message is guarded — resume is still re-attempted each pass, so the
  // moment a slot frees up the habit comes back.
  String? _lastAutoResumeBlockedKey;

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
  /// Brings back any paused habit whose booked return has arrived.
  ///
  /// Runs from the same listeners as the quit-day clean below, so it fires
  /// on cold start and every time the habit list settles, which together
  /// cover "opened the app" and "the day rolled over while it was open".
  ///
  /// Two preconditions matter and neither is optional:
  ///
  ///  * The habit list must have loaded. Resuming against an empty list
  ///    would read every booking as a habit that no longer exists and prune
  ///    it, quietly cancelling every return date on the device.
  ///  * The free tier's habit cap still applies. A booking made three weeks
  ///    ago cannot know how full the board is today, so this asks the same
  ///    question GridScreen._resumeHabit asks and, when the answer is no,
  ///    leaves the habit paused and its booking armed rather than either
  ///    breaking the cap or failing silently.
  Future<void> _maybeAutoResumeDueHabits() async {
    if (ref.read(habitsStillLoadingProvider)) return;
    final schedule = ref.read(habitResumeScheduleProvider.notifier);
    // The bookings are read from storage asynchronously, so asking before
    // that lands would see an empty schedule and resume nothing.
    await schedule.ready;
    if (!mounted) return;
    final due = schedule.dueBy(DateTime.now());
    if (due.isEmpty) return;

    // Localizations come from localeProvider, not S.of(context): this State's
    // own context sits ABOVE the MaterialApp it builds, so it has no
    // Localizations ancestor and S.of(context) throws here (see
    // _messengerContext). Reading the locale directly needs no context at all.
    final isAr = ref.read(localeProvider).languageCode == 'ar';
    final paused = {for (final h in ref.read(pausedHabitsProvider)) h.id: h};
    final activeIds = {for (final h in ref.read(habitListProvider)) h.id};
    for (final id in due) {
      // Already back, by hand or on another device: the booking is spent.
      if (activeIds.contains(id)) {
        schedule.schedule(id, null).ignore();
        continue;
      }
      final habit = paused[id];
      if (habit == null) continue; // pruned below, not here
      if (!canAddHabits(ref)) {
        // Board is full: leave it paused and armed, but say so at most once a
        // day rather than on every settle (the return below keeps re-entering
        // this branch until a slot frees).
        final blockedKey = DateTime.now().effectiveDay.toDateKey();
        if (_lastAutoResumeBlockedKey != blockedKey) {
          _lastAutoResumeBlockedKey = blockedKey;
          _showAutoResumeBlocked(habit.localName(isAr));
        }
        return;
      }
      if (IslamicHabitCatalog.findById(id) != null) {
        ref.read(activeCatalogProvider.notifier).toggle(id);
      } else {
        ref.read(customHabitsProvider.notifier).unarchive(id);
      }
      schedule.schedule(id, null).ignore();
      _showAutoResumed(habit.localName(isAr));
    }
    // Bookings whose habit is neither active nor paused no longer refer to
    // anything on this account.
    schedule.pruneMissing({...activeIds, ...paused.keys}).ignore();
  }

  /// A context that actually sits UNDER the MaterialApp this State builds — the
  /// only place a snackbar can be shown from these lifecycle callbacks. This
  /// State's `context` is above the MaterialApp its build() returns, so it has
  /// no ScaffoldMessenger (or Localizations) ancestor and ScaffoldMessenger.of
  /// on it throws. The navigator key resolves to the Navigator's context, which
  /// is below both. Null only before the first frame, when there is nothing to
  /// show anyway.
  BuildContext? get _messengerContext => _navKey.currentContext;

  void _showAutoResumed(String name) {
    final ctx = _messengerContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showOne(
      SnackBar(
        content:
            Text(S(ref.read(localeProvider)).autoResumedConfirmation(name)),
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.down,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  void _showAutoResumeBlocked(String name) {
    final ctx = _messengerContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showOne(
      SnackBar(
        content:
            Text(S(ref.read(localeProvider)).autoResumeBlockedByLimit(name)),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.down,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  void _maybeAutoCleanQuitYesterday() {
    final todayKey = DateTime.now().effectiveDay.toDateKey();
    if (_lastQuitAutoCleanKey == todayKey) return;
    // While auth is still resolving, every provider read below is the
    // transient GUEST instance, whose Hive load settles within microtasks —
    // before Firebase Auth's first emission. Passing the loading checks
    // against that (typically empty) store used to burn the once-per-day
    // key on account-less data, so for signed-in users the real pass never
    // ran on any cold start. Wait for auth to settle; the listeners that
    // call this re-fire as the real account's stores load.
    if (ref.read(authStateProvider).isLoading) return;
    final dash = ref.read(dashboardProvider);
    if (dash.isLoading || ref.read(habitsStillLoadingProvider)) return;
    _lastQuitAutoCleanKey = todayKey;

    final yesterday =
        DateTime.now().effectiveDay.subtract(const Duration(days: 1));
    final ids = [
      for (final h in ref.read(habitListProvider))
        if (isQuitAutoCleanEligible(
          isQuit: h.goalType == GoalType.quit,
          isSingleTap: h.effectiveDailyTarget == 1,
          wasScheduled: h.isScheduledFor(yesterday),
          hasEverCompleted: dash.habitLastCompletedDate.containsKey(h.id),
        ))
          h.id,
    ];
    ref
        .read(weeklyGridProvider.notifier)
        .autoCleanQuitDay(ids, yesterday)
        .then((_) {
      // Rooms grade off the stored squares, so a day marked kept here reached
      // a room only on its next full resync; until then the room strip showed
      // the day empty while the Grid showed it green.
      if (ids.isNotEmpty && mounted) _resyncMyRooms();
    }).ignore();
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

    final dash = ref.read(dashboardProvider);
    final today = DateTime.now().effectiveDay;
    final todayHabits = ref
        .read(habitListProvider)
        .where((h) => h.isScheduledFor(today))
        .toList();

    // Reminders are scheduled from every habit due in the WEEK AHEAD, not
    // just today's.
    //
    // Today-only was half of the wrong-day bug. A habit set to specific
    // weekdays kept its reminders only while today happened to be one of
    // them: on any other day it fell out of this list, the stale sweep
    // cancelled its slots, and nothing re-armed the next real occurrence
    // until the app was opened on that morning. Paired with a fire time
    // that rolled a single day forward regardless of the schedule, the
    // result was a reminder that fired on days the habit did not run and
    // could go missing on days it did. The scheduler now places each habit
    // on its own next scheduled occurrence (see
    // HabitReminderInput.scheduledWeekdays), so it needs to see the habits
    // that are not due today too. Seven days is the full weekday cycle, so
    // this catches every habit that has any upcoming occurrence at all,
    // while still dropping ones that are archived or not yet born.
    final upcomingHabits = ref.read(habitListProvider).where((h) {
      for (var i = 0; i < 7; i++) {
        if (h.isScheduledFor(today.add(Duration(days: i)))) return true;
      }
      return false;
    }).toList();

    final reminders = <HabitReminderInput>[];
    // Read once for this pass: the quit check-ins and the weekly digest
    // below read it too, and a flexible weekly quota's reminder wording
    // needs this week's squares. Reading it fresh here can transiently
    // miss data while the grid is still loading or showing a past week —
    // the _gridSub recompute corrects that the moment the real data lands.
    final grid = ref.read(weeklyGridProvider);
    // Counts only what is actually owed TODAY — it feeds the evening
    // streak-risk nudge, which is a question about today's board.
    var pendingCount = 0;
    for (final habit in todayHabits) {
      if (!dash.isCompleted(habit.id, habit.effectiveDailyTarget)) {
        pendingCount++;
      }
    }
    for (final habit in upcomingHabits) {
      final scheduledToday = habit.isScheduledFor(today);
      final isFlexibleQuota =
          habit.frequencyType == HabitFrequencyType.weekly &&
              habit.scheduledWeekdays.isEmpty;
      final cue = HabitCue.fromStoredValue(habit.cueAfter);
      // Days since this habit was last logged, or null if it never has
      // been. Read off the same map habitStreak reads, so "never done" and
      // "streak lapsed" can't disagree about one habit. It is wording
      // input only: see HabitReminderInput.lastDoneDaysAgo.
      final lastDoneKey = dash.habitLastCompletedDate[habit.id];
      final lastDone =
          lastDoneKey == null ? null : DateTime.tryParse(lastDoneKey);
      // The cue's own shifts when it has them (multi-time), the habit's
      // single field when it does not. Never both: see HabitCue.offsetsAreOwn.
      final baseTimes = cue.clockTimes;
      final baseOffsets = cue.offsetsAreOwn
          ? cue.clockOffsets
          : [habit.reminderOffsetMinutes];
      // A stacked reminder is the SAME occurrence fired at several shifts, so
      // it is expanded into the (time, offset) pairs the scheduler already
      // speaks in — one pair per slot, index-aligned, exactly the shape a
      // multi-time habit produces. That keeps resolveClockSlots the single
      // unchanged piece of clock arithmetic, and slot 0 the pair it has
      // always been.
      final expanded = NotificationService.expandStackedSlots(
        times: baseTimes,
        offsets: baseOffsets,
        primaryOffset: habit.reminderOffsetMinutes,
        extraOffsets: habit.extraReminderOffsets,
      );
      reminders.add((
        id: habit.id,
        name: habit.localName(isAr),
        clockTimes: expanded.times,
        clockOffsets: expanded.offsets,
        // How many of those slots belong to ONE occurrence — see
        // HabitReminderInput.remindersPerOccurrence. Logging a habit once has
        // to stand down its whole stack, not just the earliest entry of it.
        remindersPerOccurrence: expanded.perOccurrence,
        extraReminderOffsets: habit.extraReminderOffsets,
        prayerKey: cue.prayerKey,
        // On the habit's own days: a Wed/Sat habit done Wednesday still has
        // its streak on Saturday. See DashboardState.habitStreak.
        streak: dash.habitStreak(
          habit.id,
          scheduledWeekdays: habit.scheduledWeekdays.toSet(),
        ),
        // The raw count, not the done bool: a habit counted twice a day with
        // one logged is neither "done" nor "untouched", and the scheduler
        // needs the number to know how many of today's reminders to stand
        // down. pendingCount above is computed separately, off today's board
        // only, and is unaffected.
        //
        // Zero for a habit that is not due today: the count answers "how
        // many of TODAY's target are logged", and today's answer must not
        // stand down a reminder belonging to a later day.
        completedCount: scheduledToday ? (dash.completions[habit.id] ?? 0) : 0,
        dailyTarget: habit.effectiveDailyTarget,
        // What days this habit actually runs, so a fire time that rolls
        // past its own clock time lands on the next one it is due — see
        // HabitReminderInput.scheduledWeekdays.
        scheduledWeekdays: habit.scheduledWeekdays.toSet(),
        reminderOffsetMinutes: habit.reminderOffsetMinutes,
        ignoreQuietHours: habit.ignoreQuietHours,
        alarm: habit.alarm,
        isQuit: habit.goalType == GoalType.quit,
        isLimit: habit.reductionType == ReductionType.limit,
        // Only a prayer gets named in the reminder's own text ("باقي ٤٥
        // دقيقة على المغرب"). A clock cue's anchor is a clock, and the
        // notification is already stamped with one.
        anchorLabel: cue.prayerKey != null ? cue.labelForLocale(isAr) : null,
        lastDoneDaysAgo: lastDone == null
            ? null
            : today
                .difference(
                    DateTime(lastDone.year, lastDone.month, lastDone.day))
                .inDays,
        // Only a habit that really runs a timer can state a length; a
        // hasTimer habit with no duration stored has nothing true to say.
        timerSeconds: habit.hasTimer ? habit.timerDurationSeconds : null,
        // A flexible weekly quota ("N times a week, any days") is judged by
        // its week, and the week's squares are the Grid's. Null target for
        // every other cadence; null squares while the Grid is not showing
        // the current week, in which case the wording makes no claim about
        // the week until the next recompute. Same predicate the Grid row
        // uses (grid_screen_table's isFlexibleQuota): "Specific Days" is
        // also stored as weekly, told apart only by scheduledWeekdays.
        weekTarget: isFlexibleQuota ? habit.frequencyTarget : null,
        weekDoneDays:
            !isFlexibleQuota || !grid.isCurrentWeek || grid.isLoading
                ? null
                : {
                    for (var i = 0; i < grid.days.length; i++)
                      if (grid.squareFor(habit.id, grid.days[i]).isGreen) i,
                  },
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
    // The daily reminder is worded from today's board, so it is scheduled
    // here, once the counts exist, rather than at the top of this method.
    final reminderTime = ref.read(reminderTimeProvider);
    if (reminderTime != null && settings.masterEnabled) {
      NotificationService.instance.scheduleDailyReminder(
        hour: reminderTime.hour,
        minute: reminderTime.minute,
        isAr: isAr,
        done: todayHabits.length - pendingCount,
        total: todayHabits.length,
        streak: dash.streak,
      );
    } else {
      NotificationService.instance.cancelDailyReminder();
    }

    NotificationService.instance.scheduleStreakRiskCheck(
      settings: settings,
      streak: dash.streak,
      doneHabitCount: todayHabits.length - pendingCount,
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
    // red). Same single-tap-only rule as HabitCard's slip link. The grid
    // read above can transiently miss a slip while the grid is still
    // loading or showing a past week — the _gridSub recompute corrects
    // that the moment the real data lands.
    final quitCheckIns = <QuitCheckInInput>[
      for (final habit in todayHabits)
        if (habit.goalType == GoalType.quit && habit.effectiveDailyTarget == 1)
          (
            id: habit.id,
            name: habit.localName(isAr),
            isLimit: habit.reductionType == ReductionType.limit,
            isResolvedToday:
                dash.isCompleted(habit.id, habit.effectiveDailyTarget) ||
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
      _processPendingNotificationActions();
      ref.read(dashboardProvider.notifier).refresh();
      ref.read(premiumProvider.notifier).refresh();
      // A booked return can fall due while the app sits warm in the switcher
      // (iOS keeps apps resumable for days) or after the day rolls over with
      // the app open. Neither re-fires the habit-list listener that is auto-
      // resume's only other trigger — habitListProvider has no time-dependent
      // input — so without this the habit silently stays paused past its date
      // until the next cold start. Cheap and self-guarding: it no-ops unless a
      // booking is actually due.
      _maybeAutoResumeDueHabits().ignore();
      // The Grid's visible week is otherwise only computed once, at
      // construction — leaving the app open/backgrounded across the day
      // cutoff (see DateTimeGameExt.effectiveDay), and especially across a
      // Saturday grid-week boundary, would keep showing the old week until
      // a full restart without this.
      ref.read(weeklyGridProvider.notifier).refresh();
      // Reminders are armed a few occurrences ahead, not indefinitely (see
      // NotificationService's class doc comment) — re-running this on every
      // resume, not just on explicit state changes, is what refills the
      // window and keeps reminders self-healing for a day-cutoff rollover
      // or a yesterday-completed habit that happened while the app was
      // closed.
      //
      // The timezone refresh runs FIRST: tz.local is otherwise resolved
      // once per process, so a device that travelled while the app stayed
      // alive kept rescheduling every reminder on the old zone's wall
      // clock. Fire-and-forget like the sync calls below; a recompute
      // triggered by anything else meanwhile just uses the fresher zone.
      unawaited(NotificationService.instance
          .refreshTimezone()
          .then((_) => _recomputeNotifications()));
      // Same self-healing idea for the ambient facts the room-finish push
      // Cloud Function reads (see _syncAmbientAccountFacts) — a trip across
      // time zones mid-session should be reflected by the next resume, not
      // require a fresh sign-in.
      final uid = ref.read(authStateProvider).asData?.value?.uid;
      if (uid != null) {
        // Not while a hydration read is in flight — see the flag's doc.
        if (!_localeHydrationInFlight) _syncAmbientAccountFacts(uid);
        // Same self-healing idea as _syncAmbientAccountFacts right above -
        // catches a token that rotated while this device was backgrounded
        // (registerForUser's onTokenRefresh listener already catches one
        // that rotates while the app is actually running).
        PushNotificationService.instance.registerForUser(uid);
        _resyncMyRooms();
      }
      // A phone left open overnight crosses the app-day boundary without any
      // provider noticing: NightReviewNotifier loads once in its constructor
      // and is not autoDispose, so yesterday's answers stayed in memory and
      // its `saved` flag suppressed tonight's prompt entirely. Outside the
      // uid branch on purpose — a guest rolls over at midnight exactly like
      // a signed-in account does.
      ref.read(nightReviewProvider.notifier).refreshIfDayChanged();
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
    // Waits for the room streams inside the controller. Reading their
    // valueOrNull here skipped every room on a cold start, when none had
    // arrived yet, so the "resume" resync mostly did nothing.
    ref.read(roomsControllerProvider).resyncAllMyRooms().ignore();
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
  /// Restores this account's language onto a device that hasn't chosen one,
  /// then syncs the ambient facts.
  ///
  /// The two are sequenced rather than fired side by side, and that ordering
  /// is the whole trick: [_syncAmbientAccountFacts] WRITES `users/{uid}.locale`
  /// from whatever this device is currently showing. Run them concurrently and
  /// a fresh install on an English phone overwrites an Arabic account's stored
  /// language with `en` before the read that was meant to restore it ever
  /// lands, so the account quietly forgets its own language instead of
  /// teaching it to the new device.
  ///
  /// A device that HAS chosen skips the read entirely and syncs straight away
  /// - the person's own pick is not something an old value on the server gets
  /// to overrule, and it's the pick that should be teaching the account.
  void _hydrateLocaleFromAccount(String uid) {
    if (ref.read(languageChosenProvider)) {
      _syncAmbientAccountFacts(uid);
      return;
    }
    _localeHydrationInFlight = true;
    unawaited(fetchAccountLocale(uid).then((accountLocale) async {
      // A network round trip, so unlike the synchronous pullFromAccount
      // calls at the call site this really can land after teardown.
      if (!mounted) return;
      final adopt = localeToAdoptFromAccount(
        deviceHasChosen: ref.read(languageChosenProvider),
        current: ref.read(localeProvider),
        account: accountLocale,
      );
      if (adopt != null) {
        await adoptAccountLocale(ref, adopt);
        if (!mounted) return;
      }
      _syncAmbientAccountFacts(uid);
    }).whenComplete(() => _localeHydrationInFlight = false));
  }

  /// True from the moment [_hydrateLocaleFromAccount] starts its read until
  /// it has finished writing back, and read only by the resume handler.
  ///
  /// The resume handler calls [_syncAmbientAccountFacts] on every foreground,
  /// which WRITES `users/{uid}.locale` from whatever this device currently
  /// shows. Foreground the app during hydration's network read and that write
  /// lands first, so the read either returns the value it just clobbered or is
  /// overtaken by it — either way the account forgets the language hydration
  /// existed to restore, permanently, because nothing reads it again once the
  /// device has synced its own.
  ///
  /// Skipping that one sync costs nothing: hydration ends by calling
  /// [_syncAmbientAccountFacts] itself, and it writes the timezone offset the
  /// resume path wanted refreshed in the same call.
  bool _localeHydrationInFlight = false;

  void _syncAmbientAccountFacts(String uid) {
    final locale = ref.read(localeProvider).languageCode;
    final tzOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    unawaited(FirebaseFirestore.instance.collection('users').doc(uid).set({
      'locale': locale,
      'tzOffsetMinutes': tzOffsetMinutes,
    }, SetOptions(merge: true)).catchError((_) {}));
  }

  /// Judges any streak gap the dashboard loader deferred, as soon as both
  /// the dashboard and the habit list have settled.
  ///
  /// The loader cannot make this call itself: deciding whether a gap was
  /// MISSED days or merely days with nothing scheduled needs the habit
  /// schedule, and the notifier is constructed before any of it exists.
  /// See DashboardState.pendingStreakGapFrom.
  ///
  /// allHabitsEverProvider rather than the active list, so a habit paused
  /// or removed since the gap still counts for the days it really demanded.
  void _watchForDeferredStreakGap() {
    void tryResolve() {
      if (ref.read(habitsStillLoadingProvider)) return;
      if (ref.read(dashboardProvider).pendingStreakGapFrom == null) return;
      ref
          .read(dashboardProvider.notifier)
          .resolveStreakGap(ref.read(allHabitsEverProvider));
    }

    _streakGapSubs.add(
      ref.listenManual(dashboardProvider, (_, __) => tryResolve()),
    );
    _streakGapSubs.add(
      ref.listenManual(habitsStillLoadingProvider, (_, __) => tryResolve()),
    );
    tryResolve();
  }

  /// Resolves true once the dashboard has finished its first load, false
  /// if it has not within [timeout] (or the load failed outright).
  ///
  /// Callers that WRITE reward state on behalf of a queued action use this
  /// so they never compute from DashboardState.initial()'s zeros. A false
  /// answer means "do nothing and leave the work queued", never "go ahead
  /// anyway".
  Future<bool> _awaitDashboardLoaded({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    bool ready(DashboardState s) => !s.isLoading && !s.loadFailed;
    if (ready(ref.read(dashboardProvider))) return true;
    final completer = Completer<bool>();
    final sub = ref.listenManual<DashboardState>(dashboardProvider,
        (previous, next) {
      if (completer.isCompleted) return;
      // loadFailed is terminal for this purpose: the state is the same
      // untrustworthy zeros and no amount of waiting improves it.
      if (next.loadFailed) completer.complete(false);
      if (ready(next)) completer.complete(true);
    });
    try {
      return await completer.future.timeout(timeout, onTimeout: () => false);
    } finally {
      sub.close();
    }
  }

  /// The habit-list counterpart of [_awaitDashboardLoaded]: resolves true
  /// once [habitsStillLoadingProvider] reports the custom-habit store has
  /// settled, false if it has not within [timeout]. Queued actions that
  /// resolve a habit by id need this as well as the dashboard wait — an
  /// empty, still-loading list makes _resolveHabit return null and the
  /// action silently dissolves.
  Future<bool> _awaitHabitsLoaded({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!ref.read(habitsStillLoadingProvider)) return true;
    final completer = Completer<bool>();
    final sub =
        ref.listenManual<bool>(habitsStillLoadingProvider, (_, stillLoading) {
      if (!completer.isCompleted && !stillLoading) completer.complete(true);
    });
    try {
      return await completer.future.timeout(timeout, onTimeout: () => false);
    } finally {
      sub.close();
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
    // Wait for the dashboard's first load before draining the queue.
    //
    // This runs from initState, so on a cold start the dashboard is still
    // DashboardState.initial() - level 1, 0 XP, 0 gold, no streak, no
    // achievements - and completeHabit writes every one of those back as an
    // ABSOLUTE value. Draining here without waiting would persist those
    // zeros over the real account, which is exactly the destruction
    // DashboardState.loadFailed exists to prevent; it just never covered
    // the not-loaded-YET case, only the load-threw case.
    //
    // Draining is what makes this urgent rather than merely wrong:
    // takePendingCompletions REMOVES the ids, so a tap refused here would
    // be gone. Waiting first means a slow load costs the tap a moment, and
    // a load that never arrives leaves the queue untouched for next launch.
    //
    // Auth FIRST, exactly like the Matrix twin below. On a signed-in cold
    // start every uid-keyed provider is initially the guest instance (auth
    // is still AsyncLoading), and the guest dashboard's Hive load settles
    // in microtasks — long before Firebase Auth's first emission. Gating on
    // the dashboard alone therefore opened against the GUEST store,
    // drained the queue, and each id then died against the real account's
    // still-loading providers: completeHabit refuses while loading, custom
    // ids resolve to nothing. The taps were unrecoverable — the exact loss
    // this gate exists to prevent, reintroduced one provider earlier.
    try {
      await ref.read(authStateProvider.future);
    } catch (_) {
      // Signed out or auth unavailable — the guest providers below are then
      // the correct target.
    }
    if (!mounted) return;
    if (!await _awaitDashboardLoaded()) return;
    // Custom habits need their list too: _handleNotificationAction resolves
    // the id against customHabitsProvider, and an empty in-flight list
    // silently discards the tap.
    if (!await _awaitHabitsLoaded()) return;
    if (!mounted) return;
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

    // Wait for auth and for the task list to actually load first.
    //
    // This runs on cold start, where matrixProvider keys on a uid that
    // authStateProvider has not produced yet — so `tasks` was empty, no id
    // matched anything, and every queued checkmark was silently discarded.
    // takePendingTaskCompletions has ALREADY cleared the queue by then, so
    // those taps were unrecoverable: the widget showed them ticked while the
    // app never recorded them.
    try {
      await ref.read(authStateProvider.future);
    } catch (_) {
      // Guest: matrixProvider's local load is the right target below.
    }
    if (!mounted) return;
    // The notifier loads asynchronously after construction; give it up to a
    // few frames rather than reading an empty list the instant it exists.
    for (var i = 0; i < 20 && ref.read(matrixProvider).isLoading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }

    final tasks = ref.read(matrixProvider).tasks;
    final notifier = ref.read(matrixProvider.notifier);
    for (final id in ids) {
      final matches = tasks.where((t) => t.id == id);
      if (matches.isNotEmpty && !matches.first.isDone) {
        notifier.toggle(id);
      }
    }
  }

  /// Drains the taps the background half of a notification action queued
  /// while the app was closed (see notification_action_background.dart) and
  /// runs each through [_handleNotificationAction], the same path a tap
  /// that opened the app has always taken. Same auth-then-data gates as
  /// [_processPendingWidgetCompletions], for the same reason: the take
  /// removes the entries, so a drain that ran against the guest store or a
  /// still-loading account would lose them.
  ///
  /// Each entry names the effective day it was tapped on. A day that is
  /// still open (today, or yesterday inside its grace tail) is paid in full
  /// on that day, exactly as a Grid tap on it would be. A day that has
  /// closed gets its record corrected and nothing paid, the same division
  /// of labour a late step-count read gets (see _creditYesterdayWalks in
  /// step_auto_complete.dart): setSquare's anti-backdating guard has always
  /// refused to pay for a day that is over, and a notification button is
  /// not a way around it.
  Future<void> _processPendingNotificationActions() async {
    try {
      await ref.read(authStateProvider.future);
    } catch (_) {
      // Signed out or auth unavailable: the guest providers below are then
      // the correct target.
    }
    if (!mounted) return;
    if (!await _awaitDashboardLoaded()) return;
    if (!await _awaitHabitsLoaded()) return;
    if (!mounted) return;
    final entries =
        await HomeWidgetService.instance.takePendingNotificationActions();
    if (entries.isEmpty) return;
    debugPrint('[NotificationAction] draining ${entries.length} queued '
        'tap(s): ${entries.map((e) => '${e.action}:${e.habitId}@${e.day}').join(', ')}');
    for (final entry in entries) {
      if (!mounted) return;
      final day = entry.dayDate;
      if (day == null) continue;
      if (day.isOpenDay) {
        await _handleNotificationAction(entry.action, entry.habitId,
            day: day);
      } else {
        await _recordClosedDayAction(entry.action, entry.habitId, day);
      }
    }
    _syncBadge();
  }

  /// A queued tap whose day has closed: mark the square it asked for, only
  /// if nobody has said anything about that habit-day since, and let the
  /// room follow. No reward, see [_processPendingNotificationActions].
  Future<void> _recordClosedDayAction(
      String action, String habitId, DateTime day) async {
    final habit = _resolveHabit(habitId);
    if (habit == null) return;
    final SquareState result;
    if (action == NotificationService.actionMarkDone ||
        action == NotificationService.actionStayedClean) {
      result = SquareState.complete;
    } else if (action == NotificationService.actionSlipped) {
      result = SquareState.failed;
    } else {
      return;
    }
    // The stored day, not the in-memory week: a closed day may be outside
    // the visible week, where WeeklyGridState answers `none` for everything
    // it has not loaded. See storedSquaresFor.
    final marks =
        await ref.read(weeklyGridProvider.notifier).storedSquaresFor(day);
    if (!mounted) return;
    if (marks == null) {
      // The day could not be read (offline cold start). Deciding anything
      // about a day the app has not seen is the mistake this guards
      // against, so the tap goes back in the queue for the next drain.
      await HomeWidgetService.instance.queueNotificationAction(
        QueuedNotificationAction(
          action: action,
          habitId: habitId,
          day: day.toDateKey(),
        ),
      );
      return;
    }
    // An explicit mark of any kind ends it: a late tap does not overrule
    // what the person has since said about that day.
    if ((marks[habit.id] ?? SquareState.none) != SquareState.none) return;
    await ref
        .read(weeklyGridProvider.notifier)
        .setSquareStateOnlyAsync(habit.id, day, result,
            source: kSquareSourceNotification);
    if (!mounted) return;
    syncRoomToday(ref, habit.id, day);
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
      // The middle of the invite funnel: shared, then opened, then joined.
      // Fired here rather than in the join sheet because this is the only
      // point that knows the person arrived from a link at all, and most
      // of the drop-off is between here and joinRoom.
      AnalyticsService.instance.track('room_code_opened', props: {
        'scheme': uri.scheme,
      });
      ref.read(pendingJoinCodeProvider.notifier).state = code;
      return;
    }
    if (isMatrixQuickAddLink(uri)) {
      ref.read(requestedHomeTabProvider.notifier).state = NavTab.matrix;
      ref.read(requestedMatrixQuickAddProvider.notifier).state = true;
      return;
    }
    final resetCode = parsePasswordResetLink(uri);
    if (resetCode != null) _openPasswordReset(resetCode);
  }

  /// The code from a reset link, held only until there is a Navigator to
  /// push it onto.
  ///
  /// A cold start runs [_initDeepLinks] from initState, so the very link
  /// that launched the app arrives before the first frame and
  /// `_navKey.currentState` is still null. Pushing on the next frame instead
  /// of dropping it is the difference between the email link working and the
  /// app opening on the grid as if nothing had been tapped.
  String? _pendingResetCode;

  void _openPasswordReset(String code) {
    _pendingResetCode = code;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = _pendingResetCode;
      final nav = _navKey.currentState;
      if (pending == null || nav == null || !mounted) return;
      _pendingResetCode = null;
      // Pushed over whatever is showing rather than routed to, because it
      // is an interruption with one job and a close button: the screen
      // underneath, signed in or out, is where the person goes back to.
      nav.push(MaterialPageRoute<void>(
        builder: (_) => SetNewPasswordScreen(oobCode: pending),
      ));
    });
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
    final habits =
        <({String id, String name, bool done, int count, int perDay})>[];
    for (final h in scheduled) {
      final done = dash.isCompleted(h.id, h.effectiveDailyTarget);
      if (done) completed++;
      habits.add((
        id: h.id,
        name: h.localName(isAr),
        done: done,
        // For the background action handler, which has to know whether one
        // more tap finishes a counted habit; see HomeWidgetService.
        count: dash.completions[h.id] ?? 0,
        perDay: h.effectiveDailyTarget,
      ));
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
  ///
  /// [day] is the effective day the tap belongs to, today when omitted. A
  /// tap made with the app closed reaches here from the queue in
  /// _processPendingNotificationActions, possibly the next morning, and
  /// then names the evening it was made on. The caller only sends a day
  /// that is still open (see DateTimeGameExt.isOpenDay), so paying it in
  /// full here is the same thing the Grid does for a grace-day square.
  Future<void> _handleNotificationAction(
    String actionId,
    String? habitId, {
    DateTime? day,
  }) async {
    // A plain body tap (no action button) carries an empty actionId — that
    // used to just open the app wherever it last was. Now it lands where
    // the notification actually points: see _handleNotificationBodyTap.
    if (actionId.isEmpty) {
      _handleNotificationBodyTap(habitId);
      return;
    }
    if (habitId == null || habitId.isEmpty) return;
    final actionDay = day ?? DateTime.now().effectiveDay;

    // Wait for auth before touching ANY uid-keyed provider.
    //
    // On a cold launch this runs synchronously the moment onAction is
    // assigned (the setter replays a pending response on that same tick),
    // which is before authStateProvider — a StreamProvider over
    // authStateChanges — has produced its first value. dashboardProvider and
    // customHabitsProvider both key on that uid, so reading them here built
    // a GUEST notifier: the completion was written to guest Hive, auth then
    // resolved, the provider rebuilt against Firestore, and the whole thing
    // vanished. A signed-in person tapping "Mark Done" on a lock-screen
    // reminder with the app closed got no XP, no gold, no streak and no
    // square — deterministically, not as a race. Custom habits failed a
    // second way: _resolveHabit's list was empty too, so it returned null
    // and this bailed silently.
    //
    // Awaiting the future settles the provider first, so everything below
    // reads the real account.
    try {
      await ref.read(authStateProvider.future);
    } catch (_) {
      // Signed out, or auth genuinely unavailable — the guest path below is
      // then the correct one, which is exactly what the un-awaited version
      // could never distinguish.
    }
    if (!mounted) return;
    // Auth settles WHICH account — not that account's DATA. Immediately
    // after the await, the uid-keyed dashboard and habit providers are
    // freshly constructed and still loading from Firestore, so on a cold
    // launch _resolveHabit found an empty list (killing every action) and
    // completeHabit refused while state.isLoading (killing Mark Done for
    // catalog habits). The notification is already dismissed by then, so
    // the tap was silently unrecoverable. Wait for the data the same way
    // the widget queue does; on a warm app both gates resolve instantly.
    if (!await _awaitDashboardLoaded()) return;
    if (!await _awaitHabitsLoaded()) return;
    if (!mounted) return;
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
            day: actionDay,
            // Mirrors the completion's boost — see roomBoostedReward.
            xpReward: roomBoostedReward(ref, habit.id, habit.xpReward),
            goldReward: roomBoostedReward(ref, habit.id, habit.goldReward),
            // Same per-day count the completion was priced against, so
            // the refund matches the debit — see uncompleteHabit.
            frequencyTarget: habit.effectiveDailyTarget,
            category: habit.category.name,
          );
      final today = actionDay;
      ref.read(weeklyGridProvider.notifier).markResultFromHabit(
          habit.id, today, SquareState.failed,
          source: kSquareSourceNotification);
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
          .where((h) => h.isScheduledFor(actionDay))
          .map((h) => (id: h.id, frequencyTarget: h.effectiveDailyTarget));
      final mirroredBySingleTap =
          await ref.read(dashboardProvider.notifier).completeHabit(
                habitId: habit.id,
                day: actionDay,
                scheduledWeekdays: habit.scheduledWeekdays.toSet(),
                // 2x while a linked room is live — see roomBoostedReward.
                xpReward: roomBoostedReward(ref, habit.id, habit.xpReward),
                goldReward:
                    roomBoostedReward(ref, habit.id, habit.goldReward),
                frequencyTarget: habit.effectiveDailyTarget,
                // Today's answer comes from `completions`; a grace day's
                // has to come from that day's own squares, because
                // `completions` only ever holds today's counts. Same split
                // the Grid makes, see willCompleteAllSquaresOn.
                allHabitsDoneAfter: actionDay.isToday
                    ? willCompleteAllHabitsToday(
                        state: dashState,
                        todayHabits: todayHabits,
                        habitId: habit.id,
                        frequencyTarget: habit.effectiveDailyTarget,
                      )
                    : willCompleteAllSquaresOn(ref, habit, actionDay),
                // Scales the daily earn ceiling with the roster, see
                // dailyXpCapFor. Same list the predicate above uses.
                scheduledHabitCount: todayHabits.length,
                category: habit.category.name,
                habitName: habit.localName(isAr),
              );
      final perDay = habit.effectiveDailyTarget;
      if (mirroredBySingleTap) {
        final today = actionDay;
        ref
            .read(weeklyGridProvider.notifier)
            .markCompleteFromHabit(habit.id, today,
                source: kSquareSourceNotification);
        syncRoomToday(ref, habit.id, today);
      } else if (perDay > 1) {
        // A habit counted several times a day also has to paint its square,
        // and completeHabit's flag cannot say so: it returns isGridSyncable,
        // `frequencyTarget == 1`, which is false for every counted habit on
        // every tap. Left alone, marking one done from a notification moved
        // the count but never touched the board, so the square stayed empty
        // while the day filled up — and the Grid's own "إنجاز اليوم" figure
        // reads the stored square, so the day's percentage was wrong too,
        // not just the picture.
        final today = actionDay;
        final done = ref.read(dashboardProvider).completions[habit.id] ?? 0;
        if (done > 0) {
          ref.read(weeklyGridProvider.notifier).markResultFromHabit(
                habit.id,
                today,
                done >= perDay ? SquareState.complete : SquareState.partial,
                source: kSquareSourceNotification,
              );
          syncRoomToday(ref, habit.id, today);
        }
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
  Future<void> _handleNotificationBodyTap(String? payload) async {
    if (payload == null || payload.isEmpty) return;
    final String route;
    if (payload == NotificationService.openTodayPayload ||
        _resolveHabit(payload) != null) {
      route = '/grid';
    } else {
      // A task id. On a cold launch this tap is replayed the moment
      // onAction is assigned — before matrixProvider's async load has
      // produced any tasks — so a synchronous membership check always
      // failed and the app opened on the default tab instead of the
      // board. Same await-then-poll shape as _handleNotificationAction
      // and _processPendingWidgetTaskCompletions, which each document
      // this exact cold-start race for their own payloads.
      try {
        await ref.read(authStateProvider.future);
      } catch (_) {
        // Same guard as _handleNotificationAction: an auth stream error
        // must not detonate inside a notification callback.
        return;
      }
      if (!mounted) return;
      for (var i = 0; i < 20 && ref.read(matrixProvider).isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
      }
      if (!ref.read(matrixProvider).tasks.any((t) => t.id == payload)) {
        // Fully loaded and genuinely absent: a stale payload for a task
        // deleted since the notification fired. Nothing useful to open.
        return;
      }
      route = '/matrix';
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
    _localeSub?.close();
    _habitRemindersSub?.close();
    _widgetSub?.close();
    _notificationSettingsSub?.close();
    _gridSub?.close();
    _authSub?.close();
    _passwordDroppedSub?.close();
    _roomRaceSub?.close();
    _matrixWidgetSub?.close();
    _linkSub?.cancel();
    for (final sub in _streakGapSubs) {
      sub.close();
    }
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
      supportedLocales: kSupportedLocales,
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
        // On the web, a phone-sized frame on any window wider than a phone
        // (see _WebPhoneFrame); a no-op everywhere else, and on narrow
        // windows.
        child: _WebPhoneFrame(
          child: Stack(
            children: [
              if (child != null) child,
              const GlobalVoiceNotePlayerOverlay(),
            ],
          ),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const _AuthGate(),
        '/heatmap': (_) => const MonthlyHeatmapScreen(),
        '/night-review': (_) => const NightReviewScreen(),
        '/tasbih': (_) => const TasbihScreen(),
        '/grid-journal': (_) => const GridJournalScreen(),
        '/insights': (_) => const InsightsScreen(),
        '/premium': (_) => const PremiumScreen(),
        '/auth': (_) => const AuthScreen(),
        '/notification-settings': (_) => const NotificationSettingsScreen(),
        '/help-support': (_) => const HelpSupportScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/nav-bar': (_) => const NavBarSettingsScreen(),
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
          '/grid' => (_) => const HomeShell(initialTab: NavTab.grid),
          '/profile' => (_) => const HomeShell(initialTab: NavTab.profile),
          '/matrix' => (_) => const HomeShell(initialTab: NavTab.matrix),
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

// A _LanguageGate used to sit here, in front of _AuthGate: a full-screen
// first-launch language picker, shown once per device. It is gone, and what
// replaced it is nothing — the app reads the phone's own language at boot
// (see resolveInitialLocale) and restores the account's at sign-in (see
// _hydrateLocaleFromAccount), so for almost everyone the question the screen
// asked is already answered before it could have been shown. The minority it
// gets wrong correct it with the LanguageToggle on the auth screen, from
// Profile once signed in, or from the per-app Language row iOS offers.
//
// languageChosenProvider outlived it and still matters: it is now only the
// record of whether a language was DECIDED, which is what stops detection and
// the account's own value from overruling a person who picked. Nothing gates
// on it any more.

/// On the web, the app inside a phone-sized panel whenever the window is
/// wider than a phone; the app itself everywhere else.
///
/// GrowDaily is a phone app. Stretched across a laptop window every column
/// of the Grid, every room row and every sheet lays out for a width it was
/// never designed for, and the Arabic type in particular reads badly at
/// forty characters a line. So on a wide window the whole app is laid out
/// in a 402-point frame, the width of the iPhone it is built and verified
/// on, centred on a quiet backdrop drawn from the current theme. The
/// MediaQuery handed down is the FRAME's, not the window's, so every screen
/// that asks "how wide am I" gets the phone answer and lays out exactly as
/// it does on the device; the keyboard inset is left alone, since a tablet
/// wide enough to get the frame still has a real keyboard to avoid.
///
/// Below [kWideWindow] the app is full-bleed, which is what a phone or a
/// narrow browser window should get. Never active off the web.
class _WebPhoneFrame extends StatelessWidget {
  final Widget child;
  const _WebPhoneFrame({required this.child});

  static const double kWideWindow = 600;
  static const double kFrameWidth = 402;
  static const double kFrameHeight = 874;
  static const double kMargin = 24;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kWideWindow) return child;
        final theme = Theme.of(context);
        final surface = theme.scaffoldBackgroundColor;
        final dark = theme.brightness == Brightness.dark;
        final backdrop =
            Color.lerp(surface, Colors.black, dark ? 0.45 : 0.10)!;
        final width = kFrameWidth;
        final height = (constraints.maxHeight - kMargin * 2)
            .clamp(480.0, kFrameHeight)
            .toDouble();
        final mq = MediaQuery.of(context);
        return ColoredBox(
          color: backdrop,
          child: Center(
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.55 : 0.18),
                    blurRadius: 48,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: MediaQuery(
                  data: mq.copyWith(
                    size: Size(width, height),
                    padding: EdgeInsets.zero,
                    viewPadding: EdgeInsets.zero,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

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
    // One question between onboarding and the Grid, asked once per device.
    // See FirstRunOfferScreen for why it is a question rather than a tour, and
    // firstRunOfferProvider for why only the ASKING is persisted and never the
    // answer.
    final offerAsked = ref.watch(firstRunOfferAskedProvider);
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

    // ── Drain a code that arrived BEFORE this widget's first build ──────
    //
    // ref.listen reports changes made after registration, and both pending
    // codes above can be set earlier than that: a cold start from a tapped
    // link or push sets them while the language/auth gates above this
    // widget are still on screen. For a signed-in user those gates resolve
    // asynchronously, so the value was already sitting in the provider when
    // the listeners registered — and a listener that never fires meant the
    // app opened normally with the join silently dropped. One post-frame
    // read closes the gap; the null-and-consume shape keeps it idempotent
    // with the listeners (whichever runs first wins, the other no-ops).
    //
    // Deferred to a post-frame callback because consuming the code writes
    // provider state, which Riverpod forbids during build.
    if (ref.read(pendingJoinCodeProvider) != null ||
        ref.read(pendingOpenRoomCodeProvider) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final joinCode = ref.read(pendingJoinCodeProvider);
        if (joinCode != null) {
          // Re-set to itself is not enough to fire the listener (no
          // change); null-then-set is. This replays the exact listener
          // path rather than duplicating its navigation logic here.
          ref.read(pendingJoinCodeProvider.notifier).state = null;
          ref.read(pendingJoinCodeProvider.notifier).state = joinCode;
        }
        final roomCode = ref.read(pendingOpenRoomCodeProvider);
        if (roomCode != null) {
          ref.read(pendingOpenRoomCodeProvider.notifier).state = null;
          ref.read(pendingOpenRoomCodeProvider.notifier).state = roomCode;
        }
      });
    }

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
    return GuestReconnectPrompt(
      child: RoomFinaleAnnouncer(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: !seen
              ? const OnboardingScreen(key: ValueKey('onboarding'))
              : offerAsked
                  ? const HomeShell(key: ValueKey('home'))
                  : const FirstRunOfferScreen(key: ValueKey('offer')),
        ),
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
            // The real app icon, matching the auth screen this splash hands
            // off to. They used to draw two different marks at two different
            // sizes, so a cold start flashed a gold grid glyph and then
            // replaced it with the seedling one frame later.
            const AppLogo(size: 64),
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
