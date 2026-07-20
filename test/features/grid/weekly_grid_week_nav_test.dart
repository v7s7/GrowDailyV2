// Tests for the Grid's week-navigation ceiling — see
// WeeklyGridState.canGoForward's doc comment for the bug this guards
// against: right after a week boundary (e.g. 1am Saturday), effectiveDay's
// 3-hour grace period still points at last week, but the real calendar has
// already moved into the new one. Gating the forward arrow on the
// reward-eligible week (as it used to) stranded the user on last week's
// board with the arrow disabled and no way back to the day they actually
// opened the app to see. These tests use the real DateTime.now() (not a
// fixed date) so they hold regardless of which day they happen to run on.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

void main() {
  group('startOfGridWeek', () {
    test('a Saturday maps to itself', () {
      // 2026-07-18 is a Saturday.
      final saturday = DateTime(2026, 7, 18);
      expect(startOfGridWeek(saturday), saturday);
    });

    test('any other day maps back to that week\'s Saturday', () {
      // 2026-07-24 is the Friday closing the week that starts 2026-07-18.
      final friday = DateTime(2026, 7, 24);
      expect(startOfGridWeek(friday), DateTime(2026, 7, 18));
    });
  });

  group('WeeklyGridState.canGoForward', () {
    WeeklyGridState stateAt(DateTime weekStart) => WeeklyGridState(
          weekStart: weekStart,
          states: const {},
          notes: const {},
        );

    test('the real week itself cannot go further forward', () {
      final realWeek = startOfGridWeek(DateTime.now());
      expect(stateAt(realWeek).canGoForward, isFalse);
    });

    test(
        'a week behind the real one CAN go forward — the exact grace-window '
        'bug: effectiveDay can still be pointing at last week for up to 3 '
        'hours after a week boundary, but the board must still be able to '
        'arrow into the week the real calendar has already moved into',
        () {
      final lastWeek =
          startOfGridWeek(DateTime.now()).subtract(const Duration(days: 7));
      expect(stateAt(lastWeek).canGoForward, isTrue);
    });

    test('two weeks behind can also still go forward', () {
      final twoWeeksAgo =
          startOfGridWeek(DateTime.now()).subtract(const Duration(days: 14));
      expect(stateAt(twoWeeksAgo).canGoForward, isTrue);
    });
  });

  group('WeeklyGridState.initial', () {
    test('opens on the real calendar week, not a stale earlier one', () {
      final state = WeeklyGridState.initial();
      expect(state.weekStart, startOfGridWeek(DateTime.now()));
    });
  });
}
