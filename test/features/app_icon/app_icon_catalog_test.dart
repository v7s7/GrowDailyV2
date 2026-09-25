// The Home Screen icon's rules, all pure (lib/features/app_icon/app_icon_catalog.dart):
// what each icon is called on iOS, which colour a theme gets (the custom
// theme's nearest one included), when the plant grows, and when the
// Ramadan icon can be picked.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/theme_preset.dart';
import 'package:grow_daily_v2/core/utils/ramadan_calendar.dart';
import 'package:grow_daily_v2/features/app_icon/app_icon_catalog.dart';

void main() {
  group('colours', () {
    test('sixteen: the free themes, the Premium themes, then five more', () {
      expect(kIconColours, hasLength(16));
      expect(
        kIconColours
            .where((c) => c.tier == IconColourTier.free)
            .map((c) => c.id),
        ['emerald_gold', 'baby_pink'],
      );
      expect(
        kIconColours.where((c) => c.tier == IconColourTier.premium).length,
        9,
      );
      expect(
        kIconColours
            .where((c) => c.tier == IconColourTier.more)
            .map((c) => c.id),
        kExtraIconColourIds,
      );
      expect(kIconColours.map((c) => c.id).toSet(), hasLength(16));
    });

    test('a colour costs what its theme costs', () {
      for (final preset in ThemePresets.all) {
        expect(
          iconColourById(preset.id).needsPremium,
          preset.isPremium,
          reason: preset.id,
        );
      }
      for (final id in kExtraIconColourIds) {
        expect(iconColourById(id).needsPremium, isTrue, reason: id);
      }
    });
  });

  group('iOS names', () {
    test('the shipped icon has none, every other one is AppIcon-shape-colour',
        () {
      expect(AppIconChoice.shipped.iosName, isNull);
      expect(
        const AppIconChoice(PlantShape.bloom, 'sage').iosName,
        'AppIcon-bloom-sage',
      );
      expect(
        const AppIconChoice(PlantShape.sprout, 'baby_pink').iosName,
        'AppIcon-sprout-baby_pink',
      );
    });

    test('every one of the 64 reads back as itself', () {
      for (final shape in PlantShape.values) {
        for (final colour in kIconColours) {
          final choice = AppIconChoice(shape, colour.id);
          expect(AppIconChoice.fromIosName(choice.iosName), choice);
        }
      }
    });

    test('the Ramadan icon is AppIcon-ramadan, and reads back as itself', () {
      expect(AppIconChoice.ramadan.iosName, 'AppIcon-ramadan');
      expect(
        AppIconChoice.fromIosName('AppIcon-ramadan'),
        AppIconChoice.ramadan,
      );
      expect(AppIconChoice.ramadan.isRamadan, isTrue);
      expect(AppIconChoice.shipped.isRamadan, isFalse);
      // Not a colour for the other shapes: the colour grid never lists it.
      expect(kIconColours.map((c) => c.id), isNot(contains(kRamadanIconId)));
    });

    test('a name this build does not know reads as the shipped icon', () {
      for (final name in [
        'AppIcon-tree-sage',
        'AppIcon-bloom-purple',
        'AppIcon',
        'Something',
        'AppIcon-bloom',
      ]) {
        expect(
          AppIconChoice.fromIosName(name),
          AppIconChoice.shipped,
          reason: name,
        );
      }
    });
  });

  group('the colour that goes with a theme', () {
    test('a built-in theme has its own', () {
      for (final preset in ThemePresets.all) {
        expect(iconColourForTheme(preset.id, Colors.red), preset.id);
      }
    });

    test('the custom theme takes the nearest to its accent', () {
      expect(
        iconColourForTheme(ThemePresets.customId, const Color(0xFF3894EF)),
        'baby_blue',
      );
    });

    // Every swatch of the custom theme's own palette, column by column
    // (red, orange, brown, yellow, green, teal, blue, purple, pink), lands
    // on the icon a person would call the same colour, in all three tones.
    test('all 27 custom swatches land on their colour', () {
      const expected = [
        'red',
        'amber_dusk',
        'brown',
        'yellow',
        'green',
        'ocean',
        'baby_blue',
        'nour_violet',
        'baby_pink',
      ];
      for (final row in kCustomSwatches) {
        for (var i = 0; i < row.length; i++) {
          expect(
            nearestIconColour(row[i]),
            expected[i],
            reason: 'column $i, ${row[i]}',
          );
        }
      }
    });

    test('a grey accent is grey, whatever hue it reports', () {
      expect(nearestIconColour(const Color(0xFF9AA0A6)), 'grey');
      expect(nearestIconColour(const Color(0xFFA7A29B)), 'grey');
    });
  });

  group('Premium', () {
    test('the Ramadan icon is everyone\'s; a colour costs what it costs', () {
      expect(AppIconChoice.ramadan.needsPremium, isFalse);
      expect(
        const AppIconChoice(PlantShape.grown, 'ocean').needsPremium,
        isTrue,
      );
      expect(
        const AppIconChoice(PlantShape.bloom, 'baby_pink').needsPremium,
        isFalse,
      );
    });

    test('another shape from the Ramadan icon comes in the original colours',
        () {
      expect(
        AppIconChoice.ramadan.withShape(PlantShape.grown),
        const AppIconChoice(PlantShape.grown, 'emerald_gold'),
      );
      expect(
        const AppIconChoice(PlantShape.sprout, 'sage')
            .withShape(PlantShape.bloom),
        const AppIconChoice(PlantShape.bloom, 'sage'),
      );
    });
  });

  group('growth', () {
    test('30 full days open the grown plant, 90 the bloom', () {
      expect(grownShapeFor(0), PlantShape.sprout);
      expect(grownShapeFor(29), PlantShape.sprout);
      expect(grownShapeFor(30), PlantShape.grown);
      expect(grownShapeFor(89), PlantShape.grown);
      expect(grownShapeFor(90), PlantShape.bloom);
      expect(grownShapeFor(400), PlantShape.bloom);
    });

    test('what is next, until nothing is', () {
      expect(nextShapeFor(0), PlantShape.grown);
      expect(nextShapeFor(30), PlantShape.bloom);
      expect(nextShapeFor(90), isNull);
    });

    test('full days read right in Arabic, whatever the number', () {
      const ar = S(Locale('ar'));
      expect(ar.fullDaysInSentence(1), 'يوم كامل');
      expect(ar.fullDaysInSentence(2), 'يومين كاملين');
      expect(ar.fullDaysInSentence(5), '5 أيام كاملة');
      expect(ar.fullDaysInSentence(18), '18 يومًا كاملًا');
      expect(ar.fullDaysInSentence(100), '100 يوم كامل');
      expect(ar.fullDaysInSentence(105), '105 أيام كاملة');
      const en = S(Locale('en'));
      expect(en.fullDaysInSentence(1), '1 full day');
      expect(en.fullDaysInSentence(18), '18 full days');
    });
  });

  group('the Ramadan icon\'s window', () {
    // Ramadan 1448 is 8 February to 9 March 2027 (Eid), Umm al-Qura.
    test('opens the day before 1 Ramadan and closes after Eid day', () {
      final w = RamadanIconWindow.at(DateTime(2026, 9, 25, 14))!;
      expect(w.dates.hijriYear, 1448);
      expect(w.opens, DateTime(2027, 2, 7));
      expect(w.closes, DateTime(2027, 3, 10));
      expect(w.isOpenAt(DateTime(2027, 2, 6, 23, 59)), isFalse);
      expect(w.isOpenAt(DateTime(2027, 2, 7)), isTrue);
      expect(w.isOpenAt(DateTime(2027, 3, 9, 23, 59)), isTrue);
      expect(w.isOpenAt(DateTime(2027, 3, 10)), isFalse);
    });

    test('counts the days until it opens', () {
      final now = DateTime(2026, 9, 25, 14);
      expect(RamadanIconWindow.at(now)!.daysUntilOpen(now), 135);
      final eve = DateTime(2027, 2, 6, 21);
      expect(RamadanIconWindow.at(eve)!.daysUntilOpen(eve), 1);
      final inside = DateTime(2027, 2, 20);
      expect(RamadanIconWindow.at(inside)!.daysUntilOpen(inside), 0);
    });

    test('the day after Eid looks ahead to the next Ramadan', () {
      final w = RamadanIconWindow.at(DateTime(2027, 3, 10, 8))!;
      expect(w.dates.hijriYear, 1449);
      expect(w.opens, DateTime(2028, 1, 27));
    });

    test('the calendar has at least ten years left in it', () {
      // When this fails, add the next years from Apple's
      // Calendar(identifier: .islamicUmmAlQura), as ramadan_calendar.dart says.
      final tenYears = DateTime.now().add(const Duration(days: 3653));
      expect(ramadanOnOrAfter(tenYears), isNotNull);
      final table = ramadanTable;
      for (var i = 1; i < table.length; i++) {
        expect(table[i].hijriYear, table[i - 1].hijriYear + 1);
        final length = table[i].eid.difference(table[i].start).inDays;
        expect(
          length,
          inInclusiveRange(29, 30),
          reason: '${table[i].hijriYear}',
        );
      }
    });
  });
}
