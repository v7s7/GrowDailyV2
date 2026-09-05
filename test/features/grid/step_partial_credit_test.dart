// A walking habit linked to the step count, part-way through today's goal.
//
// Before this, half a walk was worth exactly as much as no walk: the square
// stayed empty and "إنجاز اليوم" stayed at zero until the goal landed, at
// which point the habit jumped straight to done. The square now fills to the
// real proportion (grid_screen_table's stepFraction) and the percentage
// counts that same proportion, through the partialUnits map built in
// _SummaryCard._stepPartials.
//
// Why the true fraction and not the flat half a جزئي square gets: a tap is a
// decision — one of four taps means the person chose to do the thing, and the
// app rounds that decision up to half a day. Steps are measured, not decided.
// 300 of 6,000 is not half a walk, and paying half for it would put credit on
// the home screen for carrying the phone to the kitchen.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

void main() {
  // The ratio only ever answers for TODAY inside the current week (see
  // today_ratio_rest_test.dart's note on effectiveDay vs the raw clock), so
  // every case is built around the real current day.
  final today = DateTime.now().effectiveDay;
  final weekStart = startOfGridWeek(today);

  WeeklyGridState stateWith(Map<String, SquareState> row) => WeeklyGridState(
        weekStart: weekStart,
        states: {today.toDateKey(): row},
        notes: const {},
      );

  group('measured part-done credit', () {
    test('half the goal walked is half a habit, not zero', () {
      final s = stateWith({'walk': SquareState.none});
      expect(
        s.todayCompletionRatio(['walk'], partialUnits: {'walk': 0.5}),
        0.5,
      );
    });

    test('a few steps is worth a few steps, not half a day', () {
      // 300 of 6,000. The flat جزئي half would have read 50% here.
      final s = stateWith({'walk': SquareState.none});
      expect(
        s.todayCompletionRatio(['walk'], partialUnits: {'walk': 300 / 6000}),
        closeTo(0.05, 1e-9),
      );
    });

    test('it mixes with ordinary squares in the same day', () {
      // One habit done, one walk 60% through: 1.6 of 2 owed.
      final s = stateWith({
        'dhikr': SquareState.complete,
        'walk': SquareState.none,
      });
      expect(
        s.todayCompletionRatio(
          ['dhikr', 'walk'],
          partialUnits: {'walk': 0.6},
        ),
        closeTo(0.8, 1e-9),
      );
    });

    test('no steps yet reads exactly as it did before', () {
      final s = stateWith({'walk': SquareState.none});
      expect(s.todayCompletionRatio(['walk'], partialUnits: const {}), 0.0);
      expect(s.todayCompletionRatio(['walk']), 0.0);
    });
  });

  group('an explicit mark still outranks the count', () {
    test('a finished walk scores one, never one-plus-a-fraction', () {
      // The map should not contain a finished habit at all (see
      // _stepPartials), but the ratio must not double count even if it does.
      final s = stateWith({'walk': SquareState.complete});
      expect(
        s.todayCompletionRatio(['walk'], partialUnits: {'walk': 0.9}),
        1.0,
      );
    });

    test('a rested walk leaves the denominator, steps or not', () {
      final s = stateWith({
        'walk': SquareState.skipped,
        'dhikr': SquareState.complete,
      });
      expect(
        s.todayCompletionRatio(
          ['walk', 'dhikr'],
          partialUnits: {'walk': 0.5},
        ),
        1.0,
      );
    });

    test('a walk marked failed scores zero however far it got', () {
      // Saying "this did not happen" is a statement about the day; the step
      // counter does not get to argue with it.
      final s = stateWith({'walk': SquareState.failed});
      expect(
        s.todayCompletionRatio(['walk'], partialUnits: {'walk': 0.9}),
        0.0,
      );
    });

    test('a hand-marked جزئي keeps its flat half', () {
      final s = stateWith({'walk': SquareState.partial});
      expect(
        s.todayCompletionRatio(['walk'], partialUnits: {'walk': 0.1}),
        0.5,
      );
    });
  });

  group('the fraction cannot break the percentage', () {
    test('an out-of-range value is clamped, never over 100%', () {
      final s = stateWith({'walk': SquareState.none});
      expect(
        s.todayCompletionRatio(['walk'], partialUnits: {'walk': 4.0}),
        1.0,
      );
      expect(
        s.todayCompletionRatio(['walk'], partialUnits: {'walk': -2.0}),
        0.0,
      );
    });

    test('an entry for a habit not scheduled today changes nothing', () {
      final s = stateWith({'dhikr': SquareState.complete});
      expect(
        s.todayCompletionRatio(['dhikr'], partialUnits: {'walk': 0.5}),
        1.0,
      );
    });
  });
}
