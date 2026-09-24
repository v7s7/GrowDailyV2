// A skipped habit (تخطّي) leaves its day's streak count.
//
// Aziz, 2026-09-22, choosing between three rules: "Skip a habit: fine. Skip
// the whole day: no." Before this a تخطّي stayed in the streak roster as a
// habit not done, so the palette's own promise «راحة باختيارك. لا تُحسب
// عليك.» was false for the streak, and the Grid ring (which already left it
// out) could read 80% while the streak point was not earned. Rooms are not
// touched: a ranked room still counts a skip, on purpose.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

void main() {
  group('streakCreditOf', () {
    test('green 1, جزئي half, a miss nothing, a skip out of the count', () {
      expect(streakCreditOf(SquareState.complete), 1);
      expect(streakCreditOf(SquareState.bonus), 1);
      expect(streakCreditOf(SquareState.partial), 0.5);
      expect(streakCreditOf(SquareState.none), 0);
      expect(streakCreditOf(SquareState.failed), 0);
      expect(streakCreditOf(SquareState.skipped), isNull);
    });
  });

  group('squaresCrossStreakThreshold, what a palette pick asks', () {
    bool cross(Map<String, SquareState> squares, String id, SquareState mark) =>
        squaresCrossStreakThreshold(
          dayHabits: squares.keys,
          squareOf: (h) => squares[h] ?? SquareState.none,
          habitId: id,
          mark: mark,
        );

    test('skipping the last habit of four, three done, finishes the day', () {
      final day = {
        'a': SquareState.complete,
        'b': SquareState.complete,
        'c': SquareState.complete,
        'd': SquareState.none,
      };
      expect(cross(day, 'd', SquareState.skipped), isTrue,
          reason: 'three of three once the fourth leaves the count');
    });

    test('one skip is not always enough: 3 of 4 is still 75%', () {
      final day = {
        'a': SquareState.complete,
        'b': SquareState.complete,
        'c': SquareState.complete,
        'd': SquareState.none,
        'e': SquareState.none,
      };
      expect(cross(day, 'd', SquareState.skipped), isFalse);
      day['d'] = SquareState.skipped;
      expect(cross(day, 'e', SquareState.skipped), isTrue);
    });

    test('a day skipped whole earns nothing', () {
      final day = {
        'a': SquareState.skipped,
        'b': SquareState.skipped,
        'c': SquareState.none,
      };
      expect(cross(day, 'c', SquareState.skipped), isFalse,
          reason: 'nothing is left to count, so there is no completed day; '
              'the day is then judged a miss like any other without a point');
    });

    test('skips cannot let جزئي squares carry a day on their own', () {
      final day = {
        'a': SquareState.skipped,
        'b': SquareState.skipped,
        'c': SquareState.skipped,
        'd': SquareState.none,
      };
      expect(cross(day, 'd', SquareState.partial), isFalse,
          reason: 'half of one habit is 50%, never 80%');
    });

    test('finishing a habit with another one skipped', () {
      final day = {
        'a': SquareState.complete,
        'b': SquareState.complete,
        'c': SquareState.complete,
        'd': SquareState.skipped,
        'e': SquareState.none,
      };
      expect(cross(day, 'e', SquareState.complete), isTrue,
          reason: 'four of four; it was four of five before this rule');
    });
  });

  group('willCompleteAllHabitsToday, what a tick today asks', () {
    final six = [for (var i = 1; i <= 6; i++) (id: 'h$i', frequencyTarget: 1)];
    DashboardState doneThrough(int n) => DashboardState(
          level: 1,
          currentLevelXp: 0,
          cumulativeXp: 0,
          gold: 0,
          streak: 3,
          completions: {for (var i = 1; i <= n; i++) 'h$i': 1},
        );

    test('a skipped habit leaves the count: 4 of 5, not 4 of 6', () {
      expect(
        willCompleteAllHabitsToday(
          state: doneThrough(3),
          todayHabits: six,
          habitId: 'h4',
          frequencyTarget: 1,
          skippedHabitIds: const {'h6'},
        ),
        isTrue,
      );
      expect(
        willCompleteAllHabitsToday(
          state: doneThrough(3),
          todayHabits: six,
          habitId: 'h4',
          frequencyTarget: 1,
        ),
        isFalse,
        reason: 'the same day before the rule: 4 of 6 is 67%',
      );
    });

    test('completing the habit that was skipped counts it as done', () {
      expect(
        willCompleteAllHabitsToday(
          state: doneThrough(4),
          todayHabits: six.take(5),
          habitId: 'h5',
          frequencyTarget: 1,
          skippedHabitIds: const {'h5'},
        ),
        isTrue,
        reason: 'its square is about to turn green: 5 of 5',
      );
    });
  });

  test('every caller of willCompleteAllHabitsToday passes today\'s skips', () {
    // The same sweep half_square_counts_everywhere_test.dart runs for جزئي:
    // a caller that forgets the argument judges the same day on a bigger
    // roster, and a day kept on the Grid is lost from the other screen.
    final missing = <String>[];
    var seen = 0;
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      var i = src.indexOf('willCompleteAllHabitsToday(');
      while (i != -1) {
        var depth = 0;
        var j = src.indexOf('(', i);
        final start = j;
        for (; j < src.length; j++) {
          if (src[j] == '(') depth++;
          if (src[j] == ')') {
            depth--;
            if (depth == 0) break;
          }
        }
        final call = src.substring(start, j + 1);
        // The definition itself declares the parameter; skip it.
        if (!call.contains('required DashboardState state')) {
          seen++;
          if (!call.contains('skippedHabitIds')) missing.add(entity.path);
        }
        i = src.indexOf('willCompleteAllHabitsToday(', j);
      }
    }
    expect(seen, greaterThanOrEqualTo(7),
        reason: 'call sites disappeared, so this sweep guards nothing');
    expect(missing, isEmpty);
  });
}
