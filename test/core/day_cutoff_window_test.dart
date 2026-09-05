// The day model itself: when a new day starts, and how long the finished one
// stays open behind it.
//
// This file used to pin the OPPOSITE rule. effectiveDay shifted back by
// kDayCutoffHour, so until 10 AM the whole app still called yesterday
// "today", and these tests asserted exactly that ("every hour before the
// cutoff still belongs to the day before").
//
// That rule is gone. It protected night owls by making the app disagree with
// the phone in their hand for ten hours a day, and the two halves of the app
// then disagreed with each other: the Grid drew its week and its gold ring
// from the real calendar while the reward engine was still on yesterday, so
// the square labelled TODAY at 2 AM was tappable, turned green, and paid
// nothing. Rooms grade off that square, so a room credited the day while the
// person's own XP did not.
//
// The rule now: the day rolls at MIDNIGHT, everywhere. What the cutoff bought
// is kept explicitly instead — yesterday stays OPEN for marking until the
// cutoff, so a night owl can still finish it and still earn its streak point.
// From midnight to 10 AM there are two open days, and both pay in full.
//
// Written against kDayCutoffHour rather than the literal 10, so these
// describe the rule and survive the next move.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';

void main() {
  // A Wednesday, and the Thursday after it.
  final wed = DateTime(2026, 8, 19);
  final thu = DateTime(2026, 8, 20);
  final fri = DateTime(2026, 8, 21);

  DateTime thuAt(int h, [int m = 0]) => DateTime(2026, 8, 20, h, m);

  group('effectiveDay rolls at midnight, at every hour of the day', () {
    test('every hour of Thursday is Thursday, including the small hours', () {
      for (var h = 0; h < 24; h++) {
        expect(
          thuAt(h).effectiveDay,
          thu,
          reason: '${h}:00 Thursday should be Thursday',
        );
      }
    });

    test('the hours the old cutoff stole back are Thursday now', () {
      // 00:00 through 09:59 used to resolve to Wednesday. This is the whole
      // behaviour change, stated as plainly as it can be.
      for (var h = 0; h < kDayCutoffHour; h++) {
        expect(thuAt(h).effectiveDay, isNot(wed), reason: '${h}:00');
        expect(thuAt(h).effectiveDay, thu, reason: '${h}:00');
      }
    });

    test('midnight is the boundary, to the minute', () {
      expect(thuAt(23, 59).effectiveDay, thu);
      expect(fri.effectiveDay, fri);
      expect(fri.subtract(const Duration(minutes: 1)).effectiveDay, thu);
    });

    test('a 9:40 AM completion belongs to the day it happened on', () {
      // The old shift banked this against YESTERDAY, which is why the cutoff
      // had to be argued down from noon to clear Bahrain's earliest Dhuhr
      // (11:22 across all 521 days in bahrain_official.json). Nothing is
      // mis-attributed now, so that constraint no longer binds anything.
      expect(thuAt(9, 40).effectiveDay, thu);
      expect(thuAt(11, 22).effectiveDay, thu, reason: 'earliest Dhuhr');
      expect(thuAt(11, 53).effectiveDay, thu, reason: 'latest Dhuhr');
    });
  });

  group('isOpenDay: two days are open from midnight to the cutoff', () {
    test('a day is open from its own midnight', () {
      expect(thu.isOpenDayAt(thuAt(0, 0)), isTrue);
      expect(thu.isOpenDayAt(thuAt(12, 0)), isTrue);
      expect(thu.isOpenDayAt(thuAt(23, 59)), isTrue);
    });

    test('a day stays open through the whole grace tail of the next one', () {
      for (var h = 0; h < kDayCutoffHour; h++) {
        expect(
          wed.isOpenDayAt(thuAt(h)),
          isTrue,
          reason: 'Wednesday should still be markable at ${h}:00 Thursday',
        );
      }
    });

    test('the grace ends exactly at the cutoff', () {
      expect(wed.isOpenDayAt(thuAt(kDayCutoffHour - 1, 59)), isTrue);
      expect(wed.isOpenDayAt(thuAt(kDayCutoffHour, 0)), isFalse);
      expect(wed.isOpenDayAt(thuAt(kDayCutoffHour, 1)), isFalse);
    });

    test('a day is never open before it has started', () {
      // The bug in one line: no square may earn anything ahead of its day.
      expect(fri.isOpenDayAt(thuAt(23, 59)), isFalse);
      expect(thu.isOpenDayAt(DateTime(2026, 8, 19, 23, 59)), isFalse);
    });

    test('the day before yesterday is closed for good', () {
      expect(DateTime(2026, 8, 18).isOpenDayAt(thuAt(0, 1)), isFalse);
      expect(DateTime(2026, 8, 18).isOpenDayAt(thuAt(9, 59)), isFalse);
    });

    test('the window is exactly 24 + kDayCutoffHour hours long', () {
      final opens = thu;
      final closes = thu.add(const Duration(days: 1, hours: kDayCutoffHour));
      expect(thu.isOpenDayAt(opens), isTrue);
      expect(
        thu.isOpenDayAt(opens.subtract(const Duration(minutes: 1))),
        isFalse,
      );
      expect(
        thu.isOpenDayAt(closes.subtract(const Duration(minutes: 1))),
        isTrue,
      );
      expect(thu.isOpenDayAt(closes), isFalse);
    });
  });

  group('isInGraceWindow separates yesterday-still-open from today', () {
    test('today is open but never "in grace"', () {
      expect(thu.isInGraceWindowAt(thuAt(2, 0)), isFalse);
      expect(thu.isInGraceWindowAt(thuAt(14, 0)), isFalse);
    });

    test('yesterday before the cutoff is open AND in grace', () {
      expect(wed.isOpenDayAt(thuAt(2, 0)), isTrue);
      expect(wed.isInGraceWindowAt(thuAt(2, 0)), isTrue);
    });

    test('yesterday after the cutoff is neither', () {
      expect(wed.isOpenDayAt(thuAt(10, 0)), isFalse);
      expect(wed.isInGraceWindowAt(thuAt(10, 0)), isFalse);
    });
  });

  group('the promise the grace is made to keep', () {
    test('asleep until half nine, Wednesday is still markable', () {
      // The person this window is really for: not the one up at 3am, but the
      // one simply asleep at 6 who opens the app at 9. Wednesday's board is
      // one day back, and marking it still earns Wednesday's streak point.
      expect(wed.isOpenDayAt(thuAt(9, 0)), isTrue);
      expect(wed.isOpenDayAt(thuAt(9, 59)), isTrue);
      // And Thursday is what the app OPENS on, which is the half that used
      // to be missing.
      expect(thuAt(9, 59).effectiveDay, thu);
      expect(thu.isOpenDayAt(thuAt(9, 59)), isTrue);
    });

    test('4am, the case the original 6am window covered, still works', () {
      expect(wed.isOpenDayAt(thuAt(4, 0)), isTrue);
    });

    test('2:18am: both days open, which is the case that started all this', () {
      // Room ELQVF8, 2026-09-05. She prayed Witr at 02:18 and marked the
      // square the app labelled today. Under the old rule that square could
      // not pay. Under this one both days are markable and both pay.
      expect(thu.isOpenDayAt(thuAt(2, 18)), isTrue, reason: 'the new day');
      expect(wed.isOpenDayAt(thuAt(2, 18)), isTrue, reason: 'the night before');
      expect(thuAt(2, 18).effectiveDay, thu, reason: 'and today is the new day');
    });
  });

  group('isToday and isRealToday can no longer disagree', () {
    test('they answer the same at whatever hour this suite runs', () {
      final today = DateTime.now().effectiveDay;
      expect(today.isToday, isTrue);
      expect(today.isRealToday, isTrue);
      expect(today.add(const Duration(days: 1)).isToday, isFalse);
      expect(today.add(const Duration(days: 1)).isRealToday, isFalse);
      expect(today.subtract(const Duration(days: 1)).isYesterday, isTrue);
    });

    test('today is open, tomorrow is not, at any hour', () {
      final today = DateTime.now().effectiveDay;
      expect(today.isOpenDay, isTrue);
      expect(today.add(const Duration(days: 1)).isOpenDay, isFalse);
      expect(today.subtract(const Duration(days: 2)).isOpenDay, isFalse);
    });

    test('yesterday is open exactly while the clock is before the cutoff', () {
      final yesterday =
          DateTime.now().effectiveDay.subtract(const Duration(days: 1));
      expect(yesterday.isOpenDay, DateTime.now().hour < kDayCutoffHour);
    });
  });
}
