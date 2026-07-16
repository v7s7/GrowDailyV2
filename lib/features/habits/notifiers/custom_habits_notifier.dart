import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/game_constants.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/utils/intention_phrase.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../catalog/habit_plans.dart';
import '../catalog/islamic_habit_catalog.dart';
import '../models/habit_model.dart';
import 'habit_order_notifier.dart';

class CustomHabitsNotifier
    extends StateNotifier<List<IslamicHabitTemplate>> {
  final String? _uid;

  /// True until the very first Firestore/Hive read resolves - a plain
  /// instance field rather than folding it into [state] itself, since
  /// [state]'s type (a bare List) is read directly by a wide swath of the
  /// app (habitListProvider, Grid, AddHabitSheet, tests, ...) and wrapping
  /// it in a loading-aware class would mean updating every one of those
  /// call sites for a change that's really only about the first second of
  /// app launch. [habitsStillLoadingProvider] below is what screens should
  /// actually watch - it combines this with [ActiveCatalogNotifier.
  /// isLoading] into the one signal "is the habit list still settling"
  /// question actually needs.
  bool isLoading = true;

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
    isLoading = false;
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
    } catch (_) {
    } finally {
      // Guards a redundant second notification on the success path above
      // (which already reassigned `state` once) while still guaranteeing
      // one happens on the error path, where `state` never changed at all
      // - habitsStillLoadingProvider only re-reads this field when
      // [customHabitsProvider]'s own state changes, so a silent flip with
      // no accompanying change would leave a "still loading" screen
      // spinning forever after a failed read.
      if (mounted && isLoading) {
        isLoading = false;
        state = List.of(state);
      }
    }
  }

  /// Returns the created template so callers that add several habits back
  /// to back (the Quick Add tab) can track/undo each one by id without
  /// re-deriving it from name matching.
  IslamicHabitTemplate add({
    required String name,
    required HabitCategory category,
    String? cueAfter,
    required HabitFrequencyType frequencyType,
    required int frequencyTarget,
    List<int> scheduledWeekdays = const [],
    GoalType goalType = GoalType.build,
    ReductionType reductionType = ReductionType.avoid,
    int? limitAmount,
    LimitUnit? limitUnit,
    String? customUnitLabel,
    String? iconColorHex,
    int reminderLeadMinutes = 0,
  }) {
    final rewards = _rewards(category);
    final template = IslamicHabitTemplate(
      id: const Uuid().v4(),
      name: name,
      description: cueAfter == null || cueAfter.trim().isEmpty
          ? ''
          : buildIntentionSentence(cueAfter, name),
      cueAfter: cueAfter?.trim().isEmpty == true ? null : cueAfter?.trim(),
      category: category,
      frequencyType: frequencyType,
      frequencyTarget: frequencyTarget,
      scheduledWeekdays: scheduledWeekdays,
      goalType: goalType,
      reductionType: reductionType,
      limitAmount: limitAmount,
      limitUnit: limitUnit,
      customUnitLabel: limitUnit == LimitUnit.custom ? customUnitLabel : null,
      hasTimer: false,
      xpReward: rewards.$1,
      goldReward: rewards.$2,
      iconColorHex: iconColorHex,
      reminderLeadMinutes: reminderLeadMinutes,
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
    return template;
  }

  void update({
    required String id,
    required String name,
    required HabitCategory category,
    String? cueAfter,
    required HabitFrequencyType frequencyType,
    required int frequencyTarget,
    List<int>? scheduledWeekdays,
    GoalType? goalType,
    ReductionType? reductionType,
    int? limitAmount,
    LimitUnit? limitUnit,
    String? customUnitLabel,
    String? iconColorHex,
    int? reminderLeadMinutes,
    // Distinguishes "leave the current icon color alone" (the default —
    // every other caller that doesn't touch color just omits iconColorHex)
    // from "the user explicitly chose to go back to the default color" —
    // AddHabitSheet's "Use default color" action sets this instead of just
    // passing a null iconColorHex, which `iconColorHex ?? existing.
    // iconColorHex` below would otherwise silently ignore.
    bool clearIconColor = false,
  }) {
    final existing = state.firstWhere((h) => h.id == id);
    final rewards = _rewards(category);
    final cue = cueAfter?.trim().isEmpty == true ? null : cueAfter?.trim();
    final effectiveGoalType = goalType ?? existing.goalType;
    final effectiveReductionType = reductionType ?? existing.reductionType;
    final effectiveLimitAmount = effectiveGoalType == GoalType.quit &&
            effectiveReductionType == ReductionType.limit
        ? limitAmount ?? existing.limitAmount
        : null;
    final effectiveLimitUnit = effectiveGoalType == GoalType.quit &&
            effectiveReductionType == ReductionType.limit
        ? limitUnit ?? existing.limitUnit
        : null;
    final effectiveCustomUnitLabel = effectiveLimitUnit == LimitUnit.custom
        ? customUnitLabel ?? existing.customUnitLabel
        : null;
    final effectiveIconColorHex =
        clearIconColor ? null : (iconColorHex ?? existing.iconColorHex);
    final updated = IslamicHabitTemplate(
      id: id,
      name: name,
      description: cue == null ? '' : buildIntentionSentence(cue, name),
      cueAfter: cue,
      category: category,
      frequencyType: frequencyType,
      frequencyTarget: frequencyTarget,
      goalType: effectiveGoalType,
      reductionType: effectiveReductionType,
      limitAmount: effectiveLimitAmount,
      limitUnit: effectiveLimitUnit,
      customUnitLabel: effectiveCustomUnitLabel,
      hasTimer: existing.hasTimer,
      timerDurationSeconds: existing.timerDurationSeconds,
      xpReward: rewards.$1,
      goldReward: rewards.$2,
      iconColorHex: effectiveIconColorHex,
      reminderLeadMinutes: reminderLeadMinutes ?? existing.reminderLeadMinutes,
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

  /// Default reward for a custom habit in category [c] — sourced from
  /// [GameConstants] so this isn't a second, driftable copy of the same
  /// numbers.
  static (int, int) _rewards(HabitCategory c) => (
        GameConstants.categoryXpRewards[c.name] ?? 10,
        GameConstants.categoryGoldRewards[c.name] ?? 5,
      );
}

final customHabitsProvider =
    StateNotifierProvider<CustomHabitsNotifier, List<IslamicHabitTemplate>>(
        (ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return CustomHabitsNotifier(uid);
});

/// Combined list: user-activated catalog habits + user custom habits, sorted
/// by the user's manual drag order where one exists.
///
/// A habit with no entry in [habitOrderProvider] (never dragged) keeps its
/// original catalog-then-custom position — that position is used as its own
/// fallback rank, so freshly added habits land after existing ones instead
/// of jumping to the front, and dragged/undragged habits sort correctly
/// against each other.
final habitListProvider = Provider<List<IslamicHabitTemplate>>((ref) {
  final activeIds = ref.watch(activeCatalogProvider);
  final custom = ref.watch(customHabitsProvider);
  final activeTemplates = IslamicHabitCatalog.templates
      .where((t) => activeIds.contains(t.id))
      .toList();
  final combined = [...activeTemplates, ...custom];

  final order = ref.watch(habitOrderProvider);
  final ranked = combined.asMap().entries.toList()
    ..sort((a, b) {
      final rankA = order[a.value.id] ?? a.key.toDouble();
      final rankB = order[b.value.id] ?? b.key.toDouble();
      return rankA.compareTo(rankB);
    });
  return [for (final entry in ranked) entry.value];
});

/// Whether [habitListProvider]'s two sources (custom habits + the active
/// catalog set) are still on their very first Firestore/Hive read. False
/// for the rest of the app's lifetime after that - this is purely a cold-
/// start signal, never true again once both have loaded once.
///
/// Screens that show an empty-state prompt ("no habits yet, add one!")
/// when the list is empty should check this *first* and show a neutral
/// loading spinner instead while it's still true - without it, a returning
/// user with a real habit list sees a flash of "you have nothing" for
/// however long the read takes, right before their actual habits appear
/// and silently replace it. See DashboardScreen/GridScreen's own body
/// gates for the two places that actually matter.
///
/// Watches both providers' plain state (to know *when* to re-check - a
/// StateNotifier's own instance fields aren't reactive on their own) and
/// then reads [CustomHabitsNotifier.isLoading]/[ActiveCatalogNotifier.
/// isLoading] off each notifier instance directly, since neither's `state`
/// type can safely carry a loading flag of its own without changing what
/// every existing reader of [customHabitsProvider]/[activeCatalogProvider]
/// gets back.
final habitsStillLoadingProvider = Provider<bool>((ref) {
  ref.watch(customHabitsProvider);
  ref.watch(activeCatalogProvider);
  return ref.watch(customHabitsProvider.notifier).isLoading ||
      ref.watch(activeCatalogProvider.notifier).isLoading;
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

