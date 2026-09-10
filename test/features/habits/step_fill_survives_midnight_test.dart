import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/step_auto_complete.dart';

/// The walk that used to vanish at midnight.
///
/// Reported by Aziz on 2026-09-10: "it records correctly from the app, but
/// later when it hits 00:00 it becomes zero, like the user never walked."
/// The cause was not a write being overwritten. Nothing was ever written:
/// below half the goal the ladder leaves no square by design
/// ([kStepPartialShare]), so the only trace of the walk was a fill the board
/// drew from the LIVE count, and only for `day.isToday`. The day itself was
/// the thing that expired.
///
/// The fill rule no longer takes a day, which is the fix stated as a type:
/// whichever day the caller has a count for gets its fill.
void main() {
  group('stepsMapWith', () {
    const today = '2026-09-10';

    test('a first count for a day is recorded', () {
      expect(stepsMapWith(const {}, today, 4000), {today: 4000});
    });

    test('a bigger count for the same day replaces it', () {
      expect(stepsMapWith(const {today: 4000}, today, 9000), {today: 9000});
    });

    test('a SMALLER count for the same day is refused', () {
      // The bug this exists for: on iOS a refused read is indistinguishable
      // from a quiet morning and arrives as a well-formed zero. Letting one
      // land on a day already measured is what turned 9,000 steps into "you
      // never walked".
      expect(stepsMapWith(const {today: 9000}, today, 0), {today: 9000});
      expect(stepsMapWith(const {today: 9000}, today, 4000), {today: 9000});
    });

    test('the same count changes nothing, and says so by identity', () {
      const current = {today: 9000};
      expect(identical(stepsMapWith(current, today, 9000), current), isTrue);
    });

    test('a different day is a different key, so midnight still resets', () {
      final next = stepsMapWith(const {today: 9000}, '2026-09-11', 0);
      expect(next['2026-09-10'], 9000);
      expect(next.containsKey('2026-09-11'), isFalse,
          reason: 'zero is not worth recording, but it must not erase either');
    });

    test('every other day is left alone', () {
      final next = stepsMapWith(
        const {'2026-09-08': 12000, today: 100},
        today,
        5000,
      );
      expect(next, {'2026-09-08': 12000, today: 5000});
    });
  });

  group('stepFillFraction', () {
    test('a part-done walk fills its share of the square', () {
      expect(
        stepFillFraction(
          steps: 4000,
          goal: 10000,
          scheduled: true,
          square: SquareState.none,
        ),
        0.4,
      );
    });

    test('the same walk on a day that is over fills exactly the same', () {
      // There is no day in this call at all any more. That is the whole
      // point: nothing here can expire at midnight.
      final live = stepFillFraction(
        steps: 4000,
        goal: 10000,
        scheduled: true,
        square: SquareState.none,
      );
      final yesterday = stepFillFraction(
        steps: 4000,
        goal: 10000,
        scheduled: true,
        square: SquareState.none,
      );
      expect(yesterday, live);
    });

    test('nothing walked draws nothing', () {
      expect(
        stepFillFraction(
          steps: 0,
          goal: 10000,
          scheduled: true,
          square: SquareState.none,
        ),
        isNull,
      );
    });

    test('at the goal the square is already green and speaks for itself', () {
      expect(
        stepFillFraction(
          steps: 10000,
          goal: 10000,
          scheduled: true,
          square: SquareState.none,
        ),
        isNull,
      );
    });

    test('a day the habit does not run on is not part done', () {
      expect(
        stepFillFraction(
          steps: 4000,
          goal: 10000,
          scheduled: false,
          square: SquareState.none,
        ),
        isNull,
      );
    });

    test('any mark on the square outranks a measured count', () {
      for (final marked in const [
        SquareState.partial,
        SquareState.complete,
        SquareState.bonus,
        SquareState.failed,
        SquareState.skipped,
      ]) {
        expect(
          stepFillFraction(
            steps: 4000,
            goal: 10000,
            scheduled: true,
            square: marked,
          ),
          isNull,
          reason: '$marked is somebody\'s statement about the day',
        );
      }
    });

    test('an unlinked habit and an unread day both draw nothing', () {
      expect(
        stepFillFraction(
          steps: 4000,
          goal: null,
          scheduled: true,
          square: SquareState.none,
        ),
        isNull,
      );
      expect(
        stepFillFraction(
          steps: null,
          goal: 10000,
          scheduled: true,
          square: SquareState.none,
        ),
        isNull,
      );
    });

    test('a zero goal cannot be divided by', () {
      expect(
        stepFillFraction(
          steps: 4000,
          goal: 0,
          scheduled: true,
          square: SquareState.none,
        ),
        isNull,
      );
    });
  });

  /// The day log on disk.
  ///
  /// The second half of the same report: "when the day finish it saves the
  /// data, and start count to the next day, it should not go to 0, even if
  /// its 3921 steps and the goal is 6000" (Aziz, 2026-09-10). A map in
  /// memory made HealthKit the only record, and a revoked permission there
  /// answers a well-formed zero for every day at once.
  group('stepsLogFrom', () {
    test('reads back what was written', () {
      expect(
        stepsLogFrom(const {'2026-09-09': 3921, '2026-09-10': 6200}),
        {'2026-09-09': 3921, '2026-09-10': 6200},
      );
    });

    test('accepts a num, because Hive may hand back a double', () {
      expect(stepsLogFrom(const {'2026-09-09': 3921.0}), {'2026-09-09': 3921});
    });

    test('drops entries that are not a usable count', () {
      expect(
        stepsLogFrom(const {
          '2026-09-09': 'lots',
          '2026-09-08': 0,
          '2026-09-07': -5,
          '2026-09-06': null,
        }),
        isEmpty,
      );
    });

    test('drops a key that is not a date', () {
      expect(stepsLogFrom(const {'yesterday': 4000}), isEmpty);
    });
  });

  group('prunedStepsLog', () {
    final now = DateTime(2026, 9, 10, 5, 16);

    test('keeps the window', () {
      expect(
        prunedStepsLog(const {'2026-09-09': 3921}, now),
        {'2026-09-09': 3921},
      );
    });

    test('drops a day older than the window', () {
      expect(
        prunedStepsLog(
          const {'2026-07-01': 8000, '2026-09-09': 3921},
          now,
        ),
        {'2026-09-09': 3921},
      );
    });

    test('keeps today, which is still being walked', () {
      expect(prunedStepsLog(const {'2026-09-10': 500}, now), {'2026-09-10': 500});
    });

    test('drops a future day, which cannot have been walked', () {
      // A device whose clock was wrong for a moment must not be able to
      // leave a day in the log that nothing will ever prune or correct.
      expect(prunedStepsLog(const {'2026-09-11': 9000}, now), isEmpty);
    });

    test('the edge of the window is kept, the day before it is not', () {
      expect(
        prunedStepsLog(
          const {'2026-07-12': 1, '2026-07-11': 2},
          now,
          keepDays: 60,
        ),
        {'2026-07-12': 1},
      );
    });
  });
}
