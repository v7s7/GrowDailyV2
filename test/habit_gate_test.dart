import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/habits/catalog/habit_plans.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

void main() {
  group('habitLimitFor — the monetization seam', () {
    test('guests trial 5 habits', () {
      expect(habitLimitFor(isGuest: true, isPremium: false), kGuestHabitLimit);
      expect(kGuestHabitLimit, 5);
    });

    // The reason the guest cap is five and not three. The plan picker checks
    // a whole plan against the cap in one go (canAddHabits with
    // additionalCount), so a plan bigger than the cap can never be started
    // by a guest at all: at three, «الصلوات الخمس» met the create-an-account
    // sheet on its first tap, before a single day was tracked.
    test('a guest can start the five daily prayers plan', () {
      final prayers = habitPlans.firstWhere((p) => p.id == 'five_daily_prayers');
      expect(prayers.catalogIds, hasLength(5));
      expect(prayers.catalogIds.length, lessThanOrEqualTo(kGuestHabitLimit));
    });

    test('free accounts get the generous free cap', () {
      expect(habitLimitFor(isGuest: false, isPremium: false), kFreeHabitLimit);
      expect(kFreeHabitLimit, 10);
    });

    test('the guest cap stays below the free cap', () {
      // Making an account has to be worth something.
      expect(kGuestHabitLimit, lessThan(kFreeHabitLimit));
    });

    test('premium is uncapped regardless of guest state', () {
      expect(habitLimitFor(isGuest: false, isPremium: true), isNull);
      expect(habitLimitFor(isGuest: true, isPremium: true), isNull);
    });
  });
}
