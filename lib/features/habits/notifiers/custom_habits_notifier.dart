import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/local_store_service.dart';
import '../../../core/utils/intention_phrase.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../catalog/habit_plans.dart';
import '../catalog/islamic_habit_catalog.dart';
import '../models/habit_model.dart';

class CustomHabitsNotifier
    extends StateNotifier<List<IslamicHabitTemplate>> {
  final String? _uid;

  CustomHabitsNotifier(this._uid) : super([]) {
    if (_uid != null) {
      _load();
    } else {
      _loadGuest();
    }
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('custom_habits');

  Future<void> _loadGuest() async {
    final box = await LocalStoreService.habitsBox();
    final raw = LocalStoreService.asMapList(
      box.get(LocalStoreService.guestCustomHabitsKey),
    );
    if (!mounted) return;
    state = raw
        .map((item) => IslamicHabitTemplate.fromMap(
              item['id'] as String? ?? const Uuid().v4(),
              item,
            ))
        .toList();
  }

  Future<void> _saveGuest() async {
    final box = await LocalStoreService.habitsBox();
    await box.put(
      LocalStoreService.guestCustomHabitsKey,
      state.map((habit) => {'id': habit.id, ...habit.toFirestore()}).toList(),
    );
  }

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
    String? cueAfter,
    required HabitFrequencyType frequencyType,
    required int frequencyTarget,
  }) {
    final rewards = _rewards(category);
    final template = IslamicHabitTemplate(
      id: const Uuid().v4(),
      name: name,
      description: cueAfter == null || cueAfter.trim().isEmpty
          ? ''
          : buildIntentionSentence(cueAfter, name),
      cueAfter: cueAfter?.trim().isEmpty == true ? null : cueAfter?.trim(),
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
    } else {
      _saveGuest().ignore();
    }
  }

  void update({
    required String id,
    required String name,
    required HabitCategory category,
    String? cueAfter,
    required HabitFrequencyType frequencyType,
    required int frequencyTarget,
  }) {
    final existing = state.firstWhere((h) => h.id == id);
    final rewards = _rewards(category);
    final cue = cueAfter?.trim().isEmpty == true ? null : cueAfter?.trim();
    final updated = IslamicHabitTemplate(
      id: id,
      name: name,
      description: cue == null ? '' : buildIntentionSentence(cue, name),
      cueAfter: cue,
      iconEmoji: existing.iconEmoji,
      category: category,
      frequencyType: frequencyType,
      frequencyTarget: frequencyTarget,
      hasTimer: existing.hasTimer,
      timerDurationSeconds: existing.timerDurationSeconds,
      xpReward: rewards.$1,
      goldReward: rewards.$2,
    );
    state = [
      for (final h in state) h.id == id ? updated : h,
    ];
    if (_uid != null) {
      _col.doc(id).set(updated.toFirestore()).ignore();
    } else {
      _saveGuest().ignore();
    }
  }

  void remove(String id) {
    state = state.where((h) => h.id != id).toList();
    if (_uid != null) {
      _col.doc(id).delete().ignore();
    } else {
      _saveGuest().ignore();
    }
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

/// Combined list: user-activated catalog habits + user custom habits
final habitListProvider = Provider<List<IslamicHabitTemplate>>((ref) {
  final activeIds = ref.watch(activeCatalogProvider);
  final custom = ref.watch(customHabitsProvider);
  final activeTemplates = IslamicHabitCatalog.templates
      .where((t) => activeIds.contains(t.id))
      .toList();
  return [...activeTemplates, ...custom];
});

/// Guests get a 3-habit trial before being asked to create an account.
const int kGuestHabitLimit = 3;

/// The habit cap for a given tier: guests trial 3, free accounts get
/// [kFreeHabitLimit], premium is uncapped (null). Pure so it's testable.
int? habitLimitFor({required bool isGuest, required bool isPremium}) {
  if (isPremium) return null;
  return isGuest ? kGuestHabitLimit : kFreeHabitLimit;
}

/// Whether [additionalCount] more habits fit within the account's tier.
/// This is the monetization seam: the free ceiling is where the Premium
/// invitation appears.
bool canAddHabits(WidgetRef ref, {int additionalCount = 1}) {
  final limit = habitLimitFor(
    isGuest: ref.read(guestModeProvider),
    isPremium: ref.read(premiumProvider),
  );
  if (limit == null) return true;
  final current = ref.read(habitListProvider).length;
  return current + additionalCount <= limit;
}

