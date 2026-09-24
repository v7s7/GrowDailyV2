// One rule for "did this habit owe this day", shared by every denominator.
//
// The bug this file pins (Aziz, 2026-09-16, on 13 September 2026): the Grid
// row for تمرين — «4 times a week, any days» — read the day as covered while
// the progress map's cell above it read the same day as partial. Two pictures
// of one day on one screen, because the Grid resolved the quota's week and
// the map counted the habit through isScheduledFor, which says yes on all
// seven days.
//
// The guarantee that makes habitOwesDay safe as a denominator everywhere:
// across a week, the owed-and-empty days number exactly the shortfall. Never
// more (a 4x week left blank marks 4 days, not 7), never fewer (a week that
// fell short still names the days it fell short on).
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/grid/models/covered_day.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_day_demand.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

void main() {
  // Saturday 12 September 2026 starts the week 13 September falls in — the
  // week from the report.
  final weekStart = DateTime(2026, 9, 12);
  List<DateTime> week() =>
      [for (var i = 0; i < 7; i++) DateTime(2026, 9, 12 + i)];

  IslamicHabitTemplate makeHabit({
    required HabitFrequencyType type,
    required int target,
    List<int> weekdays = const [],
    DateTime? created,
    String id = 'tamreen',
  }) =>
      IslamicHabitTemplate(
        id: id,
        name: 'Exercise',
        description: '',
        nameAr: 'تمرين',
        category: HabitCategory.custom,
        frequencyType: type,
        frequencyTarget: target,
        scheduledWeekdays: weekdays,
        hasTimer: false,
        xpReward: 10,
        goldReward: 5,
        createdAt: created ?? DateTime(2026, 1, 1),
      );

  // Answers for whichever habit asks: only a flexible quota ever consults it,
  // and every test here has at most one.
  GreenOnDay greenOn(Set<int> dayIndexes) => (habitId, day) => dayIndexes
      .any((i) => DateTime(2026, 9, 12 + i).difference(day).inDays == 0);

  final quota4 = makeHabit(type: HabitFrequencyType.weekly, target: 4);

  group('a flexible weekly quota', () {
    test('owes nothing on the early days of an untouched week', () {
      final isGreen = greenOn(const {});
      // Sat/Sun/Mon: three blank days a 4x week can still afford.
      for (final i in [0, 1, 2]) {
        expect(
          habitOwesDay(habit: quota4, day: week()[i], isGreen: isGreen),
          isFalse,
          reason: 'day $i of an untouched 4x week is spare, not owed',
        );
      }
      // 13 September is index 1 — the day in the report.
      expect(
        habitOwesDay(habit: quota4, day: DateTime(2026, 9, 13), isGreen: isGreen),
        isFalse,
      );
    });

    test('owes the days that put the target out of reach', () {
      final isGreen = greenOn(const {});
      // Tue onward: four days left, four sessions still needed.
      for (final i in [3, 4, 5, 6]) {
        expect(
          habitOwesDay(habit: quota4, day: week()[i], isGreen: isGreen),
          isTrue,
          reason: 'skipping day $i makes 4 arithmetically impossible',
        );
      }
    });

    test('owes nothing once the target is banked, and the extra day counts',
        () {
      // Four sessions landed Sat-Tue: the rest of the week is earned.
      final isGreen = greenOn(const {0, 1, 2, 3});
      for (final i in [4, 5, 6]) {
        expect(habitOwesDay(habit: quota4, day: week()[i], isGreen: isGreen),
            isFalse);
      }
      // ...unless a fifth session actually happened, which belongs on BOTH
      // sides of the ratio so extra work can only pull a day up.
      final withFifth = greenOn(const {0, 1, 2, 3, 5});
      expect(habitOwesDay(habit: quota4, day: week()[5], isGreen: withFifth),
          isTrue);
      expect(habitOwesDay(habit: quota4, day: week()[6], isGreen: withFifth),
          isFalse);
    });

    test('marks exactly the shortfall, for every pattern of the week', () {
      for (var target = 1; target <= 7; target++) {
        final habit = makeHabit(
          type: HabitFrequencyType.weekly,
          target: target,
        );
        for (var mask = 0; mask < 128; mask++) {
          final done = {
            for (var i = 0; i < 7; i++)
              if (mask & (1 << i) != 0) i,
          };
          final isGreen = greenOn(done);
          var missed = 0;
          for (var i = 0; i < 7; i++) {
            if (done.contains(i)) continue;
            if (habitOwesDay(habit: habit, day: week()[i], isGreen: isGreen)) {
              missed++;
            }
          }
          expect(
            missed,
            target - done.length < 0 ? 0 : target - done.length,
            reason: 'target $target, days done $done',
          );
        }
      }
    });

    test('never owes a day before it existed', () {
      final born = makeHabit(
        type: HabitFrequencyType.weekly,
        target: 4,
        created: DateTime(2026, 9, 16),
      );
      expect(
        habitOwesDay(
            habit: born, day: DateTime(2026, 9, 13), isGreen: greenOn(const {})),
        isFalse,
      );
    });
  });

  group('every other cadence is unchanged', () {
    test('a daily habit owes every day it is alive for', () {
      final daily =
        makeHabit(type: HabitFrequencyType.daily, target: 1, id: 'daily');
      for (final day in week()) {
        expect(habitOwesDay(habit: daily, day: day, isGreen: greenOn(const {})),
            isTrue);
      }
    });

    test('a specific-days habit owes only its own weekdays', () {
      // Saturday and Tuesday.
      final sched = makeHabit(
        type: HabitFrequencyType.weekly,
        target: 2,
        weekdays: const [DateTime.saturday, DateTime.tuesday],
      );
      final owed = [
        for (final day in week())
          if (habitOwesDay(habit: sched, day: day, isGreen: greenOn(const {})))
            day.weekday,
      ];
      expect(owed, [DateTime.saturday, DateTime.tuesday]);
    });
  });

  group("Aziz's shampoo: a session on a day off the plan", () {
    // «شامبو ضد القشرة», as stored on his phone: Monday, Thursday and
    // Saturday, created Monday 21 September 2026. That week runs Saturday
    // the 19th to Friday the 25th. He showered on Monday and on Wednesday.
    final shampoo = makeHabit(
      type: HabitFrequencyType.weekly,
      target: 3,
      weekdays: const [DateTime.monday, DateTime.thursday, DateTime.saturday],
      created: DateTime(2026, 9, 21),
      id: 'shampoo',
    );
    final sat = DateTime(2026, 9, 19),
        mon = DateTime(2026, 9, 21),
        tue = DateTime(2026, 9, 22),
        wed = DateTime(2026, 9, 23),
        thu = DateTime(2026, 9, 24);
    final shampooWeek = [
      for (var i = 0; i < 7; i++) DateTime(2026, 9, 19 + i),
    ];
    // Thursday afternoon, the moment he asked.
    final thursdayAfternoon = DateTime(2026, 9, 24, 15);
    bool same(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    GreenOnDay greenOnDays(Set<DateTime> on) =>
        (id, day) => on.any((d) => same(d, day));
    MarkOnDay marks(Map<DateTime, SquareState> on) => (id, day) {
          for (final e in on.entries) {
            if (same(e.key, day)) return e.value;
          }
          return SquareState.none;
        };

    test('Wednesday counts, and Thursday owes nothing any more', () {
      final isGreen = greenOnDays({mon, wed});
      expect(habitOwesDay(habit: shampoo, day: wed, isGreen: isGreen), isTrue,
          reason: 'the session counts on the day it happened');
      expect(habitOwesDay(habit: shampoo, day: thu, isGreen: isGreen), isFalse,
          reason: 'Wednesday stood in for Thursday');
      expect(habitOwesDay(habit: shampoo, day: mon, isGreen: isGreen), isTrue);
      expect(habitOwesDay(habit: shampoo, day: tue, isGreen: isGreen), isFalse);
      expect(habitOwesDay(habit: shampoo, day: sat, isGreen: isGreen), isFalse,
          reason: 'the Saturday before it existed');
    });

    test('without the Wednesday shower, Thursday is owed as before', () {
      final isGreen = greenOnDays({mon});
      expect(habitOwesDay(habit: shampoo, day: thu, isGreen: isGreen), isTrue);
      expect(habitOwesDay(habit: shampoo, day: wed, isGreen: isGreen), isFalse);
    });

    test('the Grid row paints Thursday covered, Tuesday plain', () {
      final green = {mon, wed};
      final row = quotaDemandForRow(
        habit: shampoo,
        days: shampooWeek,
        isGreenAt: (i) => green.any((d) => same(d, shampooWeek[i])),
        isUnmarkedAt: (i) => !green.any((d) => same(d, shampooWeek[i])),
        now: thursdayAfternoon,
      )!;
      expect(row[0], isNull, reason: 'before it existed');
      expect(row[2], DayDemand.done);
      expect(row[4], DayDemand.done);
      expect(row[5], DayDemand.earned);
      expect(
        isCoveredDay(
          habit: shampoo,
          day: thu,
          today: thursdayAfternoon,
          square: SquareState.none,
          demand: row[5],
        ),
        isTrue,
      );
      expect(
        showsTodayRing(isToday: true, isScheduled: true, isCovered: true),
        isFalse,
        reason: 'Thursday stops asking the moment Wednesday lands',
      );
    });

    test('a Monday marked فشل keeps its mark; the shower covers Thursday', () {
      final isGreen = greenOnDays({wed});
      final markOn = marks({mon: SquareState.failed, wed: SquareState.complete});
      expect(
        habitOwesDay(habit: shampoo, day: mon, isGreen: isGreen, markOn: markOn),
        isTrue,
        reason: 'their own verdict on Monday stands',
      );
      expect(
        habitOwesDay(habit: shampoo, day: thu, isGreen: isGreen, markOn: markOn),
        isFalse,
      );
    });

    test('a blank Monday is made up before Thursday', () {
      // Nothing marked on Monday at all: the Wednesday shower makes up the
      // real miss, and Thursday, still ahead, is expected in person.
      final isGreen = greenOnDays({wed});
      final markOn = marks({wed: SquareState.complete});
      expect(
        habitOwesDay(habit: shampoo, day: mon, isGreen: isGreen, markOn: markOn),
        isFalse,
      );
      expect(
        habitOwesDay(habit: shampoo, day: thu, isGreen: isGreen, markOn: markOn),
        isTrue,
      );
    });

    test('a square on a day before it existed is not a session', () {
      // Saturday the 19th, two days before the habit was made: nothing
      // there can stand in for Thursday.
      final isGreen = greenOnDays({mon, sat});
      expect(habitOwesDay(habit: shampoo, day: thu, isGreen: isGreen), isTrue);
    });

    test('a daily row never reads a square for this', () {
      // The progress map asks this of every habit on every day it draws.
      final daily =
          makeHabit(type: HabitFrequencyType.daily, target: 1, id: 'daily');
      var reads = 0;
      final row = movedDemandForRow(
        habit: daily,
        days: shampooWeek,
        isGreenAt: (_) {
          reads++;
          return true;
        },
      );
      expect((row, reads), (null, 0));
    });

    test('its own streak does not count Thursday as a gap', () {
      final isGreen = greenOnDays({mon, wed});
      final runsOn = runsOnExcusing(shampoo, isGreen);
      expect(runsOn(thu), isFalse);
      expect(runsOn(mon), isTrue);
      expect(runsOnExcusing(shampoo, null)(thu), isTrue,
          reason: 'an unreadable week excuses nothing');
    });

    test('Wednesday\'s board carries the shower once it is done', () {
      expect(
        boardHabitsOn(habits: [shampoo], day: wed, isGreen: greenOnDays({mon})),
        isEmpty,
        reason: 'not one of its days, and nothing done on it',
      );
      expect(
        boardHabitsOn(
          habits: [shampoo],
          day: wed,
          isGreen: greenOnDays({mon, wed}),
        ),
        hasLength(1),
      );
      expect(
        boardHabitsOn(
          habits: [shampoo],
          day: thu,
          isGreen: greenOnDays({mon, wed}),
        ),
        isEmpty,
        reason: 'covered: Thursday no longer asks for it',
      );
    });
  });

  group('a live board', () {
    test('keeps a quota habit when this week cannot be read', () {
      final board = boardHabitsOn(
        habits: [quota4],
        day: DateTime(2026, 9, 13),
        isGreen: null,
      );
      expect(board, hasLength(1),
          reason: 'an unreadable week is not evidence of a rest day');
    });

    test('drops it on a rest day once the week can be read', () {
      final board = boardHabitsOn(
        habits: [quota4],
        day: DateTime(2026, 9, 13),
        isGreen: greenOn(const {}),
      );
      expect(board, isEmpty);
    });

    test('keeps the completion that is landing right now', () {
      // Without this, finishing a quota habit on one of its spare days drops
      // it out of the very board it is being counted into, and
      // willCompleteAllHabitsToday denies a day that was actually finished.
      final board = boardHabitsOn(
        habits: [quota4],
        day: DateTime(2026, 9, 13),
        isGreen: greenOn(const {}),
        alsoOwing: {quota4.id},
      );
      expect(board, hasLength(1));
    });
  });

  group("the widget's roster and its count", () {
    // Mirrors _todayHabitStats in main.dart: the LIST is everything allowed
    // today so every row stays tappable from the home screen, while the ring
    // and the app badge count only what the day owed. The invariant that must
    // hold for any week: completed <= total <= list, and total never drops a
    // habit that was actually done.
    // A distinct id: it shares this group's board with quota4, and two
    // habits answering to one id would collapse into a single row.
    final daily =
        makeHabit(type: HabitFrequencyType.daily, target: 1, id: 'daily');

    ({int completed, int total, int listed}) stats({
      required DateTime day,
      required Set<int> quotaDoneDays,
      required Set<String> doneToday,
    }) {
      final habits = [daily, quota4];
      final scheduled = habits.where((h) => h.isScheduledFor(day)).toList();
      final owed = boardHabitsOn(
        habits: scheduled,
        day: day,
        isGreen: greenOn(quotaDoneDays),
        alsoOwing: doneToday,
      ).map((h) => h.id).toSet();
      return (
        completed: doneToday.length,
        total: owed.length,
        listed: scheduled.length,
      );
    }

    test('a rest day leaves the count but keeps the row', () {
      // Sunday 13 September: the quota owes nothing, the daily habit does.
      final s = stats(
        day: DateTime(2026, 9, 13),
        quotaDoneDays: const {},
        doneToday: const {},
      );
      expect(s.listed, 2, reason: 'both rows stay tappable');
      expect(s.total, 1, reason: 'only the daily habit was owed');
      expect(s.completed, 0);
    });

    test('training on a rest day fills the ring rather than bursting it', () {
      // The trap: credit the extra session without also counting it as owed
      // and the ring reads 2 of 1.
      final s = stats(
        day: DateTime(2026, 9, 13),
        quotaDoneDays: const {1},
        doneToday: {daily.id, quota4.id},
      );
      expect(s.total, 2);
      expect(s.completed, 2);
      expect(s.completed, lessThanOrEqualTo(s.total));
    });

    test('completed <= total <= listed, every day of every pattern', () {
      for (var mask = 0; mask < 128; mask++) {
        final done = {
          for (var i = 0; i < 7; i++)
            if (mask & (1 << i) != 0) i,
        };
        for (var i = 0; i < 7; i++) {
          final day = week()[i];
          final s = stats(
            day: day,
            quotaDoneDays: done,
            doneToday: done.contains(i) ? {quota4.id} : const {},
          );
          expect(s.completed, lessThanOrEqualTo(s.total),
              reason: 'day $i, done $done');
          expect(s.total, lessThanOrEqualTo(s.listed),
              reason: 'day $i, done $done');
        }
      }
    });

    test('the badge only ever counts a habit the day asked for', () {
      // badge == total - completed (see _syncBadge).
      final s = stats(
        day: DateTime(2026, 9, 13),
        quotaDoneDays: const {},
        doneToday: {daily.id},
      );
      expect(s.total - s.completed, 0,
          reason: 'nothing outstanding: the quota was never due');
    });
  });

  test('weekStart anchors on Saturday, like every other week in the app', () {
    expect(weekStart.weekday, DateTime.saturday);
    expect(DateTime(2026, 9, 13).weekday, DateTime.sunday);
  });
}
