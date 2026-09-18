import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/habit_mirror.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/services/user_doc.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../catalog/islamic_habit_catalog.dart';
import '../models/habit_cadence.dart';
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
  final bool? alarm;
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

  /// The schedules this person ran the preset on before its current one (see
  /// IslamicHabitTemplate.pastCadences). Empty when it has never changed.
  ///
  /// Not an override of anything the catalog ships: a preset has no history
  /// of its own, so this is always this person's. Which is also why it keeps
  /// the entry alive on its own. Editing a preset back to its catalog
  /// schedule empties every other field, and dropping the entry then would
  /// hand every day before that edit the catalog's schedule again.
  final List<PastCadence> pastCadences;

  const CatalogHabitOverride({
    this.name,
    this.cueAfter,
    this.frequencyType,
    this.frequencyTarget,
    this.scheduledWeekdays,
    this.reminderOffsetMinutes,
    this.extraReminderOffsets,
    this.ignoreQuietHours,
    this.alarm,
    this.iconColorHex,
    this.stepGoal,
    this.pastCadences = const [],
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
      alarm == null &&
      iconColorHex == null &&
      stepGoal == null &&
      pastCadences.isEmpty;

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
        alarm: alarm ?? t.alarm,
        createdAt: t.createdAt,
        archivedAt: t.archivedAt,
        stepGoal: stepGoal ?? t.stepGoal,
        // Carried, not overridable: the catalog's suggestion is what the Add
        // Habit picker opens on, and it has to survive an edit or reopening
        // a linked preset would offer the generic default instead of the
        // number this habit is actually about.
        suggestedStepGoal: t.suggestedStepGoal,
        pastCadences: pastCadences,
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
        if (alarm != null) 'alarm': alarm,
        if (iconColorHex != null) 'iconColorHex': iconColorHex,
        if (stepGoal != null) 'stepGoal': stepGoal,
        if (pastCadences.isNotEmpty)
          'scheduleHistory': pastCadencesToRaw(pastCadences),
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
        alarm: d['alarm'] as bool?,
        iconColorHex: d['iconColorHex'] as String?,
        stepGoal: (d['stepGoal'] as num?)?.toInt(),
        pastCadences: parsePastCadences(d['scheduleHistory']),
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

  /// Whether the load ended in the catch below rather than with a real
  /// answer. [_isLoading] cannot say this: it is cleared on failure too, on
  /// purpose (see the catch), so "settled" and "trustworthy" are different
  /// questions. Anything that writes what it read back to the device has to
  /// ask this one, or one offline boot gets saved as the truth.
  bool loadFailed = false;

  /// Whether [state] was filled from the device's copy before the read ran.
  /// Paint signal only; [isLoading] still says whether the server answered.
  bool hydratedFromMirror = false;

  CatalogOverridesNotifier(this._uid) : super(const {}) {
    if (_uid != null) {
      // Overrides are not decoration: habitListProvider layers them over the
      // const template, so a preset someone set to 4x a week resolves as its
      // catalog default without them. Hydrating them alongside the ids is
      // what stops the mirrored board being subtly the wrong board.
      final mirror = HabitMirror.snapshot;
      if (mirror != null && mirror.uid == _uid) {
        state = Map.of(_parse(mirror.catalogOverrides));
        hydratedFromMirror = true;
      }
    }
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
        // Shared with the three other notifiers that want a field from this
        // same document on the same launch — see [UserDoc].
        final data = await UserDoc.read(_uid);
        final raw = data?[kCatalogOverridesKey];
        if (!mounted) return;
        _isLoading = false;
        // Map.of, not the parsed map itself. An account with no overrides —
        // the common case this file's own doc comment names — parses to
        // `const {}`, which is IDENTICAL to the `const {}` this notifier was
        // constructed with, so StateNotifier's !identical check suppresses
        // the notification and nothing re-reads [isLoading]. The other two
        // notifiers behind habitsStillLoadingProvider already force a fresh
        // reference for exactly this reason; this one did not, and was saved
        // only by never being the last of the three to settle.
        state = Map.of(_parse(raw));
        return;
      }
      final box = await LocalStoreService.settingsBox();
      if (!mounted) return;
      _isLoading = false;
      state = Map.of(_parse(box.get(kCatalogOverridesKey)));
    } catch (_) {
      // Offline or a malformed doc: presets simply behave as their catalog
      // defaults until the next successful load. Never a crash on boot.
      if (!mounted) return;
      // Cleared even on failure: a read that threw has settled as much as it
      // ever will, and leaving this true would block room grading forever
      // for anyone who booted offline once. [loadFailed] is what carries the
      // difference to anyone who cares.
      _isLoading = false;
      loadFailed = true;
      // Map.of(state), NOT an empty map: state may have been hydrated from
      // the device's copy, and blanking it leaves every preset at its
      // catalog default cadence, name, colour and reminder mode while
      // habitsStillLoadingProvider already reads false — so the reminder
      // pass, the alarm reap and room grading all act on the wrong habits.
      // The two sibling notifiers already keep theirs on failure for this
      // reason. A fresh reference is still required rather than leaving it
      // untouched: this notifier can be the last of the three to settle, and
      // an identical map notifies nobody.
      state = Map.of(state);
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
        //
        // mergeFields, not merge: true. A merge-set merges a nested map leaf
        // by leaf, so a key this map no longer has was never removed on the
        // server: a preset edited back to its catalog schedule dropped its
        // frequency fields here and got them back on the next launch, still
        // on the schedule it had been moved off. Naming the one field
        // replaces that field whole and leaves every other field of the
        // user document alone, which is what this write always meant.
        await _userRef.set(
          {kCatalogOverridesKey: raw},
          SetOptions(mergeFields: [kCatalogOverridesKey]),
        );
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
