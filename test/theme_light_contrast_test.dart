// Contrast guard for LIGHT mode's accent-derived colours.
//
// The bug this exists to prevent shipped for months and was invisible in
// dark mode, which is how the app is usually looked at: `GameColors.gold`
// is 1.86:1 on the default light background, and the light theme painted
// every OutlinedButton's label, icon AND border in it. Dark mode measures
// 10.09:1 for the same pair, so nothing ever looked wrong to anyone
// testing in dark.
//
// The rule these tests lock down is that light mode never paints TEXT or a
// BORDER in the raw accent — it uses the darkened `goldInk`/`goldEdge`
// derived in ThemePreset instead. That has to hold for all thirteen
// selectable presets AND for any custom accent a Premium user can build,
// which is why the last test sweeps the whole permitted accent space
// rather than spot-checking a few colours.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/core/theme/theme_preset.dart';

/// WCAG AA: 4.5:1 for body text, 3:1 for a border or other non-text UI.
const double kText = 4.5;
const double kNonText = 3.0;

/// Ratios are compared with a hair of slack, because the ink is solved by
/// bisection onto the threshold itself and lands a few ten-thousandths
/// either side of it.
const double kSlack = 0.005;

/// Flatten a translucent [fg] over an opaque [bg], as the compositor does.
/// Contrast is only defined between opaque colours, so anything drawn with
/// an alpha has to come through here first.
Color flatten(Color fg, Color bg) {
  final a = fg.a;
  int ch(double f, double b) =>
      ((f * 255) * a + (b * 255) * (1 - a)).round().clamp(0, 255);
  return Color.fromARGB(
      255, ch(fg.r, bg.r), ch(fg.g, bg.g), ch(fg.b, bg.b));
}

/// Every opaque light-mode surface a button or label can sit on.
List<Color> lightSurfaces(ThemePreset p) =>
    [p.lightBg, p.lightSurface, p.lightSurfaceHigh, p.lightSurfaceHL];

/// The same for dark mode.
List<Color> darkSurfaces(ThemePreset p) =>
    [p.darkBg, p.darkSurface, p.darkSurfaceElevated, p.darkSurfaceHighlight];

void expectPasses(Color fg, ThemePreset p, double bar, String what) {
  for (final bg in lightSurfaces(p)) {
    final r = contrastRatio(fg, bg);
    expect(r, greaterThanOrEqualTo(bar - kSlack),
        reason: '${p.id}: $what measured ${r.toStringAsFixed(2)}:1 on '
            '${bg.toARGB32().toRadixString(16)}, needs $bar:1');
  }
}

void main() {
  // GameTheme.light resolves its text styles through google_fonts,
  // which needs a binding before it can look a font up.
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // applyPreset writes global statics; leave the default in place so a
    // preset set here cannot leak into another test file.
    GameColors.applyPreset(ThemePresets.byId(ThemePresets.defaultId));
  });

  group('the derived light-mode ink clears AA', () {
    for (final p in ThemePresets.selectable) {
      test('${p.id}: ink is text-legible, edge is border-legible', () {
        expectPasses(p.goldInkLight, p, kText, 'goldInk');
        expectPasses(p.emeraldInkLight, p, kText, 'emeraldInk');
        expectPasses(p.goldEdgeLight, p, kNonText, 'goldEdge');
      });
    }

    test('the raw accent is exactly what could NOT be used', () {
      // Not a style assertion — the reason the tokens above exist. If a
      // future palette ever made the raw accent legible on light, this
      // would fail and the extra tokens could be reconsidered.
      final failing = ThemePresets.selectable
          .where((p) => contrastRatio(p.gold, p.lightBg) < kText)
          .length;
      expect(failing, ThemePresets.selectable.length,
          reason: 'every preset accent still fails AA text on its own '
              'light background, so goldInk is still needed');
    });
  });

  group('the light ThemeData actually uses it', () {
    for (final p in ThemePresets.selectable) {
      test('${p.id}: outlined and text buttons are legible', () {
        GameColors.applyPreset(p);
        final t = GameTheme.light;

        final outlined = t.outlinedButtonTheme.style!;
        final fg = outlined.foregroundColor!.resolve({})!;
        final side = outlined.side!.resolve({})!.color;
        expectPasses(fg, p, kText, 'OutlinedButton label');
        expectPasses(side, p, kNonText, 'OutlinedButton border');

        final textFg =
            t.textButtonTheme.style!.foregroundColor!.resolve({})!;
        expectPasses(textFg, p, kText, 'TextButton label');
      });

      test('${p.id}: filled button ink reads on the accent fill', () {
        GameColors.applyPreset(p);
        final style = GameTheme.light.filledButtonTheme.style!;
        final fill = style.backgroundColor!.resolve({})!;
        final ink = style.foregroundColor!.resolve({})!;
        final r = contrastRatio(ink, fill);
        expect(r, greaterThanOrEqualTo(kText - kSlack),
            reason: '${p.id}: FilledButton label is '
                '${r.toStringAsFixed(2)}:1 on its own fill');
      });

      test('${p.id}: nav bar selected label reads over its indicator', () {
        GameColors.applyPreset(p);
        final nav = GameTheme.light.navigationBarTheme;
        final selected = {WidgetState.selected};
        final label = nav.labelTextStyle!.resolve(selected)!.color!;
        final icon = nav.iconTheme!.resolve(selected)!.color!;
        // The indicator is a translucent pill over the bar's own background.
        final onIndicator = flatten(nav.indicatorColor!, p.lightBg);
        for (final entry in {'label': label, 'icon': icon}.entries) {
          final r = contrastRatio(entry.value, onIndicator);
          expect(r, greaterThanOrEqualTo(kNonText - kSlack),
              reason: '${p.id}: nav ${entry.key} is '
                  '${r.toStringAsFixed(2)}:1 on the selected indicator');
        }
      });
    }
  });

  test('the room screens that override the theme still pass', () {
    // Three room buttons set their own foregroundColor/side, so the theme
    // fix cannot reach them and they have to be checked on their own terms.
    // The lobby's border is the one with an alpha on it, which is why it is
    // flattened before being measured rather than taken at face value.
    for (final p in ThemePresets.selectable) {
      GameColors.applyPreset(p);
      // Finale extend + header copy: ink label, edge border.
      expectPasses(GameColors.goldInkLight, p, kText, 'room gold override label');
      expectPasses(GameColors.goldEdgeLight, p, kNonText, 'room gold override border');
      // Lobby pick-time: grid-colour ink label, grid-colour edge border.
      expectPasses(GameColors.emeraldInkLight, p, kText, 'lobby label');
      expectPasses(GameColors.emeraldEdgeLight, p, kNonText, 'lobby border');
    }
  });

  test('the custom bottom bar reads on its own selected pill', () {
    // GameNavBar is hand-drawn and never reads navigationBarTheme, so the
    // theme fix could not reach it. It was measured at 2.24:1 on device
    // (sage preset) with the raw accent, on the one control that stays on
    // screen for the whole session. These are its literal values: a 16%
    // accent pill, with the tab's ink on top.
    for (final p in ThemePresets.selectable) {
      GameColors.applyPreset(p);
      for (final bg in lightSurfaces(p)) {
        final pill = flatten(GameColors.gold.withValues(alpha: 0.16), bg);
        final r = contrastRatio(GameColors.goldInkLight, pill);
        expect(r, greaterThanOrEqualTo(kNonText - kSlack),
            reason: '${p.id}: selected tab ink is '
                '${r.toStringAsFixed(2)}:1 on its own pill');
      }
    }
  });

  group('the fixed semantic stat colours', () {
    // These are NOT preset-driven by design (a Gold stat should look gold
    // under every preset), so their light variants are single fixed
    // constants too. They still have to clear the bar against the darkest
    // light surface ANY preset can produce, which is what this checks.
    final inks = {
      'iconGold': (GameColors.iconGold, GameColors.iconGoldInkLight),
      'iconStreak': (GameColors.iconStreak, GameColors.iconStreakInkLight),
      'iconXp': (GameColors.iconXp, GameColors.iconXpInkLight),
      'iconSuccess': (GameColors.iconSuccess, GameColors.iconSuccessInkLight),
      'iconSleep': (GameColors.iconSleep, GameColors.iconSleepInkLight),
    };

    test('the light ink clears AA text on every preset surface', () {
      for (final e in inks.entries) {
        for (final p in ThemePresets.selectable) {
          expectPasses(e.value.$2, p, kText, '${e.key} light ink');
        }
      }
    });

    test('and on any accent a Premium user can build', () {
      var worst = 99.0;
      var checked = 0;
      for (var h = 0; h < 360; h += 5) {
        for (var s = 1; s <= 10; s++) {
          for (var v = 1; v <= 10; v++) {
            final a = HSVColor.fromAHSV(1, h.toDouble(), s / 10, v / 10).toColor();
            if (!accentColourFits(a)) continue;
            checked++;
            final p = ThemePreset.custom(
                id: 'c', nameEn: 'c', nameAr: 'c', accent: a, grid: a);
            for (final e in inks.entries) {
              for (final bg in lightSurfaces(p)) {
                worst = math.min(worst, contrastRatio(e.value.$2, bg));
              }
            }
          }
        }
      }
      expect(checked, greaterThan(1000));
      expect(worst, greaterThanOrEqualTo(kText - kSlack),
          reason: 'worst fixed icon ink was ${worst.toStringAsFixed(2)}:1');
    });

    test('the raw colours are what could NOT be used, and *Dim was not '
        'the answer either', () {
      // Both halves matter. The raw set fails on light, which is why the
      // ink exists; and the `*Dim` set - the obvious shortcut, since it is
      // already in the palette - clears 3:1 on the pale presets but not on
      // the tinted ones, which is why it was not reused.
      final dims = {
        'iconGold': GameColors.iconGoldDim,
        'iconStreak': GameColors.iconStreakDim,
        'iconSuccess': GameColors.iconSuccessDim,
      };
      for (final e in inks.entries) {
        var worstRaw = 99.0;
        for (final p in ThemePresets.selectable) {
          for (final bg in lightSurfaces(p)) {
            worstRaw = math.min(worstRaw, contrastRatio(e.value.$1, bg));
          }
        }
        expect(worstRaw, lessThan(kNonText),
            reason: '${e.key} raw would now pass on light; the ink could '
                'be reconsidered');
      }
      for (final e in dims.entries) {
        var worstDim = 99.0;
        for (final p in ThemePresets.selectable) {
          for (final bg in lightSurfaces(p)) {
            worstDim = math.min(worstDim, contrastRatio(e.value, bg));
          }
        }
        expect(worstDim, lessThan(kNonText),
            reason: '${e.key}Dim would now clear 3:1 everywhere; reusing it '
                'instead of a dedicated ink could be reconsidered');
      }
    });

    // `gp` reads only Theme.of(context).brightness, so a bare ThemeData is
    // enough here - and deliberately so: pumping GameTheme itself would drag
    // google_fonts into a widget test.
    Future<Map<String, Color>> read(WidgetTester tester, Brightness b) async {
      late Map<String, Color> got;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: b),
        home: Builder(builder: (context) {
          got = {
            'gold': context.gp.iconGold,
            'streak': context.gp.iconStreak,
            'xp': context.gp.iconXp,
            'success': context.gp.iconSuccess,
            'sleep': context.gp.iconSleep,
          };
          return const SizedBox();
        }),
      ));
      return got;
    }

    testWidgets('dark keeps the vivid original', (tester) async {
      final got = await read(tester, Brightness.dark);
      expect(got['gold'], GameColors.iconGold);
      expect(got['streak'], GameColors.iconStreak);
      expect(got['xp'], GameColors.iconXp);
      expect(got['success'], GameColors.iconSuccess);
      expect(got['sleep'], GameColors.iconSleep);
    });

    testWidgets('light takes the ink', (tester) async {
      final got = await read(tester, Brightness.light);
      expect(got['gold'], GameColors.iconGoldInkLight);
      expect(got['streak'], GameColors.iconStreakInkLight);
      expect(got['xp'], GameColors.iconXpInkLight);
      expect(got['success'], GameColors.iconSuccessInkLight);
      expect(got['sleep'], GameColors.iconSleepInkLight);
    });
  });

  group('the fixed semantic alarm colours', () {
    // error and warning are chosen to ALARM, not to read: on light surfaces
    // they measure 1.98:1 and 1.01:1 - warning is very nearly invisible on
    // cream - and error only reaches 4.34:1 even on dark.
    test('their inks clear AA text in both modes', () {
      for (final p in ThemePresets.selectable) {
        for (final bg in lightSurfaces(p)) {
          for (final e in {
            'errorInk': GameColors.errorInkLight,
            'warningInk': GameColors.warningInkLight,
          }.entries) {
            final r = contrastRatio(e.value, bg);
            expect(r, greaterThanOrEqualTo(kText - kSlack),
                reason: '${p.id}: light ${e.key} is '
                    '${r.toStringAsFixed(2)}:1');
          }
        }
        for (final bg in darkSurfaces(p)) {
          for (final e in {
            'errorInk': GameColors.errorInkDark,
            'warningInk': GameColors.warningInkDark,
          }.entries) {
            final r = contrastRatio(e.value, bg);
            expect(r, greaterThanOrEqualTo(kText - kSlack),
                reason: '${p.id}: dark ${e.key} is '
                    '${r.toStringAsFixed(2)}:1');
          }
        }
      }
    });

    test('the raw pair is what could not be used', () {
      final eg = ThemePresets.byId(ThemePresets.defaultId);
      expect(contrastRatio(GameColors.warning, eg.lightSurfaceHL),
          lessThan(kNonText));
      expect(contrastRatio(GameColors.error, eg.lightSurfaceHL),
          lessThan(kText));
    });
  });

  test('inkFor lands any colour on the bar, in either mode', () {
    // The generic primitive, for colours the palette cannot enumerate: a
    // prestige tier's metal, a Matrix quadrant's accent, a habit's custom
    // colour. Swept over the whole hue/sat/value cube, not spot-checked.
    var worstLight = 99.0, worstDark = 99.0;
    var checked = 0;
    for (var h = 0; h < 360; h += 15) {
      for (var sat = 0; sat <= 10; sat += 2) {
        for (var v = 0; v <= 10; v += 2) {
          final c =
              HSVColor.fromAHSV(1, h.toDouble(), sat / 10, v / 10).toColor();
          checked++;
          for (final p in ThemePresets.selectable) {
            for (final bg in lightSurfaces(p)) {
              worstLight = math.min(
                  worstLight, contrastRatio(GameColors.inkFor(c, false), bg));
            }
            for (final bg in darkSurfaces(p)) {
              worstDark = math.min(
                  worstDark, contrastRatio(GameColors.inkFor(c, true), bg));
            }
          }
        }
      }
    }
    expect(checked, greaterThan(500));
    expect(worstLight, greaterThanOrEqualTo(kText - kSlack),
        reason: 'worst inkFor on light was '
            '${worstLight.toStringAsFixed(2)}:1');
    expect(worstDark, greaterThanOrEqualTo(kText - kSlack),
        reason: 'worst inkFor on dark was ${worstDark.toStringAsFixed(2)}:1');
  });

  test('dark clears the same bars, on its own surfaces', () {
    // Dark was left alone at first because the DEFAULT preset measures
    // 7.00:1 there and looked fine. It is the signature-colour presets that
    // fail: Navy's accent is 3.16:1 on its own dark card and Nour Violet's
    // grid colour 1.76:1. The lift is a no-op wherever the preset already
    // passed, so this asserts the bar rather than a fixed colour.
    for (final p in ThemePresets.selectable) {
      GameColors.applyPreset(p);
      final t = GameTheme.dark;
      final outlined = t.outlinedButtonTheme.style!;
      final fg = outlined.foregroundColor!.resolve({})!;
      final side = outlined.side!.resolve({})!.color;
      final textFg = t.textButtonTheme.style!.foregroundColor!.resolve({})!;
      for (final bg in darkSurfaces(p)) {
        for (final entry in {'label': fg, 'text button': textFg}.entries) {
          final r = contrastRatio(entry.value, bg);
          expect(r, greaterThanOrEqualTo(kText - kSlack),
              reason: '${p.id}: dark ${entry.key} is '
                  '${r.toStringAsFixed(2)}:1');
        }
        final rb = contrastRatio(side, bg);
        expect(rb, greaterThanOrEqualTo(kNonText - kSlack),
            reason: '${p.id}: dark border is ${rb.toStringAsFixed(2)}:1');
      }
    }
  });

  test('a preset that already passed in dark is handed back untouched', () {
    // The lift must not repaint presets that were never broken - that is
    // what keeps this a fix rather than a restyle.
    final eg = ThemePresets.byId(ThemePresets.defaultId);
    expect(eg.goldInkDark, eg.gold);
    expect(eg.emeraldInkDark, eg.emerald);
    expect(eg.goldEdgeDark, eg.gold);
  });

  test('every accent a Premium user can build still lands legible', () {
    // ThemePreset.custom accepts any colour inside the accent guard's
    // luminance band, at any hue, so the built-in presets are not the
    // whole input space — and the band's own floor is the proof that the
    // raw accent could never have worked: at luminance 0.26, the darkest
    // accent the guard admits, contrast on cream is still only ~3.3:1.
    var checked = 0;
    var worstInk = 99.0;
    var worstEdge = 99.0;
    for (var h = 0; h < 360; h += 5) {
      for (var s = 1; s <= 10; s++) {
        for (var v = 1; v <= 10; v++) {
          final accent =
              HSVColor.fromAHSV(1, h.toDouble(), s / 10, v / 10).toColor();
          if (!accentColourFits(accent)) continue;
          checked++;
          final p = ThemePreset.custom(
            id: 'custom',
            nameEn: 'c',
            nameAr: 'c',
            accent: accent,
            grid: accent,
          );
          for (final bg in lightSurfaces(p)) {
            final ink = contrastRatio(p.goldInkLight, bg);
            final edge = contrastRatio(p.goldEdgeLight, bg);
            if (ink < worstInk) worstInk = ink;
            if (edge < worstEdge) worstEdge = edge;
          }
        }
      }
    }
    expect(checked, greaterThan(1000),
        reason: 'the sweep should cover a real range of accents');
    expect(worstInk, greaterThanOrEqualTo(kText - kSlack),
        reason: 'worst custom ink was ${worstInk.toStringAsFixed(2)}:1');
    expect(worstEdge, greaterThanOrEqualTo(kNonText - kSlack),
        reason: 'worst custom edge was ${worstEdge.toStringAsFixed(2)}:1');
  });
}
