// Which board a habit belongs to, and in what order the three appear.
//
// The Grid used to be one table with everything in it, then two once quit
// habits earned their own board. A paused habit stayed mixed in with live
// ones the whole time — it is on the board for a real reason (a habit paused
// at 9pm must not blank out squares already earned that morning, and the
// pause has to be undoable from the row), but sitting between things you
// still owe today, it read as one more of them.
//
// Three boards now, ordered by what the day is actually asking: doing,
// staying away from, put down.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/grid/screens/grid_screen.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

void main() {
  IslamicHabitTemplate habit(
    String id, {
    GoalType goal = GoalType.build,
    DateTime? archivedAt,
  }) =>
      IslamicHabitTemplate(
        id: id,
        name: id,
        description: '',
        category: HabitCategory.custom,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        goalType: goal,
        hasTimer: false,
        xpReward: 10,
        goldReward: 5,
      ).withDates(createdAt: DateTime(2026, 1, 1), archivedAt: archivedAt);

  final paused = DateTime(2026, 8, 26);

  test('each habit lands on exactly one board', () {
    final all = [
      habit('build-a'),
      habit('quit-a', goal: GoalType.quit),
      habit('paused-a', archivedAt: paused),
    ];
    final parts = partitionGridHabits(all);
    expect(parts.build.map((h) => h.id), ['build-a']);
    expect(parts.quit.map((h) => h.id), ['quit-a']);
    expect(parts.paused.map((h) => h.id), ['paused-a']);
    expect(
      parts.build.length + parts.quit.length + parts.paused.length,
      all.length,
      reason: 'nothing may be dropped or counted twice',
    );
  });

  test('a PAUSED quit habit goes with the paused ones, not the quit ones', () {
    // The case a filter on one list would get wrong. Quit and paused are not
    // alternatives: you can stand down a quit habit, and while it is down it
    // belongs where the other stood-down habits are.
    final parts = partitionGridHabits([
      habit('quit-live', goal: GoalType.quit),
      habit('quit-paused', goal: GoalType.quit, archivedAt: paused),
    ]);
    expect(parts.quit.map((h) => h.id), ['quit-live']);
    expect(parts.paused.map((h) => h.id), ['quit-paused']);
  });

  test('a paused build habit leaves the build board too', () {
    final parts = partitionGridHabits([
      habit('build-live'),
      habit('build-paused', archivedAt: paused),
    ]);
    expect(parts.build.map((h) => h.id), ['build-live']);
    expect(parts.paused.map((h) => h.id), ['build-paused']);
  });

  test('order within a board is the order it was given', () {
    // The Grid's own ordering (however habitListProvider arranges it) has to
    // survive the split — re-sorting here would silently reshuffle everyone's
    // board the day this shipped.
    final parts = partitionGridHabits([
      habit('b3'),
      habit('b1'),
      habit('b2'),
    ]);
    expect(parts.build.map((h) => h.id), ['b3', 'b1', 'b2']);
  });

  test('an all-active board puts everything on Build and nothing elsewhere',
      () {
    // The common case, and the one that must look exactly as it always did:
    // with only one list populated the screen draws a single table with no
    // headings at all.
    final parts = partitionGridHabits([habit('a'), habit('b')]);
    expect(parts.build, hasLength(2));
    expect(parts.quit, isEmpty);
    expect(parts.paused, isEmpty);
  });

  test('an empty board partitions into three empty lists, not a crash', () {
    final parts = partitionGridHabits(const []);
    expect(parts.build, isEmpty);
    expect(parts.quit, isEmpty);
    expect(parts.paused, isEmpty);
  });
}
