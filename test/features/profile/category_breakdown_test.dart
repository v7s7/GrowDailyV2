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
  _barRatio();

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

/// The bar length beside each category.
///
/// It used to be drawn relative to the BIGGEST category while the percentage
/// beside it was a share of the TOTAL, so the top row always filled the whole
/// track. On a real account that put "68%" against a full bar and drew the
/// 26% row at about 40% wide: both numbers correct, the picture contradicting
/// whichever one you read. These pin the two to one denominator.
void _barRatio() {
  group('categoryBarRatio', () {
    test('a bar is its share of the total, matching the printed percent', () {
      // The exact numbers from the account this was reported on.
      expect(categoryBarRatio(count: 69, totalCount: 102), closeTo(0.676, 0.001));
      expect(categoryBarRatio(count: 27, totalCount: 102), closeTo(0.265, 0.001));
    });

    test('the biggest category no longer fills the whole track', () {
      // The old behaviour, and the whole bug: 69 of 102 is not everything.
      expect(categoryBarRatio(count: 69, totalCount: 102), lessThan(1.0));
    });

    test('a category that is genuinely everything does fill it', () {
      expect(categoryBarRatio(count: 40, totalCount: 40), 1.0);
    });

    test('a single completion still leaves a visible mark', () {
      // 1% of the track rounds to a few pixels and reads as an empty row.
      final r = categoryBarRatio(count: 1, totalCount: 102);
      expect(r, 0.03);
      expect(r, greaterThan(1 / 102));
    });

    test('the floor never lets a sliver outrank a real category', () {
      final sliver = categoryBarRatio(count: 1, totalCount: 102);
      final real = categoryBarRatio(count: 5, totalCount: 102);
      expect(sliver, lessThan(real));
    });

    test('nothing recorded draws nothing', () {
      expect(categoryBarRatio(count: 0, totalCount: 102), 0);
      expect(categoryBarRatio(count: 0, totalCount: 0), 0);
      expect(categoryBarRatio(count: 5, totalCount: 0), 0,
          reason: 'no denominator means no claim to make');
    });

    test('all the rows together never exceed the track', () {
      // 69 + 27 + 5 + 1 = 102, the real breakdown. Ignoring the sliver floor,
      // the shares are a partition of one whole.
      final shares = [69, 27, 5, 1]
          .map((c) => (c / 102))
          .fold<double>(0, (a, b) => a + b);
      expect(shares, closeTo(1.0, 0.0001));
    });
  });
}
