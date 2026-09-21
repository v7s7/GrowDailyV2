// A جزئي square is worth 0.5 of a habit. Every surface that closes a day has
// to read it, or the same day scores differently depending on where the last
// tap happened.
//
// The bug this exists to prevent, reported 2026-09-20: a day at 78% with one
// half-done habit. On the Grid that day was 7.5 of 9 (83%), over the 80%
// streak threshold. Completed from the Habits page instead, the half counted
// as ZERO, the day landed under the threshold, the streak broke, and the next
// launch greeted a person who had not missed a day with "welcome back".
//
// willCompleteAllHabitsToday has always supported [halfDoneHabitIds]; three of
// its four callers simply never passed them, which is why this is a sweep over
// the call sites and not a unit test of the function. A unit test would have
// passed throughout the entire life of the bug.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';

/// Every `willCompleteAllHabitsToday(` call in lib, with its arguments.
List<({String file, String call})> _callSites() {
  final out = <({String file, String call})>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final src = entity.readAsStringSync();
    var i = src.indexOf('willCompleteAllHabitsToday(');
    while (i != -1) {
      // Balance the parentheses so the whole argument list is captured,
      // however many nested calls it contains.
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
      out.add((file: entity.path, call: src.substring(start, j + 1)));
      i = src.indexOf('willCompleteAllHabitsToday(', j);
    }
  }
  return out;
}

void main() {
  test('every caller credits half-done squares', () {
    final sites = _callSites();
    // Four today: Habits (main.dart), the Grid table, the Grid cell editor,
    // Tasbih, and the step auto-complete. If this number drops, a surface
    // stopped closing days and the sweep below is measuring less than it
    // should.
    expect(sites.length, greaterThanOrEqualTo(4),
        reason: 'call sites disappeared, so this sweep guards nothing');

    final missing = [
      for (final site in sites)
        if (!site.call.contains('halfDoneHabitIds')) site.file,
    ];
    expect(missing, isEmpty,
        reason: 'these close a day without counting جزئي as 0.5, so the same '
            'day keeps its streak on the Grid and loses it here');
  });

  test('half squares are what push a near-miss day over the threshold', () {
    // 9 habits, 7 finished, 1 half done: 7/9 is 77.8% and fails, 7.5/9 is
    // 83.3% and passes. Exactly the day that was reported.
    final habits = [
      for (var i = 0; i < 9; i++) (id: 'h$i', frequencyTarget: 1),
    ];
    final state = DashboardState(
      level: 1,
      currentLevelXp: 0,
      cumulativeXp: 0,
      gold: 0,
      streak: 0,
      completions: {for (var i = 0; i < 6; i++) 'h$i': 1},
    );

    bool dayCloses({Set<String> halves = const {}}) =>
        willCompleteAllHabitsToday(
          state: state,
          todayHabits: habits,
          // The seventh habit is the one being completed right now.
          habitId: 'h6',
          frequencyTarget: 1,
          halfDoneHabitIds: halves,
        );

    expect(dayCloses(), isFalse, reason: '7 of 9 is 77.8%, under 80%');
    expect(dayCloses(halves: {'h7'}), isTrue,
        reason: '7.5 of 9 is 83.3%, over 80%');
  });
}
