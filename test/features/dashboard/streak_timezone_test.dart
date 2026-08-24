// A streak has to survive a flight.
//
// lastActiveDate was written as Timestamp.fromDate(localMidnightOfTheDay).
// An instant is a point in time, not a calendar day, so reading it back in
// another zone hands you a different day: local midnight on 2026-08-23 in
// Bahrain (UTC+3) is 21:00 on the 22nd in UTC, and reads back as the 22nd
// anywhere west of Bahrain. The fabricated gap reached the streak gap check,
// which spends a freeze or writes currentStreak 0, about a second after the
// app opens and before the person can touch anything.
//
// Complete everything in Bahrain on Monday, land in London, open the app on
// Tuesday, and a 200 day streak was gone. Same for anyone in Europe, North
// America, the Levant or Morocco on the day the clocks go back.
//
// The fix stores the calendar day as a 'YYYY-MM-DD' string alongside the
// Timestamp, the way habitLastCompletedDate always did. These tests assert on
// the ARITHMETIC that fed the bug, so they hold without a Firestore.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';

/// The OLD read: local midnight of the earned day, stored as an absolute
/// instant, then reinterpreted as a calendar day in whatever zone the phone
/// happens to be in when the app next opens.
///
/// All arithmetic is in UTC so the machine running the test cannot influence
/// the answer, which is the entire point of the bug.
int gapFromInstant({
  required DateTime earnedDay,
  required Duration writerOffset,
  required Duration readerOffset,
  required DateTime readerToday,
}) {
  final instant = earnedDay.subtract(writerOffset);
  final readerWallClock = instant.add(readerOffset);
  final lastDay = DateTime.utc(
      readerWallClock.year, readerWallClock.month, readerWallClock.day);
  return readerToday.difference(lastDay).inDays;
}

/// The NEW read: a calendar day, which means the same thing everywhere.
int gapFromDayKey({
  required String writtenKey,
  required DateTime readerToday,
}) {
  final d = DateTime.parse(writtenKey);
  return readerToday.difference(DateTime.utc(d.year, d.month, d.day)).inDays;
}

void main() {
  // Monday 2026-08-24, the day the streak was earned. The writer is in
  // Bahrain, UTC+3.
  final earnedDay = DateTime.utc(2026, 8, 24);
  const bahrain = Duration(hours: 3);
  // The app is next opened on Tuesday.
  final openedOn = DateTime.utc(2026, 8, 25);

  group('the old instant based read', () {
    test('is correct as long as you never leave the country', () {
      expect(
        gapFromInstant(
          earnedDay: earnedDay,
          writerOffset: bahrain,
          readerOffset: bahrain,
          readerToday: openedOn,
        ),
        1,
        reason: 'one day is a normal overnight gap, nothing is spent',
      );
    });

    test('fabricates a gap after a flight west', () {
      // Bahrain UTC+3 to London UTC+1: the reader is 2 hours behind, so local
      // midnight lands at 22:00 the previous day.
      // London is UTC+1, two hours behind Bahrain, so the instant written at
      // Bahrain local midnight is 22:00 on the previous day there.
      final gap = gapFromInstant(
        earnedDay: earnedDay,
        writerOffset: bahrain,
        readerOffset: const Duration(hours: 1),
        readerToday: openedOn,
      );
      expect(gap, 2,
          reason: 'this is the bug: a gap of 2 spends a streak freeze, and '
              'with no freeze left it writes currentStreak 0');
      expect(gap > 1, isTrue);
    });

    test('fabricates a gap on a westward DST rollback, without any travel', () {
      // No travel at all: the same phone, one hour behind where it was when
      // the streak was earned.
      final gap = gapFromInstant(
        earnedDay: earnedDay,
        writerOffset: bahrain,
        readerOffset: const Duration(hours: 2),
        readerToday: openedOn,
      );
      expect(gap, 2,
          reason: 'the clocks going back one hour is enough on its own');
    });
  });

  group('the calendar day read', () {
    test('is the same day in every timezone on earth', () {
      final key = earnedDay.toDateKey();
      // The written key does not depend on where it is read, so the only
      // input that can move is the reader's own today.
      // The instant based read gives a different answer per zone. The key
      // based read cannot, because the key does not carry a time at all: the
      // only input left is the reader's own today.
      for (final readerOffset in [
        bahrain,
        const Duration(hours: 1),
        const Duration(hours: 2),
        const Duration(hours: 9),
        const Duration(hours: -8),
      ]) {
        expect(
          gapFromInstant(
            earnedDay: earnedDay,
            writerOffset: bahrain,
            readerOffset: readerOffset,
            readerToday: openedOn,
          ),
          readerOffset >= bahrain ? 1 : 2,
          reason: 'sanity: the old read really does depend on $readerOffset',
        );
        expect(
          gapFromDayKey(writtenKey: key, readerToday: openedOn),
          1,
          reason: 'the new read must not: $readerOffset changed the answer',
        );
      }
    });

    test('still catches a real missed day', () {
      expect(
        gapFromDayKey(
          writtenKey: earnedDay.toDateKey(),
          readerToday: DateTime.utc(2026, 8, 27),
        ),
        3,
        reason: 'the gap check has to keep working, this is not a way to '
            'make streaks unbreakable',
      );
    });

    test('round trips through the key format the app already uses', () {
      final key = earnedDay.toDateKey();
      expect(key, '2026-08-24');
      expect(DateTime.parse(key), DateTime(2026, 8, 24));
    });
  });
}
