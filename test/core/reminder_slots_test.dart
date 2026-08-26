// One habit, several reminders a day.
//
// A habit counted N times a day wants N reminders, and the notification id is
// the only handle the OS gives us on an already-scheduled one. Two slots
// sharing an id means the second silently replaces the first — a habit set to
// four times a day pings once and looks broken — and an id that moves between
// releases strands whatever is already in the system scheduler.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';

void main() {
  int off(String id, int slot) =>
      NotificationService.reminderSlotOffset(id, slot);

  const habit = 'habit_abc123';

  test('slot 0 is exactly the id this habit had before slots existed', () {
    // The pre-slot scheme, spelled out rather than referenced, so this fails
    // if anyone changes it: upgrading must not orphan a scheduled reminder.
    expect(off(habit, 0), habit.hashCode.abs() % 1000);
  });

  test('every slot of one habit gets its own id', () {
    final ids = {for (var s = 0; s < 12; s++) off(habit, s)};
    expect(ids.length, 12,
        reason: 'two slots sharing an id means one reminder overwrites the '
            'other and never fires');
  });

  test('no slot escapes the 0-999 band its family is allotted', () {
    for (var s = 0; s < 12; s++) {
      expect(off(habit, s), inInclusiveRange(0, 999),
          reason: 'the habit band is 5000-5999 and snooze is 6000-6999; an '
              'offset past 999 collides with the next family');
    }
  });

  test('different habits do not share a slot id', () {
    for (var s = 0; s < 12; s++) {
      expect(off('habit_one', s), isNot(off('habit_two', s)),
          reason: 'slot $s collided across two habits');
    }
  });

  test('the same habit and slot is stable across calls', () {
    // It has to be: cancelling works by recomputing the id later.
    expect(off(habit, 3), off(habit, 3));
    expect(off(habit, 0), off(habit, 0));
  });

  test('an empty habit id still produces a legal offset', () {
    for (var s = 0; s < 12; s++) {
      expect(off('', s), inInclusiveRange(0, 999));
    }
  });
}
