// The per-day score behind the 14-day chart on ProgressHubScreen
// (lib/features/milestones/reports/day_score.dart).
//
// ── Why this file is mostly about the DENOMINATOR ────────────────────────
// The numerator is easy and was never wrong: count the green marks. What the
// chart could not do before was say "of how many", and every interesting way
// to get that wrong is a way to accuse somebody of a day nobody owed them.
// A quota habit ("three times a week, any three") owes no particular
// Tuesday; a habit created last week owes nothing the week before; a day
// marked تخطّي owes nothing at all. Each of those, got wrong, turns a
// perfectly kept fortnight into a chart full of gaps.
//
// The chart it replaced summed the daily document's habitCompletions map,
// which is a TAP count. Cross-checked on a real account over 29 Aug - 4 Sep
// it read 13 for a week the reports hub read as 12. Several tests here pin
// the difference between those two numbers directly.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/milestones/reports/day_score.dart';

void main() {
  IslamicHabitTemplate habit({
    String id = 'h1',
    HabitFrequencyType frequencyType = HabitFrequencyType.daily,
    int frequencyTarget = 1,
    List<int> scheduledWeekdays = const [],
    DateTime? createdAt,
    DateTime? archivedAt,
  }) =>
      IslamicHabitTemplate(
        id: id,
        name: id,
        description: '',
        category: HabitCategory.faith,
        frequencyType: frequencyType,
        frequencyTarget: frequencyTarget,
        scheduledWeekdays: scheduledWeekdays,
        hasTimer: false,
        xpReward: 10,
        goldReward: 1,
        createdAt: createdAt,
        archivedAt: archivedAt,
      );

  // 2026-08-19 is a Wednesday.
  final wed = DateTime(2026, 8, 19);
  final thu = DateTime(2026, 8, 20);

  Map<String, Map<String, SquareState>> historyOf(
    Map<String, Map<DateTime, SquareState>> raw,
  ) =>
      {
        for (final entry in raw.entries)
          entry.key: {
            for (final day in entry.value.entries) day.key.toDateKey(): day.value,
          },
      };

  DayScore scoreOf(
    List<IslamicHabitTemplate> habits,
    Map<String, Map<DateTime, SquareState>> raw, {
    DateTime? day,
  }) =>
      dayScoreFor(
        habits: habits,
        history: historyOf(raw),
        day: day ?? wed,
      );

  group('the plain case', () {
    test('four of ten done reads as 4 out of 10', () {
      final habits = [for (var i = 0; i < 10; i++) habit(id: 'h$i')];
      final score = scoreOf(habits, {
        for (var i = 0; i < 4; i++) 'h$i': {wed: SquareState.complete},
      });
      expect(score.done, 4);
      expect(score.owed, 10);
      expect(score.credit, 4);
      expect(score.rate, closeTo(0.4, 1e-9));
    });

    test('a perfect day is perfect, an empty one is not', () {
      final habits = [habit(id: 'a'), habit(id: 'b')];
      expect(
        scoreOf(habits, {
          'a': {wed: SquareState.complete},
          'b': {wed: SquareState.bonus},
        }).isPerfect,
        isTrue,
      );
      expect(scoreOf(habits, const {}).isPerfect, isFalse);
    });
  });

  group('the marks carry their documented weights', () {
    test('bonus is a full day and keeps its own mark', () {
      final score = scoreOf([habit()], {
        'h1': {wed: SquareState.bonus},
      });
      expect(score.done, 1);
      expect(score.credit, 1);
    });

    test('جزئي is half a day but is NOT counted as done', () {
      // The two numbers deliberately disagree here, and that is the whole
      // reason DayScore carries both. The chart prints `done`, which must
      // equal what dayCountsFrom and the day sheet print, while the line
      // height uses `credit`, which carries the half. Printing 0.5 would put
      // a number on screen no other surface in this app can produce.
      final score = scoreOf([habit()], {
        'h1': {wed: SquareState.partial},
      });
      expect(score.done, 0);
      expect(score.credit, 0.5);
      expect(score.rate, closeTo(0.5, 1e-9));
    });

    test('فشل earns nothing and STAYS in the denominator', () {
      final score = scoreOf([habit()], {
        'h1': {wed: SquareState.failed},
      });
      expect(score.credit, 0);
      expect(score.owed, 1);
      expect(score.failed, 1);
      expect(score.rate, 0);
    });

    test('تخطّي leaves the denominator entirely', () {
      // The app's stated position is that a rest day is not a missed day.
      // Before the reports learned this, choosing to rest lowered a
      // percentage by exactly as much as forgetting would have.
      final score = scoreOf([habit(id: 'a'), habit(id: 'b')], {
        'a': {wed: SquareState.complete},
        'b': {wed: SquareState.skipped},
      });
      expect(score.owed, 1);
      expect(score.rested, 1);
      expect(score.rate, 1.0);
      expect(score.isPerfect, isTrue);
    });

    test('a day where everything was rested owes nothing and is not silent', () {
      final score = scoreOf([habit()], {
        'h1': {wed: SquareState.skipped},
      });
      expect(score.owed, 0);
      expect(score.rested, 1);
      expect(score.rate, isNull, reason: 'never 0%, and never 100%');
      expect(score.isSilent, isFalse, reason: 'a stand-down earns its own mark');
    });

    test('فشل and an empty square score the same but are not the same', () {
      final failed = scoreOf([habit()], {
        'h1': {wed: SquareState.failed},
      });
      final blank = scoreOf([habit()], const {});
      expect(failed.rate, blank.rate);
      expect(failed.failed, 1);
      expect(blank.failed, 0, reason: 'only the chart marker distinguishes them');
    });
  });

  group('a quota habit owes no particular day', () {
    final quota = habit(
      id: 'q',
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 3,
    );

    test('a blank day for a quota habit is not a miss', () {
      // This is the bug missIsAttributable exists to forbid: a habit with a
      // target of four, hit four times, was rendering four filled cells
      // beside three "missed" outlines AND a PERFECT badge on one row.
      final score = scoreOf([quota], const {});
      expect(score.owed, 0);
      expect(score.rate, isNull);
    });

    test('a quota habit that WAS done adds to both sides, never above 100%', () {
      final score = scoreOf([quota], {
        'q': {wed: SquareState.complete},
      });
      expect(score.done, 1);
      expect(score.owed, 1);
      expect(score.rate, 1.0);
    });

    test('a quota habit cannot push a real day above its own ceiling', () {
      final score = scoreOf([habit(id: 'daily'), quota], {
        'daily': {wed: SquareState.complete},
        'q': {wed: SquareState.complete},
      });
      expect(score.done, 2);
      expect(score.owed, 2);
      expect(score.rate, 1.0);
    });

    test('an explicit فشل on a quota day still counts against it', () {
      // Marking a failure is someone telling the app that day was owed.
      final score = scoreOf([quota], {
        'q': {wed: SquareState.failed},
      });
      expect(score.owed, 1);
      expect(score.rate, 0);
    });
  });

  group('a habit only answers for days it was alive', () {
    test('nothing is owed before the habit was created', () {
      final score = scoreOf([habit(createdAt: thu)], const {});
      expect(score.owed, 0, reason: 'wed is the day before it existed');
      expect(score.isSilent, isTrue);
    });

    test('nothing is owed after it was archived', () {
      final score = scoreOf(
        [habit(createdAt: DateTime(2026, 1, 1), archivedAt: wed)],
        const {},
        day: thu,
      );
      expect(score.owed, 0);
    });

    test('an archived habit still counts on a day it actually did something', () {
      // Archiving means "not part of my present". It does not mean the day
      // it was kept never happened, and hiding that would be its own lie.
      final score = scoreOf(
        [habit(createdAt: DateTime(2026, 1, 1), archivedAt: wed)],
        {
          'h1': {thu: SquareState.complete},
        },
        day: thu,
      );
      expect(score.done, 1);
      expect(score.owed, 1);
    });

    test('a weekday-scheduled habit owes only its own weekdays', () {
      // Mondays and Thursdays only; wed is a Wednesday.
      final monThu = habit(scheduledWeekdays: const [1, 4]);
      expect(scoreOf([monThu], const {}).owed, 0);
      expect(scoreOf([monThu], const {}, day: thu).owed, 1);
    });
  });

  group('stints: the same habit id emitted more than once', () {
    test('a paused and resumed habit answers for BOTH of its stints', () {
      // allHabitsEverProvider emits one synthetic template per catalog
      // stint, each with its own createdAt/archivedAt. Deduping by id first
      // (which the reports hub does, for its own good reason: it renders one
      // row per habit) keeps whichever came out first and silently drops
      // every day belonging to the others. dayScoreFor collects ids into a
      // Set instead, so each stint claims its own days.
      final stints = [
        habit(
          createdAt: DateTime(2026, 8, 1),
          archivedAt: DateTime(2026, 8, 10),
        ),
        habit(createdAt: DateTime(2026, 8, 18)),
      ];
      expect(scoreOf(stints, const {}, day: DateTime(2026, 8, 5)).owed, 1);
      expect(scoreOf(stints, const {}, day: DateTime(2026, 8, 14)).owed, 0);
      expect(scoreOf(stints, const {}, day: wed).owed, 1);
    });

    test('two stints never double-count the same day', () {
      final stints = [
        habit(createdAt: DateTime(2026, 1, 1)),
        habit(createdAt: DateTime(2026, 1, 1)),
      ];
      final score = scoreOf(stints, {
        'h1': {wed: SquareState.complete},
      });
      expect(score.owed, 1);
      expect(score.done, 1);
    });
  });

  group('a day that asked for nothing is never a zero', () {
    test('no habits at all is silent, not failed', () {
      final score = scoreOf(const [], const {});
      expect(score.owed, 0);
      expect(score.rate, isNull);
      expect(score.isSilent, isTrue);
      expect(score.isPerfect, isFalse);
    });

    test('rate is null rather than 0 so a caller cannot render it as failure', () {
      // `rate ?? 0` at a call site reintroduces exactly the lie the nullable
      // return type exists to prevent, so this pins the type, not a value.
      expect(scoreOf(const [], const {}).rate, isNull);
    });
  });

  group('computeDayScores and windowRate', () {
    final days = [for (var i = 0; i < 5; i++) DateTime(2026, 8, 15 + i)];

    test('scores come back in the order the days went in', () {
      final scores = computeDayScores(
        habits: [habit()],
        history: const {},
        days: days,
      );
      expect(scores.map((s) => s.day), days);
    });

    test('the window rate weighs days by size, not by day', () {
      // Deliberately not the mean of the daily rates. Day one owed ten and
      // got one; day two owed one and got one. The mean of the rates is 55%,
      // which flatters a bad fortnight by letting a one-habit day count as
      // much as a ten-habit one. Credit over obligation is 2 of 11.
      final habits = [for (var i = 0; i < 10; i++) habit(id: 'h$i')];
      final scores = [
        dayScoreFor(
          habits: habits,
          history: historyOf({
            'h0': {days[0]: SquareState.complete},
          }),
          day: days[0],
        ),
        dayScoreFor(
          habits: [habit(id: 'h0')],
          history: historyOf({
            'h0': {days[1]: SquareState.complete},
          }),
          day: days[1],
        ),
      ];
      expect(windowRate(scores), closeTo(2 / 11, 1e-9));
    });

    test('a window that owed nothing has no rate', () {
      expect(windowRate(const []), isNull);
      expect(
        windowRate(computeDayScores(habits: const [], history: const {}, days: days)),
        isNull,
      );
    });
  });

  group('silentHabitsOn: the denominator, itemised', () {
    test('names exactly the habits that owed the day and did nothing', () {
      final habits = [habit(id: 'a'), habit(id: 'b'), habit(id: 'c')];
      final history = historyOf({
        'a': {wed: SquareState.complete},
        'b': {wed: SquareState.skipped},
      });
      final silent = silentHabitsOn(habits: habits, history: history, day: wed);
      expect(silent.map((h) => h.id), ['c']);
    });

    test('the rows and the fraction can never disagree', () {
      // The sheet claims "N of OWED"; this pins that OWED is always
      // reachable as (rows that recorded something) + (silent rows).
      final habits = [for (var i = 0; i < 6; i++) habit(id: 'h$i')];
      final history = historyOf({
        'h0': {wed: SquareState.complete},
        'h1': {wed: SquareState.partial},
        'h2': {wed: SquareState.failed},
      });
      final score = dayScoreFor(habits: habits, history: history, day: wed);
      final silent = silentHabitsOn(habits: habits, history: history, day: wed);
      expect(score.owed, 3 + silent.length);
      expect(silent.length, 3);
    });

    test('a quota habit is never listed as owing a particular day', () {
      final quota = habit(
        id: 'q',
        frequencyType: HabitFrequencyType.weekly,
        frequencyTarget: 3,
      );
      expect(silentHabitsOn(habits: [quota], history: const {}, day: wed), isEmpty);
    });

    test('one row per habit even when its id arrives twice', () {
      final stints = [
        habit(createdAt: DateTime(2026, 1, 1)),
        habit(createdAt: DateTime(2026, 1, 1)),
      ];
      expect(
        silentHabitsOn(habits: stints, history: const {}, day: wed).length,
        1,
      );
    });
  });
}
