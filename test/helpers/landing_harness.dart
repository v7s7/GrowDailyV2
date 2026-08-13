import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/grid/screens/grid_screen.dart';
import 'package:grow_daily_v2/features/grid/screens/monthly_heatmap_screen.dart';
import 'package:grow_daily_v2/features/intention/screens/intention_screen.dart';
import 'package:grow_daily_v2/features/night_review/screens/night_review_screen.dart';
import 'package:grow_daily_v2/features/premium/screens/premium_screen.dart';

/// Widget-test harness for the landing flows.
///
/// The golden rule here: **all Hive boxes are opened in [prepare], in the
/// real async zone, before any widget builds.** Once a box is open, every
/// LocalStoreService call the app makes is synchronous (memory-backed), so
/// the widget tests never need `tester.runAsync` and there is no real IO
/// that can freeze inside the fake-async test zone — the class of bug that
/// produced 10-minute `pumpAndSettle` hangs.
class LandingHarness {
  late final Directory tmp;
  late final ProviderContainer container;

  /// Call from setUp. Opens the app's boxes for real, then resolves auth so
  /// dependent notifiers are created exactly once.
  Future<void> prepare({List<String> activeCatalogIds = const []}) async {
    // Completion fires a local "habit completed" notification, and the
    // flutter_local_notifications platform interface is never registered in
    // a pure Dart test — so the plugin call throws a LateInitializationError
    // that surfaces the moment a test lets real async run (tester.runAsync).
    // Nothing here is testing notifications; switch the celebration ones off
    // rather than have the reward path explode on a platform channel that
    // only exists on a device.
    NotificationService.instance.celebrationsEnabled = false;
    // google_fonts falls back to downloading a .ttf at runtime when the font
    // isn't bundled. Inside a widget test that becomes a real HTTP request
    // the moment tester.runAsync lets actual async run, and it fails (no
    // network, and the test HTTP client rejects it anyway). Tests should
    // never reach the network; make the fetch a no-op so the theme falls
    // back to a local font instead of throwing.
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('landing_test_');
    Hive.init(tmp.path);
    final settings = await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
    if (activeCatalogIds.isNotEmpty) {
      await settings.put('active_catalog_ids_v1', activeCatalogIds);
    }
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      ],
    );
    await container.read(authStateProvider.future);
  }

  /// Call from tearDown. Deliberately does NOT await Hive cleanup: disk
  /// flushes queued from the fake-async zone can never complete, and each
  /// test file runs in its own process anyway — the temp dir is disposable.
  void dispose() {
    container.dispose();
  }

  /// [home] defaults to [GridScreen] on its own, which is what the landing
  /// flows below actually exercise. Pass [HomeShell] instead for anything
  /// that needs the bottom bar: the shell owns the single [GameNavBar] and
  /// hosts Grid/Profile/Matrix as pages of one PageView (see its doc
  /// comment), so a test pumping GridScreen alone has no nav bar in the tree
  /// at all — which is exactly why nav_bar_labels_test could never find one.
  Widget app({Widget? home}) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          // Mirror production: the localization delegates initialize intl's
          // date symbols, which DateFormat('EEE', …) in the grid depends on.
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // Light theme is pure const styles — no runtime font fetching.
          theme: GameTheme.light,
          home: home ?? const GridScreen(),
          routes: {
            '/heatmap': (_) => const MonthlyHeatmapScreen(),
            '/intention': (_) => const IntentionScreen(),
            '/night-review': (_) => const NightReviewScreen(),
            '/premium': (_) => const PremiumScreen(),
          },
        ),
      );

  /// Settle with a hard cap so animation leaks fail in seconds, not minutes.
  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 15),
      );

  Future<void> pumpApp(WidgetTester tester, {Widget? home}) async {
    await tester.pumpWidget(app(home: home));
    await settle(tester);
  }
}
