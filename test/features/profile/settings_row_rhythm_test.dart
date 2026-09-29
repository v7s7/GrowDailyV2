// Settings was rebuilt around one row anatomy, and "one rhythm" is the
// whole point of that rewrite — so it is measured rather than trusted.
//
// Two things this pins, both found by an adversarial review of the
// redesign rather than by looking at the screen:
//
//  1. ROW HEIGHT. A Material 3 Switch carries its own 48pt padded tap
//     target, so the Dark Mode row rendered 68pt against its siblings'
//     46pt — the first row of the first card, half again as tall as
//     everything under it, on a screen whose stated goal was one rhythm.
//     The old hand-built code had compensated with a per-row padding; the
//     rewrite lost that compensation and nobody would have noticed from a
//     screenshot.
//
//  2. RIPPLES. An InkWell paints onto the nearest Material ANCESTOR. With
//     the group card as a plain Container the nearest one was the
//     Scaffold's, so every ripple painted underneath the card's opaque
//     surface and no settings row — Sign Out included — showed any
//     pressed feedback at all. Invisible in a screenshot, obvious under a
//     finger.
//
// Since 2026-09-28 Settings is five rows that each open a page (Aziz picked
// option C of the Settings canvas). The rows moved, the rules did not: the
// first page has its own rhythm (one height for its five rows), and each
// inner page keeps the old one.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/constants/game_constants.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/profile/screens/profile_screen.dart';
import 'package:grow_daily_v2/features/settings/widgets/notification_summary.dart';
import 'package:hive/hive.dart';

void main() {
  // The Prayer location row shows the saved place, which its notifier reads
  // from the settings box. Opened here, before any test body: real disk I/O
  // started inside testWidgets never finishes (see LandingHarness).
  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('settings_rhythm_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>(GameConstants.boxSettings);
  });

  Future<void> pumpPage(WidgetTester tester, Widget page,
      {Locale locale = const Locale('en')}) async {
    await tester.binding.setSurfaceSize(const Size(402, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The phone's answer, without the notifications plugin.
          systemNotificationPermissionProvider
              .overrideWithValue(() async => true),
        ],
        child: MaterialApp(
          // S reads Localizations.localeOf, so setting the app's locale is
          // what puts this screen into Arabic — same as production.
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // Light: pure const styles, no runtime font fetching (see
          // LandingHarness for the same reasoning).
          theme: GameTheme.light,
          home: page,
        ),
      ),
    );
    await tester.pump();
  }

  /// The height of the row whose label is [label], measured on the InkWell
  /// that actually carries the tap — the same box a finger lands on.
  double rowHeight(WidgetTester tester, String label) {
    final inkWell = find.ancestor(
      of: find.text(label),
      matching: find.byType(InkWell),
    );
    expect(inkWell, findsWidgets,
        reason: 'no tappable row found for "$label" — if the label changed, '
            'update this finder rather than deleting the assertion');
    return tester.getSize(inkWell.first).height;
  }

  const firstPage = [
    'Notifications',
    'Look',
    'Language and prayer location',
    'Help',
    'Account',
  ];

  testWidgets('the first page\'s five rows are one height', (tester) async {
    await pumpPage(tester, const SettingsScreen());
    final heights = {for (final l in firstPage) rowHeight(tester, l)};
    expect(heights, hasLength(1),
        reason: 'the first page\'s rows drifted apart: $heights');
    expect(heights.single, greaterThanOrEqualTo(44));
  });

  testWidgets('every Look row is the same height', (tester) async {
    await pumpPage(tester, const SettingsLookScreen());

    final dark = rowHeight(tester, 'Dark Mode');
    final appearance = rowHeight(tester, 'Appearance');
    final font = rowHeight(tester, 'Font');
    final bar = rowHeight(tester, 'Bottom bar');
    final doum = rowHeight(tester, 'Doum on the Habits page');

    expect({appearance, font, bar}, hasLength(1),
        reason: 'the plain text rows drifted apart from each other: '
            '$appearance / $font / $bar');
    // The toggle rows are allowed a hair of slack (the Switch is a fixed
    // 40pt once shrink-wrapped, and rounding can leave a pixel), but not
    // the 22pt gap the un-compensated version had.
    for (final toggle in [dark, doum]) {
      expect((toggle - appearance).abs(), lessThanOrEqualTo(2),
          reason: 'a switch row is $toggle against $appearance for its '
              'siblings — give the Switch materialTapTargetSize.shrinkWrap '
              'and the row its smaller verticalPadding');
    }
  });

  testWidgets('the prayer location sits under Language and names the place',
      (tester) async {
    await pumpPage(tester, const SettingsLanguagePlaceScreen());
    final language = tester.getTopLeft(find.text('Language')).dy;
    final place = tester.getTopLeft(find.text('Prayer location')).dy;
    expect(place, greaterThan(language));
    expect(rowHeight(tester, 'Language'), rowHeight(tester, 'Prayer location'));
    // Nothing saved in this test's box.
    expect(find.text('Not set'), findsOneWidget);
  });

  testWidgets('rows are tall enough to hit comfortably', (tester) async {
    // A rhythm that matched at 20pt would pass the tests above and be
    // unusable. This is the other half of the constraint.
    await pumpPage(tester, const SettingsLookScreen());
    expect(rowHeight(tester, 'Appearance'), greaterThanOrEqualTo(44));
  });

  /// The InkWell must find a Material BETWEEN itself and the Scaffold —
  /// the group card — or its ink paints below that card's opaque fill and
  /// is never seen. Asserting the tree shape is the honest test: the
  /// alternative (pumping a press and diffing pixels) tests Flutter's
  /// renderer, not this decision.
  void expectRippleShows(WidgetTester tester, String label) {
    final inkWell = find
        .ancestor(of: find.text(label), matching: find.byType(InkWell))
        .first;
    final materialsAbove = find.ancestor(
      of: inkWell,
      matching: find.byType(Material),
    );
    expect(materialsAbove, findsWidgets);

    final nearest = tester.widget<Material>(materialsAbove.first);
    expect(nearest.color, isNotNull,
        reason: 'the nearest Material above "$label" paints no color, '
            'so it is not the group card — the ripple will land on the '
            'Scaffold and be hidden under the card');
    expect(nearest.clipBehavior, isNot(Clip.none),
        reason: 'the group card must clip, or the top and bottom rows ripple '
            'past its rounded corners');
  }

  testWidgets('a settings row can actually show its ripple', (tester) async {
    await pumpPage(tester, const SettingsScreen());
    expectRippleShows(tester, 'Look');
    await pumpPage(tester, const SettingsLookScreen());
    expectRippleShows(tester, 'Appearance');
    await pumpPage(tester, const SettingsAccountScreen());
    expectRippleShows(tester, 'Sign Out');
  });

  testWidgets('a section heading has no letter spacing', (tester) async {
    // Letter spacing pulls joined Arabic letters apart; the old 11pt
    // headings with letterSpacing 1.5 read broken in the app's main
    // language (2026-09-28).
    await pumpPage(tester, const SettingsLookScreen(),
        locale: const Locale('ar'));
    final heading = tester.widget<Text>(find.text('الصفحات'));
    expect(heading.style?.letterSpacing ?? 0, 0);
    expect(heading.style?.fontSize, greaterThanOrEqualTo(13));
  });

  testWidgets('the Arabic pages keep the same rhythm', (tester) async {
    // RTL flips the row, and a padding written physically instead of
    // directionally would show up here as a different height or a missing
    // row rather than as a subtle misalignment.
    await pumpPage(tester, const SettingsScreen(), locale: const Locale('ar'));
    final hub = {
      for (final l in ['الإشعارات', 'الشكل', 'اللغة وموقع الصلاة', 'المساعدة', 'الحساب'])
        rowHeight(tester, l),
    };
    expect(hub, hasLength(1), reason: 'Arabic first-page rows drifted: $hub');

    await pumpPage(tester, const SettingsLookScreen(),
        locale: const Locale('ar'));
    final dark = rowHeight(tester, 'الوضع الداكن');
    final appearance = rowHeight(tester, 'المظهر');
    expect((dark - appearance).abs(), lessThanOrEqualTo(2),
        reason: 'Arabic rows drifted: $dark vs $appearance');
  });
}
