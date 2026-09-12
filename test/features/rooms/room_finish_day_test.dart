// The room hears about the day you actually finished.
//
// syncLinkedHabitsProgress judged its finish push against
// `DateTime.now().effectiveDay`, which rolls at midnight, while a day stays
// markable until kDayCutoffHour the next morning. Finishing yesterday at
// 02:00 therefore wrote allDoneToday for TODAY, a day barely begun and
// certainly not done, so the flag stayed false and the push never fired for
// the day that had just been completed. The same tap counted for the
// percentage and the streak, which is what made it easy to miss: everything
// on the board agreed, and only the room stayed quiet.
//
// finishDayKey is the whole decision, kept pure so it can be asked about at
// any hour. The hard half is the fallback: Grid edits any square in its
// window through syncHabitDay's non-today branch, so "the day just marked"
// must NOT be announced when that day closed long ago.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

void main() {
  final seventh = DateTime(2026, 9, 7);
  final eighth = DateTime(2026, 9, 8);

  group('a finish made in the grace window', () {
    test('is announced for yesterday, the day actually finished', () {
      // Hoor's hour: the 7th finished at 02:42 on the 8th.
      expect(finishDayKey(seventh, DateTime(2026, 9, 8, 2, 42)), '2026-09-07');
      expect(finishDayKey(seventh, DateTime(2026, 9, 8, 0, 1)), '2026-09-07');
      expect(
        finishDayKey(seventh, DateTime(2026, 9, 8, kDayCutoffHour - 1, 59)),
        '2026-09-07',
      );
    });

    test('falls back to today the moment that day closes', () {
      // Past the cutoff the 7th can no longer be marked, so a sync naming it
      // is not a fresh finish and must not claim one.
      expect(
        finishDayKey(seventh, DateTime(2026, 9, 8, kDayCutoffHour)),
        '2026-09-08',
      );
      expect(finishDayKey(seventh, DateTime(2026, 9, 8, 12)), '2026-09-08');
    });
  });

  group('an ordinary finish', () {
    test('is announced for today at every hour of the day', () {
      for (final at in [
        DateTime(2026, 9, 8, 0, 1),
        DateTime(2026, 9, 8, 2, 42),
        DateTime(2026, 9, 8, kDayCutoffHour),
        DateTime(2026, 9, 8, 12),
        DateTime(2026, 9, 8, 23, 59),
      ]) {
        expect(finishDayKey(eighth, at), '2026-09-08', reason: 'at $at');
      }
    });
  });

  group('the fallback that keeps it honest', () {
    test('backfilling a long-closed square announces nothing for that day', () {
      // A Grid edit of the 1st, made on the 8th, reaches the same grader.
      // It must be graded against today, which is not finished, rather than
      // telling the room someone just finished the 1st.
      expect(
        finishDayKey(DateTime(2026, 9), DateTime(2026, 9, 8, 2)),
        '2026-09-08',
      );
      expect(
        finishDayKey(DateTime(2026, 9), DateTime(2026, 9, 8, 12)),
        '2026-09-08',
      );
    });

    test('a day that has not started yet falls back too', () {
      // isOpenDayAt is false before a day begins as well as after it closes,
      // so a clock-skewed or future-dated square cannot announce a finish.
      expect(
        finishDayKey(DateTime(2026, 9, 20), DateTime(2026, 9, 8, 12)),
        '2026-09-08',
      );
    });

    test('the two boundaries sit exactly where the day window says', () {
      // Pinned against isOpenDayAt itself, so this can never drift into
      // being a second, quietly different definition of an open day.
      expect(
        seventh.isOpenDayAt(DateTime(2026, 9, 8, kDayCutoffHour - 1)),
        isTrue,
      );
      expect(
        seventh.isOpenDayAt(DateTime(2026, 9, 8, kDayCutoffHour)),
        isFalse,
      );
    });
  });
}
