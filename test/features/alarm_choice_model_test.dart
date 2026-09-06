// The alarm choice as a stored fact, on each of the three records that
// carry it: a custom habit, a catalog habit's override, and a task. All
// three default to false and write the field only when it is set, so an
// older build reading the document finds nothing new.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/catalog_overrides_notifier.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';

void main() {
  group('IslamicHabitTemplate.alarm', () {
    const base = IslamicHabitTemplate(
      id: 'h1',
      name: 'Walk',
      description: '',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 20,
      goldReward: 8,
    );

    test('is off by default and absent from the map', () {
      expect(base.alarm, isFalse);
      expect(base.toFirestore().containsKey('alarm'), isFalse);
      expect(IslamicHabitTemplate.fromMap('h1', base.toFirestore()).alarm, isFalse);
    });

    test('round-trips when set', () {
      const on = IslamicHabitTemplate(
        id: 'h1',
        name: 'Fajr',
        description: '',
        category: HabitCategory.custom,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        hasTimer: false,
        xpReward: 20,
        goldReward: 8,
        alarm: true,
      );
      expect(on.toFirestore()['alarm'], isTrue);
      expect(IslamicHabitTemplate.fromMap('h1', on.toFirestore()).alarm,
          isTrue);
    });

    test('survives the reminder-offset copy', () {
      const on = IslamicHabitTemplate(
        id: 'h1',
        name: 'Fajr',
        description: '',
        category: HabitCategory.custom,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        hasTimer: false,
        xpReward: 20,
        goldReward: 8,
        alarm: true,
      );
      expect(on.withReminderOffset(-10).alarm, isTrue,
          reason: 'a copy helper that dropped the flag would silently '
              'turn an alarm back into a notification');
    });
  });

  group('CatalogHabitOverride.alarm', () {
    test('null means untouched, and applies over the catalog default', () {
      const none = CatalogHabitOverride();
      expect(none.isEmpty, isTrue);
      expect(none.toMap().containsKey('alarm'), isFalse);
      const on = CatalogHabitOverride(alarm: true);
      expect(on.isEmpty, isFalse);
      expect(CatalogHabitOverride.fromMap(on.toMap()).alarm, isTrue);
      const template = IslamicHabitTemplate(
        id: 'fajr',
        name: 'Fajr',
        description: '',
        category: HabitCategory.faith,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        hasTimer: false,
        xpReward: 20,
        goldReward: 8,
      );
      expect(on.applyTo(template).alarm, isTrue);
      expect(none.applyTo(template).alarm, isFalse);
    });
  });

  group('MatrixTask.alarm', () {
    test('is off by default and round-trips through the guest map', () {
      final task = MatrixTask.create('Call mum', MatrixQuadrant.doFirst);
      expect(task.alarm, isFalse);
      expect(MatrixTask.fromMap(task.toMap()).alarm, isFalse);
      final on = MatrixTask.create('Call mum', MatrixQuadrant.doFirst,
          alarm: true);
      expect(MatrixTask.fromMap(on.toMap()).alarm, isTrue);
    });

    test('copyWith keeps it unless told otherwise', () {
      final on = MatrixTask.create('t', MatrixQuadrant.schedule, alarm: true);
      expect(on.copyWith(title: 'u').alarm, isTrue);
      expect(on.copyWith(alarm: false).alarm, isFalse);
    });
  });
}
