// A room must count a completion made in a day's grace tail.
//
// Traced on Aziz's own account on 2026-09-07. He prayed الوتر at 1 AM and,
// at 02:13, marked the 6th in the Grid: the day doc for the 6th shows the
// completion, the square, 100 XP and 40 gold on its own ledger, and no clock
// stamp, exactly as the overlapping-day window prescribes for a grace mark.
// Both rooms that link the habit recorded nothing for the 6th, and the full
// regrade later that day still refused it: the anti-backdating clamp in
// syncLinkedHabitsProgress asked "is this day before today" and "has the
// room observed it", and both were true, because the first sync after
// midnight stamps lastSyncedDay with the new day. The app had paid the day;
// the room held it at the zero a midnight sync had seen.
//
// The rule is now roomDayIsClosedAt: the clamp applies only once the day is
// closed, which under DateTimeGameExt.isOpenDayAt is 10:00 the next morning,
// the same moment the Grid stops paying it.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

void main() {
  final sixth = DateTime(2026, 9, 6);

  test('yesterday inside its grace tail is still open to the room', () {
    expect(roomDayIsClosedAt(sixth, DateTime(2026, 9, 7, 2, 13)), isFalse,
        reason: 'the Witr mark at 02:13 on the 7th belongs to the 6th');
    expect(roomDayIsClosedAt(sixth, DateTime(2026, 9, 7, 9, 59)), isFalse);
  });

  test('yesterday closes at the cutoff, the same moment the Grid stops paying',
      () {
    expect(roomDayIsClosedAt(sixth, DateTime(2026, 9, 7, kDayCutoffHour)),
        isTrue);
    expect(roomDayIsClosedAt(sixth, DateTime(2026, 9, 7, 18, 32)), isTrue);
  });

  test('today is never closed, at any hour', () {
    expect(roomDayIsClosedAt(sixth, DateTime(2026, 9, 6, 0, 0)), isFalse);
    expect(roomDayIsClosedAt(sixth, DateTime(2026, 9, 6, 23, 59)), isFalse);
  });

  test('two days back is closed even during the grace hours', () {
    expect(roomDayIsClosedAt(DateTime(2026, 9, 5), DateTime(2026, 9, 7, 2, 13)),
        isTrue);
  });

  test('a day that has not started is closed to backfill as well', () {
    // Nothing marked ahead of its own midnight, matching setSquare's guard.
    expect(roomDayIsClosedAt(DateTime(2026, 9, 8), DateTime(2026, 9, 7, 23)),
        isTrue);
  });

  test('the rule is the Grid\'s own open-day rule, not a copy of it', () {
    for (var hour = 0; hour < 24; hour++) {
      for (final day in [sixth, DateTime(2026, 9, 7), DateTime(2026, 9, 5)]) {
        final now = DateTime(2026, 9, 7, hour, 30);
        expect(roomDayIsClosedAt(day, now), !day.isOpenDayAt(now),
            reason: '$day at $now');
      }
    }
  });

  group('roomDayMarkedWhileOpen', () {
    test('a day written inside its grace window holds on-time marks', () {
      // The Witr mark: the 6th's document last written at 02:13 on the 7th.
      expect(roomDayMarkedWhileOpen(sixth, DateTime(2026, 9, 7, 2, 13)), isTrue);
      expect(roomDayMarkedWhileOpen(sixth, DateTime(2026, 9, 6, 22, 0)), isTrue);
    });

    test('a day written after it closed may hold late marks, so no exemption',
        () {
      expect(roomDayMarkedWhileOpen(sixth, DateTime(2026, 9, 7, kDayCutoffHour)),
          isFalse);
      expect(roomDayMarkedWhileOpen(sixth, DateTime(2026, 9, 9, 15, 0)), isFalse);
    });

    test('no stamp, no exemption', () {
      expect(roomDayMarkedWhileOpen(sixth, null), isFalse);
    });
  });
}
