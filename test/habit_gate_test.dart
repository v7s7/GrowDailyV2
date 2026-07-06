import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

void main() {
  group('habitLimitFor — the monetization seam', () {
    test('guests trial 3 habits', () {
      expect(habitLimitFor(isGuest: true, isPremium: false), kGuestHabitLimit);
      expect(kGuestHabitLimit, 3);
    });

    test('free accounts get the generous free cap', () {
      expect(habitLimitFor(isGuest: false, isPremium: false), kFreeHabitLimit);
      expect(kFreeHabitLimit, 10);
    });

    test('premium is uncapped regardless of guest state', () {
      expect(habitLimitFor(isGuest: false, isPremium: true), isNull);
      expect(habitLimitFor(isGuest: true, isPremium: true), isNull);
    });
  });
}
