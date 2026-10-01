// Where HomeShell opens, what it treats as home, and a bar without Habits.
//
// Aziz, 2026-09-30: someone who lives in their task list can open the app
// on Tasks (the start page, free), or drop the habit page from the bar
// altogether (Premium, like every bar edit). The shell used to assume Habits
// at page 0 in three places: where it opened, where Android's back button
// walked to, and where a removed tab that was showing landed. And the
// level-up and medal moments lived on the Habits page, which is not built
// while another page shows, so they are the shell's now.
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/home_tab_provider.dart';
import 'package:grow_daily_v2/core/providers/nav_layout_provider.dart';
import 'package:grow_daily_v2/core/providers/start_page_provider.dart';
import 'package:grow_daily_v2/core/utils/xp_calculator.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/screens/grid_screen.dart';
import 'package:grow_daily_v2/features/matrix/screens/matrix_screen.dart';
import 'package:grow_daily_v2/shared/widgets/game_nav_bar.dart';
import 'package:grow_daily_v2/shared/widgets/home_shell.dart';

import '../helpers/landing_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A phone, not the 800x600 default: MatrixScreen's quadrants overflow at
  /// 600pt, which no phone produces (same helper as nav_bar_labels_test).
  Future<void> phoneSized(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// Fixed frames, not pumpAndSettle: an empty quadrant's "+" breathes
  /// forever, so settle would burn its whole timeout once Tasks is up.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  int barIndex(WidgetTester tester) => tester
      .widget<GameNavBar>(find.byType(GameNavBar, skipOffstage: false))
      .currentIndex;

  // ProfileScreen reads FirebaseAuth.instance, which a widget test has no
  // app for, so no test below lets it build: a page-turn animates THROUGH
  // the pages between, and the layouts keep Profile off every path.

  void ask(LandingHarness h, NavTab tab) {
    h.container.read(requestedHomeTabInstantProvider.notifier).state = true;
    h.container.read(requestedHomeTabProvider.notifier).state = tab;
  }

  group('Tasks as the start page (default bar)', () {
    late LandingHarness h;

    setUp(() async {
      h = LandingHarness();
      await h.prepare(extraOverrides: [
        startPageProvider.overrideWith((ref) => StartPageNotifier(NavTab.matrix)),
      ]);
    });

    tearDown(() => h.dispose());

    testWidgets('opens on Tasks, and never builds the Habits page',
        (tester) async {
      await phoneSized(tester);
      await tester.pumpWidget(h.app(home: const HomeShell()));
      await pumpFrames(tester);

      expect(barIndex(tester), 2, reason: 'Tasks is the third tab');
      expect(find.byType(MatrixScreen), findsOneWidget);
      expect(find.byType(GridScreen), findsNothing);
    });

    testWidgets('back walks to Tasks, not to page 0', (tester) async {
      // Habits, Tasks, Profile: the walk back is one page, not through
      // Profile (see the note above).
      // State first, disk after: the write is not awaited (see below).
      unawaited(h.container
          .read(navLayoutProvider.notifier)
          .set(const [NavTab.grid, NavTab.matrix, NavTab.profile]));
      await phoneSized(tester);
      await tester.pumpWidget(h.app(home: const HomeShell()));
      await pumpFrames(tester);
      expect(barIndex(tester), 1);

      ask(h, NavTab.grid);
      await pumpFrames(tester);
      expect(barIndex(tester), 0);

      // Android's system back. On Habits it is swallowed and walks home.
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);
      expect(barIndex(tester), 1);
      expect(find.byType(MatrixScreen), findsOneWidget);
    });

    testWidgets('a named tab still wins over the start page', (tester) async {
      // The legacy '/grid' route, and a notification tap on a habit reminder.
      await phoneSized(tester);
      await tester.pumpWidget(
          h.app(home: const HomeShell(initialTab: NavTab.grid)));
      await pumpFrames(tester);
      expect(barIndex(tester), 0);
    });

    testWidgets('a level reached while Tasks shows is celebrated there',
        (tester) async {
      // The Grid is not built on this page. The moment used to be its, and
      // played nothing here.
      await phoneSized(tester);
      await tester.pumpWidget(h.app(home: const HomeShell()));
      await pumpFrames(tester);
      expect(find.byType(GridScreen), findsNothing);

      // Not awaited: the level is in state at once, and the save behind it
      // is a disk write the fake-async zone never finishes.
      unawaited(h.container.read(dashboardProvider.notifier).awardBonus(
            xp: XpCalculator.xpToNextLevel(1),
            gold: 0,
            countsTowardDailyCap: false,
          ));
      await pumpFrames(tester);
      expect(h.container.read(dashboardProvider).level, 2);
      expect(find.textContaining('LEVEL UP'), findsOneWidget);
    });
  });

  group('Tasks picked, then removed from the bar', () {
    late LandingHarness h;

    setUp(() async {
      h = LandingHarness();
      await h.prepare(extraOverrides: [
        startPageProvider.overrideWith((ref) => StartPageNotifier(NavTab.matrix)),
        navLayoutProvider.overrideWith((ref) => NavLayoutNotifier(
            const [NavTab.grid, NavTab.profile, NavTab.tasbih])),
      ]);
    });

    tearDown(() => h.dispose());

    testWidgets('opens on Habits instead of pushing Tasks', (tester) async {
      await phoneSized(tester);
      await tester.pumpWidget(h.app(home: const HomeShell()));
      await pumpFrames(tester);

      expect(barIndex(tester), 0);
      expect(find.byType(MatrixScreen), findsNothing);
      expect(find.byType(BackButton), findsNothing);
    });
  });

  group('a bar without Habits', () {
    // Tasks at 1, so "home" is provably not page 0.
    const layout = [NavTab.tasbih, NavTab.matrix, NavTab.profile];
    late LandingHarness h;

    setUp(() async {
      h = LandingHarness();
      await h.prepare(extraOverrides: [
        navLayoutProvider.overrideWith((ref) => NavLayoutNotifier(layout)),
      ]);
    });

    tearDown(() => h.dispose());

    testWidgets('opens on Tasks, though the start page says Habits',
        (tester) async {
      await phoneSized(tester);
      await tester.pumpWidget(h.app(home: const HomeShell()));
      await pumpFrames(tester);

      expect(h.container.read(startPageProvider), NavTab.grid);
      expect(barIndex(tester), 1);
      expect(find.byType(MatrixScreen), findsOneWidget);
      expect(find.byType(GridScreen), findsNothing);
    });

    testWidgets('back on another tab walks to Tasks', (tester) async {
      await phoneSized(tester);
      await tester.pumpWidget(h.app(home: const HomeShell()));
      await pumpFrames(tester);

      ask(h, NavTab.tasbih);
      await pumpFrames(tester);
      expect(barIndex(tester), 0);

      await tester.binding.handlePopRoute();
      await pumpFrames(tester);
      expect(barIndex(tester), 1);
    });

    testWidgets('Habits, asked for, is pushed with a way back',
        (tester) async {
      // A habit reminder or a Habits widget tap, for someone who removed
      // the page. The Grid draws no AppBar of its own.
      await phoneSized(tester);
      await tester.pumpWidget(h.app(home: const HomeShell()));
      await pumpFrames(tester);

      ask(h, NavTab.grid);
      await pumpFrames(tester);
      expect(find.byType(GridScreen), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Habits'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await pumpFrames(tester);
      expect(find.byType(GridScreen), findsNothing);
      expect(find.byType(MatrixScreen), findsOneWidget);
    });

    testWidgets('asked for again from on top, it is not stacked twice',
        (tester) async {
      // The Get Started card on the pushed Habits page asks for Habits.
      await phoneSized(tester);
      await tester.pumpWidget(h.app(home: const HomeShell()));
      await pumpFrames(tester);

      ask(h, NavTab.grid);
      await pumpFrames(tester);
      final first = tester.state(find.byType(GridScreen));
      ask(h, NavTab.grid);
      await pumpFrames(tester);
      expect(find.byType(GridScreen), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(tester.state(find.byType(GridScreen)), same(first),
          reason: 'the page on screen stays; not closed and opened again');
    });

    testWidgets('a tab in the bar, asked for from on top, closes it',
        (tester) async {
      // The same card's Tasks row: the page-turn used to happen underneath
      // the pushed page, where nobody could see it.
      await phoneSized(tester);
      await tester.pumpWidget(h.app(home: const HomeShell()));
      await pumpFrames(tester);

      ask(h, NavTab.tasbih);
      await pumpFrames(tester);
      ask(h, NavTab.grid);
      await pumpFrames(tester);
      expect(find.byType(GridScreen), findsOneWidget);

      ask(h, NavTab.matrix);
      await pumpFrames(tester);
      expect(find.byType(GridScreen), findsNothing);
      expect(barIndex(tester), 1);
      expect(find.byType(MatrixScreen), findsOneWidget);
    });

    testWidgets('removing the tab that shows lands on Tasks, not page 0',
        (tester) async {
      unawaited(h.container
          .read(navLayoutProvider.notifier)
          .set(const [NavTab.profile, NavTab.tasbih, NavTab.matrix]));
      await phoneSized(tester);
      await tester.pumpWidget(h.app(home: const HomeShell()));
      await pumpFrames(tester);
      expect(barIndex(tester), 2);

      ask(h, NavTab.tasbih);
      await pumpFrames(tester);
      expect(barIndex(tester), 1);

      unawaited(
          h.container.read(navLayoutProvider.notifier).remove(NavTab.tasbih));
      await pumpFrames(tester);
      expect(h.container.read(navLayoutProvider),
          [NavTab.profile, NavTab.matrix]);
      expect(barIndex(tester), 1);
      expect(find.byType(MatrixScreen), findsOneWidget);
    });
  });
}
