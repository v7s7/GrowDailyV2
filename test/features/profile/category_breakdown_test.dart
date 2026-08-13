// Pure-logic tests for aggregateCategoryCompletions (progress_hub_screen.
// dart) — the rollup that lets DashboardState.categoryCompletions' mixed-
// granularity keys (some fine-grained like 'quran', some already-collapsed
// like 'faith' — see IslamicHabitTemplate.fromMap's category-recovery fix)
// render as one broad-category breakdown instead of splitting what a user
// experiences as the same life area into two rows.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/profile/screens/progress_hub_screen.dart';

void main() {
  group('aggregateCategoryCompletions', () {
    test('rolls fine-grained faith-family keys up and sums them together',
        () {
      final result = aggregateCategoryCompletions({
        'quran': 10,
        'athkar': 5,
        'fasting': 3,
        'sadaqah': 2,
      });
      expect(result, {HabitCategory.faith: 20});
    });

    test('rolls fitness up into health', () {
      final result = aggregateCategoryCompletions({'fitness': 7});
      expect(result, {HabitCategory.health: 7});
    });

    test('an already-broad key combines with fine-grained keys of the same '
        'display category', () {
      // 'faith' here represents completions recorded before the
      // fromMap category-recovery fix shipped (already collapsed at write
      // time); 'quran' represents ones recorded after. Both should land in
      // the same bucket rather than showing as two separate Faith rows.
      final result = aggregateCategoryCompletions({'faith': 4, 'quran': 6});
      expect(result, {HabitCategory.faith: 10});
    });

    test('categories with no fine-grained counterpart pass through as-is',
        () {
      final result =
          aggregateCategoryCompletions({'learning': 3, 'sleep': 1});
      expect(result, {HabitCategory.learning: 3, HabitCategory.sleep: 1});
    });

    test('zero and negative counts are dropped entirely, not shown as 0', () {
      final result = aggregateCategoryCompletions({
        'faith': 5,
        'health': 0,
        'mind': -2,
      });
      expect(result, {HabitCategory.faith: 5});
    });

    test('an unrecognized key falls back to custom rather than throwing', () {
      final result = aggregateCategoryCompletions({'some_removed_key': 1});
      expect(result, {HabitCategory.custom: 1});
    });

    test('empty input produces an empty map', () {
      expect(aggregateCategoryCompletions(const {}), isEmpty);
    });
  });
}
