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

  /// The extra shifts stacked on top of [reminderOffsetMinutes] — see
  /// IslamicHabitTemplate.extraReminderOffsets.
  ///
  /// An EMPTY list is a real override here, not "not overridden": clearing
  /// every extra reminder off a preset has to survive a reload, and null
  /// would hand the catalog's own default straight back. Only the field
  /// being absent means untouched.
  final List<int>? extraReminderOffsets;
  final bool? ignoreQuietHours;
  final String? iconColorHex;

  /// The daily step goal this person linked this preset to, or null for the
  /// ordinary case of a preset nobody linked.
  ///
  /// The one override field that is not a tweak to how the preset LOOKS or
  /// when it fires: it is the link itself (see IslamicHabitTemplate.stepGoal
  /// for why non-null IS the link). It lives here rather than on the catalog
  /// template because a link belongs to one person, not to the preset every
  /// account shares, and because the template's own suggestedStepGoal has to
  /// stay a suggestion.
  final int? stepGoal;

  const CatalogHabitOverride({
    this.name,
    this.cueAfter,
    this.frequencyType,
    this.frequencyTarget,
    this.scheduledWeekdays,
    this.reminderOffsetMinutes,
    this.extraReminderOffsets,
    this.ignoreQuietHours,
    this.iconColorHex,
    this.stepGoal,
  });

  bool get isEmpty =>
      name == null &&
      cueAfter == null &&
      frequencyType == null &&
      frequencyTarget == null &&
      scheduledWeekdays == null &&
      reminderOffsetMinutes == null &&
      extraReminderOffsets == null &&
      ignoreQuietHours == null &&
      iconColorHex == null &&
      stepGoal == null;

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
        extraReminderOffsets:
            extraReminderOffsets ?? t.extraReminderOffsets,
        ignoreQuietHours: ignoreQuietHours ?? t.ignoreQuietHours,
        createdAt: t.createdAt,
        archivedAt: t.archivedAt,
        stepGoal: stepGoal ?? t.stepGoal,
        // Carried, not overridable: the catalog's suggestion is what the Add
        // Habit picker opens on, and it has to survive an edit or reopening
        // a linked preset would offer the generic default instead of the
        // number this habit is actually about.
        suggestedStepGoal: t.suggestedStepGoal,
      );

  Map<String, dynamic> toMap() => {
        if (name != null) 'name': name,
        if (cueAfter != null) 'cueAfter': cueAfter,
        if (frequencyType != null) 'frequencyType': frequencyType!.toJson(),
        if (frequencyTarget != null) 'frequencyTarget': frequencyTarget,
        if (scheduledWeekdays != null) 'scheduledWeekdays': scheduledWeekdays,
        if (reminderOffsetMinutes != null)
          'reminderOffsetMinutes': reminderOffsetMinutes,
        // Written even when empty — see the field's doc: [] is "no extras",
        // which is a different answer from "never touched".
        if (extraReminderOffsets != null)
          'extraReminderOffsets': extraReminderOffsets,
        if (ignoreQuietHours != null) 'ignoreQuietHours': ignoreQuietHours,
        if (iconColorHex != null) 'iconColorHex': iconColorHex,
        if (stepGoal != null) 'stepGoal': stepGoal,
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
        extraReminderOffsets: (d['extraReminderOffsets'] as List?)
            ?.whereType<num>()
            .map((n) => n.toInt())
            .toSet()
            .toList()
          ?..sort(),
        ignoreQuietHours: d['ignoreQuietHours'] as bool?,
        iconColorHex: d['iconColorHex'] as String?,
        stepGoal: (d['stepGoal'] as num?)?.toInt(),
      );
}

const String kCatalogOverridesKey = LocalStoreService.catalogOverridesKey;

/// catalogId -> that person's changes to it. Empty for anyone who has never
/// edited a preset, which is the overwhelmingly common case, so this costs
/// nothing until it's used.
class CatalogOverridesNotifier
    extends StateNotifier<Map<String, CatalogHabitOverride>> {
  final String? _uid;

  /// True until the first load settles, exactly like CustomHabitsNotifier's.
  ///
  /// Without it, `const {}` — the state before anything has been read — is
  /// indistinguishable from "this person has never edited a preset", and a
  /// preset then resolves to its CATALOG default rather than the cadence the
  /// member actually set. That is not merely a display glitch: a room freezes
  /// its grading rule from the resolved habit exactly once and never revisits
  /// it, so a 4x/week preset caught mid-load is sealed as daily/1 and that
  /// member is mis-graded for the life of the room. Same failure that wiped a
  /// real member's rest days in production; this is the half the first fix
  /// missed, because habitsStillLoadingProvider never watched this notifier.
  bool get isLoading => _isLoading;
  bool _isLoading = true;

  CatalogOverridesNotifier(this._uid) : super(const {}) {
    _load();
  }

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  Future<void> _load() async {
    // Every assignment below sits after an `await`, and this notifier is
    // recreated whenever the signed-in uid changes (see catalogOverrides-
    // Provider). Sign in, sign out, or simply leaving the screen while the
    // Firestore/Hive read is still in flight disposes the old instance
    // mid-await — and StateNotifier throws "Tried to use ... after dispose
    // was called" on the assignment that lands afterwards. That throw was
    // escaping into Crashlytics on a plain guest launch, so guard every
    // assignment on `mounted`; a disposed loader has nobody left to inform.
    try {
      if (_uid != null) {
        final snap = await _userRef.get();
        final raw = snap.data()?[kCatalogOverridesKey];
        if (!mounted) return;
        _isLoading = false;
        state = _parse(raw);
        return;
      }
      final box = await LocalStoreService.settingsBox();
      if (!mounted) return;
      _isLoading = false;
      state = _parse(box.get(kCatalogOverridesKey));
    } catch (_) {
      // Offline or a malformed doc: presets simply behave as their catalog
      // defaults until the next successful load. Never a crash on boot.
      if (!mounted) return;
      // Cleared even on failure: a read that threw has settled as much as it
      // ever will, and leaving this true would block room grading forever
      // for anyone who booted offline once.
      _isLoading = false;
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
