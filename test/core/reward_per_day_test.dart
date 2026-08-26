// A habit counted N times a day is worth what it was worth at one time a
// day. These pin the two properties the rest of the feature leans on: the
// slices sum to exactly the day's price, and a target of 1 is untouched.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/utils/xp_calculator.dart';

int _slice(int total, int target, int i) =>
    XpCalculator.rewardSliceForTap(total: total, target: target, tapIndex: i);

int _dayTotal(int total, int target) =>
    List.generate(target, (i) => _slice(total, target, i))
        .fold(0, (a, b) => a + b);

void main() {
  group('one tap a day is exactly what it always was', () {
    test('a target of 1 pays the whole reward on the only tap', () {
      expect(_slice(10, 1, 0), 10);
      expect(_slice(37, 1, 0), 37);
    });

    test('a target of 0 or below is treated as 1, never as a divide by zero', () {
      expect(_slice(10, 0, 0), 10);
      expect(_slice(10, -3, 0), 10);
    });
  });

  group('a day\'s slices sum to the day\'s price, never more', () {
    test('10 XP over 4 taps pays 10, not 40', () {
      expect(_dayTotal(10, 4), 10);
      expect(_slice(10, 4, 0), 2);
      expect(_slice(10, 4, 1), 3);
      expect(_slice(10, 4, 2), 2);
      expect(_slice(10, 4, 3), 3);
    });

    test('nothing evaporates for any target up to the 12 the stepper allows', () {
      for (var target = 1; target <= 12; target++) {
        for (final total in [0, 1, 5, 7, 10, 13, 50, 999]) {
          expect(_dayTotal(total, target), total,
              reason: 'total=$total target=$target lost or gained XP');
        }
      }
    });

    test('a tapIndex past the target cannot mint extra reward', () {
      expect(_slice(10, 4, 99), _slice(10, 4, 3));
    });

    test('every slice is non-negative, so no tap ever costs the user', () {
      for (var target = 1; target <= 12; target++) {
        for (var i = 0; i < target; i++) {
          expect(_slice(7, target, i), greaterThanOrEqualTo(0));
        }
      }
    });
  });

  group('what an unfinished day has already been paid', () {
    test('nothing done has been paid nothing', () {
      expect(XpCalculator.rewardPaidSoFar(total: 10, target: 4, done: 0), 0);
    });

    test('a part-done day refunds only what it earned', () {
      expect(XpCalculator.rewardPaidSoFar(total: 10, target: 4, done: 2), 5);
    });

    test('a finished day has been paid the whole price', () {
      expect(XpCalculator.rewardPaidSoFar(total: 10, target: 4, done: 4), 10);
    });

    test('paid-so-far always equals the slices actually handed over', () {
      for (var target = 1; target <= 12; target++) {
        for (final total in [0, 3, 10, 41]) {
          for (var done = 0; done <= target; done++) {
            final summed = List.generate(done, (i) => _slice(total, target, i))
                .fold(0, (a, b) => a + b);
            expect(XpCalculator.rewardPaidSoFar(total: total, target: target, done: done),
                summed,
                reason: 'total=$total target=$target done=$done');
          }
        }
      }
    });

    test('a single-tap habit is all-or-nothing, as it always was', () {
      expect(XpCalculator.rewardPaidSoFar(total: 10, target: 1, done: 0), 0);
      expect(XpCalculator.rewardPaidSoFar(total: 10, target: 1, done: 1), 10);
    });
  });
}
