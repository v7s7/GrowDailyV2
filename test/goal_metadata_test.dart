import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cue.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

void main() {
  group('goal metadata compatibility', () {
    test('existing habits default to build goal type', () {
      final template = IslamicHabitTemplate.fromMap('legacy', {
        'name': 'Legacy habit',
        'category': 'quran',
        'frequencyType': 'daily',
        'frequencyTarget': 1,
        'hasTimer': false,
      });

      expect(template.goalType, GoalType.build);
      expect(template.reductionType, ReductionType.avoid);
    });

    test('canonical category keys display localized labels', () {
      expect(HabitCategory.faith.localizedName(false), 'Faith');
      expect(HabitCategory.faith.localizedName(true), 'الإيمان');
      expect(HabitCategory.health.localizedName(false), 'Health');
      expect(HabitCategory.money.localizedName(true), 'المال');
    });

    test('legacy category keys still display correctly as broader categories', () {
      expect(HabitCategory.quran.localizedName(false), 'Faith');
      expect(HabitCategory.fitness.localizedName(false), 'Health');
      expect(HabitCategory.athkar.toJson(), 'faith');
      expect(HabitCategory.fitness.toJson(), 'health');
    });

    test('build goal creation values serialize with stable keys', () {
      const template = IslamicHabitTemplate(
        id: 'build',
        name: 'Walk 10 minutes',
        description: '',
        cueAfter: 'maghrib',
        category: HabitCategory.health,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        hasTimer: false,
        xpReward: 20,
        goldReward: 8,
      );

      final stored = template.toFirestore();
      expect(stored['goalType'], 'build');
      expect(stored['category'], 'health');
      expect(stored['cueAfter'], 'maghrib');
    });

    test('quit/reduce goal creation stores stable values', () {
      const template = IslamicHabitTemplate(
        id: 'quit',
        name: 'Reduce scrolling',
        description: '',
        cueAfter: 'before_sleep',
        category: HabitCategory.focus,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        goalType: GoalType.quit,
        reductionType: ReductionType.limit,
        limitAmount: 30,
        limitUnit: LimitUnit.minutes,
        hasTimer: false,
        xpReward: 20,
        goldReward: 8,
      );

      final stored = template.toFirestore();
      expect(stored['goalType'], 'quit');
      expect(stored['reductionType'], 'limit');
      expect(stored['limitUnit'], 'minutes');
      expect(stored['category'], 'focus');
    });

    test('preset cue storage remains canonical across languages', () {
      final cue = HabitCue.fromStoredValue('المغرب');
      expect(cue.toStorageValue(), 'maghrib');
      expect(cue.labelForLocale(false), 'Maghrib');
      expect(cue.labelForLocale(true), 'المغرب');
    });

    test('freeform Arabic text remains freeform', () {
      final cue = HabitCue.fromStoredValue('بعد المدرسة');
      expect(cue.toStorageValue(), 'بعد المدرسة');
      expect(cue.labelForLocale(false), 'بعد المدرسة');
    });

    test('localized category labels are display-only, not storage values', () {
      final ar = const S(Locale('ar')).limitUnitLabel(LimitUnit.minutes.name);
      final en = const S(Locale('en')).limitUnitLabel(LimitUnit.minutes.name);
      expect(ar, isNot(en));
      expect(LimitUnit.minutes.toJson(), 'minutes');
    });
  });
}
