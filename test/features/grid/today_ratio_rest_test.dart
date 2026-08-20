// A rest day and the "إنجاز اليوم" figure on the Grid's own summary.
//
// The number used to score a تخطّي as zero and keep it in the denominator,
// which meant deliberately resting a habit lowered the day's percentage by
// exactly as much as forgetting it would have. The app's stated position is
// that a rest day is not a missed day, and the reports had already been fixed
// to agree with it while the home screen still did not.
//
// Safe to exempt here because this ratio is DISPLAY ONLY: it feeds the
// percentage in grid_screen_summary and nothing else. No XP, no gold, no
// streak reads it, so there is nothing to game by resting. The Rooms
// leaderboard, which IS ranked, deliberately does NOT do this; see
// RoomParticipant.dailyRestedCount.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

void main() {
  // The ratio only answers for TODAY inside the current week, by design, so
  // every case here is built around the real current day.
  final today = DateTime.now().effectiveDay;
  final weekStart = startOfGridWeek(DateTime.now());

  WeeklyGridState stateWith(Map<String, SquareState> row) => WeeklyGridState(
        weekStart: weekStart,
        states: {today.toDateKey(): row},
        notes: const {},
      );

  group('a rest leaves the denominator', () {
    test('two habits, one done and one rested, is a finished day', () {
      // The headline change. This used to read 50%.
      final s = stateWith({
        'a': SquareState.complete,
        'b': SquareState.skipped,
      });
      expect(s.todayCompletionRatio(['a', 'b']), 1.0);
    });

    test('resting everything is a finished day, not an empty one', () {
      // The same answer RoomParticipant.creditFor gives when its scheduled
      // count reaches zero: nothing was owed, so nothing was fallen short of.
      final s = stateWith({
        'a': SquareState.skipped,
        'b': SquareState.skipped,
      });
      expect(s.todayCompletionRatio(['a', 'b']), 1.0);
    });

    test('a miss still costs exactly what it always did', () {
      final s = stateWith({'a': SquareState.complete});
      expect(s.todayCompletionRatio(['a', 'b']), 0.5);
    });
  });

  group('the other states are untouched', () {
    test('partial is still worth half', () {
      final s = stateWith({
        'a': SquareState.partial,
        'b': SquareState.partial,
      });
      expect(s.todayCompletionRatio(['a', 'b']), 0.5);
    });

    test('bonus is worth a whole day, not more', () {
      final s = stateWith({
        'a': SquareState.bonus,
        'b': SquareState.complete,
      });
      expect(s.todayCompletionRatio(['a', 'b']), 1.0);
    });

    test('failed still counts against you, unlike a rest', () {
      // The distinction this whole change rests on: فشل is an admission and
      // it costs, تخطّي is a decision and it does not.
      final failed = stateWith({
        'a': SquareState.complete,
        'b': SquareState.failed,
      });
      final rested = stateWith({
        'a': SquareState.complete,
        'b': SquareState.skipped,
      });
      expect(failed.todayCompletionRatio(['a', 'b']), 0.5);
      expect(rested.todayCompletionRatio(['a', 'b']), 1.0);
    });

    test('an empty square costs the same as a failed one', () {
      // They differ in what they SAY, not in what they cost. The difference
      // is that فشل is kept in Habit Notes and an empty square is silent.
      final empty = stateWith({'a': SquareState.complete});
      final failed = stateWith({
        'a': SquareState.complete,
        'b': SquareState.failed,
      });
      expect(
        empty.todayCompletionRatio(['a', 'b']),
        failed.todayCompletionRatio(['a', 'b']),
      );
    });
  });

  group('the guards that were already there still hold', () {
    test('no habits means no ratio', () {
      expect(stateWith(const {}).todayCompletionRatio(const []), 0);
    });

    test('a past week answers zero, not a stale percentage', () {
      final old = WeeklyGridState(
        weekStart: DateTime(weekStart.year, weekStart.month, weekStart.day - 7),
        states: {today.toDateKey(): {'a': SquareState.complete}},
        notes: const {},
      );
      expect(old.todayCompletionRatio(['a']), 0);
    });
  });
}
