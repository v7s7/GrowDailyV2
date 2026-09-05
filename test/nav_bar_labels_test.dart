import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/home_tab_provider.dart';
import 'package:grow_daily_v2/core/providers/nav_layout_provider.dart';
import 'package:grow_daily_v2/features/matrix/screens/matrix_screen.dart';
import 'package:grow_daily_v2/features/settings/screens/nav_bar_settings_screen.dart';
import 'package:grow_daily_v2/shared/widgets/coach_mark_overlay.dart';
import 'package:grow_daily_v2/shared/widgets/game_nav_bar.dart';
import 'package:grow_daily_v2/shared/widgets/home_shell.dart';

import 'helpers/landing_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GameNavBar', () {
    late LandingHarness harness;

    setUp(() async {
      harness = LandingHarness();
      await harness.prepare();
    });

    tearDown(() => harness.dispose());

    testWidgets('shows three tabs — Habits, Profile, Tasks — with no Today',
        (tester) async {
      // HomeShell, not the default GridScreen: the shell is what actually
      // owns the one GameNavBar (Grid/Profile/Matrix are pages inside its
      // PageView), so pumping GridScreen on its own put no nav bar in the
      // tree for these tests to find.
      await harness.pumpApp(tester, home: const HomeShell(initialTab: NavTab.grid));

      expect(find.text('Today'), findsNothing);
      expect(find.text('Habits'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      // A free account (this harness has no entitlement and no trial)
      // never sees the "arrange your bar" coach-mark: it points at a
      // Premium feature. And a fresh account has no badges to show.
      expect(find.byType(CoachMarkOverlay), findsNothing);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('Grid screen (the harness home) is tab 0', (tester) async {
      // HomeShell, not the default GridScreen: the shell is what actually
      // owns the one GameNavBar (Grid/Profile/Matrix are pages inside its
      // PageView), so pumping GridScreen on its own put no nav bar in the
      // tree for these tests to find.
      await harness.pumpApp(tester, home: const HomeShell(initialTab: NavTab.grid));

      final navBar = tester.widget<GameNavBar>(find.byType(GameNavBar));
      expect(navBar.currentIndex, 0);
    });

    testWidgets('press and hold on the bar opens the customiser',
        (tester) async {
      // The undocumented way in. A plain tap must still just switch tabs,
      // which the first assertion pins before the hold.
      await harness.pumpApp(tester, home: const HomeShell(initialTab: NavTab.grid));
      // Scoped to the bar: once Profile is the page on screen, its own
      // title says "Profile" too, and a bare text finder lands on that.
      Finder inBar(String label) => find.descendant(
          of: find.byType(GameNavBar), matching: find.text(label));

      // Habits, not Profile: ProfileScreen reaches for FirebaseAuth in its
      // build and this harness has no Firebase app, so no test here can
      // land on it. A tap on the bar must never open the customiser.
      await tester.tap(inBar('Habits'));
      await harness.settle(tester);
      expect(find.byType(NavBarSettingsScreen), findsNothing);

      await tester.longPress(inBar('Habits'));
      await harness.settle(tester);
      expect(find.byType(NavBarSettingsScreen), findsOneWidget);
    });
  });

  // A Premium account's own bar. Rooms sits LAST on purpose: a PageView
  // builds its neighbours ahead of time, and RoomsHubScreen for a signed-in
  // account opens Firestore streams this harness has no Firebase for. At
  // index 4 it is never built while the shell sits on Habits.
  group('GameNavBar with a custom layout', () {
    const layout = [
      NavTab.grid,
      NavTab.profile,
      NavTab.tasbih,
      NavTab.settings,
      NavTab.rooms,
    ];
    late LandingHarness harness;

    setUp(() async {
      harness = LandingHarness();
      await harness.prepare(extraOverrides: [
        navLayoutProvider.overrideWith((ref) => NavLayoutNotifier(layout)),
      ]);
    });

    tearDown(() => harness.dispose());

    /// A phone, not the 800x600 test default: MatrixScreen's four quadrants
    /// share the height with the Get Started card, and at 600pt the
    /// quadrant tiles overflow, which is not a layout any phone produces.
    Future<void> phoneSized(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    /// Fixed frames instead of pumpAndSettle: an empty quadrant's "+" icon
    /// breathes forever (see matrix_add_task_test.dart's identical helper),
    /// so settle would burn its whole timeout once Tasks is on screen.
    Future<void> pumpFrames(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('draws the five tabs in the account\'s order, and no Tasks',
        (tester) async {
      await phoneSized(tester);
      await harness.pumpApp(tester,
          home: const HomeShell(initialTab: NavTab.grid));

      expect(find.text('Tasks'), findsNothing);
      const labels = ['Habits', 'Profile', 'Tasbih', 'Settings', 'Rooms'];
      for (final label in labels) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // English is LTR, so the bar's order is left to right.
      final xs = [for (final l in labels) tester.getCenter(find.text(l)).dx];
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i], greaterThan(xs[i - 1]),
            reason: '${labels[i]} is not to the right of ${labels[i - 1]}');
      }
    });

    testWidgets('a requested tab that is not in the bar is pushed on top',
        (tester) async {
      // The Grid checklist's "add your first task" asks for Tasks by
      // identity. With Tasks out of the bar it still has to get there.
      await phoneSized(tester);
      await harness.pumpApp(tester,
          home: const HomeShell(initialTab: NavTab.grid));
      expect(find.byType(MatrixScreen), findsNothing);

      harness.container.read(requestedHomeTabProvider.notifier).state =
          NavTab.matrix;
      await pumpFrames(tester);

      expect(find.byType(MatrixScreen), findsOneWidget);
      // A route over the shell, not a page in it: the bar stays on Habits
      // and back returns to it.
      // skipOffstage: the shell sits under an opaque route now, and a
      // default finder would not look there.
      final navBar = tester.widget<GameNavBar>(
          find.byType(GameNavBar, skipOffstage: false));
      expect(navBar.currentIndex, 0);
      expect(harness.container.read(requestedHomeTabProvider), isNull,
          reason: 'the one-shot request was not consumed');
    });

    testWidgets('opening the shell on a tab that is not in the bar',
        (tester) async {
      // A stale '/matrix' route (a notification tap from before Tasks was
      // removed) lands on Habits with Tasks pushed over it.
      await phoneSized(tester);
      await tester.pumpWidget(
          harness.app(home: const HomeShell(initialTab: NavTab.matrix)));
      await pumpFrames(tester);
      expect(find.byType(MatrixScreen), findsOneWidget);
      final navBar = tester.widget<GameNavBar>(
          find.byType(GameNavBar, skipOffstage: false));
      expect(navBar.currentIndex, 0);
    });
  });
}
