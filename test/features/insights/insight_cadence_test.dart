// What the Insights engine may say about a habit that does not run every
// day (Aziz, 2026-09-18). His screenshot: «الصدقة ولو بالقليل», a Monday and
// Thursday habit, 63% over «آخر 8 أسابيع · 25 يوليو – 18 سبتمبر», Monday 75%
// and Thursday 50%, drawn on a seven-day wave with five dashes.
//
// Three things are pinned here, all pure:
//  * a specific-days habit keeps a record of its own days only, and the
//    record's cells are exactly the days its counts were taken from;
//  * "slips most on X" needs a real comparison: two or more weekdays with
//    samples, and for a specific-days habit no tie;
//  * a weekly quota never makes a weekday claim at all, because which of its
//    blank days count as owed is arithmetic that always lands on the end of
//    a short week. Its record is its weeks instead.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/insights/insight_engine.dart';
import 'package:grow_daily_v2/features/insights/insights_screen.dart'
    show recordRowDays;

IslamicHabitTemplate habit(
  String id, {
  HabitFrequencyType type = HabitFrequencyType.daily,
  int target = 1,
  List<int> weekdays = const [],
  DateTime? createdAt,
}) =>
    IslamicHabitTemplate(
      id: id,
      name: id,
      description: '',
      category: HabitCategory.faith,
      frequencyType: type,
      frequencyTarget: target,
      scheduledWeekdays: weekdays,
      hasTimer: false,
      xpReward: 10,
      goldReward: 1,
      createdAt: createdAt,
    );

/// The screenshot's window: 56 days, Saturday 25 July to Friday 18 September
/// 2026, newest first, the way loadInsightsWindow hands them over.
final end = DateTime(2026, 9, 18);
final start = DateTime(2026, 7, 25);
List<DateTime> windowDays() => [
      for (var i = 0; i < 56; i++) DateTime(end.year, end.month, end.day - i),
    ];

List<(DateTime, Map<String, dynamic>)> docs(
  String id,
  Map<DateTime, SquareState> marks,
) =>
    [
      for (final d in windowDays())
        (
          d,
          {
            if (marks[d] != null) 'squareStates': {id: marks[d]!.name},
          },
        ),
    ];

void main() {
  // Friday 18 September at 14:00: Thursday closed at 10:00 this morning.
  final at1400 = DateTime(2026, 9, 18, 14);

  group('InsightCadence', () {
    test('tells the three shapes apart the way the habit is stored', () {
      expect(InsightCadence.of(habit('d')), InsightCadence.daily);
      // "Specific days" is stored as weekly, told apart by its weekday list.
      expect(
        InsightCadence.of(habit('s',
            type: HabitFrequencyType.weekly,
            target: 2,
            weekdays: const [DateTime.monday, DateTime.thursday])),
        InsightCadence.specificDays,
      );
      expect(
        InsightCadence.of(habit('q', type: HabitFrequencyType.weekly, target: 4)),
        InsightCadence.weeklyQuota,
      );
      expect(
        InsightCadence.of(habit('all', weekdays: const [1, 2, 3, 4, 5, 6, 7])),
        InsightCadence.daily,
        reason: 'all seven days is a daily habit spelled the long way',
      );
    });

    test('the week runs in the Grid order, Saturday first', () {
      expect(displayWeekOrder, [
        DateTime.saturday,
        DateTime.sunday,
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
        DateTime.friday,
      ]);
    });
  });

  group("the screenshot's habit, Monday and Thursday", () {
    final sadaqa = habit(
      'sadaqa',
      type: HabitFrequencyType.weekly,
      target: 2,
      weekdays: const [DateTime.monday, DateTime.thursday],
      createdAt: DateTime(2026, 6, 1),
    );
    // Monday 6 of 8, Thursday 4 of 8: the screenshot's 75% and 50%.
    final marks = <DateTime, SquareState>{
      for (final d in [
        DateTime(2026, 7, 27),
        DateTime(2026, 8, 10),
        DateTime(2026, 8, 17),
        DateTime(2026, 8, 24),
        DateTime(2026, 8, 31),
        DateTime(2026, 9, 14),
      ])
        d: SquareState.complete,
      for (final d in [
        DateTime(2026, 7, 30),
        DateTime(2026, 8, 20),
        DateTime(2026, 8, 27),
        DateTime(2026, 9, 10),
      ])
        d: SquareState.complete,
    };
    late HabitPattern p;
    late InsightsResult result;

    setUp(() {
      result = computeInsights(
        habits: [sadaqa],
        days: docs('sadaqa', marks),
        now: at1400,
      );
      p = result.patterns['sadaqa']!;
    });

    test('the numbers on the screenshot', () {
      expect((p.completed, p.scheduled), (10, 16));
      expect((p.rate * 100).round(), 63);
      expect(p.scheduledByWeekday,
          {DateTime.monday: 8, DateTime.thursday: 8});
      expect(p.completedByWeekday,
          {DateTime.monday: 6, DateTime.thursday: 4});
      expect(p.worstWeekday(), DateTime.thursday);
    });

    test('its record holds its own two days and nothing else', () {
      expect(p.cadence, InsightCadence.specificDays);
      expect(p.weekdays, [DateTime.monday, DateTime.thursday]);
      expect(p.record, hasLength(16));
      expect(
        p.record.values.map((d) => d.day.weekday).toSet(),
        {DateTime.monday, DateTime.thursday},
      );
    });

    test('the cells ARE the counts: counted cells sum to the rate', () {
      final counted = p.record.values.where((d) => d.counted);
      expect(counted.length, p.scheduled);
      expect(counted.where((d) => d.done).length, p.completed);
      for (final weekday in p.weekdays) {
        final row = counted.where((d) => d.day.weekday == weekday);
        expect(row.length, p.scheduledByWeekday[weekday]);
        expect(row.where((d) => d.done).length, p.completedByWeekday[weekday]);
      }
    });

    test('each row lays out exactly the eight days its count came from', () {
      final window = (windowStart: result.windowStart!, windowEnd: result.windowEnd!);
      expect(window, (windowStart: start, windowEnd: end));
      final mondays = recordRowDays(
        weekday: DateTime.monday,
        windowStart: window.windowStart,
        windowEnd: window.windowEnd,
      );
      expect(mondays, [
        DateTime(2026, 7, 27),
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 10),
        DateTime(2026, 8, 17),
        DateTime(2026, 8, 24),
        DateTime(2026, 8, 31),
        DateTime(2026, 9, 7),
        DateTime(2026, 9, 14),
      ]);
      final thursdays = recordRowDays(
        weekday: DateTime.thursday,
        windowStart: window.windowStart,
        windowEnd: window.windowEnd,
      );
      expect(thursdays.first, DateTime(2026, 7, 30));
      expect(thursdays.last, DateTime(2026, 9, 17));
      for (final row in [mondays, thursdays]) {
        expect(row, hasLength(8));
        expect(row.every((d) => p.record.containsKey(d!.toDateKey())), isTrue);
      }
    });

    test('a Thursday still open at 05:00 is a cell, but not a miss yet', () {
      final early = computeInsights(
        habits: [sadaqa],
        days: docs('sadaqa', marks),
        now: DateTime(2026, 9, 18, 5),
      ).patterns['sadaqa']!;
      final thursday = early.record[DateTime(2026, 9, 17).toDateKey()]!;
      expect(thursday.state, InsightDayState.open);
      expect(early.scheduledByWeekday[DateTime.thursday], 7);
      expect(p.record[DateTime(2026, 9, 17).toDateKey()]!.state,
          InsightDayState.missed,
          reason: 'at 14:00 the same Thursday has closed');
    });
  });

  group('InsightDay.state', () {
    InsightDayState state(
      SquareState mark, {
      bool done = false,
      bool owed = true,
      bool counted = true,
    }) =>
        InsightDay(
          day: DateTime(2026, 9, 17),
          mark: mark,
          done: done,
          owed: owed,
          counted: counted,
        ).state;

    test('reads each mark the way the row count read it', () {
      expect(state(SquareState.complete, done: true), InsightDayState.done);
      expect(state(SquareState.bonus, done: true), InsightDayState.bonus);
      // A counted habit part way there has no green square, and this engine
      // calls it done: its cell says so too.
      expect(state(SquareState.none, done: true), InsightDayState.done);
      expect(state(SquareState.partial), InsightDayState.partial);
      expect(state(SquareState.failed), InsightDayState.failed);
      expect(state(SquareState.none), InsightDayState.missed);
      expect(state(SquareState.skipped, counted: false), InsightDayState.rest);
      expect(state(SquareState.none, counted: false), InsightDayState.open);
      expect(state(SquareState.partial, counted: false), InsightDayState.open);
      expect(state(SquareState.none, owed: false, counted: false),
          InsightDayState.covered);
    });
  });

  group('"slips most on X" needs a real comparison', () {
    Map<DateTime, SquareState> doneOn(bool Function(DateTime) when) => {
          for (final d in windowDays())
            if (when(d)) d: SquareState.complete,
        };

    test('a specific-days habit with its two days level names neither', () {
      final h = habit('mt',
          type: HabitFrequencyType.weekly,
          target: 2,
          weekdays: const [DateTime.monday, DateTime.thursday]);
      // Four of eight on each: a tie is the absence of a weaker day.
      final p = computeInsights(
        habits: [h],
        days: docs('mt', doneOn((d) => d.day <= 14)),
        now: at1400,
      ).patterns['mt']!;
      expect(p.completedByWeekday[DateTime.monday],
          p.completedByWeekday[DateTime.thursday]);
      expect(p.worstWeekday(), isNull);
    });

    test('a daily habit keeps the first of a tie, as it always has', () {
      // Every Monday and every Thursday missed, every other day done.
      final p = computeInsights(
        habits: [habit('d')],
        days: docs(
            'd',
            doneOn((d) =>
                d.weekday != DateTime.monday &&
                d.weekday != DateTime.thursday)),
        now: at1400,
      ).patterns['d']!;
      expect(p.worstWeekday(), anyOf(DateTime.monday, DateTime.thursday));
    });

    test('a habit with one day has nothing to compare it with', () {
      final friday = habit('kahf', weekdays: const [DateTime.friday]);
      final p = computeInsights(
        habits: [friday],
        days: docs('kahf', const {}),
        now: at1400,
      ).patterns['kahf']!;
      expect(p.scheduledByWeekday, {DateTime.friday: 7},
          reason: 'today, Friday, is still open');
      expect(p.worstWeekday(), isNull,
          reason: '"slips most on Fridays" of a Friday-only habit says nothing');
    });
  });

  group('a weekly quota', () {
    // «تمرين», 4 times a week, trained Saturday, Sunday and Monday every week:
    // three of four, every week.
    final training = habit('ex',
        type: HabitFrequencyType.weekly,
        target: 4,
        createdAt: DateTime(2026, 6, 1));
    Map<DateTime, SquareState> satSunMon() => {
          for (final d in windowDays())
            if (d.weekday == DateTime.saturday ||
                d.weekday == DateTime.sunday ||
                d.weekday == DateTime.monday)
              d: SquareState.complete,
        };

    test('never slips "most on" a weekday: that is where its weeks end', () {
      final result = computeInsights(
        habits: [training],
        days: docs('ex', satSunMon()),
        now: at1400,
      );
      final p = result.patterns['ex']!;
      // The artifact itself: every blank day a short week owes is its LAST.
      expect(p.scheduledByWeekday.keys.toSet(),
          {DateTime.saturday, DateTime.sunday, DateTime.monday, DateTime.friday});
      expect(p.completedByWeekday[DateTime.friday], isNull,
          reason: 'Friday enters only as the owed, empty last day');
      expect(p.worstWeekday(), isNull);
      expect(result.overallScheduledByWeekday, isEmpty,
          reason: 'a quota stays out of the account-wide weekday spread');
      expect(result.totalSamples, p.scheduled,
          reason: 'but still counts toward having enough data');
    });

    test('its record is its eight Saturday weeks', () {
      final p = computeInsights(
        habits: [training],
        days: docs('ex', satSunMon()),
        now: at1400,
      ).patterns['ex']!;
      expect(p.quotaWeeks, hasLength(8));
      expect(p.quotaWeeks.first.start, DateTime(2026, 7, 25));
      expect(p.quotaWeeks.last.start, DateTime(2026, 9, 12));
      expect(p.quotaWeeks.every((w) => w.done == 3 && w.target == 4), isTrue);
      expect(p.quotaWeeks.every((w) => w.whole), isTrue);
      // This week: 3 done, and today, Friday, still open. One session left
      // and one day to do it in, so the week is not decided yet.
      expect(p.quotaWeeks.last.settled, isFalse);
      expect(p.quotaWeeks.take(7).every((w) => w.scored), isTrue);
      expect(p.quotaShortfall(), (met: 0, weeks: 7));
      expect(p.quotaAveragePerWeek, 3);
      expect(p.quotaTarget, 4);
    });

    test('a week already out of reach is decided before it ends', () {
      // Nothing at all this week, read on Friday: four sessions needed, one
      // day left.
      final marks = satSunMon()
        ..removeWhere((d, _) => !d.isBefore(DateTime(2026, 9, 12)));
      final p = computeInsights(
        habits: [training],
        days: docs('ex', marks),
        now: at1400,
      ).patterns['ex']!;
      expect(p.quotaWeeks.last.done, 0);
      expect(p.quotaWeeks.last.settled, isTrue);
      expect(p.quotaShortfall(), (met: 0, weeks: 8));
    });

    test('a week that reached its target is decided at once', () {
      final marks = satSunMon()..[DateTime(2026, 9, 15)] = SquareState.complete;
      final p = computeInsights(
        habits: [training],
        days: docs('ex', marks),
        now: at1400,
      ).patterns['ex']!;
      expect(p.quotaWeeks.last.met, isTrue);
      expect(p.quotaWeeks.last.scored, isTrue);
      expect(p.quotaShortfall(), (met: 1, weeks: 8));
    });

    test('a habit that began mid-window scores only its whole weeks', () {
      final late = habit('ex',
          type: HabitFrequencyType.weekly,
          target: 4,
          createdAt: DateTime(2026, 8, 19)); // a Wednesday
      final p = computeInsights(
        habits: [late],
        days: docs('ex', satSunMon()),
        now: at1400,
      ).patterns['ex']!;
      final scored = p.quotaWeeks.where((w) => w.scored).toList();
      expect(scored.first.start, DateTime(2026, 8, 22),
          reason: 'the week of 15 August asked for less than four');
      expect(scored, hasLength(3));
    });

    test('meeting the target most weeks is not a slip worth a card', () {
      // A fourth session every Tuesday but one: seven weeks of eight met.
      final marks = satSunMon();
      for (final d in windowDays()) {
        if (d.weekday == DateTime.tuesday && d != DateTime(2026, 8, 4)) {
          marks[d] = SquareState.complete;
        }
      }
      final p = computeInsights(
        habits: [training],
        days: docs('ex', marks),
        now: at1400,
      ).patterns['ex']!;
      final met = p.quotaWeeks.where((w) => w.scored && w.met).length;
      final scored = p.quotaWeeks.where((w) => w.scored).length;
      expect(met * 2 > scored, isTrue, reason: 'the fixture: most weeks met');
      expect(p.quotaShortfall(), isNull);
    });
  });

  group('recordRowDays', () {
    test('a window that is not whole weeks leaves the front of a row empty', () {
      // Ten days, Wednesday 9 to Friday 18 September: two blocks.
      final row = recordRowDays(
        weekday: DateTime.monday,
        windowStart: DateTime(2026, 9, 9),
        windowEnd: DateTime(2026, 9, 18),
      );
      expect(row, [null, DateTime(2026, 9, 14)],
          reason: 'the Monday of the first block, 7 September, was never read');
      expect(
        recordRowDays(
          weekday: DateTime.thursday,
          windowStart: DateTime(2026, 9, 9),
          windowEnd: DateTime(2026, 9, 18),
        ),
        [DateTime(2026, 9, 10), DateTime(2026, 9, 17)],
      );
    });
  });
}
