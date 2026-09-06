// The edit rule behind a reminder row in Add Habit: tap a row, pick another
// value, and that value takes the row's place. Pure model, no widgets.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_reminder_stack.dart';

void main() {
  group('HabitReminderStack.replace', () {
    test('the primary edited becomes the new primary', () {
      const stack = HabitReminderStack(primary: 0, extras: {-15});
      final next = stack.replace(0, 30);
      expect(next.primary, 30);
      expect(next.extras, {-15});
    });

    test('an extra edited keeps the primary and swaps the extra', () {
      const stack = HabitReminderStack(primary: 0, extras: {-15, -30});
      final next = stack.replace(-15, 60);
      expect(next.primary, 0);
      expect(next.extras, {-30, 60});
    });

    test('a lone reminder is edited in place, never removed', () {
      const stack = HabitReminderStack(primary: 0);
      final next = stack.replace(0, -10);
      expect(next.all, [-10]);
    });

    test('editing to a value already on the list only drops the old one',
        () {
      const stack = HabitReminderStack(primary: 0, extras: {-15});
      final next = stack.replace(-15, 0);
      expect(next.all, [0], reason: 'no doubled reminder');
      expect(next.primary, 0);
    });

    test('the primary edited to an existing extra promotes that extra', () {
      const stack = HabitReminderStack(primary: 0, extras: {-15, 30});
      final next = stack.replace(0, -15);
      expect(next.primary, -15);
      expect(next.extras, {30});
    });

    test('editing to the same value, or a value not carried, is a no-op', () {
      const stack = HabitReminderStack(primary: 0, extras: {-15});
      expect(identical(stack.replace(0, 0), stack), isTrue);
      expect(identical(stack.replace(45, 10), stack), isTrue);
    });
  });
}
