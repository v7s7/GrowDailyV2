// A session on a day that is not one of a specific-days habit's days takes
// the place of one of its days (lib/features/habits/models/moved_day_plan.dart).
//
// Aziz's shampoo runs Monday, Thursday and Saturday; he showered on Wednesday.
// The rule lets that session count and covers a planned day with it, and the
// property tests below pin the one promise that makes it safe to feed every
// denominator: a finished week shows exactly as many misses as it fell short
// by, never more and never fewer.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/moved_day_plan.dart';
import 'package:grow_daily_v2/features/habits/models/weekly_quota_plan.dart';

void main() {
  List<bool> bits(int mask, [int n = 7]) =>
      [for (var i = 0; i < n; i++) (mask >> i) & 1 == 1];
  const allAlive = [true, true, true, true, true, true, true];
  const allClosed = [true, true, true, true, true, true, true];
  const noneClosed = [false, false, false, false, false, false, false];

  // Index 0 is Saturday, as in every display week of the app.
  const sat = 0, sun = 1, mon = 2, tue = 3, wed = 4, thu = 5, fri = 6;

  List<bool> days(Set<int> on) => [for (var i = 0; i < 7; i++) on.contains(i)];

  group('Aziz\'s week', () {
    test('Wednesday\'s shower covers Thursday, the next day of the plan', () {
      // Created on Monday the 21st, so Saturday the 19th was never his to owe.
      // Monday done, Wednesday done off the plan, Thursday is today.
      final week = movedDayDemand(
        alive: days({mon, tue, wed, thu, fri}),
        planned: days({sat, mon, thu}),
        green: days({mon, wed}),
        closed: days({mon, tue, wed}),
      );
      expect(week[sat], isNull, reason: 'before the habit existed');
      expect(week[mon], DayDemand.done);
      expect(week[wed], DayDemand.done,
          reason: 'the session counts on the day it happened');
      expect(week[thu], DayDemand.earned,
          reason: 'Thursday is covered: nothing is owed on it any more');
      expect(week[thu]!.isRest, isTrue);
      expect(week[tue], DayDemand.spare, reason: 'an empty off day owes nothing');
    });

    test('without the Wednesday session, Thursday is owed as it always was',
        () {
      final week = movedDayDemand(
        alive: days({mon, tue, wed, thu, fri}),
        planned: days({sat, mon, thu}),
        green: days({mon}),
        closed: days({mon, tue, wed}),
      );
      expect(week[thu], DayDemand.owed);
    });
  });

  group('which planned day a moved session stands in for', () {
    test('a real miss is made up before a day still to come', () {
      // Saturday done, Monday missed and closed, Tuesday done off the plan,
      // Thursday still ahead: Tuesday makes up Monday, and Thursday stays
      // expected, because it can still be done in person.
      final week = movedDayDemand(
        alive: allAlive,
        planned: days({sat, mon, thu}),
        green: days({sat, tue}),
        closed: days({sat, sun, mon}),
      );
      expect(week[mon], DayDemand.earned, reason: 'made up on Tuesday');
      expect(week[thu], DayDemand.owed);
    });

    test('with no miss behind it, a session covers the next planned day', () {
      final week = movedDayDemand(
        alive: allAlive,
        planned: days({sat, mon, thu}),
        green: days({sat, sun}),
        closed: days({sat}),
      );
      expect(week[mon], DayDemand.earned, reason: 'done early, on Sunday');
      expect(week[thu], DayDemand.owed);
    });

    test('sessions beyond the plan are extra and cover nothing more', () {
      final week = movedDayDemand(
        alive: allAlive,
        planned: days({mon, thu}),
        green: days({sun, mon, tue, wed, thu}),
        closed: allClosed,
      );
      expect(week.where((d) => d == DayDemand.owed), isEmpty);
      expect(week.where((d) => d == DayDemand.earned), isEmpty,
          reason: 'every planned day has a session of its own');
      expect(week.where((d) => d == DayDemand.done), hasLength(5));
    });

    test('two moved sessions cover two planned days, earliest first', () {
      final week = movedDayDemand(
        alive: allAlive,
        planned: days({sat, mon, thu}),
        green: days({sun, tue}),
        closed: noneClosed,
      );
      expect(week[sat], DayDemand.earned);
      expect(week[mon], DayDemand.earned);
      expect(week[thu], DayDemand.owed, reason: 'two sessions, three days');
    });

    test('an archived habit\'s dead days are nobody\'s to owe', () {
      final week = movedDayDemand(
        alive: days({sat, sun, mon, tue}),
        planned: days({sat, mon, thu}),
        green: days({sun}),
        closed: allClosed,
      );
      expect(week[thu], isNull);
      expect(week[wed], isNull);
    });
  });

  group('a planned day the person marked keeps its mark', () {
    test('a فشل is never covered: the session goes to the next empty day', () {
      // Monday marked فشل, Wednesday showered off the plan, Thursday empty.
      final week = movedDayDemand(
        alive: allAlive,
        planned: days({sat, mon, thu}),
        green: days({sat, wed}),
        unmarked: days({sun, tue, thu, fri}),
        closed: days({sat, sun, mon, tue, wed}),
      );
      expect(week[mon], DayDemand.owed,
          reason: 'their own verdict on Monday stands');
      expect(week[thu], DayDemand.earned,
          reason: 'Wednesday stands in for the day nobody marked');
    });

    test('with only marked days left, the session is simply extra', () {
      // Monday تخطّي, Thursday جزئي: neither is empty, so nothing is covered
      // and the Wednesday session counts on its own day and nowhere else.
      final week = movedDayDemand(
        alive: allAlive,
        planned: days({sat, mon, thu}),
        green: days({sat, wed}),
        unmarked: days({sun, tue, fri}),
        closed: allClosed,
      );
      expect(week.where((d) => d == DayDemand.earned), isEmpty);
      expect(week[wed], DayDemand.done);
      expect(week[mon], DayDemand.owed);
      expect(week[thu], DayDemand.owed);
    });

    test('over every schedule, sessions and marks: marked days never move, '
        'and the unmarked ones fall short by exactly the shortfall', () {
      for (var plan = 1; plan < 128; plan++) {
        for (var done = 0; done < 128; done++) {
          // Mark every subset of the planned days left empty.
          final emptyPlanned = plan & ~done;
          for (var marked = emptyPlanned;;
              marked = (marked - 1) & emptyPlanned) {
            final planned = bits(plan);
            final green = bits(done);
            final unmarked = [
              for (var i = 0; i < 7; i++) !green[i] && (marked >> i) & 1 == 0,
            ];
            final week = movedDayDemand(
              alive: allAlive,
              planned: planned,
              green: green,
              unmarked: unmarked,
              closed: allClosed,
            );
            var offDay = 0, candidates = 0, owedEmpty = 0;
            for (var i = 0; i < 7; i++) {
              if (!planned[i] && green[i]) offDay++;
              if (planned[i] && !green[i] && unmarked[i]) {
                candidates++;
                if (week[i] == DayDemand.owed) owedEmpty++;
              }
              if ((marked >> i) & 1 == 1) {
                expect(week[i], DayDemand.owed,
                    reason: 'a marked day is never covered, day $i of '
                        'plan ${plan.toRadixString(2)}');
              }
            }
            final left = candidates - offDay;
            expect(owedEmpty, left > 0 ? left : 0,
                reason: 'plan ${plan.toRadixString(2)}, done '
                    '${done.toRadixString(2)}, marked '
                    '${marked.toRadixString(2)}');
            if (marked == 0) break;
          }
        }
      }
    });
  });

  group('properties, over every schedule and every week', () {
    test('a finished week shows exactly its shortfall as misses', () {
      for (var plan = 1; plan < 128; plan++) {
        for (var done = 0; done < 128; done++) {
          final planned = bits(plan);
          final green = bits(done);
          final week = movedDayDemand(
            alive: allAlive,
            planned: planned,
            green: green,
            closed: allClosed,
          );
          final misses = week.where((d) => d == DayDemand.owed).length;
          final plannedCount = planned.where((p) => p).length;
          final sessions = green.where((g) => g).length;
          final shortfall =
              plannedCount - sessions > 0 ? plannedCount - sessions : 0;
          expect(misses, shortfall,
              reason: 'plan ${plan.toRadixString(2)}, '
                  'done ${done.toRadixString(2)}');
        }
      }
    });

    test('with no session off the plan, every empty planned day is owed', () {
      for (var plan = 1; plan < 128; plan++) {
        for (var done = 0; done < 128; done++) {
          if (done & ~plan != 0) continue; // sessions only on planned days
          final week = movedDayDemand(
            alive: allAlive,
            planned: bits(plan),
            green: bits(done),
            closed: allClosed,
          );
          for (var i = 0; i < 7; i++) {
            final isPlanned = bits(plan)[i];
            final isDone = bits(done)[i];
            if (isPlanned && !isDone) {
              expect(week[i], DayDemand.owed,
                  reason: 'unchanged from before, day $i of '
                      '${plan.toRadixString(2)}');
            }
          }
        }
      }
    });

    test('a session is never lost and never marks anything worse', () {
      // Adding a session anywhere can only turn owed into done or earned.
      for (var plan = 1; plan < 128; plan++) {
        for (var done = 0; done < 128; done++) {
          final before = movedDayDemand(
            alive: allAlive,
            planned: bits(plan),
            green: bits(done),
            closed: allClosed,
          );
          for (var add = 0; add < 7; add++) {
            if ((done >> add) & 1 == 1) continue;
            final after = movedDayDemand(
              alive: allAlive,
              planned: bits(plan),
              green: bits(done | (1 << add)),
              closed: allClosed,
            );
            final owedBefore = before.where((d) => d == DayDemand.owed).length;
            final owedAfter = after.where((d) => d == DayDemand.owed).length;
            expect(owedAfter, lessThanOrEqualTo(owedBefore));
            for (var i = 0; i < 7; i++) {
              if (before[i] != DayDemand.owed) {
                expect(after[i], isNot(DayDemand.owed),
                    reason: 'a day that was fine stays fine');
              }
            }
          }
        }
      }
    });
  });
}
