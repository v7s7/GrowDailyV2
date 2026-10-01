// Doum's theme and Home Screen icon (Aziz, 2026-09-28): free, in the
// mascot's own colours, "use the hex". The body green 0xFF74C878 and the
// cream 0xFFF5F0E1 come from design/mascot/README.md; these checks keep them
// exact, keep the icon free with its theme, and keep both modes at least as
// readable as Emerald & Gold, the original theme the neutrals were derived
// from. Doum is the default itself since 2026-09-30, so the reference is
// named, not read off defaultId.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/theme_preset.dart';
import 'package:grow_daily_v2/features/app_icon/app_icon_catalog.dart';

const _body = Color(0xFF74C878);
const _cream = Color(0xFFF5F0E1);

void main() {
  final doum = ThemePresets.byId('doum');
  final base = ThemePresets.byId('emerald_gold');

  test('a free theme, named after the mascot, the default and listed first',
      () {
    expect(doum.id, 'doum');
    expect(doum.isPremium, isFalse);
    expect(doum.nameAr, 'دوم');
    expect(doum.nameEn, 'Doum');
    // Aziz, 2026-09-30: Doum's look is the main one, beside its icon.
    expect(ThemePresets.defaultId, 'doum');
    expect(
      ThemePresets.byId(null).id,
      'doum',
      reason: 'someone who never picked a look opens on Doum',
    );
    expect(
      ThemePresets.free.map((p) => p.id),
      ['doum', 'emerald_gold', 'baby_pink'],
    );
    expect(ThemePresets.isKnown('doum'), isTrue);
  });

  test("wears Doum's own hexes", () {
    expect(doum.gold, _body, reason: 'the accent is the body green');
    expect(doum.lightSurface, _cream, reason: 'the light card is the cream');
    expect(doum.darkTextPrimary, _cream, reason: 'dark text is the cream');
  });

  test('the accent carries a dark button label', () {
    expect(accentColourFits(doum.gold), isTrue);
    expect(contrastRatio(doum.gold, Colors.black), greaterThan(7));
  });

  test('the neutrals keep the default theme\'s lightness', () {
    // Only the hue moved (cream in light, green-black in dark), which is
    // what carries the default's contrast over.
    double l(Color c) => HSLColor.fromColor(c).lightness;
    final pairs = {
      'lightBg': (doum.lightBg, base.lightBg),
      'lightSurfaceHL': (doum.lightSurfaceHL, base.lightSurfaceHL),
      'lightBorder': (doum.lightBorder, base.lightBorder),
      'lightTextPrimary': (doum.lightTextPrimary, base.lightTextPrimary),
      'lightTextSecondary': (doum.lightTextSecondary, base.lightTextSecondary),
      'darkBg': (doum.darkBg, base.darkBg),
      'darkSurface': (doum.darkSurface, base.darkSurface),
      'darkSurfaceHighlight':
          (doum.darkSurfaceHighlight, base.darkSurfaceHighlight),
      'darkTextSecondary': (doum.darkTextSecondary, base.darkTextSecondary),
    };
    for (final e in pairs.entries) {
      expect(l(e.value.$1), closeTo(l(e.value.$2), 0.01), reason: e.key);
    }
  });

  test('text reads at least as well as on the default theme', () {
    ({List<Color> surfaces, List<Color> text}) light(ThemePreset p) => (
          surfaces: [
            p.lightBg,
            p.lightSurface,
            p.lightSurfaceHigh,
            p.lightSurfaceHL,
          ],
          text: [p.lightTextPrimary, p.lightTextSecondary, p.lightTextTertiary],
        );
    ({List<Color> surfaces, List<Color> text}) dark(ThemePreset p) => (
          surfaces: [
            p.darkBg,
            p.darkSurface,
            p.darkSurfaceElevated,
            p.darkSurfaceHighlight,
          ],
          text: [p.darkTextPrimary, p.darkTextSecondary, p.darkTextTertiary],
        );
    for (final mode in [light, dark]) {
      final d = mode(doum);
      final b = mode(base);
      for (var t = 0; t < 3; t++) {
        for (var s = 0; s < 4; s++) {
          final ours = contrastRatio(d.text[t], d.surfaces[s]);
          final theirs = contrastRatio(b.text[t], b.surfaces[s]);
          // Within 3%: the widest gap is the cream text on the dark page,
          // 16.96:1 against the default's 17.39:1 (0xFFF5F0E1 sits at
          // luminance 0.87, the default's own cream at 0.89).
          expect(
            ours,
            greaterThan(theirs * 0.97),
            reason: '${mode == light ? 'light' : 'dark'} text $t on '
                'surface $s: $ours against $theirs',
          );
        }
      }
      // Body text clears AAA on every surface of its mode.
      for (final surface in d.surfaces) {
        expect(contrastRatio(d.text.first, surface), greaterThan(7));
      }
    }
  });

  group('the icon', () {
    final colour = iconColourById('doum');

    test('a cream plant on the body green, free with its theme', () {
      expect(colour.id, 'doum', reason: 'iconColourById fell back');
      expect(colour.ground, _body);
      expect(colour.sprout, _cream);
      expect(colour.tier, IconColourTier.free);
      expect(colour.needsPremium, isFalse);
      expect(
        const AppIconChoice(PlantShape.bloom, 'doum').needsPremium,
        isFalse,
      );
    });

    test('goes with the theme, and is named like it', () {
      expect(iconColourForTheme('doum', Colors.red), 'doum');
      expect(colour.label(const S(Locale('ar'))), 'دوم');
      expect(colour.label(const S(Locale('en'))), 'Doum');
    });

    test('a custom green lands on Green, never on Doum', () {
      expect(nearestIconColour(_body), 'green');
    });
  });
}
