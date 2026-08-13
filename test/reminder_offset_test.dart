import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';

/// Covers the signed reminder-offset convention and the read-time migration
/// off the old `reminderLeadMinutes` field.
///
/// Why this file exists: the old field was always *subtracted* (so it could
/// only ever mean "before"), while a separate global setting was *added* on
/// top of it — the two silently cancelled each other out and made Add
/// Habit's own preview disagree with the reminder that actually fired. The
/// replacement is one signed number per habit (negative = before, positive
/// = after), so these tests pin both the sign convention itself and the
/// promise that nobody's existing "15 minutes before" habit silently
/// becomes "15 minutes after" on upgrade.
void main() {
  Map<String, dynamic> baseMap() => {
        'name': 'Test Habit',
        'description': '',
        'category': 'custom',
        'frequencyType': 'daily',
        'frequencyTarget': 1,
        'hasTimer': false,
        'xpReward': 20,
        'goldReward': 8,
      };

  group('reminderOffsetMinutes sign convention', () {
    test('defaults to 0 ("on time") when nothing is stored', () {
      final habit = IslamicHabitTemplate.fromMap('id', baseMap());
      expect(habit.reminderOffsetMinutes, 0);
    });

    test('negative means before, positive means after', () {
      final before = IslamicHabitTemplate.fromMap(
          'id', {...baseMap(), 'reminderOffsetMinutes': -30});
      final after = IslamicHabitTemplate.fromMap(
          'id', {...baseMap(), 'reminderOffsetMinutes': 15});
      expect(before.reminderOffsetMinutes, -30);
      expect(after.reminderOffsetMinutes, 15);
    });

    test('a negative offset survives a save/load round trip', () {
      // Regression guard: toFirestore's guard used to be `> 0`, which would
      // silently drop every "before" value now that they're negative.
      final original = IslamicHabitTemplate.fromMap(
          'id', {...baseMap(), 'reminderOffsetMinutes': -45});
      final reloaded =
          IslamicHabitTemplate.fromMap('id', original.toFirestore());
      expect(reloaded.reminderOffsetMinutes, -45);
    });

    test('an on-time (0) offset round trips as 0', () {
      final original = IslamicHabitTemplate.fromMap('id', baseMap());
      final reloaded =
          IslamicHabitTemplate.fromMap('id', original.toFirestore());
      expect(reloaded.reminderOffsetMinutes, 0);
    });
  });

  group('legacy reminderLeadMinutes migration', () {
    test('an old lead of 15 becomes an offset of -15 (still "before")', () {
      final habit = IslamicHabitTemplate.fromMap(
          'id', {...baseMap(), 'reminderLeadMinutes': 15});
      expect(habit.reminderOffsetMinutes, -15);
    });

    test('an old lead of 0 stays 0', () {
      final habit = IslamicHabitTemplate.fromMap(
          'id', {...baseMap(), 'reminderLeadMinutes': 0});
      expect(habit.reminderOffsetMinutes, 0);
    });

    test('the new field wins when both are present', () {
      // Can happen on a device that wrote the new key while an older build
      // elsewhere still had the old one on the same doc.
      final habit = IslamicHabitTemplate.fromMap('id', {
        ...baseMap(),
        'reminderLeadMinutes': 15,
        'reminderOffsetMinutes': 30,
      });
      expect(habit.reminderOffsetMinutes, 30);
    });

    test('migrating writes back under the new key only', () {
      final habit = IslamicHabitTemplate.fromMap(
          'id', {...baseMap(), 'reminderLeadMinutes': 45});
      final saved = habit.toFirestore();
      expect(saved['reminderOffsetMinutes'], -45);
      expect(saved.containsKey('reminderLeadMinutes'), isFalse);
    });
  });

  group('ignoreQuietHours', () {
    test('defaults to false', () {
      expect(
        IslamicHabitTemplate.fromMap('id', baseMap()).ignoreQuietHours,
        isFalse,
      );
    });

    test('round trips when set', () {
      final habit = IslamicHabitTemplate.fromMap(
          'id', {...baseMap(), 'ignoreQuietHours': true});
      final reloaded =
          IslamicHabitTemplate.fromMap('id', habit.toFirestore());
      expect(reloaded.ignoreQuietHours, isTrue);
    });
  });

  group('editing an existing habit re-saves the reminder correctly', () {
    // CustomHabitsNotifier.update writes with a plain `set()` (a full
    // document overwrite), not `set(..., merge: true)`. These pin the
    // behavior that depends on it — a merge write would silently keep a
    // stale offset around forever, which is the one way "edit the reminder"
    // could look like it worked but not actually change anything.

    test('changing the offset replaces the old value', () {
      final saved = IslamicHabitTemplate.fromMap(
          'id', {...baseMap(), 'reminderOffsetMinutes': -30});
      final edited = saved.withReminderOffset(15);
      final reloaded =
          IslamicHabitTemplate.fromMap('id', edited.toFirestore());
      expect(reloaded.reminderOffsetMinutes, 15);
    });

    test('resetting to "On time" clears the stored offset entirely', () {
      // The regression a merge-write would cause: toFirestore omits the key
      // when the offset is 0, so only a full overwrite actually erases the
      // previous -30. Reading back anything but 0 here means someone who
      // set their reminder back to "On time" would keep getting it early.
      final saved = IslamicHabitTemplate.fromMap(
          'id', {...baseMap(), 'reminderOffsetMinutes': -30});
      final edited = saved.withReminderOffset(0);
      final written = edited.toFirestore();
      expect(written.containsKey('reminderOffsetMinutes'), isFalse);
      expect(
        IslamicHabitTemplate.fromMap('id', written).reminderOffsetMinutes,
        0,
      );
    });

    test('editing a legacy habit drops the old key and writes the new one',
        () {
      // A habit last saved by an older build still carries
      // reminderLeadMinutes. Opening and saving it in the edit sheet should
      // leave exactly one reminder field behind, with the same meaning.
      final legacy = IslamicHabitTemplate.fromMap(
          'id', {...baseMap(), 'reminderLeadMinutes': 30});
      expect(legacy.reminderOffsetMinutes, -30);

      final written = legacy.toFirestore();
      expect(written.containsKey('reminderLeadMinutes'), isFalse);
      expect(written['reminderOffsetMinutes'], -30);
      expect(
        IslamicHabitTemplate.fromMap('id', written).reminderOffsetMinutes,
        -30,
      );
    });

    test('flipping a reminder from before to after survives the round trip',
        () {
      final before = IslamicHabitTemplate.fromMap(
          'id', {...baseMap(), 'cueAfter': 'fajr', 'reminderOffsetMinutes': -15});
      final after = before.withReminderOffset(15);
      final reloaded =
          IslamicHabitTemplate.fromMap('id', after.toFirestore());
      expect(reloaded.reminderOffsetMinutes, 15);
      expect(reloaded.cueAfter, 'fajr');
    });

    test('the quiet-hours override survives an unrelated edit', () {
      final saved = IslamicHabitTemplate.fromMap('id', {
        ...baseMap(),
        'reminderOffsetMinutes': -15,
        'ignoreQuietHours': true,
      });
      final edited = saved.withReminderOffset(-45);
      final reloaded =
          IslamicHabitTemplate.fromMap('id', edited.toFirestore());
      expect(reloaded.reminderOffsetMinutes, -45);
      expect(reloaded.ignoreQuietHours, isTrue);
    });
  });

  group('withReminderOffset', () {
    test('swaps the offset and preserves everything else', () {
      final original = IslamicHabitTemplate.fromMap('id', {
        ...baseMap(),
        'name': 'Witr',
        'cueAfter': 'isha',
        'reminderOffsetMinutes': -10,
        'ignoreQuietHours': true,
      });
      // +10 global folded into a -10 habit lands on exactly 0 — the case
      // the prayer-offset migration in CustomHabitsNotifier produces.
      final moved =
          original.withReminderOffset(original.reminderOffsetMinutes + 10);
      expect(moved.reminderOffsetMinutes, 0);
      expect(moved.name, 'Witr');
      expect(moved.cueAfter, 'isha');
      expect(moved.ignoreQuietHours, isTrue);
      expect(moved.id, original.id);
    });
  });
}
