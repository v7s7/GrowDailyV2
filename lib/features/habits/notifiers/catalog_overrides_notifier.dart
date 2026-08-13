import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../catalog/islamic_habit_catalog.dart';
import '../models/habit_model.dart';

/// One person's changes to one preset habit.
///
/// Preset (catalog) habits used to be completely uneditable. Activate صلاة
/// الضحى from a Plan and you could never change its reminder, its frequency,
/// or the days it runs on — the only way to adjust anything was to delete it
/// and build a custom copy, which loses that habit's whole history and
/// unlinks it from every room it counted toward. Since Plans is the main
/// onboarding path, that applied to most habits most people had.
///
/// The fix stores only what someone actually changed, keyed by catalog id,
/// and merges it over the const template in [habitListProvider]. The habit's
/// **id never changes**, which is the whole point: its Grid squares, streak,
/// completion counts and room links all key off that id and survive untouched.
///
/// Every field is nullable and means "not overridden" when null, so a stored
/// override stays small and a catalog template that later gains a better
/// default still supplies it for anything the user never touched.
class CatalogHabitOverride {
  final String? name;
  final String? cueAfter;
  final HabitFrequencyType? frequencyType;
  final int? frequencyTarget;
  final List<int>? scheduledWeekdays;
  final int? reminderOffsetMinutes;
  final bool? ignoreQuietHours;
  final String? iconColorHex;

  const CatalogHabitOverride({
    this.name,
    this.cueAfter,
    this.frequencyType,
    this.frequencyTarget,
    this.scheduledWeekdays,
    this.reminderOffsetMinutes,
    this.ignoreQuietHours,
    this.iconColorHex,
  });

  bool get isEmpty =>
      name == null &&
      cueAfter == null &&
      frequencyType == null &&
      frequencyTarget == null &&
      scheduledWeekdays == null &&
      reminderOffsetMinutes == null &&
      ignoreQuietHours == null &&
      iconColorHex == null;

  /// Lays this override over [t]. Anything null here keeps the catalog's own
  /// value.
  ///
  /// A renamed habit deliberately takes the new name in BOTH languages: the
  /// catalog ships an Arabic and an English name, but someone who renamed it
  /// typed one string and means it, and quietly showing the old preset name
  /// back to them after a language switch would read as the rename not having
  /// saved.
  IslamicHabitTemplate applyTo(IslamicHabitTemplate t) => IslamicHabitTemplate(
        id: t.id,
        name: name ?? t.name,
        description: t.description,
        nameAr: name ?? t.nameAr,
        descriptionAr: t.descriptionAr,
        cueAfter: cueAfter ?? t.cueAfter,
        category: t.category,
        frequencyType: frequencyType ?? t.frequencyType,
        frequencyTarget: frequencyTarget ?? t.frequencyTarget,
        scheduledWeekdays: scheduledWeekdays ?? t.scheduledWeekdays,
        goalType: t.goalType,
        reductionType: t.reductionType,
        limitAmount: t.limitAmount,
        limitUnit: t.limitUnit,
        customUnitLabel: t.customUnitLabel,
        hasTimer: t.hasTimer,
        timerDurationSeconds: t.timerDurationSeconds,
        xpReward: t.xpReward,
        goldReward: t.goldReward,
        iconColorHex: iconColorHex ?? t.iconColorHex,
        reminderOffsetMinutes:
            reminderOffsetMinutes ?? t.reminderOffsetMinutes,
        ignoreQuietHours: ignoreQuietHours ?? t.ignoreQuietHours,
        createdAt: t.createdAt,
        archivedAt: t.archivedAt,
      );

  Map<String, dynamic> toMap() => {
        if (name != null) 'name': name,
        if (cueAfter != null) 'cueAfter': cueAfter,
        if (frequencyType != null) 'frequencyType': frequencyType!.toJson(),
        if (frequencyTarget != null) 'frequencyTarget': frequencyTarget,
        if (scheduledWeekdays != null) 'scheduledWeekdays': scheduledWeekdays,
        if (reminderOffsetMinutes != null)
          'reminderOffsetMinutes': reminderOffsetMinutes,
        if (ignoreQuietHours != null) 'ignoreQuietHours': ignoreQuietHours,
        if (iconColorHex != null) 'iconColorHex': iconColorHex,
      };

  factory CatalogHabitOverride.fromMap(Map<String, dynamic> d) =>
      CatalogHabitOverride(
        name: d['name'] as String?,
        cueAfter: d['cueAfter'] as String?,
        frequencyType: d['frequencyType'] == null
            ? null
            : HabitFrequencyType.fromJson(d['frequencyType'] as String),
        frequencyTarget: (d['frequencyTarget'] as num?)?.toInt(),
        scheduledWeekdays: (d['scheduledWeekdays'] as List?)
            ?.whereType<num>()
            .map((n) => n.toInt())
            .where((n) => n >= DateTime.monday && n <= DateTime.sunday)
            .toList(),
        reminderOffsetMinutes: (d['reminderOffsetMinutes'] as num?)?.toInt(),
        ignoreQuietHours: d['ignoreQuietHours'] as bool?,
        iconColorHex: d['iconColorHex'] as String?,
      );
}

const String kCatalogOverridesKey = 'catalog_habit_overrides_v1';

/// catalogId -> that person's changes to it. Empty for anyone who has never
/// edited a preset, which is the overwhelmingly common case, so this costs
/// nothing until it's used.
class CatalogOverridesNotifier
    extends StateNotifier<Map<String, CatalogHabitOverride>> {
  final String? _uid;
  CatalogOverridesNotifier(this._uid) : super(const {}) {
    _load();
  }

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  Future<void> _load() async {
    try {
      if (_uid != null) {
        final snap = await _userRef.get();
        final raw = snap.data()?[kCatalogOverridesKey];
        state = _parse(raw);
        return;
      }
      final box = await LocalStoreService.settingsBox();
      state = _parse(box.get(kCatalogOverridesKey));
    } catch (_) {
      // Offline or a malformed doc: presets simply behave as their catalog
      // defaults until the next successful load. Never a crash on boot.
      state = const {};
    }
  }

  Map<String, CatalogHabitOverride> _parse(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, CatalogHabitOverride>{};
    raw.forEach((key, value) {
      if (value is Map) {
        out[key.toString()] =
            CatalogHabitOverride.fromMap(Map<String, dynamic>.from(value));
      }
    });
    return out;
  }

  /// Records [override] for [id]. An override with nothing set in it removes
  /// the entry outright rather than storing an empty map, so "edited back to
  /// the defaults" leaves no trace and the habit tracks the catalog again.
  Future<void> setOverride(String id, CatalogHabitOverride override) async {
    final next = {...state};
    if (override.isEmpty) {
      next.remove(id);
    } else {
      next[id] = override;
    }
    state = next;
    await _persist();
  }

  /// Drops every change for [id] — "reset to the preset".
  Future<void> clearOverride(String id) async {
    if (!state.containsKey(id)) return;
    final next = {...state}..remove(id);
    state = next;
    await _persist();
  }

  Future<void> _persist() async {
    final raw = {
      for (final e in state.entries) e.key: e.value.toMap(),
    };
    try {
      if (_uid != null) {
        // Whole map as one nested field, never dotted 'field.key' paths —
        // see BUILD_LESSONS.md #10.
        await _userRef.set({kCatalogOverridesKey: raw}, SetOptions(merge: true));
        return;
      }
      final box = await LocalStoreService.settingsBox();
      await box.put(kCatalogOverridesKey, raw);
    } catch (_) {
      // Same posture as every other write in this app: the in-memory state
      // above already changed, so the edit is live either way, and the next
      // successful save carries it.
    }
  }
}

final catalogOverridesProvider = StateNotifierProvider<CatalogOverridesNotifier,
    Map<String, CatalogHabitOverride>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return CatalogOverridesNotifier(uid);
});
