import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/screens/dashboard_screen.dart';
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

  Widget app() => UncontrolledProviderScope(
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
          home: const GridScreen(),
          routes: {
            '/dashboard': (_) => const DashboardScreen(),
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

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
  }
}
