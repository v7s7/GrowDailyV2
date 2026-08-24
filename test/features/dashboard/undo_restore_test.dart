// Un-ticking a habit and ticking it again should give back exactly what it
// took, on the day it took it from.
//
// Before this, the two halves were not the same size. Undoing is a full
// canonical reversal; redoing is only symmetric while the day is still today,
// because every past day is kept out of the reward system on purpose (see
// WeeklyGridNotifier.setSquare's anti-backdating guard). So clearing a mark by
// mistake and noticing two days later left the square green again with the XP,
// the gold and, worst of all, the habit's streak chain gone for good, since
// the chain is driven by habitLastCompletedDate and only a same-day completion
// ever writes it.
//
// The fix is a receipt (UndoneCompletion) written by the undo and spent by the
// next completion of that same habit-day. These are its rules, pure and
// tested: what a completion does to a streak, what restoring a receipt does to
// one, and that a receipt survives storage intact.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/dashboard/models/undone_completion.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';

void main() {
  group('nextHabitStreak', () {
    test('yesterday continues the streak', () {
      expect(nextHabitStreak(gapDays: 1, previousStreak: 6), 7);
    });

    test('a gap of zero keeps the streak instead of resetting it to 1', () {
      // THE regression. Complete a habit, restart the app, undo the
      // completion (no snapshot survives a restart, so uncompleteHabit
      // deliberately leaves the streak fields alone), then re-tick it. The
      // stored last-completed date still reads today, so the gap is 0, and
      // this used to answer 1: a 40-day streak destroyed by a mis-tap.
      expect(nextHabitStreak(gapDays: 0, previousStreak: 40), 40);
    });

    test('a gap of zero on a habit with no streak yet still starts at 1', () {
      expect(nextHabitStreak(gapDays: 0, previousStreak: 0), 1);
    });

    test('a real miss restarts the streak', () {
      expect(nextHabitStreak(gapDays: 2, previousStreak: 40), 1);
      expect(nextHabitStreak(gapDays: 9, previousStreak: 3), 1);
    });

    test('a habit never completed before starts at 1', () {
      expect(nextHabitStreak(gapDays: null, previousStreak: 0), 1);
    });

    test('only the gap-of-zero case withholds the milestone bonus', () {
      // The streak did not move, so the milestone that streak crosses was
      // already paid by the completion being put back. Paying it again would
      // pay twice for one day.
      expect(habitStreakAdvanced(0), isFalse);
      expect(habitStreakAdvanced(1), isTrue);
      expect(habitStreakAdvanced(5), isTrue);
      expect(habitStreakAdvanced(null), isTrue);
    });
  });

  group('restoredHabitStreak', () {
    // Every date below is deliberately mid-month so nothing here depends on
    // month or year arithmetic.
    DateTime day(int d) => DateTime(2026, 8, d);

    test('nothing newer exists, so the receipt is simply the truth', () {
      final result = restoredHabitStreak(
        restoredDay: day(22),
        streakAtCompletion: 7,
        currentStreak: 0,
        currentLastCompleted: null,
      );
      expect(result?.streak, 7);
      expect(result?.lastCompleted, day(22));
    });

    test('an undo that rolled the date back is put straight back', () {
      // The same-session case: the snapshot rolled habitLastCompletedDate to
      // the day before and the streak down by one. Restoring undoes exactly
      // that.
      final result = restoredHabitStreak(
        restoredDay: day(22),
        streakAtCompletion: 10,
        currentStreak: 9,
        currentLastCompleted: day(21),
      );
      expect(result?.streak, 10);
      expect(result?.lastCompleted, day(22));
    });

    test('the two runs merge when the newer one starts the very next day', () {
      // Completed through the 22nd on a 10-day run, undone on the 22nd, then
      // completed again on the 23rd and 24th. Those two days could only score
      // as a fresh 2-day run while the 22nd was a hole. Filling the hole makes
      // it one 12-day run, the 13th through the 24th.
      final result = restoredHabitStreak(
        restoredDay: day(22),
        streakAtCompletion: 10,
        currentStreak: 2,
        currentLastCompleted: day(24),
      );
      expect(result?.streak, 12);
      // The newest completion is still the 24th. Restoring an older day must
      // never drag the last-completed date backwards.
      expect(result?.lastCompleted, day(24));
    });

    test('a run that does not reach the restored day is left alone', () {
      // The 23rd is missing too, so filling the 20th joins nothing. Refusing
      // to guess is the point: a streak that stays honestly short can be
      // rebuilt, one invented from a guess cannot be found again.
      final result = restoredHabitStreak(
        restoredDay: day(20),
        streakAtCompletion: 10,
        currentStreak: 2,
        currentLastCompleted: day(25),
      );
      expect(result, isNull);
    });

    test('a restored day that IS the last completed day changes nothing', () {
      // What an undo with no snapshot leaves behind: it never rolled the
      // streak fields back, so they already describe this exact day.
      final result = restoredHabitStreak(
        restoredDay: day(22),
        streakAtCompletion: 7,
        currentStreak: 7,
        currentLastCompleted: day(22),
      );
      expect(result, isNull);
    });

    test('a receipt with no streak on it restores no streak', () {
      final result = restoredHabitStreak(
        restoredDay: day(22),
        streakAtCompletion: 0,
        currentStreak: 3,
        currentLastCompleted: day(24),
      );
      expect(result, isNull);
    });

    test('a stale habit with no live run is not merged into', () {
      // currentStreak 0 with a last-completed date means the habit went cold.
      // There is no run to join, and the restored day is older, so nothing
      // here can be answered without real history.
      final result = restoredHabitStreak(
        restoredDay: day(10),
        streakAtCompletion: 4,
        currentStreak: 0,
        currentLastCompleted: day(24),
      );
      expect(result, isNull);
    });

    test('the time of day on the restored instant is irrelevant', () {
      final result = restoredHabitStreak(
        restoredDay: DateTime(2026, 8, 22, 23, 41),
        streakAtCompletion: 5,
        currentStreak: 0,
        currentLastCompleted: null,
      );
      expect(result?.lastCompleted, day(22));
    });
  });

  group('daysBetweenDates', () {
    test('counts calendar days, not elapsed hours', () {
      expect(daysBetweenDates(DateTime(2026, 8, 22), DateTime(2026, 8, 24)), 2);
      expect(
        daysBetweenDates(DateTime(2026, 8, 22, 23, 59), DateTime(2026, 8, 23, 0, 1)),
        1,
      );
      expect(daysBetweenDates(DateTime(2026, 8, 24), DateTime(2026, 8, 22)), -2);
    });

    test('crosses a month and a year boundary', () {
      expect(daysBetweenDates(DateTime(2026, 8, 31), DateTime(2026, 9, 1)), 1);
      expect(daysBetweenDates(DateTime(2025, 12, 31), DateTime(2026, 1, 1)), 1);
    });
  });

  group('UndoneCompletion storage', () {
    const receipt = UndoneCompletion(
      habitId: 'fajr_prayer',
      dateKey: '2026-08-22',
      category: 'prayer',
      xp: 30,
      gold: 12,
      streakAtCompletion: 10,
      longestAtCompletion: 14,
      undoneOnKey: '2026-08-22',
    );

    test('survives a round trip through storage', () {
      final back = UndoneCompletion.fromJson(receipt.toJson());
      expect(back, isNotNull);
      expect(back!.habitId, 'fajr_prayer');
      expect(back.dateKey, '2026-08-22');
      expect(back.category, 'prayer');
      expect(back.xp, 30);
      expect(back.gold, 12);
      expect(back.streakAtCompletion, 10);
      expect(back.longestAtCompletion, 14);
      expect(back.undoneOnKey, '2026-08-22');
    });

    test('the key names one habit and one day', () {
      expect(receipt.key, 'fajr_prayer|2026-08-22');
      expect(UndoneCompletion.keyFor('a', 'b'), 'a|b');
      // Two days of the same habit are two separate receipts.
      expect(
        UndoneCompletion.keyFor('fajr_prayer', '2026-08-21'),
        isNot(receipt.key),
      );
    });

    test('a habit with no category round trips as null, not as empty', () {
      final none = UndoneCompletion.fromJson(
        const UndoneCompletion(
          habitId: 'h',
          dateKey: '2026-08-22',
          category: null,
          xp: 1,
          gold: 1,
          streakAtCompletion: 1,
          longestAtCompletion: 1,
          undoneOnKey: '2026-08-22',
        ).toJson(),
      );
      expect(none?.category, isNull);
    });

    test('junk degrades to null instead of throwing', () {
      // One malformed entry must cost that entry and not the whole load: a
      // throw in the loader presents as level 1 with zero XP and then refuses
      // every reward write.
      expect(UndoneCompletion.fromJson(null), isNull);
      expect(UndoneCompletion.fromJson('nonsense'), isNull);
      expect(UndoneCompletion.fromJson(const {}), isNull);
      expect(UndoneCompletion.fromJson(const {'dateKey': '2026-08-22'}), isNull);
      expect(UndoneCompletion.fromJson(const {'habitId': 'h'}), isNull);
      expect(UndoneCompletion.fromJson(const {'habitId': '', 'dateKey': 'd'}),
          isNull);
    });

    test('a wrong-typed number degrades to zero, keeping the receipt', () {
      final partial = UndoneCompletion.fromJson(const {
        'habitId': 'h',
        'dateKey': '2026-08-22',
        'xp': 'lots',
        'gold': null,
      });
      expect(partial, isNotNull);
      expect(partial!.xp, 0);
      expect(partial.gold, 0);
    });

    test('a record written before receipts carried a stamp still reads', () {
      final legacy = UndoneCompletion.fromJson(const {
        'habitId': 'h',
        'dateKey': '2026-08-22',
        'xp': 10,
      });
      expect(legacy?.undoneOnKey, '2026-08-22');
    });
  });

  group('DashboardState receipts', () {
    test('are looked up by habit AND day', () {
      const receipt = UndoneCompletion(
        habitId: 'quran',
        dateKey: '2026-08-22',
        category: 'quran',
        xp: 20,
        gold: 8,
        streakAtCompletion: 3,
        longestAtCompletion: 3,
        undoneOnKey: '2026-08-22',
      );
      final state = DashboardState.initial()
          .copyWith(undoneCompletions: {receipt.key: receipt});

      expect(state.undoneFor('quran', '2026-08-22'), isNotNull);
      // The same habit on a different day owes nothing.
      expect(state.undoneFor('quran', '2026-08-21'), isNull);
      // A different habit on the same day owes nothing either. This is the
      // property that makes the whole thing unfarmable: a receipt is proof
      // about one square, not about a day.
      expect(state.undoneFor('fajr_prayer', '2026-08-22'), isNull);
    });

    test('an account with no outstanding undos has none', () {
      expect(DashboardState.initial().undoneCompletions, isEmpty);
      expect(DashboardState.initial().undoneFor('any', '2026-08-22'), isNull);
    });
  });
}
