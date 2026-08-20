// A جزئي square counting half toward the day's streak threshold.
//
// The streak needs kStreakDayCompletionThreshold (0.8) of today's scheduled
// habits. Its own doc comment says 0.8 rather than 1.0 exists so that "one
// slip on an otherwise full day still counts," because losing real progress
// over one missed habit "felt like a punishment for nearly succeeding." A
// habit someone half did is the purest form of nearly succeeding, and it was
// worth exactly nothing here.
//
// WHAT THIS DELIBERATELY IS NOT: a new way to EARN a streak. A جزئي square
// never calls completeHabit, so this predicate only ever runs while a real
// completion is landing. A day made entirely of half-done squares earns
// nothing, and the last group here pins that.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';

void main() {
  ({String id, int frequencyTarget}) h(String id) =>
      (id: id, frequencyTarget: 1);

  // copyWith off the real initial state, so this test cannot drift out of
  // sync with DashboardState's required fields.
  DashboardState stateWith(Map<String, int> completions) =>
      DashboardState.initial().copyWith(completions: completions);

  group('half credit at the margin', () {
    test('three of four plus one half done now keeps the streak', () {
      // 3/4 is 75% and misses. 3.5/4 is 87.5% and holds. This one case is
      // the whole reason for the change.
      final held = willCompleteAllHabitsToday(
        state: stateWith({'a': 1, 'b': 1}),
        todayHabits: [h('a'), h('b'), h('c'), h('d')],
        habitId: 'c',
        frequencyTarget: 1,
        halfDoneHabitIds: const {'d'},
      );
      expect(held, isTrue);
    });

    test('the same day without the half square does not', () {
      final lost = willCompleteAllHabitsToday(
        state: stateWith({'a': 1, 'b': 1}),
        todayHabits: [h('a'), h('b'), h('c'), h('d')],
        habitId: 'c',
        frequencyTarget: 1,
      );
      expect(lost, isFalse);
    });

    test('a half square cannot rescue a mostly undone day', () {
      // 1 done of 5 plus one half is 1.5/5, which is 30%. Nowhere near.
      final held = willCompleteAllHabitsToday(
        state: stateWith(const {}),
        todayHabits: [h('a'), h('b'), h('c'), h('d'), h('e')],
        habitId: 'a',
        frequencyTarget: 1,
        halfDoneHabitIds: const {'b'},
      );
      expect(held, isFalse);
    });
  });

  group('it changes nothing for callers that cannot answer', () {
    test('omitting the set reproduces the old behaviour exactly', () {
      // The parameter defaults to empty on purpose: a caller without the
      // Grid's squares in scope must behave exactly as it did before.
      final withEmpty = willCompleteAllHabitsToday(
        state: stateWith({'a': 1, 'b': 1, 'c': 1}),
        todayHabits: [h('a'), h('b'), h('c'), h('d')],
        habitId: 'd',
        frequencyTarget: 1,
        halfDoneHabitIds: const {},
      );
      final withoutParam = willCompleteAllHabitsToday(
        state: stateWith({'a': 1, 'b': 1, 'c': 1}),
        todayHabits: [h('a'), h('b'), h('c'), h('d')],
        habitId: 'd',
        frequencyTarget: 1,
      );
      expect(withEmpty, withoutParam);
      expect(withEmpty, isTrue);
    });

    test('a half square on a habit not scheduled today is ignored', () {
      final held = willCompleteAllHabitsToday(
        state: stateWith({'a': 1, 'b': 1}),
        todayHabits: [h('a'), h('b'), h('c'), h('d')],
        habitId: 'c',
        frequencyTarget: 1,
        halfDoneHabitIds: const {'z'},
      );
      expect(held, isFalse);
    });
  });

  group('a day of only half squares still earns nothing', () {
    test('every habit half done never reaches the threshold', () {
      // 0.5 across the board is 50%, below 0.8, no matter how many habits.
      for (final n in [2, 4, 8]) {
        final habits = [for (var i = 0; i < n; i++) h('h$i')];
        final held = willCompleteAllHabitsToday(
          state: stateWith(const {}),
          todayHabits: habits,
          habitId: 'h0',
          frequencyTarget: 2, // the target completion does not land
          halfDoneHabitIds: {for (var i = 1; i < n; i++) 'h$i'},
        );
        expect(held, isFalse, reason: '$n habits all half done must not hold');
      }
    });

    test('the guards that were already there still hold', () {
      expect(
        willCompleteAllHabitsToday(
          state: stateWith(const {}),
          todayHabits: const [],
          habitId: 'a',
          frequencyTarget: 1,
          halfDoneHabitIds: const {'a'},
        ),
        isFalse,
        reason: 'a day with nothing scheduled is a day off, not a win',
      );
      expect(
        willCompleteAllHabitsToday(
          state: stateWith(const {}),
          todayHabits: [h('a')],
          habitId: 'not-in-list',
          frequencyTarget: 1,
          halfDoneHabitIds: const {'a'},
        ),
        isFalse,
        reason: 'a habit missing from the list never earns the point',
      );
    });
  });
}
