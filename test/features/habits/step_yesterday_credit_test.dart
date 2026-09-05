// Which days a walk read a day late is allowed to fill in.
//
// Auto-completion only ever looked at the day in progress, so a person who
// walked their goal and did not open the app before the cutoff lost the day
// outright: the next launch reads a fresh day and yesterday stays empty for
// good. Steps are the one habit here that genuinely happen while the app is
// closed, which is the whole reason for reading them, so the app now looks
// back exactly one day on the first run of each new day.
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
      stepHabitsOwedYesterday(
        linked: linked,
        marks: marks,
        yesterday: yesterday,
      ).map((h) => h.id).toList();

  group('a blank day is the only day in play', () {
    test('an untouched square is owed an answer', () {
      expect(owedIds([habit()], const {}), ['walk']);
      expect(
        owedIds([habit()], {'walk': SquareState.none}),
        ['walk'],
      );
    });

    test('an already green day is left alone', () {
      // Nothing to add: the walk is on the board already.
      expect(
        owedIds([habit()], {'walk': SquareState.complete}),
        isEmpty,
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

    test('a hand-marked جزئي is somebody\'s own account of the day', () {
      expect(
        owedIds([habit()], {'walk': SquareState.partial}),
        isEmpty,
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
    };
    expect(
      owedIds([habit(id: 'done'), habit(id: 'blank'), habit(id: 'unseen')],
          grid),
      ['blank', 'unseen'],
    );
  });
}
