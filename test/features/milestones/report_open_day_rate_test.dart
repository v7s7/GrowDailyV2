// A day still open never counts as missed on the reports hub.
//
// Aziz, 2026-09-11 at 05:19, Reports > شهري > سبتمبر 2026: «2 يوم 18%» under
// أذكار الصباح, greens on the 3rd and the 7th. Eighteen percent is 2 of 11,
// which is only true if the 11th, still open, already counted as a miss. The
// rule these tests pin: a day still open enters a percentage only once it is
// answered (done, or فشل) or once it closes at kDayCutoffHour the next
// morning, and a blank day that has closed counts as missed exactly as it
// always did.
//
// The four habits below are the shapes his card percentages imply. They were
// inferred from the screenshot, not read from his account.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/milestones/reports/habit_day_marks.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';

void main() {
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

  String sep(int day) => DateTime(2026, 9, day).toDateKey();
  DateTime sepAt(int day, int hour, [int minute = 0]) =>
      DateTime(2026, 9, day, hour, minute);

  // The clocks that matter on Friday the 11th and the morning after it.
  final midnight11 = sepAt(11, 0);
  final at0519 = sepAt(11, 5, 19);
  final beforeCutoff11 = sepAt(11, kDayCutoffHour - 1, 59);
  final cutoff11 = sepAt(11, kDayCutoffHour);
  final lateOn11 = sepAt(11, 23, 59);
  final beforeCutoff12 = sepAt(12, kDayCutoffHour - 1, 59);
  final cutoff12 = sepAt(12, kDayCutoffHour);

  test('the calendar these tests rest on', () {
    expect(DateTime(2026, 9, 5).weekday, DateTime.saturday);
    expect(DateTime(2026, 9, 7).weekday, DateTime.monday);
    expect(DateTime(2026, 9, 10).weekday, DateTime.thursday);
    expect(DateTime(2026, 9, 11).weekday, DateTime.friday);
  });

  final adhkar = habit('adhkar');
  final sadaqa = habit(
    'sadaqa',
    type: HabitFrequencyType.weekly,
    target: 2,
    weekdays: const [DateTime.monday, DateTime.thursday],
  );
  final quran = habit('quran', createdAt: DateTime(2026, 9, 9));
  final training = habit('training', type: HabitFrequencyType.weekly, target: 4);

  Map<String, Map<String, SquareState>> septemberHistory({
    Map<String, SquareState> adhkarExtra = const {},
  }) =>
      {
        'adhkar': {
          sep(3): SquareState.complete,
          sep(7): SquareState.complete,
          ...adhkarExtra,
        },
        'sadaqa': {sep(7): SquareState.complete, sep(10): SquareState.complete},
        'quran': {sep(9): SquareState.complete, sep(10): SquareState.complete},
        'training': {
          sep(2): SquareState.complete,
          sep(3): SquareState.complete,
          sep(8): SquareState.partial,
        },
      };

  final september = reportWindow(ReportScope.month, DateTime(2026, 9, 11));

  /// One habit's September card as the reports hub computes it at [now]. A
  /// null clock is the old reading, taken on [today].
  HabitPeriodStat card(
    IslamicHabitTemplate h,
    DateTime? now, {
    Map<String, Map<String, SquareState>>? history,
    DateTime? today,
  }) {
    final day = (now ?? today ?? DateTime(2026, 9, 11)).effectiveDay;
    return computeHabitPeriodStats(
      habits: [h],
      history: history ?? septemberHistory(),
      days: elapsedDaysIn(
        start: september.start,
        end: september.end,
        today: day,
      ),
      now: now,
      windowEnd: september.end,
    ).single;
  }

  String pct(HabitPeriodStat s) => '${(s.rate * 100).round()}%';

  group("Aziz's September cards, clock by clock", () {
    test('with no clock the numbers are exactly the screenshot', () {
      expect((card(adhkar, null).expected, pct(card(adhkar, null))), (11, '18%'));
      expect((card(sadaqa, null).expected, pct(card(sadaqa, null))), (3, '67%'));
      expect((card(quran, null).expected, pct(card(quran, null))), (3, '67%'));
      final t = card(training, null);
      expect((t.expected, t.creditedUnits, pct(t)), (8, 2.5, '31%'));
    });

    test('from 00:00 to 09:59 on the 11th, the 10th and 11th are still open',
        () {
      for (final now in [midnight11, at0519, beforeCutoff11]) {
        final a = card(adhkar, now);
        expect((a.expected, pct(a)), (9, '22%'), reason: 'adhkar at $now');
        final s = card(sadaqa, now);
        expect((s.expected, pct(s)), (3, '67%'),
            reason: 'the 10th is answered green, so it counts at once');
        final q = card(quran, now);
        expect((q.expected, pct(q), q.isPerfect), (2, '100%', true),
            reason: 'quran at $now');
        final t = card(training, now);
        expect((t.expected, t.creditedUnits, pct(t)), (6, 2.5, '42%'),
            reason: 'training at $now');
      }
    });

    test('from 10:00 on the 11th to 09:59 on the 12th, the 10th has closed',
        () {
      for (final now in [cutoff11, lateOn11, beforeCutoff12]) {
        final a = card(adhkar, now);
        expect((a.expected, pct(a)), (10, '20%'), reason: 'adhkar at $now');
        expect(pct(card(sadaqa, now)), '67%', reason: 'sadaqa at $now');
        final q = card(quran, now);
        expect((q.expected, pct(q)), (2, '100%'), reason: 'quran at $now');
        final t = card(training, now);
        expect((t.expected, pct(t)), (7, '36%'), reason: 'training at $now');
      }
    });

    test('from 10:00 on the 12th, the 11th has closed as well', () {
      final a = card(adhkar, cutoff12);
      expect((a.expected, pct(a)), (11, '18%'));
      expect(pct(card(sadaqa, cutoff12)), '67%');
      final q = card(quran, cutoff12);
      expect((q.expected, pct(q), q.isPerfect), (3, '67%', false));
      final t = card(training, cutoff12);
      expect((t.expected, pct(t)), (8, '31%'));
    });

    test('the day count beside the percentage never moves with the clock', () {
      for (final now in [null, at0519, cutoff11, cutoff12]) {
        expect(card(adhkar, now).doneCount, 2, reason: '$now');
        expect(card(training, now).doneCount, 2, reason: '$now');
      }
    });
  });

  group('a mark on the day still open', () {
    HabitPeriodStat adhkarWith(SquareState mark, DateTime now) => card(
          adhkar,
          now,
          history: septemberHistory(adhkarExtra: {sep(11): mark}),
        );

    test('done enters at once: 3 of 10', () {
      final s = adhkarWith(SquareState.complete, at0519);
      expect((s.expected, s.creditedUnits), (10, 3.0));
    });

    test('جزئي is held out of both sides until it closes, then half of one',
        () {
      final open = adhkarWith(SquareState.partial, at0519);
      expect((open.expected, open.creditedUnits), (9, 2.0));
      final closed = adhkarWith(SquareState.partial, cutoff12);
      expect((closed.expected, closed.creditedUnits), (11, 2.5));
    });

    test('فشل enters at once as a miss: 2 of 10', () {
      final s = adhkarWith(SquareState.failed, at0519);
      expect((s.expected, s.creditedUnits, s.failedCount), (10, 2.0, 1));
    });

    test('تخطّي leaves both sides, open or closed', () {
      final open = adhkarWith(SquareState.skipped, at0519);
      expect((open.expected, open.creditedUnits), (9, 2.0));
      final closed = adhkarWith(SquareState.skipped, cutoff12);
      expect((closed.expected, closed.creditedUnits), (10, 2.0));
    });

    test('finishing the open day can only raise the percentage', () {
      final blank = card(adhkar, at0519).rate;
      final half = adhkarWith(SquareState.partial, at0519).rate;
      final done = adhkarWith(SquareState.complete, at0519).rate;
      expect(half, blank, reason: 'half of today is not yet a number');
      expect(done, greaterThan(blank));
    });
  });

  group('days the habit never asked for', () {
    test('a habit created today owes nothing yet, and keeps its card', () {
      final fresh = habit('fresh', createdAt: DateTime(2026, 9, 11));
      for (final now in [at0519, cutoff11]) {
        final stats = computeHabitPeriodStats(
          habits: [fresh],
          history: const {},
          days: elapsedDaysIn(
            start: september.start,
            end: september.end,
            today: now.effectiveDay,
          ),
          now: now,
          windowEnd: september.end,
        );
        expect(stats, hasLength(1), reason: 'the card must not vanish');
        expect(stats.single.expected, 0);
        expect(stats.single.hasRate, isFalse,
            reason: 'the card prints a placeholder, not 0%');
        expect(stats.single.isPerfect, isFalse);
      }
      final closed = card(fresh, cutoff12, history: const {});
      expect((closed.expected, closed.hasRate, closed.rate), (1, true, 0.0));
    });

    test('a day off the schedule changes nothing, open or closed', () {
      final monThu = habit(
        'monThu',
        type: HabitFrequencyType.weekly,
        target: 2,
        weekdays: const [DateTime.monday, DateTime.thursday],
      );
      expect(card(monThu, at0519, history: const {}).expected, 2,
          reason: 'the 3rd and 7th have closed; the 10th is still open');
      expect(card(monThu, cutoff11, history: const {}).expected, 3);
      expect(card(monThu, cutoff12, history: const {}).expected, 3,
          reason: 'Friday was never one of its days');
    });

    test('a blank habit keeps its card before 10:00 on a week\'s first day',
        () {
      final week = reportWindow(ReportScope.week, DateTime(2026, 9, 12));
      final now = sepAt(12, 5);
      final stats = computeHabitPeriodStats(
        habits: [adhkar],
        history: const {},
        days: elapsedDaysIn(
          start: week.start,
          end: week.end,
          today: now.effectiveDay,
        ),
        now: now,
        windowEnd: week.end,
      );
      expect(stats, hasLength(1));
      expect(stats.single.hasRate, isFalse);
    });
  });

  group('a weekly quota week still running', () {
    final fourAWeek =
        habit('four', type: HabitFrequencyType.weekly, target: 4);
    final week = reportWindow(ReportScope.week, DateTime(2026, 9, 9));

    HabitPeriodStat stat(
      Map<String, SquareState> marks,
      DateTime? now, {
      DateTime? today,
    }) =>
        computeHabitPeriodStats(
          habits: [fourAWeek],
          history: {'four': marks},
          days: elapsedDaysIn(
            start: week.start,
            end: week.end,
            today: (now ?? today!).effectiveDay,
          ),
          now: now,
          windowEnd: week.end,
        ).single;

    test('a blank 4x week starts owing when its fourth blank day closes', () {
      expect(stat(const {}, sepAt(9, kDayCutoffHour - 1, 59)).expected, 0,
          reason: 'Tuesday is still open: four days left for four sessions');
      expect(stat(const {}, sepAt(9, kDayCutoffHour)).expected, 1);
      expect(stat(const {}, sepAt(10, kDayCutoffHour)).expected, 2);
      expect(stat(const {}, sepAt(11, kDayCutoffHour)).expected, 3);
      expect(stat(const {}, cutoff12).expected, 4);
    });

    test('Saturday, Sunday and Monday done: 3 of 3 until Friday closes', () {
      final marks = {
        sep(5): SquareState.complete,
        sep(6): SquareState.complete,
        sep(7): SquareState.complete,
      };
      final open = stat(marks, beforeCutoff12);
      expect((open.expected, open.rate, open.isPerfect), (3, 1.0, true));
      final closed = stat(marks, cutoff12);
      expect((closed.expected, closed.rate, closed.isPerfect),
          (4, 0.75, false));
    });

    test('a closed جزئي adds its half on top, never a whole session owed', () {
      // Three times a week, Saturday the 5th done. Counted as a finished
      // session, a closed جزئي Sunday made the week owe one session more for
      // half a session's credit: 75% on Monday, beside 100% for a blank
      // Sunday, so marking half of Sunday read worse than leaving it empty.
      final threeAWeek =
          habit('three', type: HabitFrequencyType.weekly, target: 3);
      (int, double, String) at(Map<String, SquareState> marks, DateTime now) {
        final s = computeHabitPeriodStats(
          habits: [threeAWeek],
          history: {'three': marks},
          days: elapsedDaysIn(
            start: week.start,
            end: week.end,
            today: now.effectiveDay,
          ),
          now: now,
          windowEnd: week.end,
        ).single;
        return (s.expected, s.creditedUnits, pct(s));
      }

      final blank = {sep(5): SquareState.complete};
      final half = {...blank, sep(6): SquareState.partial};
      final monday = sepAt(7, 11);
      expect(at(blank, monday), (1, 1.0, '100%'));
      expect(
        at(half, monday),
        (1, 1.5, '100%'),
        reason: 'Monday to Friday can still hold the other two sessions',
      );
      final friday = sepAt(11, 11);
      expect(at(blank, friday), (2, 1.0, '50%'));
      expect(
        at(half, friday),
        (2, 1.5, '75%'),
        reason: 'only Friday is left, so one session can no longer fit',
      );
      expect(at(blank, cutoff12), (3, 1.0, '33%'));
      expect(
        at(half, cutoff12),
        (3, 1.5, '50%'),
        reason: 'the closed week, exactly as before the open-day rule',
      );
    });

    test('without a clock the week is clamped to its elapsed days, as before',
        () {
      expect(stat(const {}, null, today: DateTime(2026, 9, 9)).expected, 4);
      expect(stat(const {}, null, today: DateTime(2026, 9, 6)).expected, 2);
    });
  });

  group('the summary card', () {
    final days = [
      DateTime(2026, 9, 9),
      DateTime(2026, 9, 10),
      DateTime(2026, 9, 11),
    ];
    final counts = {sep(9): 1, sep(11): 1};
    PeriodSummary summaryAt(DateTime? now) => computePeriodSummary(
          dayCounts: counts,
          days: days,
          habitStats: const [],
          now: now,
        );

    test('a blank day still open neither breaks the longest run nor adds to it',
        () {
      expect(summaryAt(beforeCutoff11).longestRun, 2);
      expect(summaryAt(cutoff11).longestRun, 1);
      expect(summaryAt(null).longestRun, 1);
    });

    test('a summary that owes nothing yet has no rate to print', () {
      // A blank daily habit, read on the 1st. At 05:00 its only due day is
      // still open, so the month owes nothing yet and there is no rate; once
      // the 1st closes at kDayCutoffHour on the 2nd it owes that day, and 0%
      // is a real number. Built from the stats the hub builds, so the
      // open-day rule itself has to hold for this to pass.
      final firstOnly = [DateTime(2026, 9, 1)];
      PeriodSummary firstAt(DateTime now) => computePeriodSummary(
            dayCounts: const {},
            days: firstOnly,
            habitStats: computeHabitPeriodStats(
              habits: [adhkar],
              history: const {},
              days: firstOnly,
              now: now,
              windowEnd: september.end,
            ),
            now: now,
          );
      final early = firstAt(sepAt(1, 5));
      expect((early.expectedTotal, early.hasRate), (0, false));
      final closed = firstAt(sepAt(2, kDayCutoffHour));
      expect(
        (closed.expectedTotal, closed.hasRate, closed.rate),
        (1, true, 0.0),
      );
    });
  });

  group('the change against last week', () {
    final habits = [habit('a'), habit('b'), habit('c')];

    /// [previous] habits done on Friday the 4th, [current] on the 11th.
    Map<String, Map<String, SquareState>> fridays({
      required int previous,
      required int current,
    }) =>
        {
          for (var i = 0; i < habits.length; i++)
            habits[i].id: {
              if (i < previous) sep(4): SquareState.complete,
              if (i < current) sep(11): SquareState.complete,
            },
        };

    int? deltaAt(
      Map<String, Map<String, SquareState>> history,
      DateTime? now, {
      DateTime? today,
    }) =>
        periodDelta(
          scope: ReportScope.week,
          anchor: DateTime(2026, 9, 11),
          history: history,
          habits: habits,
          today: (now ?? today!).effectiveDay,
          earliestData: DateTime(2026, 8, 1),
          now: now,
        );

    test('a Friday still open is not measured against a whole Friday', () {
      final history = fridays(previous: 3, current: 1);
      expect(deltaAt(history, null, today: DateTime(2026, 9, 11)), -2,
          reason: 'the old reading');
      expect(deltaAt(history, at0519), 0);
      expect(deltaAt(history, beforeCutoff12), 0,
          reason: 'Friday is open until 10:00 on Saturday');
      expect(deltaAt(history, cutoff12), -2,
          reason: 'and is compared in full once it closes');
    });

    test('an open day ahead of its partner still counts in full', () {
      expect(deltaAt(fridays(previous: 1, current: 3), at0519), 2);
    });
  });

  test('the weekday rhythm reads closed days only', () {
    final days = [
      DateTime(2026, 9, 9),
      DateTime(2026, 9, 10),
      DateTime(2026, 9, 11),
    ];
    expect(settledDaysAt(days: days, now: at0519), [DateTime(2026, 9, 9)]);
    expect(settledDaysAt(days: days, now: cutoff11), days.take(2).toList());
    expect(settledDaysAt(days: days, now: cutoff12), days);
  });

  group('the rule over every mark pattern', () {
    // The properties the design's standalone brute force checked, run here
    // against the real computeHabitPeriodStats. The window starts on
    // Saturday 5 September 2026: day i is the 5th plus i, and a clock (c, t)
    // is minute t of the 5th plus c.
    //  P1: once the window's last day has closed, the numbers equal the
    //      no-clock reading.
    //  P2: a habit that is not a flexible quota is never credited past what
    //      it owes. A quota week is credited past it only by its settled
    //      جزئي halves, which sit on top, or once its target was beaten.
    //  P3: what is owed never shrinks as the clock moves on.
    //  P4: finishing an open blank or جزئي day never lowers the rate.
    //  P5: a better mark on a day that has closed never lowers the rate: a
    //      جزئي reads at least what a blank or a فشل reads, and done at
    //      least what a جزئي reads.
    //  P6: the quota number agrees with a second spelling of its formula.
    final cut = kDayCutoffHour * 60;
    DateTime dayAt(int i) => DateTime(2026, 9, 5 + i);

    HabitPeriodStat statFor(
      IslamicHabitTemplate h,
      List<SquareState> p,
      DateTime clock, {
      required bool withClock,
    }) {
      final end = dayAt(p.length - 1);
      return computeHabitPeriodStats(
        habits: [h],
        history: {
          h.id: {
            for (var i = 0; i < p.length; i++)
              if (p[i] != SquareState.none) dayAt(i).toDateKey(): p[i],
          },
        },
        days: elapsedDaysIn(
          start: dayAt(0),
          end: end,
          today: clock.effectiveDay,
        ),
        now: withClock ? clock : null,
        windowEnd: end,
      ).single;
    }

    List<String> check({
      required int n,
      required List<SquareState> alphabet,
      required List<int> minutes,
      required List<IslamicHabitTemplate> habits,
    }) {
      final failures = <String>[];
      final total = pow(alphabet.length, n).toInt();
      final clocks = <(int, int)>[
        for (var c = 0; c <= n + 1; c++)
          for (final t in minutes) (c, t),
      ];
      List<SquareState> patternOf(int code) {
        final p = <SquareState>[];
        var x = code;
        for (var i = 0; i < n; i++) {
          p.add(alphabet[x % alphabet.length]);
          x ~/= alphabet.length;
        }
        return p;
      }

      for (final h in habits) {
        final quota = !missIsAttributable(h);
        // Every pattern's rate at every clock, for P5, which reads a pattern
        // beside the same pattern with one closed day marked better.
        final rates = <int, double>{};
        for (var code = 0; code < total; code++) {
          final p = patternOf(code);
          int? previous;
          for (var k = 0; k < clocks.length; k++) {
            final (c, t) = clocks[k];
            {
              bool future(int i) => c < i;
              bool open(int i) => c == i || (c == i + 1 && t < cut);
              bool closed(int i) => !future(i) && !open(i);
              var markedAhead = false;
              for (var i = 0; i < n; i++) {
                if (p[i] != SquareState.none && future(i)) markedAhead = true;
              }
              if (markedAhead) continue;
              final clock = DateTime(2026, 9, 5 + c, t ~/ 60, t % 60);
              final s = statFor(h, p, clock, withClock: true);
              rates[code * clocks.length + k] = s.rate;
              final label = '${h.id} $p at day $c minute $t';

              if (closed(n - 1)) {
                final old = statFor(h, p, clock, withClock: false);
                if (old.expected != s.expected ||
                    (old.creditedUnits - s.creditedUnits).abs() > 1e-9) {
                  failures.add('P1 $label: old ${old.expected}/'
                      '${old.creditedUnits}, new ${s.expected}/'
                      '${s.creditedUnits}');
                }
              }

              bool settled(int i) =>
                  !future(i) && (p[i].answersDay || closed(i));
              var alive = 0, halves = 0, greens = 0, stillOpen = 0;
              for (var i = 0; i < n; i++) {
                if (p[i] == SquareState.skipped) continue;
                alive++;
                if (!settled(i)) {
                  stillOpen++;
                } else if (p[i] == SquareState.partial) {
                  halves++;
                }
                if (p[i].isGreen) greens++;
              }
              final target = min(h.frequencyTarget, alive);

              final creditCap = quota ? s.expected + 0.5 * halves : s.expected;
              if (s.creditedUnits > creditCap + 1e-9 &&
                  !(quota && greens > target)) {
                failures.add('P2 $label: ${s.creditedUnits} of ${s.expected}');
              }
              if (previous != null && s.expected < previous) {
                failures.add('P3 $label: $previous then ${s.expected}');
              }
              previous = s.expected;

              for (var i = 0; i <= min(c, n - 1); i++) {
                if (!open(i)) continue;
                if (p[i] != SquareState.none && p[i] != SquareState.partial) {
                  continue;
                }
                final after = statFor(
                  h,
                  [...p]..[i] = SquareState.complete,
                  clock,
                  withClock: true,
                );
                if (after.expected == 0 || after.rate < s.rate - 1e-9) {
                  failures.add('P4 $label, finishing day $i: '
                      '${s.rate} then ${after.rate}');
                }
              }

              if (quota) {
                final alt = min(
                  target,
                  greens + max(0, target - greens - stillOpen),
                );
                if (alt != s.expected) {
                  failures.add('P6 $label: ${s.expected} against $alt');
                }
              }
            }
          }
        }

        for (var code = 0; code < total; code++) {
          final p = patternOf(code);
          for (var k = 0; k < clocks.length; k++) {
            final before = rates[code * clocks.length + k];
            if (before == null) continue; // a mark ahead of the clock
            final (c, t) = clocks[k];
            var place = 1;
            for (var i = 0; i < n; i++, place *= alphabet.length) {
              final closed = c > i + 1 || (c == i + 1 && t >= cut);
              if (!closed || p[i] == SquareState.skipped) continue;
              for (var u = 0; u < alphabet.length; u++) {
                final better = alphabet[u];
                if (better == SquareState.skipped ||
                    markCredit(better) <= markCredit(p[i])) {
                  continue;
                }
                final marked = code + (u - alphabet.indexOf(p[i])) * place;
                final after = rates[marked * clocks.length + k]!;
                if (after < before - 1e-9) {
                  failures.add('P5 ${h.id} $p at day $c minute $t, day $i '
                      'marked ${better.name}: $before then $after');
                }
              }
            }
          }
        }
      }
      return failures;
    }

    test('three days, every mark, every habit shape', () {
      final failures = check(
        n: 3,
        alphabet: SquareState.values
            .where((m) => m != SquareState.bonus)
            .toList(),
        minutes: [0, 319, cut - 1, cut, 1439],
        habits: [
          habit('daily'),
          for (var t = 1; t <= 3; t++)
            habit('quota$t', type: HabitFrequencyType.weekly, target: t),
        ],
      );
      expect(failures.take(10).toList(), isEmpty,
          reason: '${failures.length} failures');
    });

    test('a whole week of blank, جزئي and done, around every cutoff', () {
      final failures = check(
        n: 7,
        alphabet: const [
          SquareState.none,
          SquareState.partial,
          SquareState.complete,
        ],
        minutes: [cut - 1, cut],
        habits: [
          habit('daily'),
          for (final t in [1, 3, 4, 7])
            habit('quota$t', type: HabitFrequencyType.weekly, target: t),
        ],
      );
      expect(failures.take(10).toList(), isEmpty,
          reason: '${failures.length} failures');
    });
  });
}
