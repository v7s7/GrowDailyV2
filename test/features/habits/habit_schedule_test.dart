// A habit's gaps are measured on the days it runs, not on the calendar.
//
// The reported bug: a habit set to two weekdays, done on the first, was told
// «صار لها ٣ أيام، وما ضاع شي» on the second. Three calendar days had passed
// and not one of them was a day the habit ran, so nothing had lapsed. The
// same calendar arithmetic in completeHabit restarted that habit's streak at
// 1 on every completion. These pin the schedule-aware counting both now use.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/habits/models/habit_schedule.dart';

void main() {
  // August 2026: the 15th is a Saturday.
  final sat15 = DateTime(2026, 8, 15);
  final sun16 = DateTime(2026, 8, 16);
  final mon17 = DateTime(2026, 8, 17);
  final tue18 = DateTime(2026, 8, 18);
  final wed19 = DateTime(2026, 8, 19);
  final thu20 = DateTime(2026, 8, 20);
  final fri21 = DateTime(2026, 8, 21);
  final sat22 = DateTime(2026, 8, 22);
  final sun23 = DateTime(2026, 8, 23);

  const wedSat = {DateTime.wednesday, DateTime.saturday};

  test('the calendar assumption these tests rest on', () {
    expect(sat15.weekday, DateTime.saturday);
    expect(wed19.weekday, DateTime.wednesday);
    expect(sat22.weekday, DateTime.saturday);
  });

  group('runsOnWeekday', () {
    test('an empty set means every day', () {
      expect(runsOnWeekday(mon17, const {}), isTrue);
      expect(runsOnWeekday(fri21, const {}), isTrue);
    });

    test('a set means exactly those days', () {
      expect(runsOnWeekday(wed19, wedSat), isTrue);
      expect(runsOnWeekday(sat22, wedSat), isTrue);
      expect(runsOnWeekday(thu20, wedSat), isFalse);
    });
  });

  group('scheduledDaysStrictlyBetween', () {
    test('an every-day habit counts every day but the two ends', () {
      expect(scheduledDaysStrictlyBetween(sat15, sat15, const {}), 0);
      expect(scheduledDaysStrictlyBetween(sat15, sun16, const {}), 0);
      expect(scheduledDaysStrictlyBetween(sat15, tue18, const {}), 2);
    });

    test('reported bug: Wednesday to Saturday on a Wed/Sat habit is zero', () {
      // Thursday and Friday sit in between, and the habit runs on neither.
      expect(scheduledDaysStrictlyBetween(wed19, sat22, wedSat), 0);
    });

    test('a scheduled day in between is counted', () {
      // Saturday to Saturday skips a Wednesday.
      expect(scheduledDaysStrictlyBetween(sat15, sat22, wedSat), 1);
      // Thursday to the following Tuesday on Sun/Tue/Thu skips a Sunday.
      expect(
        scheduledDaysStrictlyBetween(
          thu20,
          DateTime(2026, 8, 25),
          const {DateTime.sunday, DateTime.tuesday, DateTime.thursday},
        ),
        1,
      );
    });

    test('never negative, and never counts the ends', () {
      expect(scheduledDaysStrictlyBetween(sat22, sat15, wedSat), 0);
      // Wed → Sat is zero even though both ends are scheduled days.
      expect(scheduledDaysStrictlyBetween(wed19, sat22, wedSat), 0);
    });
  });

  group('scheduledGap', () {
    int gap(DateTime last, DateTime day, [Set<int> weekdays = const {}]) =>
        scheduledGap(last: last, day: day, weekdays: weekdays);

    test('an every-day habit measures the calendar, sign included', () {
      // These three are the whole nextHabitStreak contract: 1 continues, 0
      // is the re-tick, anything else restarts.
      expect(gap(sat15, sun16), 1);
      expect(gap(sat15, sat15), 0);
      expect(gap(sat15, tue18), 3);
      // Marking yesterday inside its grace tail after today was marked.
      expect(gap(sun16, sat15), -1);
    });

    test('reported bug: a Wed/Sat habit done Wednesday then Saturday is 1', () {
      // The calendar said 3, which restarted the streak at 1 every time.
      expect(gap(wed19, sat22, wedSat), 1);
    });

    test('skipping a scheduled day restarts it', () {
      // Saturday to Saturday, with Wednesday missed in between.
      expect(gap(sat15, sat22, wedSat), 2);
    });

    test('a completion on a day off never breaks a streak', () {
      // Wednesday then Thursday: nothing scheduled was skipped, so it
      // continues. Doing more than promised is not doing less.
      expect(gap(wed19, thu20, wedSat), 1);
    });

    test('the zero and negative cases are untouched by the schedule', () {
      expect(gap(wed19, wed19, wedSat), 0);
      expect(gap(sat22, wed19, wedSat), -3);
    });
  });

  group('quotaFactsOn', () {
    // A "3 times a week" habit, in the week starting Saturday the 15th.
    ({int? done, bool owed, int missedSinceLastDone}) facts({
      required DateTime fireDay,
      Set<int>? doneDays,
      DateTime? lastDone,
      int target = 3,
      DateTime? weekStart,
    }) =>
        quotaFactsOn(
          fireDay: fireDay,
          weekStart: weekStart ?? sat15,
          doneDays: doneDays,
          target: target,
          lastDone: lastDone,
          fireTime: null,
        );

    test('an unknown week claims nothing', () {
      final f = facts(fireDay: wed19, doneDays: null, lastDone: mon17);
      expect(f.done, isNull);
      expect(f.owed, isFalse);
      expect(f.missedSinceLastDone, 0);
    });

    test('a spare day mid-week: progress known, nothing owed, nothing missed',
        () {
      // Saturday and Monday done; Wednesday still has Thu and Fri behind it.
      final f = facts(fireDay: wed19, doneDays: {0, 2}, lastDone: mon17);
      expect(f.done, 2);
      expect(f.owed, isFalse);
      expect(f.missedSinceLastDone, 0);
    });

    test('the last chance day is owed', () {
      // Two of three by Monday, nothing since: Friday is the only day left.
      final f = facts(fireDay: fri21, doneDays: {0, 2}, lastDone: mon17);
      expect(f.done, 2);
      expect(f.owed, isTrue);
      // Tue, Wed and Thu were all spare, so none of them was a miss.
      expect(f.missedSinceLastDone, 0);
    });

    test('owed days left empty this week are misses, spare ones are not', () {
      // Nothing done all week, last done the Saturday before. By Friday,
      // Wednesday and Thursday were both load-bearing and both empty.
      final f = facts(
        fireDay: fri21,
        doneDays: const {},
        lastDone: DateTime(2026, 8, 8),
      );
      expect(f.done, 0);
      expect(f.owed, isTrue);
      expect(f.missedSinceLastDone, 2);
    });

    test('a whole week with nothing in it is a proven lapse', () {
      // Last done two weeks back: the week in between was entirely empty,
      // so every one of its three owed days was missed.
      final f = facts(
        fireDay: sat15,
        doneDays: const {},
        lastDone: DateTime(2026, 8, 1),
      );
      expect(f.missedSinceLastDone, 3);
      // And the first day of a week is never owed on its own.
      expect(f.owed, isFalse);
    });

    test('the week the last completion fell in is not judged', () {
      // Last done Tuesday of the previous week. Whether that week hit its
      // target is unknown here, so it contributes nothing.
      final f = facts(
        fireDay: sat15,
        doneDays: const {},
        lastDone: DateTime(2026, 8, 11),
      );
      expect(f.missedSinceLastDone, 0);
    });

    test('a target already met makes the rest of the week free', () {
      // Sat, Sun, Mon done: Wednesday is earned, and nothing after Monday
      // can be a miss.
      final f = facts(fireDay: wed19, doneDays: {0, 1, 2}, lastDone: mon17);
      expect(f.done, 3);
      expect(f.owed, isFalse);
      expect(f.missedSinceLastDone, 0);
    });

    test('a whole empty week does not count its Friday while it is open', () {
      // The empty week before Saturday the 15th ends on Friday the 14th,
      // which stays open until kDayCutoffHour on the 15th. An all-empty week
      // owes its last days, so that Friday is one of its three.
      int missedAt(int hour) => quotaFactsOn(
            fireDay: sat15,
            weekStart: sat15,
            doneDays: const {},
            target: 3,
            lastDone: DateTime(2026, 8, 1),
            fireTime: DateTime(2026, 8, 15, hour),
          ).missedSinceLastDone;
      expect(missedAt(kDayCutoffHour - 1), 2);
      expect(missedAt(kDayCutoffHour), 3);
    });

    test('an owed day of this week still open at the fire time is no miss',
        () {
      // Nothing done all week, last done the Saturday before. At 04:00 on
      // Friday the 21st, Wednesday has closed but Thursday is still open.
      int missedAt(int hour) => quotaFactsOn(
            fireDay: fri21,
            weekStart: sat15,
            doneDays: const {},
            target: 3,
            lastDone: DateTime(2026, 8, 8),
            fireTime: DateTime(2026, 8, 21, hour),
          ).missedSinceLastDone;
      expect(missedAt(4), 1);
      expect(missedAt(kDayCutoffHour), 2);
    });

    test('an empty week between this week and a later fire week waits too',
        () {
      // The scheduler arms about four days ahead, so today a fire day never
      // lands two weeks past the current week; quotaFactsOn is general, and
      // this pins the branch that would. Current week met on Mon the 17th,
      // reminder on Sat the 29th: the whole week of the 22nd sits between,
      // empty, and owes its last three days, the 26th to Friday the 28th.
      // At 04:00 on the 29th that Friday is still open.
      int missedAt(int hour) => quotaFactsOn(
            fireDay: DateTime(2026, 8, 29),
            weekStart: sat15,
            doneDays: const {0, 1, 2},
            target: 3,
            lastDone: mon17,
            fireTime: DateTime(2026, 8, 29, hour),
          ).missedSinceLastDone;
      expect(missedAt(4), 2);
      expect(missedAt(kDayCutoffHour), 3);
    });

    test('a reminder rolled into next week starts that week from nothing', () {
      // Target met this week, reminder lands next Saturday.
      final f = facts(fireDay: sat22, doneDays: {0, 1, 2}, lastDone: mon17);
      expect(f.done, 0);
      expect(f.owed, isFalse);
      expect(f.missedSinceLastDone, 0);
      // And a 7x target owes every day, so next Sunday is owed already.
      final daily = facts(
        fireDay: sun23,
        doneDays: {0, 1, 2, 3, 4, 5, 6},
        lastDone: fri21,
        target: 7,
      );
      expect(daily.owed, isTrue);
    });

    test('rolling into next week still counts this week\'s owed empties', () {
      // Nothing done this week, last done the Saturday before: Wed, Thu
      // and Fri were all owed and will all be empty by next Saturday.
      final f = facts(
        fireDay: sat22,
        doneDays: const {},
        lastDone: DateTime(2026, 8, 8),
      );
      expect(f.missedSinceLastDone, 3);
    });

    test('a target above seven is clamped to the week', () {
      final f = facts(
        fireDay: sat15,
        doneDays: const {},
        lastDone: DateTime(2026, 8, 1),
        target: 10,
      );
      // One empty week between: seven owed days, not ten.
      expect(f.missedSinceLastDone, 7);
    });
  });

  // Aziz, 2026-09-26: a جزئي is a day trained, and «هدف الأسبوع تم» is said
  // of whole sessions only.
  group('quotaReminderWeekDays', () {
    test('halves count as days trained while the week has room', () {
      expect(quotaReminderWeekDays(whole: {}, half: {0, 1}, target: 4), {0, 1});
      expect(
          quotaReminderWeekDays(whole: {0}, half: {2}, target: 4), {0, 2});
    });

    test('met in whole sessions: only they are counted', () {
      expect(
        quotaReminderWeekDays(whole: {0, 1, 2}, half: {3}, target: 3),
        {0, 1, 2},
      );
    });

    test('met by halves adding up: the week is met, every day counted', () {
      // Aziz, 2026-10-03: three whole and two halves of a 4x week are 4 of 4,
      // so the reminder may say the week's target is done.
      final days =
          quotaReminderWeekDays(whole: {0, 1, 5}, half: {3, 4}, target: 4);
      expect(days, {0, 1, 3, 4, 5});
      expect(days!.length, greaterThanOrEqualTo(4));
    });

    test('halves filling the week short of whole ones: nothing is claimed', () {
      // Two whole and a half on a 3x habit is 2.5 of 3, and a whole session
      // today would still take the half's place: neither "met" nor "one
      // left" is true.
      expect(quotaReminderWeekDays(whole: {0, 1}, half: {2}, target: 3), isNull);
      expect(quotaReminderWeekDays(whole: {}, half: {0, 1, 2, 3}, target: 4),
          isNull);
    });
  });
}
