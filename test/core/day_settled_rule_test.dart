// When a habit-day may be counted: DateTimeGameExt.isSettledAt.
//
// Aziz, 2026-09-11, on Reports > شهري at 05:19: today was already counted
// as missed "because today still not finish", and it should only count as
// missed once the day and its flex hours are over. A day stays open until
// kDayCutoffHour the next morning; until then it counts only once it is
// answered (done, or an explicit فشل).
//
// Written against kDayCutoffHour rather than the literal 10, so these
// describe the rule and survive a move.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';

void main() {
  // Wednesday 9 to Saturday 12 September 2026.
  final wed9 = DateTime(2026, 9, 9);
  final thu10 = DateTime(2026, 9, 10);
  final fri11 = DateTime(2026, 9, 11);
  final sat12 = DateTime(2026, 9, 12);

  DateTime fri(int h, [int m = 0]) => DateTime(2026, 9, 11, h, m);
  DateTime sat(int h, [int m = 0]) => DateTime(2026, 9, 12, h, m);
  final beforeCutoff = fri(kDayCutoffHour - 1, 59);
  final atCutoff = fri(kDayCutoffHour);

  test('the calendar these tests rest on', () {
    expect(fri11.weekday, DateTime.friday);
    expect(DateTime(2026, 9, 5).weekday, DateTime.saturday);
  });

  test('a future day never counts, blank or answered', () {
    for (final now in [fri(0), fri(5, 19), beforeCutoff, atCutoff, fri(23, 59)]) {
      expect(sat12.isSettledAt(now), isFalse, reason: '$now');
      expect(sat12.isSettledAt(now, answered: true), isFalse, reason: '$now');
    }
  });

  group('today', () {
    test('a blank today is not settled at 00:00, nor at 23:59', () {
      expect(fri11.isSettledAt(fri(0)), isFalse);
      expect(fri11.isSettledAt(fri(23, 59)), isFalse);
    });

    test('an answered today counts at once', () {
      expect(fri11.isSettledAt(fri(0), answered: true), isTrue);
      expect(fri11.isSettledAt(fri(5, 19), answered: true), isTrue);
    });

    test('a blank today closes at the cutoff the next morning, not midnight',
        () {
      expect(fri11.isSettledAt(sat(0)), isFalse);
      expect(fri11.isSettledAt(sat(kDayCutoffHour - 1, 59)), isFalse);
      expect(fri11.isSettledAt(sat(kDayCutoffHour)), isTrue);
    });
  });

  group('yesterday', () {
    test('blank: still open one minute before the cutoff, closed at it', () {
      expect(thu10.isSettledAt(beforeCutoff), isFalse);
      expect(thu10.isSettledAt(atCutoff), isTrue);
    });

    test('answered: counts before the cutoff as well', () {
      expect(thu10.isSettledAt(fri(5, 19), answered: true), isTrue);
    });
  });

  test('two days back has closed at every hour of the day', () {
    for (var h = 0; h < 24; h++) {
      expect(wed9.isSettledAt(fri(h)), isTrue, reason: '$h:00');
    }
  });

  test('for a day that has begun, unanswered, it is exactly !isOpenDayAt', () {
    // The cutoff is defined once. This is what stops a second definition
    // creeping in here.
    for (final day in [wed9, thu10, fri11]) {
      for (var h = 0; h < 24; h++) {
        expect(day.isSettledAt(fri(h)), !day.isOpenDayAt(fri(h)),
            reason: '$day at $h:00');
      }
    }
  });

  test('only a finished square and an explicit فشل answer a day', () {
    expect(SquareState.complete.answersDay, isTrue);
    expect(SquareState.bonus.answersDay, isTrue);
    expect(SquareState.failed.answersDay, isTrue);
    expect(SquareState.none.answersDay, isFalse);
    expect(SquareState.partial.answersDay, isFalse,
        reason: 'a half-done day can still be finished');
    expect(SquareState.skipped.answersDay, isFalse,
        reason: 'a rest leaves every count anyway');
  });
}
