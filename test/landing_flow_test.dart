import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/screens/dashboard_screen.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/grid/screens/grid_screen.dart';
import 'package:grow_daily_v2/features/grid/screens/monthly_heatmap_screen.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_plans.dart';
import 'package:grow_daily_v2/features/intention/screens/intention_screen.dart';
import 'package:grow_daily_v2/features/night_review/screens/night_review_screen.dart';

/// Drives the real first-run journey a user lands in: Grid as home, the
/// empty-state recruitment flow, the morning intention prompt for returning
/// users, and coloring the first square of the week.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ProviderContainer container;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('landing_test_');
    Hive.init(tmp.path);
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      ],
    );
    // Resolve the auth stream BEFORE anything builds. Otherwise it emits a
    // frame later and every dependent notifier is recreated inside the test's
    // fake-async zone, where Hive IO can never complete — an eternal spinner.
    await container.read(authStateProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  Widget app() => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          // Light theme is pure const styles — no runtime font fetching.
          theme: GameTheme.light,
          home: const GridScreen(),
          routes: {
            '/dashboard': (_) => const DashboardScreen(),
            '/heatmap': (_) => const MonthlyHeatmapScreen(),
            '/intention': (_) => const IntentionScreen(),
            '/night-review': (_) => const NightReviewScreen(),
          },
        ),
      );

  /// Settle with a hard cap so animation leaks fail in seconds, not minutes.
  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 15),
      );

  /// Pumps the app and lets real Hive IO complete before settling.
  /// The 15s settle cap turns a would-be 10-minute hang into a fast,
  /// diagnosable failure.
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    await settle(tester);
  }

  /// Seeds one active catalog habit and waits for the catalog notifier to
  /// pick it up, so the app builds with the habit already equipped.
  Future<void> seedHabit(WidgetTester tester) async {
    await tester.runAsync(() async {
      final box = await Hive.openBox<dynamic>('box_settings');
      await box.put('active_catalog_ids_v1', ['morning_athkar']);
      container.read(activeCatalogProvider);
      while (!container.read(activeCatalogProvider).contains(
            'morning_athkar',
          )) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
  }

  testWidgets(
      'a brand-new user lands directly on the Grid empty state — no prompt in the way',
      (tester) async {
    await pumpApp(tester);

    // No habits yet → no intention interruption; straight to the grid.
    expect(find.text('Set your intention'), findsNothing);
    expect(find.text('Victory Grid'), findsOneWidget);
    // The empty state recruits them right here on the flagship screen.
    expect(find.text('No habits to track yet'), findsOneWidget);
    expect(find.text('Browse Plans'), findsOneWidget);

    // Browsing plans opens the picker in place — no tab switch needed.
    await tester.tap(find.text('Browse Plans'));
    await settle(tester);
    expect(find.text('Choose Your Plan'), findsOneWidget);
  });

  testWidgets(
      'a returning user with habits gets the morning intention prompt, then the grid',
      (tester) async {
    await seedHabit(tester);
    await pumpApp(tester);

    // With habits equipped, the day starts with the intention prompt.
    expect(find.text('Set your intention'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);

    // The grid shows the habit row, summary, legend, and slogan.
    expect(find.text('Morning Athkar'), findsOneWidget);
    expect(find.text('Green squares'), findsOneWidget);
    expect(find.text('Points'), findsOneWidget);
    expect(find.text('Legend'), findsOneWidget);
    expect(
      find.text('Color your life, one square at a time.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping today\'s square colors it yellow then green',
      (tester) async {
    await seedHabit(tester);
    await pumpApp(tester);
    await tester.tap(find.text('Skip'));
    await settle(tester);

    // Find today's cell in the row via its runtime fields.
    final todayCell = find.byWidgetPredicate((w) {
      if (w.runtimeType.toString() != '_SquareCell') return false;
      final dynamic cell = w;
      // ignore: avoid_dynamic_calls
      return (cell.isToday as bool) && !(cell.isFuture as bool);
    });
    expect(todayCell, findsOneWidget);

    final today = DateTime.now();

    await tester.tap(todayCell);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester);
    expect(
      container.read(weeklyGridProvider).squareFor('morning_athkar', today),
      SquareState.partial,
    );

    await tester.tap(todayCell);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester);
    expect(
      container.read(weeklyGridProvider).squareFor('morning_athkar', today),
      SquareState.complete,
    );
    // One green square on the board this week.
    expect(
      container
          .read(weeklyGridProvider)
          .greenSquares(const ['morning_athkar']),
      1,
    );
  });

  testWidgets('grid header links to the heatmap screen', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.insights_rounded));
    await settle(tester);
    expect(find.text('Progress Heatmap'), findsOneWidget);
  });
}
