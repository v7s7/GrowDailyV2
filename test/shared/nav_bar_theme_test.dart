// The nav bar has to take the theme.
//
// Reported: "why is the nav bar not getting coloured". It was two separate
// things, and only one of them was in this file.
//
// The fill read gp.surfaceHigh, which is #FFFFFF in ALL eleven presets and in
// every custom theme. Every other light token shifts hue (bg, surface,
// highlight, border all do); the "high" surface is pinned to pure white on
// purpose, because that is what an elevated card should be. The nav bar is not
// a card, so it was the one surface in the app that could not change: pick
// plum, pick navy, the bar stayed white. Dark mode was fine, because
// surfaceElevated IS themed there.
//
// On top of that the rim was a hardcoded 85 percent white and the unselected
// labels a hardcoded black54, so even a themed fill would have worn a bright
// neutral ring and neutral text.
//
// These assert the bar is different under different presets, which is the
// property that was actually missing, rather than asserting particular hexes
// that a palette edit would have to chase.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/core/theme/theme_preset.dart';
import 'package:grow_daily_v2/shared/widgets/game_nav_bar.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() =>
      GameColors.applyPreset(ThemePresets.byId(ThemePresets.defaultId)));

  Future<void> onIOS(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// The colour the glass bar actually paints, under [preset], in [brightness].
  Future<Color> barFill(
    WidgetTester tester,
    ThemePreset preset,
    Brightness brightness,
  ) async {
    GameColors.applyPreset(preset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: brightness == Brightness.dark ? GameTheme.dark : GameTheme.light,
      home: const Scaffold(bottomNavigationBar: GameNavBar(currentIndex: 0)),
    ));
    await tester.pumpAndSettle();
    final container = tester.widgetList<Container>(find.byType(Container)).
        firstWhere((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.border != null && d.borderRadius != null;
    });
    return ((container.decoration as BoxDecoration).color)!;
  }

  final plum = ThemePreset.custom(
    id: 'plum',
    nameEn: 'Plum',
    nameAr: 'برقوقي',
    accent: const Color(0xFF8E44AD),
    grid: const Color(0xFF2980B9),
  );

  for (final brightness in Brightness.values) {
    final tag = brightness.name;

    testWidgets('[$tag] a custom theme changes the bar', (tester) async {
      await onIOS(() async {
        final base = await barFill(
            tester, ThemePresets.byId(ThemePresets.defaultId), brightness);
        final custom = await barFill(tester, plum, brightness);
        expect(custom, isNot(equals(base)),
            reason: 'the bar painted the same colour under two very '
                'different themes, which is the whole bug');
      });
    });

    testWidgets('[$tag] the shipped presets do not all paint it the same',
        (tester) async {
      await onIOS(() async {
        final seen = <int, List<String>>{};
        for (final p in ThemePresets.selectable) {
          final fill = await barFill(tester, p, brightness);
          (seen[fill.value] ??= []).add(p.id);
        }
        // Deliberately NOT "all twelve differ". Some presets genuinely share a
        // surface tone in the palette table (ocean and rose_ink are both
        // #FFFFFF in light; rose_ink, sage and baby_blue are all #17251E in
        // dark), and that is a question about the palette, not about this
        // widget. What this widget owes is that the bar follows whatever the
        // palette says, which a single shared value across the WHOLE set
        // would disprove.
        expect(seen.length, greaterThan(1),
            reason: 'every preset painted the same bar, so it is reading a '
                'token that does not move');
        expect(seen.length, greaterThanOrEqualTo(6),
            reason: 'only ${seen.length} distinct bars across '
                '${ThemePresets.selectable.length} presets');
      });
    });
  }

  testWidgets('nothing in the bar is hardcoded white any more', (tester) async {
    await onIOS(() async {
      GameColors.applyPreset(plum);
      await tester.pumpWidget(MaterialApp(
        theme: GameTheme.light,
        home: const Scaffold(bottomNavigationBar: GameNavBar(currentIndex: 0)),
      ));
      await tester.pumpAndSettle();
      for (final c in tester.widgetList<Container>(find.byType(Container))) {
        final d = c.decoration;
        if (d is! BoxDecoration) continue;
        final side = d.border?.top;
        if (side == null) continue;
        expect(side.color.value, isNot(0xD9FFFFFF),
            reason: 'the 85 percent white rim is back');
      }
    });
  });
}
