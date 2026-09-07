// The ladder a day's step count climbs, and the one direction it may move a
// square.
//
// Aziz, 2026-09-07: the steps counted and showed all day, then the day rolled
// over and the row read as if nobody had moved. Only the goal used to leave a
// square; anything short of it left nothing, and the live count is today's
// alone. Now half the goal leaves a جزئي, the goal the green square, and
// twenty percent over the blue إنجاز إضافي, and the end-of-day read writes
// the same ladder into yesterday's square. Upwards only: a count never
// undoes a mark, and never touches فشل or تخطّي.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/step_auto_complete.dart';

void main() {
  group('stepSquareFor, goal 10,000', () {
    SquareState at(int steps) => stepSquareFor(steps: steps, goal: 10000);

    test('below half the goal the day stays empty', () {
      expect(at(0), SquareState.none);
      expect(at(300), SquareState.none, reason: 'a walk to the kitchen');
      expect(at(4999), SquareState.none);
    });

    test('half the goal is a جزئي, and stays one right up to the goal', () {
      expect(at(5000), SquareState.partial);
      expect(at(9000), SquareState.partial, reason: 'the 9,000 Aziz named');
      expect(at(9999), SquareState.partial);
    });

    test('the goal is the green square', () {
      expect(at(10000), SquareState.complete);
      expect(at(11999), SquareState.complete);
    });

    test('twenty percent over the goal is the blue one', () {
      expect(at(12000), SquareState.bonus);
      expect(at(30000), SquareState.bonus);
    });

    test('an odd goal rounds the shares the way arithmetic does', () {
      // Half of 7,001 is 3,500.5 and a fifth over it is 8,401.2, so the
      // step just below each line stays on the lower rung.
      expect(stepSquareFor(steps: 3500, goal: 7001), SquareState.none);
      expect(stepSquareFor(steps: 3501, goal: 7001), SquareState.partial);
      expect(stepSquareFor(steps: 8401, goal: 7001), SquareState.complete);
      expect(stepSquareFor(steps: 8402, goal: 7001), SquareState.bonus);
    });

    test('a habit with no usable goal earns nothing from a count', () {
      expect(stepSquareFor(steps: 5000, goal: 0), SquareState.none);
      expect(stepSquareFor(steps: 5000, goal: -1), SquareState.none);
    });
  });

  group('stepCountMayLift', () {
    test('climbs the ladder one or several rungs', () {
      expect(stepCountMayLift(SquareState.none, SquareState.partial), isTrue);
      expect(stepCountMayLift(SquareState.none, SquareState.bonus), isTrue);
      expect(stepCountMayLift(SquareState.partial, SquareState.complete), isTrue);
      expect(stepCountMayLift(SquareState.complete, SquareState.bonus), isTrue);
    });

    test('never steps down or stays put', () {
      expect(stepCountMayLift(SquareState.complete, SquareState.partial), isFalse,
          reason: 'a stale read must not undo a paid day');
      expect(stepCountMayLift(SquareState.bonus, SquareState.complete), isFalse);
      expect(stepCountMayLift(SquareState.partial, SquareState.partial), isFalse);
      expect(stepCountMayLift(SquareState.none, SquareState.none), isFalse);
    });

    test("never moves the owner's own word about the day", () {
      for (final theirs in [SquareState.failed, SquareState.skipped]) {
        for (final to in SquareState.values) {
          expect(stepCountMayLift(theirs, to), isFalse, reason: '$theirs -> $to');
        }
      }
    });

    test('the blue square is the top of the ladder', () {
      for (final to in SquareState.values) {
        expect(stepCountMayLift(SquareState.bonus, to), isFalse);
      }
    });
  });
}
