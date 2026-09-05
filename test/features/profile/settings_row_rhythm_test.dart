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
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/profile/screens/profile_screen.dart';

void main() {
  Future<void> pumpSettings(WidgetTester tester,
      {Locale locale = const Locale('en')}) async {
    await tester.binding.setSurfaceSize(const Size(402, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
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
          home: const SettingsScreen(),
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

  testWidgets('every Personalization row is the same height', (tester) async {
    await pumpSettings(tester);

    final dark = rowHeight(tester, 'Dark Mode');
    final appearance = rowHeight(tester, 'Appearance');
    final font = rowHeight(tester, 'Font');
    final language = rowHeight(tester, 'Language');

    expect({appearance, font, language}, hasLength(1),
        reason: 'the plain text rows drifted apart from each other: '
            '$appearance / $font / $language');
    // The toggle row is allowed a hair of slack (the Switch is a fixed
    // 40pt once shrink-wrapped, and rounding can leave a pixel), but not
    // the 22pt gap the un-compensated version had.
    expect((dark - appearance).abs(), lessThanOrEqualTo(2),
        reason: 'the Dark Mode row is $dark against $appearance for its '
            'siblings — give the Switch materialTapTargetSize.shrinkWrap '
            'and the row its smaller verticalPadding');
  });

  testWidgets('rows are tall enough to hit comfortably', (tester) async {
    // A rhythm that matched at 20pt would pass the test above and be
    // unusable. This is the other half of the constraint.
    await pumpSettings(tester);
    expect(rowHeight(tester, 'Appearance'), greaterThanOrEqualTo(44));
  });

  testWidgets('a settings row can actually show its ripple', (tester) async {
    // The InkWell must find a Material BETWEEN itself and the Scaffold —
    // the group card — or its ink paints below that card's opaque fill and
    // is never seen. Asserting the tree shape is the honest test: the
    // alternative (pumping a press and diffing pixels) tests Flutter's
    // renderer, not this decision.
    await pumpSettings(tester);

    final inkWell = find
        .ancestor(of: find.text('Appearance'), matching: find.byType(InkWell))
        .first;
    final materialsAbove = find.ancestor(
      of: inkWell,
      matching: find.byType(Material),
    );
    expect(materialsAbove, findsWidgets);

    final nearest = tester.widget<Material>(materialsAbove.first);
    expect(nearest.color, isNotNull,
        reason: 'the nearest Material above a settings row paints no color, '
            'so it is not the group card — the ripple will land on the '
            'Scaffold and be hidden under the card');
    expect(nearest.clipBehavior, isNot(Clip.none),
        reason: 'the group card must clip, or the top and bottom rows ripple '
            'past its rounded corners');
  });

  testWidgets('the Arabic screen keeps the same rhythm', (tester) async {
    // RTL flips the row, and a padding written physically instead of
    // directionally would show up here as a different height or a missing
    // row rather than as a subtle misalignment.
    await pumpSettings(tester, locale: const Locale('ar'));

    final dark = rowHeight(tester, 'الوضع الداكن');
    final appearance = rowHeight(tester, 'المظهر');
    expect((dark - appearance).abs(), lessThanOrEqualTo(2),
        reason: 'Arabic rows drifted: $dark vs $appearance');
  });
}
