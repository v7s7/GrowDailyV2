import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

// The new-install trial's window math, pinned pure the same way the
// history gate's is: no Riverpod, no RevenueCat, no real clock.
void main() {
  final start = DateTime(2026, 8, 28, 10, 0);

  group('trialIsActive', () {
    test('open the moment it starts', () {
      expect(trialIsActive(start: start, now: start), isTrue);
    });

    test('open just before the window closes', () {
      final now = start
          .add(const Duration(days: kTrialDays))
          .subtract(const Duration(minutes: 1));
      expect(trialIsActive(start: start, now: now), isTrue);
    });

    test('closed exactly at the boundary and after', () {
      final end = start.add(const Duration(days: kTrialDays));
      expect(trialIsActive(start: start, now: end), isFalse);
      expect(
        trialIsActive(start: start, now: end.add(const Duration(days: 30))),
        isFalse,
      );
    });
  });

  group('trialDaysLeft', () {
    test('a full window reports every day', () {
      expect(trialDaysLeft(start: start, now: start), kTrialDays);
    });

    test('a partial day still counts as a day, never zero while open', () {
      final now = start
          .add(Duration(days: kTrialDays - 1))
          .add(const Duration(hours: 12));
      expect(trialDaysLeft(start: start, now: now), 1);
    });

    test('zero once closed, never negative', () {
      final end = start.add(const Duration(days: kTrialDays));
      expect(trialDaysLeft(start: start, now: end), 0);
      expect(
        trialDaysLeft(start: start, now: end.add(const Duration(days: 5))),
        0,
      );
    });
  });
}
