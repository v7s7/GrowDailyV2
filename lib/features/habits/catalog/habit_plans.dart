import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/services/notification_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import 'islamic_habit_catalog.dart';

// ─── Plan definitions ─────────────────────────────────────────────────────────

class HabitPlan {
  final String id;
  final String nameEn;
  final String nameAr;
  final String descEn;
  final String descAr;
  final Color color;
  final IconData icon;
  final List<String> catalogIds;

  const HabitPlan({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.descEn,
    required this.descAr,
    required this.color,
    required this.icon,
    required this.catalogIds,
  });

  String localName(bool isAr) => isAr ? nameAr : nameEn;
  String localDesc(bool isAr) => isAr ? descAr : descEn;

  List<IslamicHabitTemplate> get habits =>
      IslamicHabitCatalog.templates.where((t) => catalogIds.contains(t.id)).toList();

  int get totalDailyXp =>
      habits.fold(0, (sum, t) => sum + t.xpReward);
}

// Curated down from 8 heavily-overlapping plans to 6 distinct ones (July
// 2026) — each maps to a routine type people demonstrably stick with
// (morning routines form fastest thanks to consistent cues; curated
// programs and timed challenges are the patterns habit apps converge on).
// Every habit inside carries a real, accurate timing anchor now — see the
// per-habit cue/weekday fixes in islamic_habit_catalog.dart made alongside
// this. quran_memorization is deliberately in no plan (too advanced for a
// starter bundle); it keeps working for anyone who already has it active.
const habitPlans = <HabitPlan>[
  HabitPlan(
    id: 'morning_warrior',
    nameEn: 'Morning Warrior',
    nameAr: 'محارب الفجر',
    descEn: 'Fajr, athkar, a page of Quran, no phone. The hour that decides your day.',
    descAr: 'فجر، أذكار، صفحة قرآن، وبدون تلفون. أول ساعة تحدد يومك.',
    color: Color(0xFF4A9EFF),
    icon: Icons.wb_twilight,
    catalogIds: [
      'wake_early', 'morning_athkar', 'quran_daily_page', 'no_phone_morning',
    ],
  ),
  HabitPlan(
    id: 'deen_essentials',
    nameEn: 'Deen Essentials',
    nameAr: 'أساس الدين',
    descEn: 'Athkar morning and evening, daily Quran, Monday & Thursday fasting, and sadaqah.',
    descAr: 'أذكار الصباح والمساء، ورد يومي، صيام الاثنين والخميس، وصدقة.',
    color: Color(0xFF34C759),
    icon: Icons.mosque,
    catalogIds: [
      'morning_athkar', 'evening_athkar', 'quran_daily_page',
      'sunnah_fasting', 'daily_sadaqah',
    ],
  ),
  HabitPlan(
    id: 'night_routine',
    nameEn: 'Night Routine',
    nameAr: 'روتين الليل',
    descEn: 'Sleep before midnight, plan tomorrow tonight, and rise for tahajjud.',
    descAr: 'نم قبل منتصف الليل، خطط لبكرة من الليلة، وقم للتهجد.',
    color: Color(0xFFBF5AF2),
    icon: Icons.bedtime_rounded,
    catalogIds: ['sleep_schedule', 'daily_planning', 'tahajjud'],
  ),
  HabitPlan(
    id: 'discipline_30',
    nameEn: '30-Day Discipline',
    nameAr: 'تحدي الانضباط 30 يوم',
    descEn: 'Cold showers, early mornings, no sugar, and the gym. One month to reset.',
    descAr: 'دش بارد، صحيان مبكر، بدون سكر، ورياضة. شهر واحد يعدّل كل شي.',
    color: Color(0xFFFF6B35),
    icon: Icons.local_fire_department_rounded,
    catalogIds: ['cold_shower', 'wake_early', 'no_sugar', 'gym_consistency'],
  ),
  HabitPlan(
    id: 'deep_focus',
    nameEn: 'Deep Focus',
    nameAr: 'تركيز عميق',
    descEn: 'One real deep work block, a clear inbox, and tomorrow planned before you sleep.',
    descAr: 'فترة تركيز بدون مقاطعات، بريد مرتب، وبكرة مخطط له من الليل.',
    color: Color(0xFF2ECF8F),
    icon: Icons.rocket_launch_rounded,
    catalogIds: ['deep_work_block', 'inbox_zero', 'daily_planning'],
  ),
  // Pre-marriage, not married life — built directly on the Prophet's ﷺ own
  // prescription for those not yet able to marry (fasting + guarding
  // chastity, صحيح البخاري ٥٠٦٥) plus the classical readiness checklist:
  // dua, learning the rights of marriage, and saving for the mahr.
  // marriage_gratitude/marriage_checkin (married-couple habits) left out on
  // purpose — they keep working for anyone who already has them active,
  // and belong to a future "Married Life" plan, not preparation.
  HabitPlan(
    id: 'marriage_prep',
    nameEn: 'Marriage Preparation',
    nameAr: 'التحضير للزواج',
    descEn: 'The sunnah path to marriage: dua, knowledge, saving, fasting, and guarding your chastity.',
    descAr: 'طريق السنة للزواج: دعاء، علم، توفير، صيام، وغض البصر.',
    color: Color(0xFFFF6FA5),
    icon: Icons.favorite_rounded,
    catalogIds: [
      'marriage_dua', 'marriage_read', 'marriage_savings',
      'lower_gaze', 'sunnah_fasting',
    ],
  ),
  // The five fard prayers, each its own habit (see islamic_habit_catalog.
  // dart's "The Five Daily Prayers" section) so each gets a real,
  // separately-timed reminder rather than one lumped "pray today" entry.
  // Timing is fully real: cueAfter on each of the five resolves through
  // PrayerTimesService (location-based astronomical calculation, live
  // Aladhan lookup first, offline fallback) via the same
  // NotificationService.scheduleSmartReminders path every other
  // prayer-linked habit in this catalog already uses — nothing
  // plan-specific needed building, this just activates all five at once.
  HabitPlan(
    id: 'five_daily_prayers',
    nameEn: 'The Five Daily Prayers',
    nameAr: 'الصلوات الخمس',
    descEn: 'Fajr, Dhuhr, Asr, Maghrib, and Isha: each reminded at its real calculated time, wherever you are.',
    descAr: 'الفجر والظهر والعصر والمغرب والعشاء: تذكير بكل وقت حسب حسابه الفعلي أينما كنت.',
    color: Color(0xFFE0A82E),
    icon: Icons.mosque_outlined,
    catalogIds: [
      'prayer_fajr', 'prayer_dhuhr', 'prayer_asr', 'prayer_maghrib', 'prayer_isha',
    ],
  ),
];

// ─── Active catalog provider ──────────────────────────────────────────────────

const _kActiveKey = 'active_catalog_ids_v1';
const _kActivatedAtKey = 'active_catalog_activated_at_v1';
const _kArchivedAtKey = 'active_catalog_archived_at_v1';
const _kStintHistoryKey = 'active_catalog_stint_history_v1';
const _kReminderKey = 'daily_reminder_time_v1';

/// Which Islamic Habit Catalog templates the user has turned on — the
/// actual on/off switch [habitListProvider] (custom_habits_notifier.dart)
/// reads before merging in [customHabitsProvider]'s user-authored habits.
///
/// This used to be Hive-only with no `_uid` branch at all — the one piece
/// of "which habits/goals am I running" that didn't follow every other
/// notifier's signed-in-Firestore/guest-local-Hive pattern (matrix tasks,
/// custom habits, dashboard, grid, etc. all already do), so a catalog habit
/// switched on here quietly never showed up on a second device even though
/// its completions (keyed by the same catalog id, in DashboardNotifier)
/// synced just fine. Now mirrors [HabitOrderNotifier] exactly: a flat field
/// on the user doc, since a handful of catalog ids doesn't need its own
/// subcollection.
class ActiveCatalogNotifier extends StateNotifier<Set<String>> {
  final String? _uid;

  /// The save currently in flight, if any.
  ///
  /// [_save] is deliberately fire-and-forget at every call site: nothing in
  /// the UI waits on a Hive put, and making a toggle await one would put a
  /// disk write between the tap and the checkmark. That is right for the app
  /// and leaves exactly one loose end for tests, which tear the Hive
  /// directory down between cases: a put still in flight then lands on a
  /// closed box and throws "Box has already been closed", AFTER the test body
  /// has already passed. The runner blames whichever test happens to be
  /// running, so the failure names an innocent test and the write it was
  /// really about succeeded.
  ///
  /// Same reasoning, and the same shape, as
  /// [LocalStoreService.settleDailyWrites] — see its doc comment, which
  /// describes this identical problem for the daily-log path.
  Future<void>? _pendingSave;

  /// True until the very first Firestore/Hive read resolves - see
  /// CustomHabitsNotifier.isLoading's doc comment (custom_habits_notifier.
  /// dart) for why this lives as a plain field rather than being folded
  /// into [state] itself, and habitsStillLoadingProvider (same file) for
  /// where the two combine into the one signal a screen actually watches.
  bool isLoading = true;

  /// True once a signed-in [_load] has thrown, meaning [state] is this
  /// notifier's empty starting value rather than anything the server said.
  ///
  /// Plain field alongside [isLoading] for the same reason: nothing renders
  /// off it, [_save] is the only reader, and it must not trigger watchers of
  /// its own. Cleared only by a later successful load — a failed one leaves
  /// it set, because nothing has since proven the empty set is real.
  bool loadFailed = false;

  /// catalogId → the day it was switched on — the catalog habits' "birth
  /// date" (see IslamicHabitTemplate.createdAt), stamped onto each active
  /// template by habitListProvider so activating a habit today never
  /// paints yesterday as a miss. Plain field like [isLoading] (updates
  /// always ride along with a [state] change, which is what triggers
  /// watchers). Missing ids — everything activated before this map
  /// existed — just get no birth date, i.e. the exact old behavior.
  /// Toggling a habit OFF now *keeps* its entry here (see
  /// [catalogArchivedAt] for why — this used to be erased on deactivation,
  /// which is exactly what made a toggled-off habit's history vanish from
  /// the Heatmap/Insights). Re-activating still overwrites it with a
  /// fresh date, though, so re-activating later is a fresh start, not a
  /// resurrection of the old stint's misses.
  Map<String, DateTime> activatedAt = {};

  /// catalogId → the day it was toggled off — the archive-side
  /// counterpart to [activatedAt]. Together the two bound the exact
  /// window a past activation covered, which is what lets
  /// allHabitsEverProvider (custom_habits_notifier.dart) keep a
  /// deactivated catalog habit's history alive in the Heatmap and
  /// Insights instead of losing it the instant it's toggled off — same
  /// reasoning as IslamicHabitTemplate.archivedAt, just stored the way
  /// this class already stores activation dates (a flat map, not a field
  /// on the immutable template itself). Only ever holds the *most
  /// recent* deactivation for a given id: if a habit is toggled on/off
  /// more than once, earlier stints aren't separately preserved, only
  /// the latest complete window. Cleared the moment a habit is active
  /// again (see [toggle]) — an active id is never also archived.
  Map<String, DateTime> catalogArchivedAt = {};

  /// catalogId → every fully-closed stint STRICTLY BEFORE the current-or-
  /// most-recent one — (start, end) pairs, oldest first. [activatedAt]/
  /// [catalogArchivedAt] only ever describe *one* window per id (the
  /// current one if active, otherwise the most recent), so without this
  /// a habit toggled on, off, on, off again would silently lose its
  /// first stint's dates the moment it's reactivated: the second
  /// [toggle] call overwrites [activatedAt] with a fresh date before the
  /// first stint's window is recorded anywhere else. [toggle] and
  /// [applyPlanSelection] both push the *outgoing* current-or-most-recent
  /// window in here right before they'd otherwise clobber it by
  /// reactivating — see [toggle]'s own comment. allHabitsEverProvider
  /// (custom_habits_notifier.dart) reads this to emit one synthetic
  /// template per stint, not just the last, so the Heatmap/Insights can
  /// credit every window a habit was ever really active for. A custom
  /// habit never needs this: it's a real, distinct Firestore document per
  /// archive, not a map slot that gets reused.
  Map<String, List<(DateTime, DateTime)>> catalogStintHistory = {};

  ActiveCatalogNotifier(this._uid) : super(const {}) {
    if (_uid != null) {
      _load();
    } else {
      _loadGuest();
    }
  }

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  static Map<String, DateTime> _parseActivatedAt(dynamic raw) => {
        if (raw is Map)
          for (final e in raw.entries)
            if (DateTime.tryParse('${e.value}') != null)
              e.key.toString(): DateTime.parse('${e.value}'),
      };

  /// Parses [catalogStintHistory] back from its stored shape: catalogId →
  /// a list of {'start': iso, 'end': iso} maps. Any entry missing either
  /// date, or not shaped like a map at all, is silently dropped rather
  /// than crashing the whole read — the same defensiveness every other
  /// parse helper in this class already has toward hand-edited/corrupt
  /// data.
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

  Future<void> _loadGuest() async {
    final box = await LocalStoreService.settingsBox();
    final raw = box.get(_kActiveKey);
    activatedAt = _parseActivatedAt(box.get(_kActivatedAtKey));
    catalogArchivedAt = _parseActivatedAt(box.get(_kArchivedAtKey));
    catalogStintHistory = _parseStintHistory(box.get(_kStintHistoryKey));
    if (!mounted) return;
    if (raw is List) {
      state = Set<String>.from(raw.whereType<String>());
    } else {
      // Nothing to load, but still force a fresh state reference so
      // habitsStillLoadingProvider's watchers notice this pass finished -
      // see isLoading's own doc comment.
      state = Set.of(state);
    }
    isLoading = false;
  }

  Future<void> _load() async {
    if (_uid == null) return;
    try {
      final snap = await _userRef.get();
      if (!mounted) return;
      // The read came back, so everything derived below is genuinely the
      // server's answer — clear any earlier failure so saving works again
      // (a resume-triggered reload is the usual way back).
      loadFailed = false;
      activatedAt =
          _parseActivatedAt(snap.data()?['activeCatalogActivatedAt']);
      catalogArchivedAt =
          _parseActivatedAt(snap.data()?['activeCatalogArchivedAt']);
      catalogStintHistory =
          _parseStintHistory(snap.data()?['activeCatalogStintHistory']);
      final raw = snap.data()?['activeCatalogIds'];
      if (raw is List) {
        state = Set<String>.from(raw.whereType<String>());
        isLoading = false;
        return;
      }
      // No Firestore field yet — either a brand-new account, or one that
      // signed in before this synced at all. In the second case there may
      // already be real picks sitting in this device's own local Hive box
      // (from back when this was Hive-only) — seed from that instead of
      // silently showing an empty list and making it look like every
      // catalog habit this person turned on just vanished, then persist it
      // so it's captured in Firestore from here on.
      final box = await LocalStoreService.settingsBox();
      final localRaw = box.get(_kActiveKey);
      if (localRaw is List) {
        state = Set<String>.from(localRaw.whereType<String>());
        if (state.isNotEmpty) _kickSave();
      }
    } catch (_) {
      // The signed-in read failed, so `state` is still the empty set this
      // notifier started with and none of it came from the server. Flag it
      // so [_save] refuses to write that emptiness back — see loadFailed.
      if (mounted) loadFailed = true;
    } finally {
      // Covers every path that didn't already return above: the local-
      // Hive-seed fallback (found or not), and the catch-all error - none
      // of those necessarily reassign `state` on their own (a fresh
      // account with no Firestore field and no local seed never does), so
      // this forces one last fresh reference through regardless, exactly
      // mirroring CustomHabitsNotifier._load's identical guard.
      if (mounted && isLoading) {
        isLoading = false;
        state = Set.of(state);
      }
    }
  }

  /// Starts a save and remembers it, so [settled] can wait for it.
  void _kickSave() {
    _pendingSave = _save();
  }

  /// Waits until no save is in flight. Test-only, exactly like
  /// [LocalStoreService.settleDailyWrites]; the app never needs it because
  /// its boxes outlive the process.
  ///
  /// Loops rather than awaiting once: a save can be kicked off WHILE an
  /// earlier one is being awaited (three toggles in a row is a normal test),
  /// and returning after the first would leave the newest write racing the
  /// teardown all over again.
  Future<void> get settled async {
    while (_pendingSave != null) {
      final inFlight = _pendingSave;
      await inFlight;
      if (identical(inFlight, _pendingSave)) _pendingSave = null;
    }
  }

  Future<void> _save() async {
    // Refuse to persist anything while the signed-in load is known to have
    // failed. `activeCatalogIds` below is written as an ABSOLUTE array, and
    // after a failed read `state` is the empty set this notifier started
    // with — so a single tap on one habit would write a one-element array
    // straight over however many catalog habits the account really has, and
    // the rest are gone. Declining is recoverable (the next successful load
    // brings the real list back); truncating is not. Same reasoning, and the
    // same shape, as DashboardState.loadFailed's guards.
    //
    // Guests are not covered on purpose: `_uid == null` means there is no
    // server list to truncate, and _loadGuest owns its own failure path.
    if (_uid != null && loadFailed) return;

    // ISO strings both paths (Hive can't hold Timestamps; Firestore holds
    // strings fine) — and always the WHOLE map as one nested field, never
    // dotted 'field.key' entries (see BUILD_LESSONS.md #10).
    final atMap = {
      for (final e in activatedAt.entries) e.key: e.value.toIso8601String(),
    };
    final archivedMap = {
      for (final e in catalogArchivedAt.entries)
        e.key: e.value.toIso8601String(),
    };
    final stintHistoryRaw = _stintHistoryToRaw(catalogStintHistory);
    if (_uid != null) {
      _userRef.set({
        'activeCatalogIds': state.toList(),
        'activeCatalogActivatedAt': atMap,
        'activeCatalogArchivedAt': archivedMap,
        'activeCatalogStintHistory': stintHistoryRaw,
      }, SetOptions(merge: true)).ignore();
      return;
    }
    final box = await LocalStoreService.settingsBox();
    await box.put(_kActiveKey, state.toList());
    await box.put(_kActivatedAtKey, atMap);
    await box.put(_kArchivedAtKey, archivedMap);
    await box.put(_kStintHistoryKey, stintHistoryRaw);
  }

  /// [everCompleted] — same meaning and same reasoning as
  /// [CustomHabitsNotifier.archive]'s own parameter (custom_habits_notifier.
  /// dart): whether this catalog habit has EVER been marked done, this
  /// stint or any earlier one (it's a lifetime count - see that parameter's
  /// own doc comment for why age doesn't factor in here at all, only
  /// whether anything was ever really done). True by default, so every
  /// existing call site that doesn't pass it keeps deactivating exactly as
  /// before. When it's false, turning it back off erases this stint
  /// entirely (no catalogArchivedAt stamp, [activatedAt] cleared too)
  /// instead of archiving it, no matter how long it had been switched on -
  /// nothing was ever completed in it, so there's nothing for the
  /// Heatmap/Insights to lose by forgetting it happened, and it avoids
  /// leaving a phantom stint that would otherwise linger in
  /// catalogStintHistory forever. allHabitsEverProvider's own null-guard
  /// (custom_habits_notifier.dart) is what keeps this safe even when real
  /// earlier stints for the same id still exist in catalogStintHistory.
  ///
  /// [eraseIfEmpty] — same split as [CustomHabitsNotifier.archive]'s
  /// parameter of the same name: true for the remove path, false for
  /// Pause, which promises the habit is kept and resumable. Without it,
  /// pausing a preset that had never been completed left no
  /// catalogArchivedAt stamp, so it was absent from the paused list and
  /// there was nothing to resume.
  void toggle(
    String catalogId, {
    bool everCompleted = true,
    bool eraseIfEmpty = true,
  }) {
    if (state.contains(catalogId)) {
      if (!everCompleted && eraseIfEmpty) {
        activatedAt = {...activatedAt}..remove(catalogId);
        state = Set.of(state)..remove(catalogId);
        _kickSave();
        return;
      }
      // Archive, don't erase: [activatedAt] keeps this stint's start
      // date exactly as-is, and this just records today as when it
      // ended — together they're the window allHabitsEverProvider needs
      // to keep crediting (see [catalogArchivedAt]'s own doc comment).
      catalogArchivedAt = {
        ...catalogArchivedAt,
        catalogId: DateTime.now().effectiveDay,
      };
      state = Set.of(state)..remove(catalogId);
    } else {
      // The stint that's about to be overwritten below (if any) is real,
      // closed history — push it into catalogStintHistory before its
      // dates are gone for good. Only fires on a genuine re-activation:
      // the very first activation has no priorStart/priorEnd yet.
      final priorStart = activatedAt[catalogId];
      final priorEnd = catalogArchivedAt[catalogId];
      final today = DateTime.now().effectiveDay;
      // Paused and resumed inside the same day: nothing about this
      // habit's timeline actually changed, so record nothing. Treating it
      // as a real stint boundary would close a window ending today and
      // open another starting today, and those two synthetic templates
      // both claim today — breaking the one invariant allHabitsEverProvider
      // states out loud ("real stints never overlap in time, so at most
      // one of the duplicates ever claims any given day") and counting
      // today twice in the Heatmap and Insights. Rare when the only way
      // back was a six-second Undo; routine now that Pause sits next to
      // Resume, one tap apart.
      if (priorStart != null && priorEnd != null && priorEnd.isSameDayAs(today)) {
        activatedAt = {...activatedAt, catalogId: priorStart};
        catalogArchivedAt = {...catalogArchivedAt}..remove(catalogId);
        state = {...state, catalogId};
        _kickSave();
        return;
      }
      if (priorStart != null && priorEnd != null) {
        catalogStintHistory = {
          ...catalogStintHistory,
          catalogId: [
            ...(catalogStintHistory[catalogId] ?? const []),
            (priorStart, priorEnd),
          ],
        };
      }
      activatedAt = {
        ...activatedAt,
        catalogId: today,
      };
      // Re-activating is a fresh start (see [activatedAt]'s doc comment)
      // — clear any archive record from a previous stint so this id
      // reads as plainly active again, not active-and-archived at once.
      catalogArchivedAt = {...catalogArchivedAt}..remove(catalogId);
      state = {...state, catalogId};
    }
    _kickSave();
  }

  /// Commits exactly [selected] as this account's active habits for
  /// [plan] — every id in [selected] ends up active (whether it already
  /// was or not), and every one of the plan's *other* catalog ids gets
  /// deactivated if it happened to be active already. This is what
  /// PlanPickerSheet's Start/"Add Selected" button actually calls: its
  /// checklist starts every habit checked, so pressing Start the moment a
  /// plan opens passes the *whole* plan (same result the old always-full
  /// activatePlan used to give unconditionally) — unchecking some first
  /// and then pressing it passes only what's still checked instead, which
  /// is the one thing the old method could never do (it only ever added,
  /// never reconciled a subset down).
  ///
  /// [everCompleted] — same meaning as [toggle]'s own parameter, just one
  /// per id instead of one for a single habit: id -> whether that specific
  /// habit has ever been marked done, on any day, ever (the caller passes
  /// `dashboardProvider.habitTotalCompletions[id] > 0` for each id about to
  /// be deactivated). An id missing from the map defaults to true (archive,
  /// the safe/conservative choice), same default [toggle] itself uses —
  /// existing callers that don't pass anything keep deactivating exactly
  /// as before.
  void applyPlanSelection(
    HabitPlan plan,
    Set<String> selected, {
    Map<String, bool> everCompleted = const {},
  }) {
    final today = DateTime.now().effectiveDay;
    final toDeactivate = plan.catalogIds
        .where((id) => !selected.contains(id) && state.contains(id))
        .toSet();
    // Split the same way [toggle] splits a single id: never-completed ones
    // are erased outright instead of archived — see [toggle]'s own doc
    // comment for why age never factors in, only whether anything was
    // ever really done.
    final toHardDelete =
        toDeactivate.where((id) => everCompleted[id] == false).toSet();
    final toArchive = toDeactivate.difference(toHardDelete);
    // Ids genuinely coming back to life here — same set activatedAt's own
    // comprehension below already isolates via !state.contains(id).
    final reactivating =
        selected.where((id) => !state.contains(id)).toSet();
    // Same "push the outgoing stint into history before it's overwritten"
    // step as [toggle]'s reactivation branch — see that doc comment.
    // Same same-day rule [toggle] applies: a stint that ended today and
    // is reopening today is not two windows, it is one uninterrupted one.
    // Recording it would put two synthetic templates from
    // allHabitsEverProvider on today at once, which the Heatmap and
    // Insights both count. Reachable from Plans the moment someone
    // switches a plan off and back on in one sitting.
    final reopeningSameDay = {
      for (final id in reactivating)
        if (catalogArchivedAt[id]?.isSameDayAs(today) ?? false) id,
    };
    catalogStintHistory = {
      ...catalogStintHistory,
      for (final id in reactivating)
        if (!reopeningSameDay.contains(id) &&
            activatedAt[id] != null &&
            catalogArchivedAt[id] != null)
          id: [
            ...(catalogStintHistory[id] ?? const []),
            (activatedAt[id]!, catalogArchivedAt[id]!),
          ],
    };
    activatedAt = {
      ...activatedAt,
      // Only ids that are genuinely NEW get today's date — re-picking an
      // already-active habit must not move its birth date forward, and a
      // habit reopening the same day it closed keeps its original start
      // for the same reason.
      for (final id in reactivating)
        if (!reopeningSameDay.contains(id)) id: today,
      // Erased, not just left alone — a hard-deleted id has no current
      // stint any more, same as [toggle]'s own hard-delete branch.
    }..removeWhere((id, _) => toHardDelete.contains(id));
    // Archive, don't erase — same reasoning as [toggle]: keep
    // activatedAt as-is for anything being archived (it's still that
    // stint's real start date) and just record today as when it ended,
    // while anything freshly selected loses any stale archive record.
    catalogArchivedAt = {
      ...catalogArchivedAt,
      for (final id in toArchive) id: today,
    }..removeWhere((id, _) => selected.contains(id));
    state = {...state}
      ..removeAll(toDeactivate)
      ..addAll(selected);
    _kickSave();
  }

  /// [everCompleted] — same meaning and default as [applyPlanSelection]'s
  /// own parameter of the same name; see its doc comment.
  void deactivatePlan(HabitPlan plan, {Map<String, bool> everCompleted = const {}}) {
    final today = DateTime.now().effectiveDay;
    final deactivating = plan.catalogIds.where(state.contains).toSet();
    final toHardDelete =
        deactivating.where((id) => everCompleted[id] == false).toSet();
    final toArchive = deactivating.difference(toHardDelete);
    // Archive, don't erase — see [toggle]'s doc comment.
    catalogArchivedAt = {
      ...catalogArchivedAt,
      for (final id in toArchive) id: today,
    };
    activatedAt = {...activatedAt}
      ..removeWhere((id, _) => toHardDelete.contains(id));
    state = state.difference(plan.catalogIds.toSet());
    _kickSave();
  }

  bool planIsActive(HabitPlan plan) =>
      plan.catalogIds.every(state.contains);
}

final activeCatalogProvider =
    StateNotifierProvider<ActiveCatalogNotifier, Set<String>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return ActiveCatalogNotifier(uid);
});

// ─── Daily reminder time provider ─────────────────────────────────────────────

class ReminderTimeNotifier extends StateNotifier<TimeOfDay?> {
  ReminderTimeNotifier() : super(null) {
    _loadFuture = _load();
  }

  // See ThemeModeNotifier's identical field (theme_provider.dart) for why
  // this is set after construction rather than threaded through the
  // provider.
  String? _uid;

  // _load() is the one thing here that's async from the very start (every
  // other synced notifier in the app seeds its initial value synchronously
  // via a boot-time provider override instead) — pullFromAccount below
  // awaits this first so it can't race _load() and stomp a value that was
  // already sitting in this device's own Hive storage.
  late final Future<void> _loadFuture;

  Future<void> _load() async {
    final box = await LocalStoreService.settingsBox();
    final raw = box.get(_kReminderKey) as String?;
    if (raw != null && mounted) {
      state = _parse(raw);
    }
  }

  TimeOfDay? _parse(String raw) {
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 20,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  /// Saves the reminder time and (re)schedules the local notification.
  /// Returns whether notification permission was actually granted — the
  /// time is saved either way (so it's ready to fire the moment the user
  /// grants permission from system settings), but previously this discarded
  /// [NotificationService.requestPermissions]'s result entirely, so a user
  /// who denied the OS permission prompt saw the reminder time saved with
  /// no indication their reminder would never actually fire.
  Future<bool> set(TimeOfDay time) async {
    state = time;
    final raw = '${time.hour}:${time.minute}';
    final box = await LocalStoreService.settingsBox();
    await box.put(_kReminderKey, raw);
    if (_uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({'reminderTime': raw}, SetOptions(merge: true))
          .catchError((_) {});
    }
    final granted = await NotificationService.instance.requestPermissions();
    await NotificationService.instance
        .scheduleDailyReminder(hour: time.hour, minute: time.minute);
    return granted;
  }

  Future<void> clear() async {
    state = null;
    final box = await LocalStoreService.settingsBox();
    await box.delete(_kReminderKey);
    if (_uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({'reminderTime': FieldValue.delete()}, SetOptions(merge: true))
          .catchError((_) {});
    }
    await NotificationService.instance.cancelDailyReminder();
  }

  /// Called once a signed-in uid is known — pulls this account's saved
  /// reminder time, if any, but ONLY fills it in when this device doesn't
  /// already have a time of its own (an existing device-local time always
  /// wins, since it's the one actually scheduled here). Deliberately does
  /// NOT request notification permission or call scheduleDailyReminder by
  /// itself: doing that automatically right after sign-in, rather than from
  /// an explicit tap on the Daily Reminder row, is exactly the kind of
  /// out-of-context permission prompt that's poor practice (and against
  /// iOS's own guidance) to spring on someone. The time still shows up
  /// pre-filled instead of "Tap to set reminder" though, so actually
  /// turning it on for real on this device is then just one confirming tap
  /// instead of having to remember what time was used elsewhere.
  Future<void> pullFromAccount(String uid) async {
    _uid = uid;
    await _loadFuture;
    if (state != null) return;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final saved = snap.data()?['reminderTime'] as String?;
      if (saved == null) return;
      final parsed = _parse(saved);
      if (parsed == null || !mounted) return;
      state = parsed;
      final box = await LocalStoreService.settingsBox();
      await box.put(_kReminderKey, saved);
    } catch (_) {}
  }

  /// Signed out - future set()/clear() calls go back to being device-local
  /// only, same as a guest.
  void detachAccount() => _uid = null;
}

final reminderTimeProvider =
    StateNotifierProvider<ReminderTimeNotifier, TimeOfDay?>(
  (_) => ReminderTimeNotifier(),
);
