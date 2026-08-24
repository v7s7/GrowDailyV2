// The safety net under the custom theme.
//
// Every other preset in this app was hand-authored and eyeballed. The custom
// one is assembled at runtime from two colours a user picked, which means
// nobody reviews it before it renders. These tests are the review.
//
// The single property that matters: a user cannot make their own app
// unreadable. That is guaranteed by construction rather than by luck, because
// ThemePreset.custom only ever changes the HUE of a structural neutral and
// keeps the default preset's saturation and lightness. Contrast is a function
// of relative luminance, which hue barely moves. These tests assert that the
// guarantee actually holds, across every pair the picker can produce.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/theme/theme_preset.dart';

/// WCAG relative luminance contrast ratio.
double _contrast(Color a, Color b) {
  double rl(Color c) {
    double lin(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * lin(c.red / 255) +
        0.7152 * lin(c.green / 255) +
        0.0722 * lin(c.blue / 255);
  }

  final x = rl(a), y = rl(b);
  final hi = x > y ? x : y, lo = x > y ? y : x;
  return (hi + 0.05) / (lo + 0.05);
}

/// The palette the picker offers, read from the real table rather than
/// copied into this file.
///
/// It used to be duplicated here, on the grounds that importing it would
/// pull in most of the app. That stopped being true once the table moved
/// next to the presets it feeds: theme_preset.dart is already imported
/// above, so the copy bought nothing and could only ever drift out of step
/// with the thing it was meant to be guarding.
List<Color> _allSwatches() => kCustomSwatchesFlat;

/// What the eleven hand-authored presets already do on a white surface. A
/// custom theme must not be able to look weaker than a built-in one.
const double _kShippedFloorOnWhite = 1.5;

Iterable<ThemePreset> _everyCombination() sync* {
  final swatches = _allSwatches();
  for (final a in swatches) {
    for (final g in swatches) {
      yield ThemePreset.custom(
        id: 'custom',
        nameEn: 'Custom',
        nameAr: 'مخصص',
        accent: a,
        grid: g,
      );
    }
  }
}

void main() {
  test('the picker offers 27 colours, and all 729 pairs build', () {
    // Three rows of nine. The count is asserted so that shrinking or growing
    // the table is a deliberate act with a test to update, not something
    // that slips through: every contrast guarantee below is only as good as
    // the set it sweeps.
    expect(_allSwatches().length, 27);
    expect(_allSwatches().toSet().length, 27, reason: 'a swatch is duplicated');
    expect(_everyCombination().length, 27 * 27);
  });

  test('no accent can make its own button label unreadable', () {
    // The trap this palette was rebuilt around. The accent is the FILL behind
    // a FilledButton whose label is DARK in BOTH themes (game_theme.dart uses
    // GameColors.background on dark and lightTextPrimary on light), so an
    // accent that is too dark hides its own label. An earlier version of this
    // table had a whole row at 3.8:1, under the 4.5 floor, on every hue.
    const darkThemeLabel = Color(0xFF07100D);
    const lightThemeLabel = Color(0xFF18251F);
    for (final c in _allSwatches()) {
      expect(_contrast(darkThemeLabel, c), greaterThanOrEqualTo(4.5),
          reason: '\$c is too dark to read a dark-theme button label on');
      expect(_contrast(lightThemeLabel, c), greaterThanOrEqualTo(4.5),
          reason: '\$c is too dark to read a light-theme button label on');
    }
  });

  group('no pair of colours can make the app unreadable', () {
    // 729 themes x 6 text/background pairs. Slow to write out by hand,
    // instant to run, and the only way to be sure — a spot check of two or
    // three combinations would have missed nothing and proved nothing.
    test('dark mode body text always clears 4.5:1 on every surface', () {
      for (final p in _everyCombination()) {
        for (final bg in [p.darkBg, p.darkSurface, p.darkSurfaceElevated]) {
          expect(_contrast(p.darkTextPrimary, bg), greaterThanOrEqualTo(4.5),
              reason: 'primary text on $bg');
          expect(_contrast(p.darkTextSecondary, bg), greaterThanOrEqualTo(3.0),
              reason: 'secondary text on $bg');
        }
      }
    });

    test('light mode body text always clears 4.5:1 on every surface', () {
      for (final p in _everyCombination()) {
        for (final bg in [p.lightBg, p.lightSurface, p.lightSurfaceHigh]) {
          expect(_contrast(p.lightTextPrimary, bg), greaterThanOrEqualTo(4.5),
              reason: 'primary text on $bg');
          expect(_contrast(p.lightTextSecondary, bg), greaterThanOrEqualTo(3.0),
              reason: 'secondary text on $bg');
        }
      }
    });

    test('borders stay visible against the surface they sit on', () {
      for (final p in _everyCombination()) {
        expect(_contrast(p.darkBorder, p.darkSurface), greaterThan(1.1));
        expect(_contrast(p.lightBorder, p.lightSurface), greaterThan(1.1));
      }
    });
  });

  group('the derivation only ever changes hue', () {
    // This is the mechanism the guarantee above rests on, asserted directly
    // so a future "improvement" that starts tweaking lightness gets caught
    // here rather than in a support ticket about grey-on-grey text.
    test('every structural neutral keeps the default preset lightness', () {
      final def = ThemePresets.byId(ThemePresets.defaultId);
      for (final p in _everyCombination()) {
        void sameLightness(Color a, Color b, String what) {
          expect(
            HSLColor.fromColor(a).lightness,
            closeTo(HSLColor.fromColor(b).lightness, 0.02),
            reason: '$what drifted in lightness',
          );
        }

        sameLightness(p.darkBg, def.darkBg, 'darkBg');
        sameLightness(p.darkSurface, def.darkSurface, 'darkSurface');
        sameLightness(p.darkTextPrimary, def.darkTextPrimary, 'darkTextPrimary');
        sameLightness(p.lightBg, def.lightBg, 'lightBg');
        sameLightness(p.lightSurface, def.lightSurface, 'lightSurface');
        sameLightness(
            p.lightTextPrimary, def.lightTextPrimary, 'lightTextPrimary');
      }
    });

    test('the two chosen colours are used verbatim, not reinterpreted', () {
      // If the user picks a colour, that exact colour is what paints their
      // buttons and their completed squares. Anything else is the app
      // overruling them.
      for (final a in _allSwatches()) {
        for (final g in _allSwatches()) {
          final p = ThemePreset.custom(
            id: 'custom',
            nameEn: 'Custom',
            nameAr: 'مخصص',
            accent: a,
            grid: g,
          );
          expect(p.gold.value, a.value);
          expect(p.emerald.value, g.value);
        }
      }
    });

    test('every offered swatch is usable on both grounds', () {
      // The two chosen colours are the ONLY ones whose lightness the user
      // controls, so they are the only ones that can be too pale or too dark.
      for (final c in _allSwatches()) {
        expect(_contrast(c, const Color(0xFF07100D)), greaterThanOrEqualTo(3.0),
            reason: '\$c is too dim on a dark card');
        expect(_contrast(c, const Color(0xFFFFFFFF)),
            greaterThanOrEqualTo(_kShippedFloorOnWhite),
            reason: '\$c is weaker on white than a built-in preset accent');
      }
    });

    test('within a row, every hue carries the same weight', () {
      // The reason these are constants rather than HSL: at a fixed HSL
      // lightness a yellow is about twice as luminous as a blue, so a
      // "uniform" row produces a palette where some swatches shout. Each was
      // solved for a target luminance instead, and this is what keeps that
      // true if anyone edits the table by eye.
      for (final row in kCustomSwatches) {
        final on = row.map((c) => _contrast(c, const Color(0xFFFFFFFF)));
        final spread = on.reduce(math.max) - on.reduce(math.min);
        expect(spread, lessThan(0.15),
            reason: 'one hue in this row is much louder than the others');
      }
    });

    test('every derived touch is a shade of the colour it came from', () {
      // 2.5 degrees, not 0: the derivation goes HSL -> RGB -> 8-bit and back,
      // and quantising to 256 levels per channel moves the recovered hue by
      // up to a degree or so. That is rounding, not drift — anything that
      // actually wandered off the accent would be tens of degrees out.
      const hueTolerance = 2.5;
      for (final p in _everyCombination()) {
        final accentHue = HSLColor.fromColor(p.gold).hue;
        for (final touch in [
          p.goldDim,
          p.xpBlue,
          p.xpBlueDim,
          p.streakOrange,
          p.streakOrangeDim,
        ]) {
          expect(HSLColor.fromColor(touch).hue, closeTo(accentHue, hueTolerance),
              reason: 'an accent touch wandered off the accent hue');
        }
        expect(
          HSLColor.fromColor(p.emeraldDim).hue,
          closeTo(HSLColor.fromColor(p.emerald).hue, hueTolerance),
        );
      }
    });
  });

  group('the registry', () {
    test('custom is last, so it reads as the escape hatch it is', () {
      expect(ThemePresets.selectable.last.id, ThemePresets.customId);
      expect(ThemePresets.selectable.length, ThemePresets.all.length + 1);
    });

    test('byId round-trips custom without falling back to the default', () {
      expect(ThemePresets.byId(ThemePresets.customId).id,
          ThemePresets.customId);
      expect(ThemePresets.byId('no-such-preset').id, ThemePresets.defaultId);
    });

    test('isKnown accepts custom, and rejects an id from a future build', () {
      // The account sync uses this. Applying an unknown id would silently
      // fall back to the default and then persist THAT back over the newer
      // device's real choice.
      expect(ThemePresets.isKnown(ThemePresets.customId), isTrue);
      expect(ThemePresets.isKnown(ThemePresets.defaultId), isTrue);
      expect(ThemePresets.isKnown('preset_from_v3'), isFalse);
      expect(ThemePresets.isKnown(null), isFalse);
    });

    test('editing the two colours changes what custom renders', () {
      final before = ThemePresets.custom.gold.value;
      final restoreA = ThemePresets.customAccent;
      final restoreG = ThemePresets.customGrid;
      addTearDown(() {
        ThemePresets.customAccent = restoreA;
        ThemePresets.customGrid = restoreG;
      });

      ThemePresets.customAccent = const Color(0xFF3355FF);
      expect(ThemePresets.custom.gold.value, isNot(before));
      expect(ThemePresets.custom.gold.value, 0xFF3355FF);
    });
  });

  // ── The readability guard ─────────────────────────────────────────────
  //
  // Everything above tests the 48 CURATED swatches, where readability is
  // true by construction because somebody solved for it once. The hex field
  // removes that construction: it accepts 000000 as readily as E4B45F, and
  // "the picker only offers safe colours" stops being a sentence anybody can
  // say. fitAccentColour/fitGridColour are what replace it, so they get the
  // same treatment the palette got — swept, not spot-checked.
  group('the readability guard holds for any colour a user can type', () {
    const darkThemeLabel = Color(0xFF07100D);
    const lightThemeLabel = Color(0xFF18251F);

    /// A dense sweep of the whole colour space: 24 hues x 11 lightnesses x 4
    /// saturations. Deliberately includes the corners a spot check never
    /// reaches — pure black, pure white, fully saturated pure hues, and the
    /// greys where hue is meaningless.
    Iterable<Color> everyColourAUserCouldType() sync* {
      for (var h = 0; h < 360; h += 15) {
        for (var l = 0; l <= 10; l++) {
          for (final s in [0.0, 0.35, 0.7, 1.0]) {
            yield HSLColor.fromAHSL(1, h.toDouble(), s, l / 10).toColor();
          }
        }
      }
      yield const Color(0xFF000000);
      yield const Color(0xFFFFFFFF);
      yield const Color(0xFF14213D); // a real brand navy, the motivating case
    }

    test('a fitted accent always lands inside the band', () {
      for (final c in everyColourAUserCouldType()) {
        final l = fitAccentColour(c).computeLuminance();
        expect(l, greaterThanOrEqualTo(kAccentLuminanceMin),
            reason: '$c came back too dark');
        expect(l, lessThanOrEqualTo(kAccentLuminanceMax),
            reason: '$c came back too pale');
      }
    });

    test('a fitted accent can never hide its own button label', () {
      // The property the whole feature turns on, stated the way a user would
      // experience it rather than as a luminance number.
      for (final c in everyColourAUserCouldType()) {
        final fitted = fitAccentColour(c);
        expect(_contrast(darkThemeLabel, fitted), greaterThanOrEqualTo(4.5),
            reason: '$c fitted to $fitted hides a dark-theme button label');
        expect(_contrast(lightThemeLabel, fitted), greaterThanOrEqualTo(4.5),
            reason: '$c fitted to $fitted hides a light-theme button label');
      }
    });

    test('a fitted grid colour always lands inside its own band', () {
      for (final c in everyColourAUserCouldType()) {
        final l = fitGridColour(c).computeLuminance();
        expect(l, greaterThanOrEqualTo(kGridLuminanceMin), reason: '$c');
        expect(l, lessThanOrEqualTo(kGridLuminanceMax), reason: '$c');
      }
    });

    test('fitting keeps the hue, so the colour is still theirs', () {
      // The difference between a guard and a veto. A navy that is too dark
      // must come back a lighter NAVY, not grey and not a different colour.
      for (final c in everyColourAUserCouldType()) {
        final before = HSLColor.fromColor(c);
        // Hue is meaningless on a grey, and HSLColor reports it as 0 there,
        // so those carry no hue to preserve.
        if (before.saturation < 0.05) continue;
        for (final fitted in [fitAccentColour(c), fitGridColour(c)]) {
          final after = HSLColor.fromColor(fitted);
          // A fit that lands on pure black or pure white has no hue left to
          // report; the bands are nowhere near either, so this never fires.
          if (after.saturation < 0.05) continue;
          // 4 degrees, not 0, because the round trip through an 8-bit
          // Color quantises: on a pale, low-saturation colour the three
          // channels sit within a few counts of each other, so a 1-count
          // rounding is a visible number of degrees while being an
          // invisible change of colour. The band this catches is a fit
          // that walked to a different HUE FAMILY, which is what would
          // make the correction feel like a refusal.
          final drift = (after.hue - before.hue).abs();
          expect(drift < 4.0 || drift > 356.0, isTrue,
              reason: '$c fitted to $fitted moved hue by $drift');
        }
      }
    });

    test('every built-in swatch is already in band, and is left untouched', () {
      // The guard and the curated table have to agree. If they ever disagree,
      // tapping a built-in swatch would silently produce a DIFFERENT colour
      // than the one shown on it, which is the worst outcome of the two.
      for (final c in _allSwatches()) {
        expect(accentColourFits(c), isTrue, reason: '$c is outside the band');
        expect(fitAccentColour(c), c, reason: '$c was altered');
        expect(fitGridColour(c), c, reason: '$c was altered as a grid colour');
      }
    });

    test('the motivating case: a brand navy stays navy and becomes readable', () {
      // 14213D measures 1.01:1 behind a dark button label. Every filled
      // button in the app would render its label invisibly.
      const navy = Color(0xFF14213D);
      expect(_contrast(lightThemeLabel, navy), lessThan(1.1));
      expect(accentColourFits(navy), isFalse);

      final fitted = fitAccentColour(navy);
      expect(_contrast(lightThemeLabel, fitted), greaterThanOrEqualTo(4.5));
      expect(
        (HSLColor.fromColor(fitted).hue - HSLColor.fromColor(navy).hue).abs(),
        lessThan(1.0),
      );
    });

    test('a whole theme built from fitted colours is still readable', () {
      // Closes the loop. The guard hands its output to ThemePreset.custom,
      // so the derivation has to survive colours that came from the fit path
      // rather than from the curated table.
      final samples = [
        const Color(0xFF000000),
        const Color(0xFFFFFFFF),
        const Color(0xFF14213D),
        const Color(0xFF7B0F0F),
        const Color(0xFFFFFEF0),
      ];
      for (final a in samples) {
        for (final g in samples) {
          final p = ThemePreset.custom(
            id: 'custom',
            nameEn: 'Custom',
            nameAr: 'مخصص',
            accent: fitAccentColour(a),
            grid: fitGridColour(g),
          );
          for (final bg in [p.darkBg, p.darkSurface, p.darkSurfaceElevated]) {
            expect(_contrast(p.darkTextPrimary, bg), greaterThanOrEqualTo(4.5),
                reason: 'dark text on $bg for accent $a grid $g');
          }
          for (final bg in [p.lightBg, p.lightSurface, p.lightSurfaceHigh]) {
            expect(_contrast(p.lightTextPrimary, bg), greaterThanOrEqualTo(4.5),
                reason: 'light text on $bg for accent $a grid $g');
          }
        }
      }
    });
  });
}
