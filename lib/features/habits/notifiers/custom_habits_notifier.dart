import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../catalog/islamic_habit_catalog.dart';
import '../models/habit_model.dart';

class CustomHabitsNotifier
    extends StateNotifier<List<IslamicHabitTemplate>> {
  CustomHabitsNotifier() : super([]);

  void add({
    required String name,
    required HabitCategory category,
    required HabitFrequencyType frequencyType,
    required int frequencyTarget,
  }) {
    final rewards = _rewards(category);
    state = [
      ...state,
      IslamicHabitTemplate(
        id: const Uuid().v4(),
        name: name,
        description: '',
        iconEmoji: '',
        category: category,
        frequencyType: frequencyType,
        frequencyTarget: frequencyTarget,
        hasTimer: false,
        xpReward: rewards.$1,
        goldReward: rewards.$2,
      ),
    ];
  }

  void remove(String id) {
    state = state.where((h) => h.id != id).toList();
  }

  static (int, int) _rewards(HabitCategory c) => switch (c) {
        HabitCategory.quran => (30, 10),
        HabitCategory.athkar => (15, 5),
        HabitCategory.fitness => (20, 8),
        HabitCategory.fasting => (40, 15),
        HabitCategory.sadaqah => (25, 10),
        HabitCategory.sleep => (15, 5),
        HabitCategory.custom => (20, 8),
      };
}

final customHabitsProvider =
    StateNotifierProvider<CustomHabitsNotifier, List<IslamicHabitTemplate>>(
        (ref) => CustomHabitsNotifier());

/// Combined list: Islamic catalog + user custom habits
final habitListProvider = Provider<List<IslamicHabitTemplate>>((ref) {
  final custom = ref.watch(customHabitsProvider);
  return [...IslamicHabitCatalog.templates, ...custom];
});
