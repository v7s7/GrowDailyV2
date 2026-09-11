// What a habit reminder knows on the day it fires, measured on the habit's
// own schedule.
//
// The reported bug, end to end: a habit set to two weekdays, done on the
// first, was told «صار لها ٣ أيام، وما ضاع شي» on the second. The wording
// was fed "days since last done" straight off the calendar, and the streak
// beside it had already been zeroed by the same calendar. Both facts are
// now re-based onto the fire day by NotificationService.reminderFactsAtFireDay,
// which is a pure static precisely so this can be asserted without a device.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/habits/models/habit_schedule.dart';

void main() {
  // September 2026: the 5th is a Saturday, the 2nd a Wednesday.
  final sat5 = DateTime(2026, 9, 5);
  final sun6 = DateTime(2026, 9, 6);
  final wed2 = DateTime(2026, 9, 2);
  const wedSat = {DateTime.wednesday, DateTime.saturday};

  ({
    int streak,
    int completedCount,
    int? lastDoneDaysAgo,
    int missedSinceLastDone,
    int? weekDone,
    bool owedOnFireDay,
    bool everyDay,
  }) facts({
    DateTime? today,
    DateTime? fireDay,
    int streak = 0,
    int completedCount = 0,
    int? lastDoneDaysAgo,
    Set<int> scheduledWeekdays = const {},
    int? weekTarget,
    Set<int>? weekDoneDays,
    DateTime? fireTime,
  }) =>
      NotificationService.reminderFactsAtFireDay(
        today: today ?? sat5,
        fireDay: fireDay ?? sat5,
        fireTime: fireTime,
        streak: streak,
        completedCount: completedCount,
        lastDoneDaysAgo: lastDoneDaysAgo,
        scheduledWeekdays: scheduledWeekdays,
        weekTarget: weekTarget,
        weekDoneDays: weekDoneDays,
      );

  test('the calendar assumption these tests rest on', () {
    expect(sat5.weekday, DateTime.saturday);
    expect(wed2.weekday, DateTime.wednesday);
  });

  group('a habit pinned to weekdays', () {
    test('reported bug: done Wednesday, reminded Saturday, nothing missed', () {
      final f = facts(
        lastDoneDaysAgo: 3,
        streak: 5,
        scheduledWeekdays: wedSat,
      );
      expect(f.missedSinceLastDone, 0,
          reason: 'Thursday and Friday are not days this habit runs');
      expect(f.streak, 5, reason: 'the streak is intact, and says so');
      expect(f.lastDoneDaysAgo, 3,
          reason: 'the calendar gap is still a fact, just not a lapse');
      expect(f.everyDay, isFalse);
    });

    test('a skipped Wednesday is a miss, and ends the streak', () {
      final f = facts(
        lastDoneDaysAgo: 7,
        streak: 5,
        scheduledWeekdays: wedSat,
      );
      expect(f.missedSinceLastDone, 1);
      expect(f.streak, 0);
      expect(f.lastDoneDaysAgo, 7);
    });

    test('never done has nothing to have missed', () {
      final f = facts(scheduledWeekdays: wedSat);
      expect(f.missedSinceLastDone, 0);
      expect(f.lastDoneDaysAgo, isNull);
    });
  });

  group('an every-day habit', () {
    test('done yesterday, fired today: on schedule', () {
      final f = facts(lastDoneDaysAgo: 1, streak: 4);
      expect(f.missedSinceLastDone, 0);
      expect(f.streak, 4);
      expect(f.everyDay, isTrue);
    });

    test('a slot rolled to tomorrow sees today as a day that will have ended',
        () {
      // Done yesterday, armed tonight for tomorrow: unless today is
      // completed (which re-arms everything), tomorrow's reminder arrives
      // with today missed. Baking today's streak into it was the old bug.
      final f = facts(
        fireDay: sun6,
        lastDoneDaysAgo: 1,
        streak: 4,
        completedCount: 1,
      );
      expect(f.missedSinceLastDone, 1);
      expect(f.streak, 0);
      expect(f.lastDoneDaysAgo, 2, reason: 're-based onto the fire day');
      expect(f.completedCount, 0,
          reason: 'a rolled slot starts its day at zero');
    });

    test('done today, armed for tomorrow: the streak carries', () {
      final f = facts(fireDay: sun6, lastDoneDaysAgo: 0, streak: 4);
      expect(f.missedSinceLastDone, 0);
      expect(f.streak, 4);
      expect(f.lastDoneDaysAgo, 1);
    });

    test('today\'s progress is only today\'s', () {
      expect(facts(completedCount: 2).completedCount, 2);
      expect(facts(fireDay: sun6, completedCount: 2).completedCount, 0);
    });
  });

  group('a flexible weekly quota', () {
    // "3 times a week"; the week starts Saturday the 29th of August, so
    // Wednesday the 2nd is index 4.
    test('is judged by its week, and never draws a streak line', () {
      final f = facts(
        today: wed2,
        fireDay: wed2,
        lastDoneDaysAgo: 2,
        streak: 3,
        weekTarget: 3,
        weekDoneDays: {0, 2},
      );
      expect(f.weekDone, 2);
      expect(f.owedOnFireDay, isFalse);
      expect(f.missedSinceLastDone, 0,
          reason: 'two days ago is a calendar fact, not a lapse');
      expect(f.streak, 0, reason: 'a calendar streak says nothing of a week');
    });

    test('an unknown week claims nothing', () {
      final f = facts(
        today: wed2,
        fireDay: wed2,
        lastDoneDaysAgo: 2,
        weekTarget: 3,
        weekDoneDays: null,
      );
      expect(f.weekDone, isNull);
      expect(f.owedOnFireDay, isFalse);
      expect(f.missedSinceLastDone, 0);
    });

    test('the last chance day is owed', () {
      // Nothing done, Friday the 4th: three days needed and one left.
      final f = facts(
        today: DateTime(2026, 9, 4),
        fireDay: DateTime(2026, 9, 4),
        weekTarget: 3,
        weekDoneDays: const {},
      );
      expect(f.weekDone, 0);
      expect(f.owedOnFireDay, isTrue);
    });
  });

  group('a reminder that lands before the cutoff', () {
    // Aziz, 2026-09-11: a day still open is not a day missed. The day before
    // the fire day stays markable until kDayCutoffHour, so a reminder landing
    // at Fajr time must not word it as lost.
    DateTime at(DateTime day, int h, [int m = 0]) =>
        DateTime(day.year, day.month, day.day, h, m);

    test('an every-day habit done on Thursday is not lapsed at 04:00', () {
      final f = facts(lastDoneDaysAgo: 2, streak: 4, fireTime: at(sat5, 4));
      expect(f.missedSinceLastDone, 0, reason: 'Friday can still be marked');
      // Nor is its streak promised. Ticking Saturday before Friday restarts
      // it at 1, and this reminder's own Mark Done ticks Saturday, so the
      // line names neither the lapse nor the streak until Friday is done.
      expect(f.streak, 0);
      expect(
        nextHabitStreak(
          gapDays: scheduledGap(
            last: dayPlus(sat5, -2),
            day: sat5,
            weekdays: const {},
          ),
          previousStreak: 4,
        ),
        1,
        reason: 'the tap a promised streak would be broken by',
      );
    });

    test('a streak with nothing unfinished before the fire day is carried',
        () {
      final f = facts(lastDoneDaysAgo: 1, streak: 4, fireTime: at(sat5, 4));
      expect((f.missedSinceLastDone, f.streak), (0, 4));
    });

    test('and has missed Friday by 11:00', () {
      final f = facts(lastDoneDaysAgo: 2, streak: 4, fireTime: at(sat5, 11));
      expect(f.missedSinceLastDone, 1);
      expect(f.streak, 0);
    });

    test('one minute either side of the cutoff', () {
      expect(
        facts(
          lastDoneDaysAgo: 2,
          streak: 4,
          fireTime: at(sat5, kDayCutoffHour - 1, 59),
        ).missedSinceLastDone,
        0,
      );
      expect(
        facts(
          lastDoneDaysAgo: 2,
          streak: 4,
          fireTime: at(sat5, kDayCutoffHour),
        ).missedSinceLastDone,
        1,
      );
    });

    test('without a fire time, the older reading stands', () {
      expect(facts(lastDoneDaysAgo: 2, streak: 4).missedSinceLastDone, 1);
    });

    test('a quota week does not count its owed Friday on Saturday at 04:00',
        () {
      // Three times a week, nothing logged in the week of Saturday the 5th,
      // last done on Friday the 4th. Wednesday, Thursday and Friday were the
      // owed days, and at 04:00 on Saturday the 12th Friday is still open.
      final fri11 = DateTime(2026, 9, 11);
      final sat12 = DateTime(2026, 9, 12);
      final early = facts(
        today: fri11,
        fireDay: sat12,
        fireTime: at(sat12, 4),
        lastDoneDaysAgo: 7,
        weekTarget: 3,
        weekDoneDays: const {},
      );
      expect(early.missedSinceLastDone, 2);
      final late = facts(
        today: fri11,
        fireDay: sat12,
        fireTime: at(sat12, 11),
        lastDoneDaysAgo: 7,
        weekTarget: 3,
        weekDoneDays: const {},
      );
      expect(late.missedSinceLastDone, 3);
    });
  });
}
