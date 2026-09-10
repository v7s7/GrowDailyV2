// Which days a walk read a day late is allowed to fill in.
//
// Auto-completion only ever looked at the day in progress, so a person who
// walked their goal and did not open the app before the cutoff lost the day
// outright: the next launch reads a fresh day and yesterday stays empty for
// good. Steps are the one habit here that genuinely happen while the app is
// closed, which is the whole reason for reading them, so the app now looks
// back exactly one day on the first run of each new day.
//
// Widened from one day to seven on 2026-09-09 (kStepCatchUpDays), Aziz's
// call after testers reported days going empty: the person who walks daily
// and opens the app twice a week used to lose every day in between, and
// nothing on screen ever said so. It is also the recovery path for days lost
// to build 66, where a walk short of the goal wrote nothing at all.
//
// Writing a square nobody asked for is only defensible while it is confined
// to days that are genuinely blank, and that confinement is what this file
// pins. Everything else about the back-fill is deliberately dull: the square
// alone is marked, never completeHabit, so a late day is recorded and paid
// nothing, which is the same deal a person gets for tapping a past square.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/step_auto_complete.dart';

void main() {
  final yesterday =
      DateTime.now().effectiveDay.subtract(const Duration(days: 1));

  IslamicHabitTemplate habit({
    String id = 'walk',
    int? stepGoal = 6000,
    List<int> weekdays = const [],
    DateTime? createdAt,
  }) =>
      IslamicHabitTemplate(
        id: id,
        name: 'Walk',
        description: '',
        category: HabitCategory.health,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        hasTimer: false,
        xpReward: 20,
        goldReward: 8,
        stepGoal: stepGoal,
        scheduledWeekdays: weekdays,
        createdAt: createdAt,
      );

  List<String> owedIds(
    List<IslamicHabitTemplate> linked,
    Map<String, SquareState> marks,
  ) =>
      stepHabitsOwedOn(
        linked: linked,
        marks: marks,
        day: yesterday,
      ).map((h) => h.id).toList();

  group('the window the pass reaches back over', () {
    test('seven days, and the number is load-bearing', () {
      // Not a taste question: one day was the old value, and it is what let
      // a walker who opens the app twice a week lose every day in between.
      // Seven matches the visible grid week, so the promise the board makes
      // and the promise the count keeps are the same length.
      expect(kStepCatchUpDays, 7);
    });

    test('a habit is owed every day of the window it existed for', () {
      final born = DateTime.now().effectiveDay.subtract(const Duration(days: 3));
      final h = habit(createdAt: born);
      for (var back = 1; back <= kStepCatchUpDays; back++) {
        final day = DateTime.now().effectiveDay.subtract(Duration(days: back));
        final owed = stepHabitsOwedOn(
          linked: [h],
          marks: const {},
          day: day,
        ).map((x) => x.id).toList();
        // Three days old: days one to three are its own, four and older are
        // days it did not exist for and must never be marked.
        expect(owed, back <= 3 ? ['walk'] : isEmpty,
            reason: 'day $back back, habit born 3 days ago');
      }
    });

    test('a specific-days habit is only owed its own weekdays in the window',
        () {
      // Whatever weekday today is, exactly one of the seven days behind it
      // shares it, so a habit scheduled for that weekday alone is owed
      // exactly one day of the window.
      final weekday = DateTime.now().effectiveDay.weekday;
      final h = habit(weekdays: [weekday]);
      var owedDays = 0;
      for (var back = 1; back <= kStepCatchUpDays; back++) {
        final day = DateTime.now().effectiveDay.subtract(Duration(days: back));
        if (stepHabitsOwedOn(linked: [h], marks: const {}, day: day)
            .isNotEmpty) {
          owedDays++;
        }
      }
      expect(owedDays, 1);
    });
  });

  group('every square the count may still lift is in play', () {
    test('an untouched square is owed an answer', () {
      expect(owedIds([habit()], const {}), ['walk']);
      expect(
        owedIds([habit()], {'walk': SquareState.none}),
        ['walk'],
      );
    });

    test('an already green day is still in play, for the blue square', () {
      // The goal is on the board; twenty percent over it is not yet. The
      // final count decides, and stepCountMayLift keeps it upwards only.
      expect(
        owedIds([habit()], {'walk': SquareState.complete}),
        ['walk'],
      );
    });

    test('a deliberate rest is not reopened by a step count', () {
      // تخطّي is the person standing the day down on purpose. A late read of
      // their pedometer does not get to argue with that.
      expect(
        owedIds([habit()], {'walk': SquareState.skipped}),
        isEmpty,
      );
    });

    test('a day marked failed stays failed', () {
      expect(
        owedIds([habit()], {'walk': SquareState.failed}),
        isEmpty,
      );
    });

    test('a جزئي is in play: yesterday\'s live reads left it there', () {
      // Half the goal sets جزئي during the day; the final count may lift it
      // to the green or the blue square, never lower it.
      expect(
        owedIds([habit()], {'walk': SquareState.partial}),
        ['walk'],
      );
    });

    test('a bonus day is already more than done', () {
      expect(
        owedIds([habit()], {'walk': SquareState.bonus}),
        isEmpty,
      );
    });
  });

  group('only habits that owed the day at all', () {
    test('an unlinked habit is none of this feature\'s business', () {
      expect(owedIds([habit(stepGoal: null)], const {}), isEmpty);
    });

    test('a habit not scheduled yesterday owed nothing', () {
      final offDay = yesterday.weekday == 1 ? 2 : 1;
      expect(owedIds([habit(weekdays: [offDay])], const {}), isEmpty);
    });

    test('a habit scheduled yesterday is in play', () {
      expect(
        owedIds([habit(weekdays: [yesterday.weekday])], const {}),
        ['walk'],
      );
    });

    test('a habit created today did not exist yesterday', () {
      // The commonest false positive there is: link a walking habit this
      // morning and the app must not go and colour in a day that predates it.
      expect(
        owedIds(
          [habit(createdAt: DateTime.now().effectiveDay)],
          const {},
        ),
        isEmpty,
      );
    });
  });

  test('each habit is judged on its own square', () {
    const grid = {
      'done': SquareState.complete,
      'blank': SquareState.none,
      'rested': SquareState.skipped,
    };
    // The green day is still in play for the blue square; the rest day is
    // its owner's word and is not.
    expect(
      owedIds([
        habit(id: 'done'),
        habit(id: 'blank'),
        habit(id: 'rested'),
        habit(id: 'unseen'),
      ], grid),
      ['done', 'blank', 'unseen'],
    );
  });
}
