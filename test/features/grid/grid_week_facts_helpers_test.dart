// The helpers the Grid's board now calls with work it did once per build
// (see _WeekFacts in grid_screen_table.dart) answer exactly what they answer
// without it. Each precomputed argument is optional and stands for one
// expression the helper used to evaluate itself, so every other caller is
// untouched: these pin that the two paths agree, day by day, on the inputs
// the board meets, daylight-saving weeks included (run with
// TZ=America/New_York as well).
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/covered_day.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/square_voice_notes.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_day_demand.dart';

import 'board_parity_fixture.dart';

void main() {
  /// Saturday weeks, one of them each side of a clock change in New York.
  final weeks = [
    DateTime(2025, 11, 1),
    DateTime(2026, 3, 7),
    DateTime(2026, 9, 26),
    DateTime(2026, 10, 31),
  ];

  /// Every day and hour a board can hand these helpers: each column's own
  /// instant (a clock-change week's are not midnights) and the hours around
  /// a birth or an archive stamped at 09:30 or 20:00.
  List<DateTime> probes(DateTime around) => [
        for (var d = -3; d <= 3; d++)
          for (final h in [0, 1, 9, 10, 20, 23])
            DateTime(around.year, around.month, around.day + d, h),
      ];

  group('aliveWindow and aliveWithin', () {
    test('agree with isAliveOn around a birth and an archive', () {
      for (final born in [
        DateTime(2026, 3, 8, 9, 30),
        DateTime(2025, 11, 2, 0, 30),
        DateTime.utc(2026, 3, 8, 23, 30),
        DateTime.utc(2025, 11, 2, 2),
      ]) {
        for (final died in [
          null,
          DateTime(2026, 3, 9, 20),
          DateTime.utc(2025, 11, 3, 1),
        ]) {
          final habit = fixtureHabit('h', 'H', 'ع',
              createdAt: born, archivedAt: died);
          final window = habit.aliveWindow;
          for (final day in [...probes(born), if (died != null) ...probes(died)]) {
            expect(IslamicHabitTemplate.aliveWithin(window, day),
                habit.isAliveOn(day),
                reason: 'born $born, archived $died, on $day');
          }
        }
      }
    });

    test('a habit with no dates is alive every day', () {
      final habit = fixtureHabit('h', 'H', 'ع');
      expect(habit.aliveWindow, (from: null, to: null));
      for (final day in probes(DateTime(2026, 3, 8))) {
        expect(IslamicHabitTemplate.aliveWithin(habit.aliveWindow, day), isTrue);
      }
    });
  });

  group('each board week of the fixture', () {
    for (final weekStart in weeks) {
      final fixture = BoardFixture(weekStart, now: DateTime(2026, 9, 30, 14));
      final state = fixture.state();
      final days = fixture.days;

      test('isCoveredDay with the midnights and window given', () {
        for (final today in [
          DateTime(2026, 9, 30),
          days[3],
          DateTime(days[5].year, days[5].month, days[5].day, 23),
        ]) {
          final todayDay = today.effectiveDay;
          for (final habit in fixture.habits) {
            final demand = quotaDemandForRow(
              habit: habit,
              days: days,
              isGreenAt: (i) => state.squareFor(habit.id, days[i]).isGreen,
              isUnmarkedAt: (i) =>
                  state.squareFor(habit.id, days[i]) == SquareState.none,
              isHalfAt: (i) =>
                  state.squareFor(habit.id, days[i]) == SquareState.partial,
            );
            for (var i = 0; i < days.length; i++) {
              for (final square in SquareState.values) {
                final plain = isCoveredDay(
                  habit: habit,
                  day: days[i],
                  today: todayDay,
                  square: square,
                  demand: demand?[i],
                );
                final given = isCoveredDay(
                  habit: habit,
                  day: days[i],
                  today: todayDay,
                  square: square,
                  demand: demand?[i],
                  dayStart: days[i].startOfDay,
                  todayStart:
                      DateTime(todayDay.year, todayDay.month, todayDay.day),
                  alive: habit.aliveWindow,
                );
                expect(given, plain,
                    reason: '${habit.id} on ${days[i]}, $square, today $today');
              }
            }
          }
        }
      });

      test('quotaDemandForRow and movedDemandForRow with alive and planned',
          () {
        for (final habit in fixture.habits) {
          final alive = [for (final d in days) habit.isAliveOn(d)];
          final planned = [for (final d in days) habit.isScheduledFor(d)];
          // A session on every day, none, and the fixture's own week: the
          // moved-session rule only speaks when a day off the plan is green.
          for (final green in [
            (int i) => state.squareFor(habit.id, days[i]).isGreen,
            (int i) => true,
            (int i) => false,
            (int i) => i.isOdd,
          ]) {
            for (final now in [null, DateTime(2026, 9, 30, 14), days[4]]) {
              bool unmarked(int i) =>
                  state.squareFor(habit.id, days[i]) == SquareState.none;
              bool half(int i) =>
                  state.squareFor(habit.id, days[i]) == SquareState.partial;
              expect(
                quotaDemandForRow(
                  habit: habit,
                  days: days,
                  isGreenAt: green,
                  isUnmarkedAt: unmarked,
                  isHalfAt: half,
                  now: now,
                  alive: alive,
                  planned: planned,
                ),
                quotaDemandForRow(
                  habit: habit,
                  days: days,
                  isGreenAt: green,
                  isUnmarkedAt: unmarked,
                  isHalfAt: half,
                  now: now,
                ),
                reason: '${habit.id}, now $now',
              );
              expect(
                movedDemandForRow(
                  habit: habit,
                  days: days,
                  isGreenAt: green,
                  isUnmarkedAt: unmarked,
                  now: now,
                  alive: alive,
                  planned: planned,
                ),
                movedDemandForRow(
                  habit: habit,
                  days: days,
                  isGreenAt: green,
                  isUnmarkedAt: unmarked,
                  now: now,
                ),
                reason: '${habit.id}, now $now',
              );
            }
          }
        }
      });

      test('the by-key lookups equal the by-day ones', () {
        for (final habit in fixture.habits) {
          for (final day in days) {
            final key = day.toDateKey();
            expect(state.squareForKey(habit.id, key),
                state.squareFor(habit.id, day));
            expect(state.noteForKey(habit.id, key), state.noteFor(habit.id, day));
            expect(squareVoiceKeyFor(habit.id, key),
                squareVoiceKey(habit.id, day));
          }
        }
        // A habit id carrying underscores of its own still parses back.
        final key = squareVoiceKeyFor('a_b_c', days.first.toDateKey());
        expect(parseSquareVoiceKey(key)?.habitId, 'a_b_c');
      });
    }
  });

  test('WeeklyGridState by-key lookups on an empty week', () {
    final empty = WeeklyGridState(
      weekStart: DateTime(2026, 9, 26),
      states: const {},
      notes: const {},
    );
    expect(empty.squareForKey('x', '2026-09-26'), SquareState.none);
    expect(empty.noteForKey('x', '2026-09-26'), '');
  });
}
