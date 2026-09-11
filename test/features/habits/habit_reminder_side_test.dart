// A habit reminder has one direction, and it is the sign of its shift.
//
// Add Habit used to ask for it twice: «بعد | قبل» chips on the main step that
// saved nothing for a prayer habit, and «قبل | بعد» in the offset sheet that
// set the sign the scheduler actually reads. The chips now light from the
// signs (HabitReminderStack.side), and tapping the other one mirrors them
// (HabitReminderStack.mirrored). This pins the pure half of that: which side
// a stack is on, and that mirroring moves only the side, never the count or
// the reminder that owns notification slot 0.
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

  group('mirrored', () {
    const stacks = [
      HabitReminderStack(primary: 0),
      HabitReminderStack(primary: -15),
      HabitReminderStack(primary: 45),
      HabitReminderStack(primary: -10, extras: {-30}),
      HabitReminderStack(primary: 0, extras: {-15, -60}),
      HabitReminderStack(primary: -15, extras: {30}),
      HabitReminderStack(primary: 720, extras: {-720, 5, 0}),
    ];

    test('moves every shift to the other side by the same amount', () {
      final m = const HabitReminderStack(primary: -10, extras: {-30}).mirrored();
      expect(m.primary, 10);
      expect(m.extras, {30});
    });

    test('keeps the count and which reminder is the primary', () {
      for (final stack in stacks) {
        final m = stack.mirrored();
        expect(m.length, stack.length, reason: '${stack.all}');
        expect(
          m.primary,
          -stack.primary,
          reason: 'slot 0 has to stay the same reminder: ${stack.all}',
        );
        expect(
          m.extras.contains(m.primary),
          isFalse,
          reason: 'extras never hold the primary: ${stack.all}',
        );
      }
    });

    test('on time stays on time', () {
      expect(const HabitReminderStack(primary: 0).mirrored().all, [0]);
      final m = const HabitReminderStack(primary: 0, extras: {-15}).mirrored();
      expect(m.primary, 0);
      expect(m.extras, {15});
    });

    test('mirroring twice gives back the original', () {
      for (final stack in stacks) {
        final twice = stack.mirrored().mirrored();
        expect(twice.primary, stack.primary, reason: '${stack.all}');
        expect(twice.extras, stack.extras, reason: '${stack.all}');
      }
    });

    test('a one-sided stack lands on the other side, the rest stay put', () {
      const sides = {
        HabitReminderSide.none: HabitReminderSide.none,
        HabitReminderSide.before: HabitReminderSide.after,
        HabitReminderSide.after: HabitReminderSide.before,
        HabitReminderSide.both: HabitReminderSide.both,
      };
      for (final stack in stacks) {
        expect(
          stack.mirrored().side,
          sides[stack.side],
          reason: '${stack.all}',
        );
      }
    });
  });
}
