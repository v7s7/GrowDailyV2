// Settings › Personalization › Bottom bar.
//
// Two things are pinned here. The editor really edits the layout the shell
// reads (add, remove, reset all land in navLayoutProvider), and the gate is
// on the EDIT, not on the screen: a free account sees the same editor with
// the lock card above it, every attempt to change something opens the
// paywall and changes nothing, and Reset alone stays open to everyone.
//
// Harness built in setUp, never in a test body (see LandingHarness).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/nav_badges_setting_provider.dart';
import 'package:grow_daily_v2/core/providers/nav_layout_provider.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/shared/providers/nav_badges_provider.dart';
import 'package:grow_daily_v2/features/premium/screens/premium_screen.dart';
import 'package:grow_daily_v2/features/settings/screens/nav_bar_settings_screen.dart';

import '../../helpers/landing_harness.dart';

void main() {
  late LandingHarness h;
  tearDown(() => h.dispose());

  /// Tall enough that every row and the Reset button are on screen: a plain
  /// ListView only builds what is visible, and a finder cannot see a row
  /// that was never built.
  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(402, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await h.pumpApp(tester, home: const NavBarSettingsScreen());
  }

  List<NavTab> layout() => h.container.read(navLayoutProvider);

  /// The remove button on the "your bar" row labelled [label]. Scoped to
  /// the row's own InkWell because the label also appears in the preview
  /// bar at the top of the screen.
  Finder removeButton(String label) => find.descendant(
        of: find.widgetWithText(InkWell, label),
        matching: find.byTooltip('Remove from bar'),
      );

  group('Premium', () {
    setUp(() async {
      h = LandingHarness();
      await h.prepare(
        extraOverrides: [premiumAccessProvider.overrideWithValue(true)],
      );
    });

    testWidgets('adds, removes and resets, and the layout follows',
        (tester) async {
      await open(tester);
      expect(find.text('Your bar  3/5'), findsOneWidget);
      expect(find.text('Make the bar your own'), findsNothing);
      // Habits and Profile show a lock, never a remove button.
      expect(find.byTooltip('Always here'), findsNWidgets(2));

      await tester.tap(find.text('Rooms'));
      await h.settle(tester);
      expect(layout(),
          [NavTab.grid, NavTab.profile, NavTab.matrix, NavTab.rooms]);
      expect(find.text('Your bar  4/5'), findsOneWidget);

      await tester.tap(removeButton('Tasks'));
      await h.settle(tester);
      expect(layout(), [NavTab.grid, NavTab.profile, NavTab.rooms]);

      await tester.tap(find.text('Reset to default'));
      await h.settle(tester);
      expect(layout(), kDefaultNavTabs);
    });

    testWidgets('a full bar says so and stops adding', (tester) async {
      await open(tester);
      await tester.tap(find.text('Rooms'));
      await h.settle(tester);
      await tester.tap(find.text('Progress'));
      await h.settle(tester);
      expect(layout().length, kNavTabsMax);
      expect(find.text('The bar is full. Remove a tab to add another.'),
          findsOneWidget);

      await tester.tap(find.text('Tasbih'));
      await h.settle(tester);
      expect(layout().length, kNavTabsMax, reason: 'a sixth got in');
    });
  });

  group('Free', () {
    setUp(() async {
      h = LandingHarness();
      await h.prepare(
        extraOverrides: [
          premiumAccessProvider.overrideWithValue(false),
          navLayoutProvider.overrideWith((ref) => NavLayoutNotifier(
              const [NavTab.grid, NavTab.profile, NavTab.matrix, NavTab.rooms])),
        ],
      );
    });

    testWidgets('sees the lock, and every edit goes to the paywall',
        (tester) async {
      await open(tester);
      expect(find.text('Make the bar your own'), findsOneWidget);

      await tester.tap(find.text('Progress'));
      await h.settle(tester);
      expect(find.byType(PremiumScreen), findsOneWidget);
      expect(layout().length, 4, reason: 'the add went through anyway');
    });

    testWidgets('the badges switch is free and clears the badge map',
        (tester) async {
      // Not a Premium edit: it lives in this screen but it is a "less"
      // option, and switching it must never open the paywall.
      await open(tester);
      expect(h.container.read(navBadgesEnabledProvider), isTrue);

      await tester.tap(find.byType(Switch));
      await h.settle(tester);
      expect(find.byType(PremiumScreen), findsNothing);
      expect(h.container.read(navBadgesEnabledProvider), isFalse);
      expect(h.container.read(navBadgesProvider), isEmpty,
          reason: 'off means no badge is computed at all');

      // Tapping the row itself flips it too, the way the Dark Mode row
      // in Settings does.
      await tester.tap(find.text('Badges'));
      await h.settle(tester);
      expect(h.container.read(navBadgesEnabledProvider), isTrue);
    });

    testWidgets('but can still go back to the default', (tester) async {
      // A lapsed account keeps the bar it built (access ending takes
      // nothing away) and is never stuck with it.
      await open(tester);
      await tester.tap(find.text('Reset to default'));
      await h.settle(tester);
      expect(find.byType(PremiumScreen), findsNothing);
      expect(layout(), kDefaultNavTabs);
    });
  });
}
