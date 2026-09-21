// The closing stretch of an effective day, which is what "your streak is
// on the line" is gated on.
//
// The bug this pins: it used `hour >= 18`, which stops being true at
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
//
// The night-review prompt and the streak-at-risk banner both used to share
// this exact window for their own on-screen display, but no longer do -
// see isEveningNudgeHour's own tests below for why the DEADLINE this file
// pins stayed put while the proactive banners about it now stop several
// hours earlier.
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

  test('the window covers one day\'s last chance, across midnight', () {
    // 11pm Wednesday and 1am Thursday are two different days now — the day
    // rolls at midnight — but they are the same WARNING, because Wednesday
    // is still markable at 1am inside its grace tail. The invariant is
    // about the last chance, not about the date: it is live for a
    // contiguous stretch, and what it points at is Wednesday throughout.
    final lateWed = DateTime(2026, 8, 19, 23, 0);
    final earlyThu = DateTime(2026, 8, 20, 1, 0);
    final wed = DateTime(2026, 8, 19);
    expect(lateWed.effectiveDay, isNot(earlyThu.effectiveDay),
        reason: 'midnight really does roll the day now');
    expect(wed.isOpenDayAt(lateWed), isTrue);
    expect(wed.isOpenDayAt(earlyThu), isTrue,
        reason: 'and Wednesday is what is still on the line at 1am');
    expect(lateWed.isDayClosing, isTrue);
    expect(earlyThu.isDayClosing, isTrue);

    // Past the cutoff Wednesday is closed for good, and so is the warning.
    final afterCutoffThu = DateTime(2026, 8, 20, kDayCutoffHour, 0);
    expect(wed.isOpenDayAt(afterCutoffThu), isFalse);
    expect(afterCutoffThu.isDayClosing, isFalse);
  });

  test('the last minute before the cutoff is yesterday\'s last chance', () {
    // Why the grace is ten hours: someone who slept until 9:30am opens the
    // app, yesterday is still markable, and the warning is still up. What
    // changed is that the BOARD is now today's, and yesterday is a day they
    // step back to rather than the one the app assumed they meant.
    final wed = DateTime(2026, 8, 19);
    final lateMorning = DateTime(2026, 8, 20, kDayCutoffHour - 1, 59);
    expect(wed.isOpenDayAt(lateMorning), isTrue);
    expect(lateMorning.effectiveDay, DateTime(2026, 8, 20),
        reason: 'the board itself has moved on to Thursday');
    expect(lateMorning.isDayClosing, isTrue);
  });

  group('isEveningNudgeHour — the proactive evening banners, narrower', () {
    // Reported live, twice: first the night-review prompt, then the
    // streak-at-risk banner, both still showing up well into the morning,
    // riding isDayClosing's 10am streak-save DEADLINE for what was really a
    // question of proactive-banner DISPLAY. The deadline did not move for
    // either one - a streak can still genuinely be saved until 10am, and
    // the review still keys by effectiveDay - only the unprompted nudge
    // about either one now stops earlier.
    test('the window opens at 6pm, same as isDayClosing', () {
      expect(at(17).isEveningNudgeHour, isFalse);
      expect(at(18).isEveningNudgeHour, isTrue);
      expect(at(23).isEveningNudgeHour, isTrue);
    });

    test('midnight does not close it, same as isDayClosing', () {
      expect(at(0).isEveningNudgeHour, isTrue);
      expect(at(kEveningNudgeCutoffHour - 1).isEveningNudgeHour, isTrue);
    });

    test('it closes at its OWN cutoff, well before isDayClosing does', () {
      expect(at(kEveningNudgeCutoffHour).isEveningNudgeHour, isFalse);
      expect(at(kEveningNudgeCutoffHour + 1).isEveningNudgeHour, isFalse);
    });

    test('the two windows genuinely diverge between the two cutoffs', () {
      // The exact stretch both live reports were about: still within
      // isDayClosing's streak-save grace (the DEADLINE), but the day is
      // well underway and neither proactive banner belongs on screen
      // anymore.
      for (var h = kEveningNudgeCutoffHour; h < kDayCutoffHour; h++) {
        expect(at(h).isDayClosing, isTrue,
            reason: 'hour $h: yesterday'
                "'s streak can still genuinely be saved");
        expect(at(h).isEveningNudgeHour, isFalse,
            reason: 'hour $h: but neither banner should be asking about it '
                'unprompted');
      }
    });
  });
}
