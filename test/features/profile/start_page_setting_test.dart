// Settings › Look › «أول صفحة»: which of Habits and Tasks the app opens on.
//
// Free (Aziz, 2026-09-30), unlike the bottom bar row above it, so a free
// account picks Tasks without meeting the paywall. The row shows only while
// the bar holds both pages: with one of them removed the app opens on the
// other, and there is nothing to pick.
//
// Harness built in setUp, never in a test body (see LandingHarness).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/nav_layout_provider.dart';
import 'package:grow_daily_v2/core/providers/start_page_provider.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/premium/screens/premium_screen.dart';
import 'package:grow_daily_v2/features/profile/screens/profile_screen.dart';

import '../../helpers/landing_harness.dart';

void main() {
  late LandingHarness h;
  tearDown(() => h.dispose());

  Future<void> open(WidgetTester tester, {Locale? locale}) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        h.app(home: const SettingsLookScreen(), locale: locale));
    await h.settle(tester);
  }

  /// The row itself, not the sheet's tile of the same name.
  Finder row(String label) => find.widgetWithText(InkWell, label);

  group('the default bar', () {
    setUp(() async {
      h = LandingHarness();
      await h.prepare(
        extraOverrides: [premiumAccessProvider.overrideWithValue(false)],
      );
    });

    testWidgets('shows Habits, and a free account picks Tasks',
        (tester) async {
      await open(tester);
      expect(row('Start page'), findsOneWidget);
      expect(
        find.descendant(of: row('Start page'), matching: find.text('Habits')),
        findsOneWidget,
      );

      await tester.tap(row('Start page'));
      await h.settle(tester);
      expect(find.text('The app opens on'), findsOneWidget);

      await tester.tap(find.text('Tasks').last);
      await h.settle(tester);
      expect(find.byType(PremiumScreen), findsNothing);
      expect(h.container.read(startPageProvider), NavTab.matrix);
      expect(find.text('The app opens on'), findsNothing,
          reason: 'a pick closes the sheet');
      expect(
        find.descendant(of: row('Start page'), matching: find.text('Tasks')),
        findsOneWidget,
      );
    });

    testWidgets('reads in Arabic', (tester) async {
      await open(tester, locale: const Locale('ar'));
      expect(row('أول صفحة'), findsOneWidget);
      expect(
        find.descendant(of: row('أول صفحة'), matching: find.text('العادات')),
        findsOneWidget,
      );
      await tester.tap(row('أول صفحة'));
      await h.settle(tester);
      expect(find.text('التطبيق يفتح على'), findsOneWidget);
      expect(find.text('المهام'), findsOneWidget);
    });
  });

  group('a bar without Habits', () {
    setUp(() async {
      h = LandingHarness();
      await h.prepare(extraOverrides: [
        premiumAccessProvider.overrideWithValue(false),
        navLayoutProvider.overrideWith(
            (ref) => NavLayoutNotifier(const [NavTab.profile, NavTab.matrix])),
      ]);
    });

    testWidgets('has no row: the app opens on Tasks', (tester) async {
      await open(tester);
      expect(find.text('Bottom bar'), findsOneWidget);
      expect(row('Start page'), findsNothing);
    });
  });

  group('a bar without Tasks', () {
    setUp(() async {
      h = LandingHarness();
      await h.prepare(extraOverrides: [
        premiumAccessProvider.overrideWithValue(false),
        navLayoutProvider.overrideWith(
            (ref) => NavLayoutNotifier(const [NavTab.grid, NavTab.profile])),
        // Picked before Tasks left the bar.
        startPageProvider.overrideWith((ref) => StartPageNotifier(NavTab.matrix)),
      ]);
    });

    testWidgets('has no row: the app opens on Habits', (tester) async {
      await open(tester);
      expect(row('Start page'), findsNothing);
    });
  });
}
