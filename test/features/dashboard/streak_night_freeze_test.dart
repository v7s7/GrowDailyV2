// A streak is not judged while the day it would judge is still open.
//
// resolveStreakGap counted the days strictly between the last earning day
// and TODAY, and today rolls at midnight. A day stays markable until
// kDayCutoffHour the next morning (DateTimeGameExt.isOpenDayAt), so opening
// the app between midnight and the cutoff counted yesterday as owed while
// yesterday could still be finished: the gap spent a streak freeze, or ended
// the streak outright when the bank was empty, for a day nobody had missed
// yet. Hoor lost her only freeze that way at about 02:42 on 2026-09-08,
// having finished the 7th inside its own grace window.
//
// The bound is firstOpenDayAt, real code rather than a replica, pinned here
// at every hour that matters. Only the one-line loop it bounds is mirrored,
// the same way streak_rest_day_test.dart mirrors it.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

/// An everyday habit, alive for all of history: the default empty weekday
/// list is exactly what "every day" means here.
IslamicHabitTemplate _daily() => const IslamicHabitTemplate(
      id: 'gym',
      name: 'تمرين',
      description: '',
      category: HabitCategory.fitness,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    );

/// resolveStreakGap's own loop, bounded the way the real one now is.
int owedDaysAt(
  DateTime from,
  DateTime now,
  Iterable<IslamicHabitTemplate> habits,
) {
  final settledBefore = firstOpenDayAt(now);
  var owed = 0;
  for (var d = from.add(const Duration(days: 1));
      d.isBefore(settledBefore);
      d = d.add(const Duration(days: 1))) {
    if (habits.any((h) => h.isScheduledFor(d))) owed++;
  }
  return owed;
}

void main() {
  final third = DateTime(2026, 9, 3);
  final sixth = DateTime(2026, 9, 6);
  final seventh = DateTime(2026, 9, 7);
  final eighth = DateTime(2026, 9, 8);

  group('firstOpenDayAt', () {
    test('is yesterday all through the grace tail', () {
      expect(firstOpenDayAt(DateTime(2026, 9, 8, 0, 1)), seventh);
      expect(firstOpenDayAt(DateTime(2026, 9, 8, 2, 42)), seventh);
      expect(
        firstOpenDayAt(DateTime(2026, 9, 8, kDayCutoffHour - 1, 59)),
        seventh,
      );
    });

    test('becomes today the moment yesterday closes', () {
      expect(firstOpenDayAt(DateTime(2026, 9, 8, kDayCutoffHour)), eighth);
      expect(firstOpenDayAt(DateTime(2026, 9, 8, 23, 59)), eighth);
    });
  });

  group('the night a freeze used to be spent', () {
    final habits = [_daily()];

    test('02:42 owes nothing, because the 7th can still be finished', () {
      // Hoor's case exactly: last earned the 6th, app opened at 02:42 on
      // the 8th. The old bound owed the 7th here and took her only freeze.
      expect(owedDaysAt(sixth, DateTime(2026, 9, 8, 2, 42), habits), 0);
    });

    test('and still nothing at one minute before the cutoff', () {
      expect(
        owedDaysAt(sixth, DateTime(2026, 9, 8, kDayCutoffHour - 1, 59), habits),
        0,
      );
    });

    test('the same gap owes the 7th once the cutoff passes', () {
      // Nothing about the data changed, only the clock: at the cutoff the
      // 7th has closed unfinished, so it is a real miss and must be paid for.
      expect(owedDaysAt(sixth, DateTime(2026, 9, 8, kDayCutoffHour), habits), 1);
      expect(owedDaysAt(sixth, DateTime(2026, 9, 8, 12), habits), 1);
    });

    test('an older gap is still owed in full at 02:00', () {
      // The freeze must still do its job. The fix defers judgment by one
      // day, it does not forgive days that closed long ago: from the 3rd,
      // the 4th, 5th and 6th are shut either way.
      expect(owedDaysAt(third, DateTime(2026, 9, 8, 2), habits), 3);
      expect(owedDaysAt(third, DateTime(2026, 9, 8, 12), habits), 4);
    });

    test('today is never judged, at any hour', () {
      // Earned yesterday, opened today: nothing strictly between them, and
      // today itself is in progress whatever the clock says.
      expect(owedDaysAt(seventh, DateTime(2026, 9, 8, 2), habits), 0);
      expect(owedDaysAt(seventh, DateTime(2026, 9, 8, 12), habits), 0);
      expect(owedDaysAt(seventh, DateTime(2026, 9, 8, 23, 59), habits), 0);
    });
  });
}
