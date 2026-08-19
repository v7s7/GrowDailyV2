// The truth table behind the duplicate catch-up fix.
//
// The bug: zonedSchedule notifications are delivered by the OS whether or
// not the app is running, so a reminder that fired ON TIME still read as
// "missed and open" to the next resync, and the app fired an identical
// catch-up banner at the next open — including when the user arrived BY
// TAPPING the original notification. shouldFireTaskCatchUp is the pure
// decision extracted so this table can be pinned without Hive.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';

void main() {
  final t3 = DateTime(2026, 8, 19, 15, 0);
  final t330 = DateTime(2026, 8, 19, 15, 30);
  final t4 = DateTime(2026, 8, 19, 16, 0);

  test('a moment this device armed never catches up — the OS delivered it',
      () {
    expect(
      shouldFireTaskCatchUp(missedAt: t3, armedThrough: t3),
      isFalse,
      reason: 'armed exactly through the missed moment',
    );
    expect(
      shouldFireTaskCatchUp(missedAt: t3, armedThrough: t4),
      isFalse,
      reason: 'armed beyond it',
    );
  });

  test('a moment never armed here catches up — the cross-device case', () {
    expect(shouldFireTaskCatchUp(missedAt: t3), isTrue);
    expect(
      shouldFireTaskCatchUp(missedAt: t4, armedThrough: t3),
      isTrue,
      reason: 'a later reminder added on another device, past arming here',
    );
  });

  test('never re-fires at or before the last catch-up', () {
    expect(
      shouldFireTaskCatchUp(missedAt: t3, previousCatchUp: t3),
      isFalse,
    );
    expect(
      shouldFireTaskCatchUp(missedAt: t330, previousCatchUp: t4),
      isFalse,
      reason: 'stack edit moved the latest-missed moment backwards',
    );
    expect(
      shouldFireTaskCatchUp(missedAt: t4, previousCatchUp: t330),
      isTrue,
    );
  });

  test('both guards apply together', () {
    expect(
      shouldFireTaskCatchUp(
        missedAt: t4,
        previousCatchUp: t3,
        armedThrough: t4,
      ),
      isFalse,
      reason: 'newer than the last catch-up but armed here — OS handled it',
    );
  });
}
