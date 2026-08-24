// The deep sweep behind the custom theme.
//
// custom_theme_preset_test.dart proves the guard and the derivation on their
// own. This file proves the PIPELINE: every colour a user can reach, through
// the guard, into ThemePreset.custom, into GameColors, and out the other side
// as the actual pairs the app paints. A picker can be shown twenty colours on
// a device in an afternoon. It cannot be shown a hundred thousand, and the
// ones that break are never the twenty somebody thought to try.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/theme/color_math.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/core/theme/theme_preset.dart';

double _lum(Color c) {
  double lin(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.red / 255) +
      0.7152 * lin(c.green / 255) +
      0.0722 * lin(c.blue / 255);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  final hi = x > y ? x : y, lo = x > y ? y : x;
  return (hi + 0.05) / (lo + 0.05);
}

/// Every colour reachable by TYPING, at a resolution no human tester gets
/// near: 36 hues x 21 lightnesses x 6 saturations, plus the corners.
Iterable<Color> _typable() sync* {
  for (var h = 0; h < 360; h += 10) {
    for (var l = 0; l <= 20; l++) {
      for (final s in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]) {
        yield HSLColor.fromAHSL(1, h.toDouble(), s, l / 20).toColor();
      }
    }
  }
  yield const Color(0xFF000000);
  yield const Color(0xFFFFFFFF);
}

/// Every position reachable by DRAGGING the picker: the saturation/value
/// field sampled on a grid, at every hue on the bar. Includes all four
/// corners, which is where the degenerate cases live.
Iterable<({double h, double s, double v})> _draggable() sync* {
  for (var h = 0; h < 360; h += 10) {
    for (var s = 0; s <= 10; s++) {
      for (var v = 0; v <= 10; v++) {
        yield (h: h.toDouble(), s: s / 10, v: v / 10);
      }
    }
  }
}


/// sRGB -> CIE L*a*b*, so two colours can be compared the way an eye does
/// rather than the way a luminance ratio does.
(double, double, double) _lab(Color c) {
  double f(int v) {
    final s = v / 255;
    return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = f(c.red), g = f(c.green), b = f(c.blue);
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  double k(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  final fx = k(x), fy = k(y), fz = k(z);
  return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

/// CIE76 colour difference. Below about 2.3 is imperceptible.
double _deltaE(Color a, Color b) {
  final (l1, a1, b1) = _lab(a);
  final (l2, a2, b2) = _lab(b);
  return math.sqrt(
      math.pow(l1 - l2, 2) + math.pow(a1 - a2, 2) + math.pow(b1 - b2, 2));
}

Color _flatten(Color fg, Color bg, double alpha) => Color.fromARGB(
      255,
      (fg.red * alpha + bg.red * (1 - alpha)).round(),
      (fg.green * alpha + bg.green * (1 - alpha)).round(),
      (fg.blue * alpha + bg.blue * (1 - alpha)).round(),
    );

/// The card a square is drawn on.
Color _cardBehind(ThemePreset p, {required bool dark}) =>
    dark ? p.darkSurfaceElevated : p.lightSurfaceHigh;

/// The FILL a completed square shows, per square_state.dart: emerald at 26%
/// in light mode and 34% in dark, over the card behind it.
Color _completedFill(ThemePreset p, {required bool dark}) => _flatten(
      p.emerald,
      _cardBehind(p, dark: dark),
      dark ? 0.34 : 0.26,
    );

/// Its BORDER, which square_state.dart paints at 50% in light mode and 55%
/// in dark. This is the cue that actually does the work: a dark grid colour
/// at 26% opacity is a weak tint, but the same colour at 50% is a strong
/// outline, and measuring only the fill declares squares invisible that a
/// person can see at a glance.
Color _completedBorder(ThemePreset p, {required bool dark}) => _flatten(
      p.emerald,
      _cardBehind(p, dark: dark),
      dark ? 0.55 : 0.5,
    );

/// The pixels an EMPTY square shows: lightSurfaceHL in light mode, and in
/// dark mode a fixed hue-free grey that deliberately ignores the preset.
Color _emptyFill(ThemePreset p, {required bool dark}) =>
    dark ? const Color(0xFF2B2B2B) : p.lightSurfaceHL;

/// And its border.
Color _emptyBorder(ThemePreset p, {required bool dark}) =>
    dark ? p.darkBorder : p.lightBorder;

/// How far apart a completed and an empty square are, judged on whichever
/// of the two cues separates them BETTER. A square only has to be
/// distinguishable, and it is distinguishable if either its fill or its
/// outline gives it away.
double _squareSeparation(ThemePreset p, {required bool dark}) {
  final fill = _deltaE(
      _completedFill(p, dark: dark), _emptyFill(p, dark: dark));
  final border = _deltaE(
      _completedBorder(p, dark: dark), _emptyBorder(p, dark: dark));
  return fill > border ? fill : border;
}


/// The picker's own 48, so "what a user can actually tap" is what gets
/// swept rather than an abstract colour space.
List<Color> _allSwatches() => kCustomSwatchesFlat;

void main() {
  // The label a filled button paints on top of the accent, in each mode.
  // Not a constant: for a custom theme lightTextPrimary is itself derived,
  // so the real label colour depends on the pair being tested.
  Color darkLabel(ThemePreset p) => p.darkBg;
  Color lightLabel(ThemePreset p) => p.lightTextPrimary;

  ThemePreset build(Color accent, Color grid) => ThemePreset.custom(
        id: 'custom',
        nameEn: 'Custom',
        nameAr: 'مخصص',
        accent: fitAccentColour(accent),
        grid: fitGridColour(grid),
      );

  group('typed colours', () {
    test('4536 typable colours all land in band as an accent', () {
      var n = 0;
      for (final c in _typable()) {
        n++;
        final l = fitAccentColour(c).computeLuminance();
        expect(l, greaterThanOrEqualTo(kAccentLuminanceMin), reason: '$c');
        expect(l, lessThanOrEqualTo(kAccentLuminanceMax), reason: '$c');
      }
      expect(n, greaterThan(4500), reason: 'the sweep shrank');
    });

    test('and all land in band as a grid colour', () {
      for (final c in _typable()) {
        final l = fitGridColour(c).computeLuminance();
        expect(l, greaterThanOrEqualTo(kGridLuminanceMin), reason: '$c');
        expect(l, lessThanOrEqualTo(kGridLuminanceMax), reason: '$c');
      }
    });

    test('fitting is idempotent, so a round trip cannot drift', () {
      // Matters because the guard runs at several boundaries (picker, then
      // setCustom, then again on the next boot's restore). If it were not
      // idempotent a colour would creep every time the app started.
      for (final c in _typable()) {
        final once = fitAccentColour(c);
        expect(fitAccentColour(once), once, reason: '$c drifted on refit');
        final onceG = fitGridColour(c);
        expect(fitGridColour(onceG), onceG, reason: '$c drifted on refit');
      }
    });
  });

  group('dragged positions', () {
    test('every point on every hue lands in band, both roles', () {
      var n = 0;
      for (final p in _draggable()) {
        n++;
        for (final accent in [true, false]) {
          final c = fitPickerColour(
            hue: p.h,
            sat: p.s,
            val: p.v,
            accent: accent,
          );
          final l = c.computeLuminance();
          final lo = accent ? kAccentLuminanceMin : kGridLuminanceMin;
          final hi = accent ? kAccentLuminanceMax : kGridLuminanceMax;
          expect(l, greaterThanOrEqualTo(lo),
              reason: 'hue ${p.h} sat ${p.s} val ${p.v} accent=$accent -> $c');
          expect(l, lessThanOrEqualTo(hi),
              reason: 'hue ${p.h} sat ${p.s} val ${p.v} accent=$accent -> $c');
        }
      }
      expect(n, 36 * 11 * 11);
    });

    test('the bottom edge never returns grey when a hue was chosen', () {
      // The bug this function exists for. val 0 is pure black, and lifting
      // the lightness of black can only make grey, so the naive fit threw
      // the user's hue away at exactly the moment they dragged to the
      // darkest part of it.
      for (var h = 0; h < 360; h += 10) {
        for (final s in [0.4, 0.7, 1.0]) {
          final c = fitPickerColour(hue: h.toDouble(), sat: s, val: 0, accent: true);
          final hsv = argbToHsv(c.value);
          expect(hsv.$2, greaterThan(0.05),
              reason: 'hue $h sat $s came back as grey ($c)');
          final drift = (hsv.$1 - h).abs();
          expect(drift < 6.0 || drift > 354.0, isTrue,
              reason: 'hue $h sat $s came back at hue ${hsv.$1} ($c)');
        }
      }
    });

    test('a saturated hue with no headroom desaturates instead of greying', () {
      // Blue peaks at luminance 0.072, well under the accent floor, so no
      // amount of brightening reaches it: the only way out is toward white.
      const blue = 240.0;
      final c = fitPickerColour(hue: blue, sat: 1, val: 1, accent: true);
      expect(c.computeLuminance(), greaterThanOrEqualTo(kAccentLuminanceMin));
      final hsv = argbToHsv(c.value);
      expect(hsv.$2, greaterThan(0.05), reason: 'went grey');
      expect((hsv.$1 - blue).abs(), lessThan(6.0), reason: 'left the blues');
    });
  });

  group('the whole theme, for a wide spread of pairs', () {
    // 24 x 24 = 576 complete themes, each checked on the pairs the app
    // actually paints rather than on the two colours the user picked.
    final seeds = [
      for (var h = 0; h < 360; h += 60)
        for (final s in [0.25, 0.65, 1.0])
          for (final l in [0.15, 0.5, 0.85])
            HSLColor.fromAHSL(1, h.toDouble(), s, l).toColor(),
    ];

    test('a filled button label always clears AA, in both modes', () {
      for (final a in seeds) {
        for (final g in seeds) {
          final p = build(a, g);
          expect(_contrast(darkLabel(p), p.gold), greaterThanOrEqualTo(4.5),
              reason: 'dark button label on ${p.gold} (accent $a grid $g)');
          expect(_contrast(lightLabel(p), p.gold), greaterThanOrEqualTo(4.5),
              reason: 'light button label on ${p.gold} (accent $a grid $g)');
        }
      }
    });

    test('body text always clears AA on every surface, in both modes', () {
      for (final a in seeds) {
        for (final g in seeds) {
          final p = build(a, g);
          for (final bg in [p.darkBg, p.darkSurface, p.darkSurfaceElevated]) {
            expect(_contrast(p.darkTextPrimary, bg), greaterThanOrEqualTo(4.5),
                reason: 'dark text on $bg');
          }
          for (final bg in [p.lightBg, p.lightSurface, p.lightSurfaceHigh]) {
            expect(_contrast(p.lightTextPrimary, bg), greaterThanOrEqualTo(4.5),
                reason: 'light text on $bg');
          }
        }
      }
    });

    test('a completed square stays distinguishable from an empty one', () {
      // What this checks, and why it is not a contrast ratio.
      //
      // A completed square is NOT solid emerald. square_state.dart paints it
      // as emerald at 26% opacity in light mode (34% in dark) with a 50%
      // emerald border, over the card behind it; an empty one is
      // lightSurfaceHL in light mode and a fixed hue-free grey in dark.
      // Measured as a WCAG contrast ratio that composite comes out at
      // 1.02:1 even for the app's own default theme, which is not a bug
      // report, it is proof that the metric is wrong here: what separates a
      // filled square from an empty one is chroma, not luminance.
      //
      // So this measures perceptual distance instead, and it measures BOTH
      // cues, taking whichever separates better. Measuring only the fill
      // declares the brown and teal columns invisible (their darkest tones
      // come out at dE 2.6 as a 26% tint) when their 50% borders are at 6.7
      // and 15.0 and perfectly obvious. The worst pair in the table on the
      // honest metric is 6.6, comfortably past the 2.3 where an eye stops
      // telling two colours apart at all.
      //
      // A hand-TYPED hex can still go lower, and it takes a deliberate
      // near-match of the accent hue at one particular lightness to get
      // there. That is left visible rather than corrected: the sheet's
      // preview strip paints three filled squares beside two empty ones in
      // the live theme, so a pair that vanishes vanishes in front of the
      // person choosing it.
      for (final a in _allSwatches()) {
        for (final g in _allSwatches()) {
          final p = build(a, g);
          expect(_squareSeparation(p, dark: false), greaterThan(4.0),
              reason: 'light: accent $a grid $g vanishes into an empty square');
          expect(_squareSeparation(p, dark: true), greaterThan(4.0),
              reason: 'dark: accent $a grid $g vanishes into an empty square');
        }
      }
    });

    test('GameColors.onEmerald picks a readable glyph for every grid colour',
        () {
      // onEmerald flips black or white on a solid emerald fill. Its 0.1791
      // threshold was chosen when every emerald was a bright green; a custom
      // grid colour can sit anywhere in its band, so the flip has to actually
      // work rather than happen to.
      final restore = GameColors.emerald;
      addTearDown(() => GameColors.emerald = restore);
      for (final g in seeds) {
        GameColors.emerald = fitGridColour(g);
        expect(_contrast(GameColors.onEmerald, GameColors.emerald),
            greaterThanOrEqualTo(4.5),
            reason: 'glyph on ${GameColors.emerald}');
      }
    });

    test('applyPreset leaves GameColors consistent with the preset', () {
      // The last hop, and the one nothing else covers: everything above
      // tests the ThemePreset object, while every screen actually reads
      // GameColors.
      final restoreId = ThemePresets.defaultId;
      addTearDown(() =>
          GameColors.applyPreset(ThemePresets.byId(restoreId)));
      for (final a in [seeds.first, seeds[7], seeds.last]) {
        for (final g in [seeds.first, seeds[13], seeds.last]) {
          final p = build(a, g);
          GameColors.applyPreset(p);
          expect(GameColors.gold, p.gold);
          expect(GameColors.emerald, p.emerald);
          expect(GameColors.background, p.darkBg);
          expect(GameColors.textPrimary, p.darkTextPrimary);
          expect(GameColors.lightTextPrimary, p.lightTextPrimary);
        }
      }
    });
  });
}
