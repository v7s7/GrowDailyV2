import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/constants/game_constants.dart';
import 'package:grow_daily_v2/core/utils/xp_calculator.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';

/// Guards the reward-system reconciliation: GameConstants is meant to be the
/// single source of truth for streak-milestone XP and default category
/// rewards. These tests fail loudly if a future edit reintroduces a second,
/// drifting copy of any of these numbers.
void main() {
  group('streak milestone bonus — single source of truth', () {
    test('GameConstants.streakBonuses holds the reconciled live values', () {
      // These are the values that were actually being paid out by
      // DashboardNotifier before reconciliation (the old GameConstants
      // duplicate under-paid 7/14/30/60/100-day milestones).
      expect(GameConstants.streakBonuses, {
        3: 25,
        7: 75,
        14: 150,
        30: 300,
        60: 600,
        100: 1500,
      });
    });

    test('XpCalculator.streakMilestoneBonus reads GameConstants directly',
        () {
      for (final entry in GameConstants.streakBonuses.entries) {
        expect(XpCalculator.streakMilestoneBonus(entry.key), entry.value);
      }
      // A non-milestone day awards nothing.
      expect(XpCalculator.streakMilestoneBonus(4), 0);
    });

    test('dashboard_notifier.milestoneXpBonus delegates to XpCalculator '
        '(no second copy of the numbers)', () {
      for (final entry in GameConstants.streakBonuses.entries) {
        expect(milestoneXpBonus(entry.key), entry.value);
      }
    });

    test('kStreakMilestones is derived from GameConstants, not hand-copied',
        () {
      expect(kStreakMilestones, GameConstants.streakBonuses.keys.toList());
    });
  });

  group('category rewards — single source of truth', () {
    test(
        'GameConstants.categoryXpRewards/categoryGoldRewards cover every '
        'HabitCategory', () {
      for (final c in HabitCategory.values) {
        expect(GameConstants.categoryXpRewards[c.name], isNotNull,
            reason: 'missing XP default for ${c.name}');
        expect(GameConstants.categoryGoldRewards[c.name], isNotNull,
            reason: 'missing Gold default for ${c.name}');
      }
    });

    test("'custom' holds the value that was actually live, not the stale "
        'lower one', () {
      // Reconciled: CustomHabitsNotifier was actually paying (20, 8) for
      // custom-category habits while the old GameConstants copy said
      // (10, 5). The live value won per the "don't silently change an
      // economy players are already in" rule.
      expect(GameConstants.categoryXpRewards['custom'], 20);
      expect(GameConstants.categoryGoldRewards['custom'], 8);
    });

    group('CustomHabitsNotifier reads rewards from GameConstants', () {
      late Directory tmp;

      setUp(() async {
        tmp = await Directory.systemTemp.createTemp('reward_const_test_');
        Hive.init(tmp.path);
        await Hive.openBox<dynamic>(GameConstants.boxHabits);
      });

      tearDown(() async {
        await Hive.deleteFromDisk();
        await tmp.delete(recursive: true);
      });

      test('a new custom habit gets exactly the GameConstants default for '
          'its category', () async {
        final notifier = CustomHabitsNotifier(null);
        // Let the notifier's own async guest-load finish first so it can't
        // race with (and clobber) the synchronous `add()` calls below.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        for (final c in HabitCategory.values) {
          notifier.add(
            name: 'Test ${c.name}',
            category: c,
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
          );
        }
        final byCategory = {for (final h in notifier.state) h.category: h};
        for (final c in HabitCategory.values) {
          expect(byCategory[c]!.xpReward, GameConstants.categoryXpRewards[c.name]);
          expect(
              byCategory[c]!.goldReward, GameConstants.categoryGoldRewards[c.name]);
        }
      });
    });
  });
}
