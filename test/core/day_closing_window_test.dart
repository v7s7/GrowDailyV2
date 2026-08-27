// The closing stretch of an effective day, which is what "your streak is
// on the line" and the night-review prompt are gated on.
//
// The bug this pins: both used `hour >= 18`, which stops being true at
// midnight. The app's day does not end at midnight, it ends at
// kDayCutoffHour, so the small hours lost the warning during the exact
// hours the cutoff was invented to protect. Someone up at 1am still had
// hours to save the streak and the app had gone quiet about it.
//
// Written against kDayCutoffHour rather than a written-out hour on
// purpose: the cutoff has already moved once (6 AM to 10 AM) and these
// assertions are about the SHAPE of the window, not the number. A test
// that hardcodes the hour fails on the next move for no reason, and
// worse, a test that hardcodes it and passes proves nothing about the
// wrapping.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';

void main() {
  DateTime at(int hour, {int day = 19}) => DateTime(2026, 8, day, hour, 30);

  test('the window opens at 6pm', () {
    expect(at(17).isDayClosing, isFalse);
    expect(at(18).isDayClosing, isTrue);
    expect(at(23).isDayClosing, isTrue);
  });

  test('midnight does NOT close it — this is the whole point', () {
    // Same effective day as 11pm the night before, so the same warning has
    // to still be on screen.
    expect(at(0).isDayClosing, isTrue);
    expect(at(1).isDayClosing, isTrue);
    expect(at(kDayCutoffHour - 1).isDayClosing, isTrue);
  });

  test('it closes at the cutoff, when the day genuinely rolls over', () {
    expect(at(kDayCutoffHour).isDayClosing, isFalse);
    expect(at(kDayCutoffHour + 1).isDayClosing, isFalse);
    expect(at(17).isDayClosing, isFalse);
  });

  test('the window agrees with effectiveDay about which day it is', () {
    // 11pm Wednesday and 1am Thursday are the same effective day, and both
    // are inside the window. That pairing is the invariant: the warning is
    // live for a contiguous stretch of ONE day, not two half-days split by
    // the calendar.
    final lateWed = DateTime(2026, 8, 19, 23, 0);
    final earlyThu = DateTime(2026, 8, 20, 1, 0);
    expect(lateWed.effectiveDay, earlyThu.effectiveDay);
    expect(lateWed.isDayClosing, isTrue);
    expect(earlyThu.isDayClosing, isTrue);

    // And the first hour past the cutoff has rolled over: new day, window
    // shut.
    final afterCutoffThu = DateTime(2026, 8, 20, kDayCutoffHour, 0);
    expect(afterCutoffThu.effectiveDay, isNot(lateWed.effectiveDay));
    expect(afterCutoffThu.isDayClosing, isFalse);
  });

  test('the last minute before the cutoff still belongs to yesterday', () {
    // The reason the cutoff was widened: someone who slept until 9:30am
    // opens the app and the board is still yesterday's, still markable,
    // still warning them.
    final lateNight = DateTime(2026, 8, 19, 23, 0);
    final lateMorning = DateTime(2026, 8, 20, kDayCutoffHour - 1, 59);
    expect(lateMorning.effectiveDay, lateNight.effectiveDay);
    expect(lateMorning.isDayClosing, isTrue);
  });
}
