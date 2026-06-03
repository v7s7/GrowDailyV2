import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../auth/notifiers/auth_notifier.dart';
import '../catalog/islamic_habit_catalog.dart';
import '../models/habit_model.dart';

class CustomHabitsNotifier
    extends StateNotifier<List<IslamicHabitTemplate>> {
  final String? _uid;

  CustomHabitsNotifier(this._uid) : super([]) {
    if (_uid != null) _load();
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('custom_habits');

  Future<void> _load() async {
    if (_uid == null) return;
    try {
      final snap = await _col.get();
      if (mounted) {
        state = snap.docs
            .map((d) => IslamicHabitTemplate.fromFirestore(d))
            .toList();
      }
    } catch (_) {}
  }

  void add({
    required String name,
    required HabitCategory category,
    required HabitFrequencyType frequencyType,
    required int frequencyTarget,
  }) {
    final rewards = _rewards(category);
    final template = IslamicHabitTemplate(
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
    );
    state = [...state, template];
    if (_uid != null) {
      _col
          .doc(template.id)
          .set(template.toFirestore())
          .ignore();
    }
  }

  void remove(String id) {
    state = state.where((h) => h.id != id).toList();
    if (_uid != null) _col.doc(id).delete().ignore();
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
        (ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return CustomHabitsNotifier(uid);
});

/// Combined list: Islamic catalog + user custom habits
final habitListProvider = Provider<List<IslamicHabitTemplate>>((ref) {
  final custom = ref.watch(customHabitsProvider);
  return [...IslamicHabitCatalog.templates, ...custom];
});
