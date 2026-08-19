// The closing stretch of an effective day, which is what "your streak is
// on the line" and the night-review prompt are gated on.
//
// The bug this pins: both used `hour >= 18`, which stops being true at
// midnight. The app's day does not end at midnight, it ends at
// kDayCutoffHour, so between 00:00 and 06:00 the warning disappeared
// during the exact hours the cutoff was invented to protect. Someone up at
// 1am still had five hours to save the streak and the app had gone quiet
// about it.
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
    expect(at(5).isDayClosing, isTrue);
  });

  test('it closes at the cutoff, when the day genuinely rolls over', () {
    expect(at(6).isDayClosing, isFalse);
    expect(at(9).isDayClosing, isFalse);
    expect(at(12).isDayClosing, isFalse);
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

    // And 7am Thursday has rolled over: new day, window shut.
    final morningThu = DateTime(2026, 8, 20, 7, 0);
    expect(morningThu.effectiveDay, isNot(lateWed.effectiveDay));
    expect(morningThu.isDayClosing, isFalse);
  });
}
