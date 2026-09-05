// The step counter is evidence about a day, not a verdict on it.
//
// Marking a linked walking habit فشل and reopening the app used to turn the
// square green again and pay the day's XP, for a day its owner had just said
// did not happen (seen live on a simulator, 2026-09-02, XP 20 -> 40 and the
// day's percentage 0% -> 14% across one relaunch). A pedometer does not get
// to overrule a person about their own day.
//
// The cleared case is the subtle one. An empty square means two different
// things — "nobody has said anything yet" and "I took that back" — so it is
// answered by the undo's receipt (UndoneCompletion) rather than by the
// square, which cannot tell them apart.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/dashboard/models/undone_completion.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/step_auto_complete.dart';

void main() {
  final today = DateTime.now().effectiveDay;

  final walk = IslamicHabitTemplate(
    id: 'walk',
    name: 'Walk',
    description: '',
    category: HabitCategory.health,
    frequencyType: HabitFrequencyType.daily,
    frequencyTarget: 1,
    hasTimer: false,
    xpReward: 20,
    goldReward: 8,
    stepGoal: 6000,
  );

  WeeklyGridState gridWith(SquareState? square) => WeeklyGridState(
        weekStart: startOfGridWeek(today),
        states: {
          today.toDateKey(): {if (square != null) 'walk': square},
        },
        notes: const {},
      );

  DashboardState dashWith({bool undone = false}) =>
      DashboardState.initial().copyWith(
        undoneCompletions: undone
            ? {
                UndoneCompletion.keyFor('walk', today.toDateKey()):
                    UndoneCompletion(
                  habitId: 'walk',
                  dateKey: today.toDateKey(),
                  category: 'health',
                  xp: 20,
                  gold: 8,
                  streakAtCompletion: 3,
                  longestAtCompletion: 5,
                  undoneOnKey: today.toDateKey(),
                ),
              }
            : const {},
      );

  bool accepts({SquareState? square, bool undone = false}) =>
      stepHabitAcceptsAutoComplete(
        habit: walk,
        grid: gridWith(square),
        dash: dashWith(undone: undone),
        day: today,
      );

  group('a day nobody has spoken about', () {
    test('an untouched square completes itself', () {
      expect(accepts(square: null), isTrue);
      expect(accepts(square: SquareState.none), isTrue);
    });

    test('an already green square is left to the completion guard', () {
      // Not this function's job: the caller reads the completion itself,
      // which is a better source than the square mirroring it.
      expect(accepts(square: SquareState.complete), isTrue);
    });
  });

  group('a day its owner has spoken about', () {
    test('فشل is not reopened by the step count', () {
      expect(accepts(square: SquareState.failed), isFalse);
    });

    test('تخطّي is a deliberate rest and stays one', () {
      expect(accepts(square: SquareState.skipped), isFalse);
    });

    test('a hand-marked جزئي is their own account of the day', () {
      expect(accepts(square: SquareState.partial), isFalse);
    });

    test('إنجاز إضافي is already more than done', () {
      expect(accepts(square: SquareState.bonus), isFalse);
    });
  });

  group('a completion the person took back', () {
    test('the receipt stops it coming straight back', () {
      // The square is empty again, exactly as it is on an untouched day, so
      // only the receipt can tell the two apart.
      expect(accepts(square: SquareState.none, undone: true), isFalse);
    });

    test('a receipt for another day does not block today', () {
      final other = DashboardState.initial().copyWith(
        undoneCompletions: {
          UndoneCompletion.keyFor('walk', '2020-01-01'): UndoneCompletion(
            habitId: 'walk',
            dateKey: '2020-01-01',
            category: 'health',
            xp: 20,
            gold: 8,
            streakAtCompletion: 1,
            longestAtCompletion: 1,
            undoneOnKey: '2020-01-01',
          ),
        },
      );
      expect(
        stepHabitAcceptsAutoComplete(
          habit: walk,
          grid: gridWith(SquareState.none),
          dash: other,
          day: today,
        ),
        isTrue,
      );
    });

    test('a receipt for another habit does not block this one', () {
      final other = DashboardState.initial().copyWith(
        undoneCompletions: {
          UndoneCompletion.keyFor('dhikr', today.toDateKey()):
              UndoneCompletion(
            habitId: 'dhikr',
            dateKey: today.toDateKey(),
            category: 'faith',
            xp: 20,
            gold: 8,
            streakAtCompletion: 1,
            longestAtCompletion: 1,
            undoneOnKey: today.toDateKey(),
          ),
        },
      );
      expect(
        stepHabitAcceptsAutoComplete(
          habit: walk,
          grid: gridWith(SquareState.none),
          dash: other,
          day: today,
        ),
        isTrue,
      );
    });
  });
}
