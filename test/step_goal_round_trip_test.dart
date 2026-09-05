import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

void main() {
  IslamicHabitTemplate makeHabit({int? stepGoal}) => IslamicHabitTemplate(
        id: 'walk-1',
        name: 'المشي اليومي',
        description: '',
        category: HabitCategory.health,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        hasTimer: false,
        xpReward: 20,
        goldReward: 8,
        stepGoal: stepGoal,
      );

  group('stepGoal serialization', () {
    test('round-trips through toFirestore/fromMap', () {
      final map = makeHabit(stepGoal: 8000).toFirestore();
      expect(map['stepGoal'], 8000);
      final back = IslamicHabitTemplate.fromMap('walk-1', map);
      expect(back.stepGoal, 8000);
    });

    test('unlinked habit writes no key and reads back null', () {
      final map = makeHabit().toFirestore();
      expect(map.containsKey('stepGoal'), isFalse);
      expect(IslamicHabitTemplate.fromMap('walk-1', map).stepGoal, isNull);
    });

    test('legacy documents without the field load as unlinked', () {
      final back = IslamicHabitTemplate.fromMap('walk-1', {
        'name': 'Walk',
        'category': 'health',
        'frequencyType': 'daily',
        'frequencyTarget': 1,
        'hasTimer': false,
      });
      expect(back.stepGoal, isNull);
    });

    test('every copy helper carries the link', () {
      final habit = makeHabit(stepGoal: 6000);
      expect(habit.withCreatedAt(DateTime(2026)).stepGoal, 6000);
      expect(habit.withReminderOffset(-15).stepGoal, 6000);
      expect(
        habit.withDates(createdAt: DateTime(2026)).stepGoal,
        6000,
      );
    });
  });
}
