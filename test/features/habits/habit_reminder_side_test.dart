// A habit reminder has one direction, and it is the sign of its shift.
//
// Add Habit used to ask for it twice: «بعد | قبل» chips on the main step that
// saved nothing for a prayer habit, and «قبل | بعد» in the offset sheet that
// set the sign the scheduler actually reads. The chips were made to light
// from the signs, then taken off the prayer step (2026-09-12), so the sheet
// is where the side is chosen, and for a reminder with no side of its own it
// leans from the signs (HabitReminderStack.side). This pins which side a
// stack is on.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/habits/models/habit_reminder_stack.dart';

void main() {
  group('side', () {
    test('on time alone has no side', () {
      expect(const HabitReminderStack(primary: 0).side, HabitReminderSide.none);
    });

    test('15 before is before', () {
      expect(
        const HabitReminderStack(primary: -15).side,
        HabitReminderSide.before,
      );
    });

    test('15 after is after', () {
      expect(
        const HabitReminderStack(primary: 15).side,
        HabitReminderSide.after,
      );
    });

    test('15 before together with 30 after is both', () {
      expect(
        const HabitReminderStack(primary: -15, extras: {30}).side,
        HabitReminderSide.both,
      );
      expect(
        const HabitReminderStack(primary: 30, extras: {-15}).side,
        HabitReminderSide.both,
        reason: 'which of the two is the primary does not change the side',
      );
    });

    test('an on-time reminder beside a shift takes no side of its own', () {
      expect(
        const HabitReminderStack(primary: 0, extras: {-15}).side,
        HabitReminderSide.before,
      );
      expect(
        const HabitReminderStack(primary: 45, extras: {0}).side,
        HabitReminderSide.after,
      );
    });
  });
}
