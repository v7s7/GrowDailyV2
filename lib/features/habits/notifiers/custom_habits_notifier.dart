import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/game_constants.dart';
import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/utils/intention_phrase.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../catalog/habit_plans.dart';
import '../catalog/islamic_habit_catalog.dart';
import '../models/habit_cue.dart';
import '../models/habit_model.dart';
import 'catalog_overrides_notifier.dart';
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

  /// Archived custom habits — everything [archive] has ever removed from
  /// [state]. Plain field, same isLoading/activatedAt pattern used
  /// throughout this file: it only ever changes alongside a [state]
  /// change (see [archive]), which is what actually notifies watchers, so
  /// reading it straight off the notifier instance right after a rebuild
  /// always sees the current value. This is what allHabitsEverProvider
  /// reads to keep an archived habit's history alive in the Heatmap and
  /// Insights after it's gone from every "active" list.
  List<IslamicHabitTemplate> archived = [];

  CustomHabitsNotifier(this._uid) : super([]) {
    if (_uid != null) {
      _load().then((_) => _migrateLegacyPrayerOffset());
    } else {
      _loadGuest().then((_) => _migrateLegacyPrayerOffset());
    }
  }

  /// Hive key for the notification-settings blob — the same one
  /// NotificationSettingsNotifier owns. Read directly here (rather than
  /// through its provider) purely so this migration can't depend on which
  /// notifier happens to finish loading first.
  static const _kNotificationSettingsKey = 'notification_settings_v1';

  /// One-shot fold of the retired global "minutes after prayer" setting
  /// into each prayer-linked habit's own [IslamicHabitTemplate.
  /// reminderOffsetMinutes].
  ///
  /// That global knob used to be *added* to every prayer reminder while the
  /// per-habit value was *subtracted* from it, so "15 min before Fajr" with
  /// the default +10 global actually fired 5 minutes before — and the Add
  /// Habit preview showed the wrong time, since it never accounted for the
  /// global. Now that the per-habit offset is signed and is the single
  /// source of truth (see that field's doc comment), the global is gone.
  /// Folding its old value in here is what makes that removal invisible:
  /// everyone's existing prayer reminders keep firing at the exact same
  /// moment they always did.
  ///
  /// Runs at most once per device — the settings blob gets a
  /// `prayerOffsetMigrated` marker, and the legacy key is dropped so a
  /// later build can never double-apply it. Deliberately silent and
  /// best-effort: a failure here just leaves the old value in place to be
  /// retried next launch, never blocks the habit list from loading.
  Future<void> _migrateLegacyPrayerOffset() async {
    try {
      final settings =
          await LocalStoreService.getSettingsMap(_kNotificationSettingsKey);
      if (settings.isEmpty) return;
      if (settings['prayerOffsetMigrated'] == true) return;

      final legacy = (settings['prayerOffsetMinutes'] as num?)?.toInt();
      // Nothing saved, or saved as a no-op — either way there's nothing to
      // fold in, so just mark it done and stop re-checking every launch.
      if (legacy != null && legacy != 0 && mounted) {
        final touched = <IslamicHabitTemplate>[];
        final migrated = [
          for (final habit in state)
            if (HabitCue.fromStoredValue(habit.cueAfter).isPrayer)
              (() {
                final next = habit
                    .withReminderOffset(habit.reminderOffsetMinutes + legacy);
                touched.add(next);
                return next;
              })()
            else
              habit,
        ];
        if (touched.isNotEmpty) {
          state = migrated;
          if (_uid != null) {
            for (final habit in touched) {
              _col.doc(habit.id).set(habit.toFirestore()).ignore();
            }
          } else {
            await _saveGuest();
          }
        }
      }

      await LocalStoreService.putSettingsMap(_kNotificationSettingsKey, {
        ...settings,
        'prayerOffsetMigrated': true,
      }..remove('prayerOffsetMinutes'));
    } catch (_) {
      // Retried on the next launch — see doc comment.
    }
  }

  /// Every fully-closed stint of a CUSTOM habit, oldest first: habitId ->
  /// [(start, end)].
  ///
  /// The mirror of ActiveCatalogNotifier.catalogStintHistory, and it exists for
  /// the same reason. A custom habit carries exactly ONE window on its document
  /// (createdAt, archivedAt), so [unarchive] used to clear archivedAt and keep
  /// the original createdAt — which reads, forever after, as "this habit was
  /// active the whole time", pause included. Rooms grades days against that,
  /// so resuming a habit silently converted a week that had been correctly
  /// excused into a week of misses.
  ///
  /// Kept beside the habits rather than as a field on the template on purpose:
  /// IslamicHabitTemplate has three hand-written copy helpers that each
  /// enumerate every field, and a new one dropped by any of them would fail
  /// silently and only show up as wrong history months later.
  Map<String, List<(DateTime, DateTime)>> customStintHistory = {};

  static Map<String, List<(DateTime, DateTime)>> _parseStintHistory(
      dynamic raw) {
    final result = <String, List<(DateTime, DateTime)>>{};
    if (raw is! Map) return result;
    for (final entry in raw.entries) {
      final rawStints = entry.value;
      if (rawStints is! List) continue;
      final stints = <(DateTime, DateTime)>[];
      for (final item in rawStints) {
        if (item is! Map) continue;
        final start = DateTime.tryParse('${item['start']}');
        final end = DateTime.tryParse('${item['end']}');
        if (start != null && end != null) stints.add((start, end));
      }
      if (stints.isNotEmpty) result[entry.key.toString()] = stints;
    }
    return result;
  }

  static Map<String, List<Map<String, String>>> _stintHistoryToRaw(
          Map<String, List<(DateTime, DateTime)>> history) =>
      {
        for (final e in history.entries)
          e.key: [
            for (final stint in e.value)
              {
                'start': stint.$1.toIso8601String(),
                'end': stint.$2.toIso8601String(),
              },
          ],
      };

  /// Records the window [habit] just finished, so resuming it cannot pretend
  /// the pause never happened. Same-day pause-and-resume records nothing, for
  /// the reason ActiveCatalogNotifier.toggle spells out: two windows both
  /// claiming today would double-count it everywhere that walks stints.
  void _closeStint(IslamicHabitTemplate habit, DateTime resumedOn) {
    final start = habit.createdAt;
    final end = habit.archivedAt;
    if (start == null || end == null) return;
    if (end.isSameDayAs(resumedOn)) return;
    customStintHistory = {
      ...customStintHistory,
      habit.id: [...(customStintHistory[habit.id] ?? const []), (start, end)],
    };
  }

  Future<void> _saveStintHistory() async {
    final raw = _stintHistoryToRaw(customStintHistory);
    if (_uid != null) {
      FirebaseFirestore.instance.collection('users').doc(_uid).set(
        {'customHabitStintHistory': raw},
        SetOptions(merge: true),
      ).ignore();
      return;
    }
    final box = await LocalStoreService.habitsBox();
    await box.put(LocalStoreService.guestCustomStintHistoryKey, raw);
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
    final rawArchived = LocalStoreService.asMapList(
      box.get(LocalStoreService.guestArchivedCustomHabitsKey),
    );
    customStintHistory =
        _parseStintHistory(box.get(LocalStoreService.guestCustomStintHistoryKey));
    if (!mounted) return;
    state = raw
        .map((item) => IslamicHabitTemplate.fromMap(
              item['id'] as String? ?? const Uuid().v4(),
              item,
            ))
        .toList();
    archived = rawArchived
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

  Future<void> _saveGuestArchived() async {
    final box = await LocalStoreService.habitsBox();
    await box.put(
      LocalStoreService.guestArchivedCustomHabitsKey,
      archived.map((habit) => {'id': habit.id, ...habit.toFirestore()}).toList(),
    );
  }

  Future<void> _load() async {
    if (_uid == null) return;
    try {
      final snap = await _col.get();
      // Read from the user doc, not the habit docs: the stints live beside the
      // habits (see customStintHistory) so no per-habit copy helper can lose
      // them. A failure here leaves the map empty, which degrades to exactly
      // the old single-window behaviour rather than to wrong history.
      try {
        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .get();
        customStintHistory =
            _parseStintHistory(userSnap.data()?['customHabitStintHistory']);
      } catch (_) {}
      if (mounted) {
        // Same collection for both — an archived habit's doc survives
        // with archivedAt stamped on it (see [archive]) rather than being
        // deleted, so one read splits cleanly into the two lists.
        final all =
            snap.docs.map((d) => IslamicHabitTemplate.fromFirestore(d));
        state = all.where((h) => h.archivedAt == null).toList();
        archived = all.where((h) => h.archivedAt != null).toList();
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
    int reminderOffsetMinutes = 0,
    bool ignoreQuietHours = false,
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
      reminderOffsetMinutes: reminderOffsetMinutes,
      ignoreQuietHours: ignoreQuietHours,
      // Birth date — what stops every history surface from painting the
      // days before this habit existed as misses. effectiveDay so a habit
      // created at 1 AM belongs to the app-day actually in progress.
      createdAt: DateTime.now().effectiveDay,
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
    int? reminderOffsetMinutes,
    bool? ignoreQuietHours,
    // Distinguishes "leave the current icon color alone" (the default —
    // every other caller that doesn't touch color just omits iconColorHex)
    // from "the user explicitly chose to go back to the default color" —
    // AddHabitSheet's "Use default color" action sets this instead of just
    // passing a null iconColorHex, which `iconColorHex ?? existing.
    // iconColorHex` below would otherwise silently ignore.
    bool clearIconColor = false,
  }) {
    // No orElse on firstWhere would throw a bare StateError for any id that
    // isn't an ACTIVE custom habit — a catalog id, or one already archived.
    // Today's only caller (AddHabitSheet's edit mode) is gated so that can't
    // happen, but the failure mode was a crash rather than a no-op, and the
    // gate lives in a different file from the throw. Bail quietly instead:
    // there is no habit here to update.
    final matches = state.where((h) => h.id == id);
    if (matches.isEmpty) return;
    final existing = matches.first;
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
      // Was missing entirely from this constructor call, which meant every
      // save of an existing habit silently fell back to
      // IslamicHabitTemplate's `const []` default no matter what the caller
      // passed — wiping a "specific days" schedule (e.g. Mon/Thu) back to
      // flexible/no-days on every single edit. add() above never had this
      // bug (it does pass scheduledWeekdays through); only editing an
      // already-created habit hit it.
      scheduledWeekdays: scheduledWeekdays ?? existing.scheduledWeekdays,
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
      reminderOffsetMinutes:
          reminderOffsetMinutes ?? existing.reminderOffsetMinutes,
      ignoreQuietHours: ignoreQuietHours ?? existing.ignoreQuietHours,
      // Editing a habit never changes when it was born.
      createdAt: existing.createdAt,
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

  /// Archives a custom habit instead of hard-deleting it: it leaves
  /// [state] immediately, exactly like the old delete did, so today's
  /// Grid, the Add sheet, and today's streak requirement all stop seeing
  /// it right away. What's different is the Firestore doc/guest record
  /// itself survives with archivedAt stamped on it instead of being
  /// erased, which is what lets allHabitsEverProvider (below) keep this
  /// habit's real name and schedule available for every day up to and
  /// including today — so the Heatmap and Insights don't silently rewrite
  /// history the moment it's removed. See IslamicHabitTemplate.archivedAt.
  ///
  /// [everCompleted] — whether this habit has ever been marked done, on
  /// any day, ever (the caller passes
  /// `dashboardProvider.habitTotalCompletions[id] > 0`; this notifier holds
  /// no Ref of its own to check that itself). True by default so every
  /// pre-existing call site that doesn't pass it keeps behaving exactly as
  /// before.
  ///
  /// When it's false, this hard-deletes instead of archiving — no real day
  /// was ever credited, so there is nothing for the soft-archive below to
  /// actually preserve, no matter how long the habit sat there untouched.
  /// A genuine `.delete()` leaves zero trace anywhere (Grid, Heatmap,
  /// Insights, room links) instead of a ghost row that lingers for the
  /// rest of today before aging out — which is exactly the "why won't
  /// this actually delete" confusion a never-touched habit produced under
  /// an earlier version of this rule that only hard-deleted a same-day
  /// add. Age was never really the thing that mattered here; whether
  /// anything was ever actually done is. The instant a habit earns even
  /// one real completion, that day's XP/gold/streak effects already
  /// happened elsewhere this method has no way to claw back, so from that
  /// point on it always falls through to the normal archive below,
  /// permanently, regardless of how long ago that one completion was.
  ///
  /// [eraseIfEmpty] — whether the hard-delete above is allowed at all.
  /// True for the multi-select REMOVE path, whose whole promise is that
  /// the habit goes away. False for PAUSE, whose promise is the opposite:
  /// its own sheet says the record is kept and the habit comes back
  /// whenever you want. Pausing a habit you had not completed yet used to
  /// destroy it on the spot — the one case where the button did the exact
  /// opposite of what the text under it said, and silently, since there
  /// was no history to notice missing afterwards. Pause always preserves
  /// now; Delete forever is the deliberate way to actually erase.
  void archive(
    String id, {
    bool everCompleted = true,
    bool eraseIfEmpty = true,
  }) {
    final existing = state.where((h) => h.id == id).toList();
    if (existing.isEmpty) return;
    final habit = existing.first;

    if (!everCompleted && eraseIfEmpty) {
      state = state.where((h) => h.id != id).toList();
      if (_uid != null) {
        _col.doc(id).delete().ignore();
      } else {
        _saveGuest().ignore();
      }
      return;
    }

    final archivedTemplate = habit.withDates(
      createdAt: habit.createdAt,
      archivedAt: DateTime.now().effectiveDay,
    );
    state = state.where((h) => h.id != id).toList();
    archived = [...archived, archivedTemplate];
    if (_uid != null) {
      _col
          .doc(id)
          .set(archivedTemplate.toFirestore(), SetOptions(merge: true))
          .ignore();
    } else {
      _saveGuest().ignore();
      _saveGuestArchived().ignore();
    }
  }

  /// Hard-deletes a custom habit and forgets it existed — the deliberate
  /// opposite of [archive], and the reason pausing can now be the safe
  /// default everywhere else.
  ///
  /// Removes the doc whether or not the habit was ever completed, and
  /// whether it is currently active or already paused, so nothing keeps
  /// its name alive: it stops appearing in allHabitsEverProvider, which
  /// is what makes it vanish from the Heatmap, Insights and Year Record
  /// too. The daily documents keep their raw per-day numbers (rewriting
  /// months of history is not something a delete should attempt), but with
  /// no template carrying this id, nothing renders them — the habit is
  /// gone everywhere a person can look.
  ///
  /// Only ever reachable behind an explicit "this cannot be undone"
  /// confirmation; every non-confirmed removal path calls [archive].
  void deleteForever(String id) {
    final wasActive = state.any((h) => h.id == id);
    final wasArchived = archived.any((h) => h.id == id);
    if (!wasActive && !wasArchived) return;
    state = state.where((h) => h.id != id).toList();
    archived = archived.where((h) => h.id != id).toList();
    if (_uid != null) {
      _col.doc(id).delete().ignore();
    } else {
      _saveGuest().ignore();
      _saveGuestArchived().ignore();
    }
  }

  /// Puts an archived habit back on the list — the exact reverse of
  /// [archive], and the thing that finally makes "Removed from your list"
  /// an honest sentence.
  ///
  /// There was no way back before this. [archive] moved a custom habit into
  /// [archived] so the Heatmap and Insights kept its history, and nothing
  /// anywhere could ever move it out again: no unarchive, no list of
  /// archived habits, no undo on the snackbar. A preset could at least be
  /// switched on again from Plans, but a habit someone had built themselves
  /// - their own name, cue, frequency, colour and reminder - was gone the
  /// moment they tapped delete, with the confirmation reassuring them their
  /// *stats* were safe and saying nothing about the habit.
  ///
  /// Restores the same id, so everything keyed to it - Grid squares, streak,
  /// completion counts, room links - simply reattaches. A no-op for an id
  /// that isn't archived (already restored, or hard-deleted because it had
  /// never been completed), which is what makes it safe to call from an Undo
  /// button that may be tapped twice.
  void unarchive(String id) {
    final match = archived.where((h) => h.id == id).toList();
    if (match.isEmpty) return;
    // The finished window is RECORDED, and the new one starts today.
    //
    // This used to keep the original createdAt and simply clear archivedAt,
    // which made the habit claim it had been active the whole time — the pause
    // included. Every surface that asks "was this habit yours on day X" then
    // answered yes for days the person had deliberately stood it down, so a
    // room re-graded a correctly-excused week as a week of misses the moment
    // they resumed, which is the opposite of what pausing promises.
    //
    // The old window is not lost by moving createdAt: it goes into
    // customStintHistory, and allHabitsEverProvider re-emits it as its own
    // synthetic template, exactly as it already does for a catalog habit
    // toggled off and back on. That is what keeps the Heatmap and Insights
    // crediting the pre-pause days.
    final resumedOn = DateTime.now().effectiveDay;
    final previous = match.first;
    _closeStint(previous, resumedOn);
    final restored = previous.withDates(
      // Same-day pause-and-resume is one uninterrupted window, never two:
      // _closeStint records nothing for it, so the original start has to
      // survive here or the day would lose its own history.
      createdAt: (previous.archivedAt?.isSameDayAs(resumedOn) ?? false)
          ? previous.createdAt
          : resumedOn,
      archivedAt: null,
    );
    archived = archived.where((h) => h.id != id).toList();
    state = [...state, restored];
    _saveStintHistory().ignore();
    if (_uid != null) {
      _col.doc(id).set(restored.toFirestore()).ignore();
    } else {
      _saveGuest().ignore();
      _saveGuestArchived().ignore();
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
  // Stamp each active catalog template with its activation day — the
  // habit's birth date, which isScheduledFor uses to stop pre-activation
  // days reading as misses. Read off the notifier (same isLoading
  // pattern): the map only ever changes alongside a state change, which
  // the watch above already reacts to.
  final activatedAt = ref.watch(activeCatalogProvider.notifier).activatedAt;
  // Whatever this person has changed about a preset (see
  // CatalogHabitOverride) - reminder cue, frequency, weekdays, colour, name.
  // Layered over the const template here, which is the ONE place presets
  // become "theirs": the id is untouched, so Grid history, streaks,
  // completion counts and room links all keep pointing at the same habit.
  final overrides = ref.watch(catalogOverridesProvider);
  final activeTemplates = IslamicHabitCatalog.templates
      .where((t) => activeIds.contains(t.id))
      .map((t) {
    final override = overrides[t.id];
    final applied = override == null ? t : override.applyTo(t);
    final born = activatedAt[t.id];
    return born == null ? applied : applied.withCreatedAt(born);
  }).toList();
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

/// Every habit this account has EVER had active, including ones since
/// archived — unlike [habitListProvider], which only ever shows what's
/// active *right now*. Order is unspecified (unlike habitListProvider,
/// nothing here needs the user's manual drag order) and archived entries
/// are included alongside active ones with no special marker; callers
/// that need to tell them apart can check [IslamicHabitTemplate.
/// archivedAt] directly, or just rely on [IslamicHabitTemplate.
/// isScheduledFor] to naturally exclude an archived habit from any day
/// after it was archived.
///
/// This is what history surfaces that look backward across many days (the
/// Heatmap, Insights) should read instead of [habitListProvider] —
/// reading the active-only list there would silently drop an archived
/// habit's entire past from their math the instant it's archived, even
/// for days from months ago when it was real and being tracked every day.
/// See [CustomHabitsNotifier.archive] and [ActiveCatalogNotifier.toggle]
/// for where archiving actually happens.
///
/// A catalog habit toggled on/off more than once emits one synthetic
/// template *per stint* here (see [ActiveCatalogNotifier.
/// catalogStintHistory]), all sharing the same id — that's deliberate,
/// not a bug: every consumer of this list (Heatmap, Insights, the weekly
/// recap card) already gates day-by-day via [IslamicHabitTemplate.
/// isScheduledFor], and real stints never overlap in time, so at most one
/// of the duplicates ever claims any given day. No consumer needed to
/// change to support this.
final allHabitsEverProvider = Provider<List<IslamicHabitTemplate>>((ref) {
  final activeIds = ref.watch(activeCatalogProvider);
  final catalogNotifier = ref.watch(activeCatalogProvider.notifier);
  final activatedAt = catalogNotifier.activatedAt;
  final catalogArchivedAt = catalogNotifier.catalogArchivedAt;
  final stintHistory = catalogNotifier.catalogStintHistory;
  final everActivatedIds = {
    ...activeIds,
    ...activatedAt.keys,
    ...catalogArchivedAt.keys,
    ...stintHistory.keys,
  };
  final catalogEver = <IslamicHabitTemplate>[
    for (final t in IslamicHabitCatalog.templates)
      if (everActivatedIds.contains(t.id)) ...[
        // The current-or-most-recent window — but only when there
        // actually is a real open end to it, i.e. it's genuinely active
        // right now (activeIds.contains), or it has a real
        // catalogArchivedAt closing it. Passing archivedAt: null through
        // for a habit that ISN'T currently active hands isScheduledFor a
        // template with no upper bound at all, which reads as "existed
        // every day, forever" — corrupting the Heatmap/Insights with a
        // phantom missed-habit painted across every day since
        // activatedAt, including today. Two different ways this can
        // happen, both covered by the same check:
        //  - Reactivate an old habit today, then hard-delete it the same
        //    day with zero lifetime completions (see ActiveCatalogNotifier.
        //    toggle's grace-period branch) clears activatedAt and leaves
        //    catalogArchivedAt already-null from that same reactivation —
        //    both dates absent, not active either.
        //  - A habit deactivated before catalogArchivedAt tracking
        //    existed: activatedAt is a real date, catalogArchivedAt was
        //    simply never stamped (the field didn't exist yet), and it's
        //    long since inactive — activatedAt present, catalogArchivedAt
        //    absent, not active.
        // Skipping either case costs nothing real: there's no current
        // stint to describe, and the loop below already re-adds every
        // genuine closed stint from stintHistory on its own.
        if (activeIds.contains(t.id) || catalogArchivedAt[t.id] != null)
          t.withDates(
            createdAt: activatedAt[t.id],
            archivedAt: catalogArchivedAt[t.id],
          ),
        // Every earlier, fully-closed stint — see catalogStintHistory's
        // doc comment for why a repeatedly toggled habit needs more than
        // just the one window above to keep its whole history alive.
        for (final stint in stintHistory[t.id] ?? const [])
          t.withDates(createdAt: stint.$1, archivedAt: stint.$2),
      ],
  ];

  final customActive = ref.watch(customHabitsProvider);
  final customNotifier = ref.watch(customHabitsProvider.notifier);
  final customArchived = customNotifier.archived;
  // Every earlier, fully-closed stint of a CUSTOM habit, for the same reason
  // the catalog loop above re-emits its own: resuming a paused habit moves its
  // createdAt to the resume day (see CustomHabitsNotifier.unarchive), so
  // without this the days before the pause would drop out of the Heatmap and
  // Insights the moment the habit came back. Real stints never overlap, so at
  // most one of the templates sharing an id ever claims a given day.
  final customStints = <IslamicHabitTemplate>[
    for (final entry in customNotifier.customStintHistory.entries)
      for (final template in [
        ...customActive.where((h) => h.id == entry.key),
        ...customArchived.where((h) => h.id == entry.key),
      ].take(1))
        for (final stint in entry.value)
          template.withDates(createdAt: stint.$1, archivedAt: stint.$2),
  ];

  return [...catalogEver, ...customActive, ...customArchived, ...customStints];
});

/// Every window each habit has ever been ACTIVE for: habitId -> [(start, end)],
/// where a null end means "still running".
///
/// One question, answered from one place: "was this habit mine on day X?"
/// Everything that grades a stretch of days has to ask it, and asking the
/// habit's own createdAt/archivedAt instead — which describe only its CURRENT
/// window — gets it wrong in both directions the moment a habit is resumed.
/// A resumed catalog habit claims it was born on the resume day, so every day
/// before it reads as "never existed" and drops out of the denominator, paying
/// full credit for a stretch nobody did (see RoomParticipant.creditFor, where a
/// day that asks nothing is a finished day). A resumed custom habit used to
/// claim the opposite, that it had been running the whole time, so the paused
/// days it had been correctly excused from turned into misses.
///
/// Both are the same mistake: one window cannot describe a habit that has been
/// stood down and picked back up. The stint list can, and both halves of it are
/// already persisted (ActiveCatalogNotifier.catalogStintHistory and
/// CustomHabitsNotifier.customStintHistory), so this is a read, not a new
/// source of truth.
final habitStintsProvider =
    Provider<Map<String, List<(DateTime?, DateTime?)>>>((ref) {
  final catalogNotifier = ref.watch(activeCatalogProvider.notifier);
  final activeIds = ref.watch(activeCatalogProvider);
  final customNotifier = ref.watch(customHabitsProvider.notifier);
  final customActive = ref.watch(customHabitsProvider);

  final out = <String, List<(DateTime?, DateTime?)>>{};
  void add(String id, DateTime? start, DateTime? end) =>
      (out[id] ??= []).add((start, end));

  // ── Catalog ──
  for (final entry in catalogNotifier.catalogStintHistory.entries) {
    for (final stint in entry.value) {
      add(entry.key, stint.$1, stint.$2);
    }
  }
  for (final id in activeIds) {
    // Open-ended: still running, so no upper bound.
    add(id, catalogNotifier.activatedAt[id], null);
  }
  catalogNotifier.catalogArchivedAt.forEach((id, archivedAt) {
    // Closed by a real archive stamp. Skipped when the habit is active again,
    // because the open window above already describes the current stint and
    // catalogArchivedAt is only the most recent deactivation.
    if (activeIds.contains(id)) return;
    add(id, catalogNotifier.activatedAt[id], archivedAt);
  });

  // ── Custom ──
  for (final entry in customNotifier.customStintHistory.entries) {
    for (final stint in entry.value) {
      add(entry.key, stint.$1, stint.$2);
    }
  }
  for (final h in customActive) {
    add(h.id, h.createdAt, null);
  }
  for (final h in customNotifier.archived) {
    add(h.id, h.createdAt, h.archivedAt);
  }
  return out;
});

/// Whether [day] falls inside any window this habit was actually active for.
///
/// [stints] empty means this device knows of no history at all, which is every
/// account that has not paused anything since this shipped — [fallback] then
/// answers exactly as the old single-window rule did, so no stored grade moves
/// on the first launch after the update.
///
/// A null start keeps the existing "no birth date known means it always
/// existed" reading, and the archive day itself still counts (isAfter, not
/// !isBefore), which is the contract paused_habit_grading_rule_test pins.
bool habitCountedOn(
  List<(DateTime?, DateTime?)>? stints,
  DateTime day, {
  required bool Function() fallback,
}) {
  if (stints == null || stints.isEmpty) return fallback();
  final d = DateTime(day.year, day.month, day.day);
  for (final (start, end) in stints) {
    if (start != null &&
        d.isBefore(DateTime(start.year, start.month, start.day))) {
      continue;
    }
    if (end != null && d.isAfter(DateTime(end.year, end.month, end.day))) {
      continue;
    }
    return true;
  }
  return false;
}

/// Every habit currently PAUSED — custom ones archived by
/// [CustomHabitsNotifier.archive], and presets switched off with a
/// recorded archive date — newest pause first.
///
/// This is what makes pausing reversible. Before it existed, archiving
/// preserved a habit's whole history and then stranded it: nothing
/// listed what was archived, so the only way back was the six-second
/// Undo on the removal snackbar. The list is surfaced inside the Add
/// Habit hub rather than in Settings, because "I want that habit back"
/// and "I want a habit" are the same intent arriving at the same moment.
///
/// Includes habits paused TODAY, which are also still on the board for
/// the rest of that day (see [habitsArchivedTodayProvider]). Excluding
/// them was tried first, to avoid one habit appearing in two lists, and
/// it left a hole with no bottom: for the rest of the day that habit was
/// listed nowhere, so once the six-second Undo expired the pause could
/// not be taken back until tomorrow. Both places now say the same thing
/// instead of one of them saying nothing — Grid paints the row with a
/// pause tile and a tertiary name, and this list offers Resume.
final pausedHabitsProvider = Provider<List<IslamicHabitTemplate>>((ref) {
  final catalogNotifier = ref.watch(activeCatalogProvider.notifier);
  final all = <IslamicHabitTemplate>[
    ...ref.watch(customHabitsProvider.notifier).archived,
    for (final t in IslamicHabitCatalog.templates)
      if (catalogNotifier.catalogArchivedAt[t.id] case final DateTime at)
        // createdAt from activatedAt, NOT from t.createdAt: every const
        // catalog template leaves createdAt null, so stamping it through
        // gave a paused preset no lower bound at all — habitExistedOn and
        // isScheduledFor then answer "yes, it existed" for every day back
        // to the beginning of time, including years before this account
        // ever switched it on. Harmless while the only reader is this
        // sheet's list of names, and a loaded gun for the next reader that
        // does date math. [habitsArchivedTodayProvider] below has always
        // stamped it correctly; this now matches.
        t.withDates(createdAt: catalogNotifier.activatedAt[t.id], archivedAt: at),
  ];
  ref.watch(customHabitsProvider);
  ref.watch(activeCatalogProvider);
  final paused = [
    for (final h in all)
      if (h.archivedAt != null) h,
  ]..sort((a, b) => b.archivedAt!.compareTo(a.archivedAt!));
  return paused;
});

/// Habits (catalog or custom) archived on exactly today's effective day —
/// what Grid and Today additionally show, layered on top of
/// [habitListProvider], so deleting or deactivating a habit doesn't erase
/// its row mid-day. [IslamicHabitTemplate.isScheduledFor] already treats
/// the archive day itself as a real day (see that method's doc comment);
/// the only reason today's Grid/Today didn't already reflect that is that
/// [habitListProvider] drops an archived habit from its source list the
/// instant [CustomHabitsNotifier.archive]/[ActiveCatalogNotifier.toggle]
/// runs, before isScheduledFor ever gets a chance to say yes. This is that
/// one day's worth of habits, handed back separately instead of folded
/// into habitListProvider itself, on purpose: habitListProvider also
/// backs today's streak requirement (willCompleteAllHabitsToday) and the
/// Add sheet's "already have this" check, and a habit someone just
/// deleted should never go back to blocking either of those - only Grid's
/// row list and Today's checklist (the two places a same-day-visible row
/// actually makes sense) read this provider.
final habitsArchivedTodayProvider = Provider<List<IslamicHabitTemplate>>((ref) {
  final catalogNotifier = ref.watch(activeCatalogProvider.notifier);
  ref.watch(activeCatalogProvider);
  final catalogToday = <IslamicHabitTemplate>[
    for (final t in IslamicHabitCatalog.templates)
      if (catalogNotifier.catalogArchivedAt[t.id]?.isToday ?? false)
        t.withDates(
          createdAt: catalogNotifier.activatedAt[t.id],
          archivedAt: catalogNotifier.catalogArchivedAt[t.id],
        ),
  ];

  ref.watch(customHabitsProvider);
  final customToday = ref
      .watch(customHabitsProvider.notifier)
      .archived
      .where((h) => h.archivedAt?.isToday ?? false)
      .toList();

  return [...catalogToday, ...customToday];
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
  // catalogOverrides too, and it is not optional: habitListProvider layers a
  // member's per-preset overrides over the const catalog template, so a
  // preset's real cadence lives HERE, not in the template. Miss it and a
  // habit the member set to 4x/week resolves as its catalog default —
  // which a room then freezes as its permanent grading rule.
  ref.watch(catalogOverridesProvider);
  return ref.watch(customHabitsProvider.notifier).isLoading ||
      ref.watch(activeCatalogProvider.notifier).isLoading ||
      ref.watch(catalogOverridesProvider.notifier).isLoading;
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

