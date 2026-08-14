import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/game_constants.dart';
import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/xp_calculator.dart';
import '../../../features/achievements/models/achievement_model.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../milestones/models/milestone_event.dart';

part 'dashboard_notifier_loading.dart';
part 'dashboard_notifier_complete_habit.dart';
part 'dashboard_notifier_uncomplete_habit.dart';
part 'dashboard_notifier_grid_rewards.dart';


/// Streak-day thresholds that trigger a milestone celebration, derived from
/// [GameConstants.streakBonuses] so the thresholds and their XP payouts
/// can't drift apart into two different lists.
final List<int> kStreakMilestones = GameConstants.streakBonuses.keys.toList();

/// One-time XP bonus for reaching [milestone] days — delegates to
/// [XpCalculator.streakMilestoneBonus] (backed by [GameConstants]) so this
/// isn't a second, independently-editable copy of the same numbers.
int milestoneXpBonus(int milestone) =>
    XpCalculator.streakMilestoneBonus(milestone);

/// Every `catch (_) {}` below a Firestore batch/set write in this file
/// calls this instead of silently discarding the error. Firestore's own
/// offline queue already covers a plain connectivity gap transparently —
/// the write sits in the local cache and syncs once the device is back
/// online, no app-level retry needed (see BUILD_LESSONS.md) — so this
/// isn't standing in for that. What it catches is a *real* rejection (a
/// rules change, an expired/invalid auth token, a quota limit, a malformed
/// field) that used to vanish with zero trace anywhere. Deliberately still
/// non-fatal and still swallowed from the caller's point of view after
/// this runs: every call site already applied its optimistic local
/// [state] update before attempting the write (see e.g. [completeHabit]'s
/// own doc comment), and reverting that on a write failure would yank
/// away XP/gold/streak progress someone already saw and reacted to —
/// worse, for a rare failure, than a stray write that silently doesn't
/// reach Firestore this one time. Logging is strictly additive: it makes
/// that rare failure visible in Crashlytics without changing what the
/// user sees.
Future<void> _recordWriteFailure(
  String where,
  Object error,
  StackTrace stackTrace,
) {
  return FirebaseCrashlytics.instance.recordError(
    error,
    stackTrace,
    reason: 'dashboard_notifier.$where: Firestore write failed',
  );
}

/// The minimum fraction of today's scheduled habits that must be done for
/// the day to earn its streak point — see [willCompleteAllHabitsToday].
/// Deliberately not 1.0 (literal 100%): staying perfect every single day
/// of a long streak is unrealistic, and losing real progress over one
/// missed habit on an otherwise full day felt like a punishment for
/// nearly succeeding rather than a fair rule. 0.8 means "one slip on an
/// otherwise full day still counts," while a day that's mostly undone
/// still doesn't (1 of 6 done is 17% — nowhere near qualifying).
const double kStreakDayCompletionThreshold = 0.8;

/// Whether completing [habitId] (today, toward [frequencyTarget]) leaves
/// today's scheduled habits at or above [kStreakDayCompletionThreshold] —
/// the completion-ratio moment that earns the day's streak point (see
/// [DashboardState.streakEarnedToday] and [DashboardNotifier.completeHabit]).
/// Name kept as-is (matching [DashboardNotifier.completeHabit]'s
/// `allHabitsDoneAfter` parameter, which every call site already spells
/// out by that name) rather than renamed for the threshold change — the
/// rule this answers is now "at or above the threshold," not literally
/// every habit.
///
/// [todayHabits] is today's scheduled habit list reduced to just the two
/// fields this needs (id + weekly target), passed in as records so this
/// stays free of any dependency on the habit catalog type — every caller
/// (DashboardScreen, the Grid screen, the notification action handler)
/// already has the real habit list in scope and can map it down to this
/// shape in one line.
bool willCompleteAllHabitsToday({
  required DashboardState state,
  required Iterable<({String id, int frequencyTarget})> todayHabits,
  required String habitId,
  required int frequencyTarget,
}) {
  var sawTarget = false;
  var total = 0;
  var doneCount = 0;
  for (final h in todayHabits) {
    total++;
    final isTarget = h.id == habitId;
    if (isTarget) sawTarget = true;
    final done = isTarget
        ? (state.completions[h.id] ?? 0) + 1 >= frequencyTarget
        : state.isCompleted(h.id, h.frequencyTarget);
    if (done) doneCount++;
  }
  // An empty (or habitId-missing) list never earns a streak point — a day
  // with nothing scheduled isn't a completed day, it's a day off.
  if (total == 0 || !sawTarget) return false;
  return doneCount / total >= kStreakDayCompletionThreshold;
}

// Milestone flavor titles ("3-Day Starter", "بداية النشامى", ...) live in
// S.milestoneTitle (app_strings.dart) since they're locale-dependent —
// keeping them here would mean an English-only title bleeding into the
// Arabic UI.

/// A per-habit streak milestone just reached — carries enough context (which
/// habit, by name) for the celebration dialog to reference it by name,
/// unlike the app-wide [DashboardState.milestoneCelebration] which only
/// needs the day count since there's only one app-wide streak to talk about.
class HabitMilestoneEvent {
  final String habitId;
  final String habitName;
  final int milestone;
  final int bonusXp;

  const HabitMilestoneEvent({
    required this.habitId,
    required this.habitName,
    required this.milestone,
    required this.bonusXp,
  });
}

/// Exactly what a single habit's per-habit streak fields (and any bonus
/// tied to that one completion) looked like the instant *before*
/// [DashboardNotifier.completeHabit] changed them — kept around just long
/// enough for a same-session [DashboardNotifier.uncompleteHabit] call to
/// reverse them precisely instead of guessing.
///
/// Guessing is the thing this exists to avoid: [prevStreak] can't be
/// recovered from the post-completion state once it's been overwritten
/// (the streak-continuation rule needs to know the date/streak as they
/// were *before* today's bump, and after the bump `habitLastCompletedDate`
/// already reads as "today" either way). Without this snapshot, an undo
/// has no way to tell "this habit was on a 6-day streak" apart from "this
/// habit has never been completed before" — both look identical once
/// `completeHabit` has already run.
class _HabitCompletionSnapshot {
  /// False when this habit had never been completed before today's tap —
  /// [prevStreak]/[prevLongest]/[prevTotal] are meaningless zeros in that
  /// case, and reversing means removing the map entries entirely rather
  /// than restoring them to 0 (keeps a never-completed habit's maps free
  /// of stray zero entries, same as they'd look if it were never tapped).
  final bool hadPrior;
  final int prevStreak;
  final int prevLongest;
  final int prevTotal;
  final String? prevLastCompletedDate;

  /// Surprise-bonus + per-habit-milestone XP/Gold this one completion
  /// awarded on top of the habit's base xpReward/goldReward — deliberately
  /// excludes any app-wide streak-milestone bonus, which stays
  /// undo-proof by design (see [DashboardNotifier.uncompleteHabit]'s doc
  /// comment).
  final int bonusXp;
  final int bonusGold;

  const _HabitCompletionSnapshot({
    required this.hadPrior,
    required this.prevStreak,
    required this.prevLongest,
    required this.prevTotal,
    required this.prevLastCompletedDate,
    required this.bonusXp,
    required this.bonusGold,
  });
}

class DashboardState {
  /// User-chosen display name, stored on the 'displayName' Firestore field
  /// that account creation already writes (defaulting to the email prefix —
  /// see AuthNotifier._createUserDoc). Empty until loaded or for a guest who
  /// hasn't set one yet; callers should fall back to something else (email
  /// prefix, 'Warrior') when this is blank rather than showing nothing.
  final String displayName;
  final int level;
  final int currentLevelXp;
  final int cumulativeXp;
  final int gold;
  final int streak;
  final int longestStreak;
  final int totalCompletions;
  final int streakFreezes;
  final Map<String, int> completions;
  final List<String> unlockedAchievements;
  final List<AchievementModel> newlyUnlocked;
  final bool didJustLevelUp;
  final bool didUseStreakFreeze;

  /// One-shot "every habit scheduled today is now done" event — set by
  /// [DashboardNotifier.completeHabit] on exactly the completion that
  /// finishes the day (the same justReachedAllDone moment that earns the
  /// streak point, so it can fire at most once per day and never from a
  /// backfilled past square). Same reset-by-default copyWith semantics as
  /// [didJustLevelUp]: any other state change clears it, so it can't stick
  /// and replay. Consumed by registerDashboardReactions' perfect-day
  /// celebration.
  final bool perfectDayCelebration;
  final String? lastCompletedId;
  final bool isLoading;

  /// True when [_loadToday] threw and this state is therefore
  /// [DashboardState.initial()]'s zeros rather than anything the server
  /// actually said.
  ///
  /// This exists because every field above is written back to Firestore as an
  /// ABSOLUTE value (see completeHabit's batch), not as an increment. A
  /// failed load that silently presents as "level 1, 0 XP, 0 gold, no streak"
  /// is therefore not merely a cosmetic wrong number on Profile — the next
  /// habit completion would persist those zeros over the real document and
  /// destroy the account's actual progress. Reward writes MUST refuse to run
  /// while this is set; there is nothing trustworthy to base them on.
  final bool loadFailed;

  /// The streak that was just lost to a missed day, still recoverable via
  /// [DashboardNotifier.useStreakFreeze] — 0 when there's nothing pending.
  /// Persisted (Firestore's 'previousStreak' field / the guest settings
  /// map), unlike the old design where this was recomputed fresh on every
  /// load and only "worked" for a single in-memory session: since
  /// `refresh()` re-runs on every app resume, a value that could only ever
  /// be derived once meant backgrounding the app before acting on the
  /// comeback card silently and permanently lost the offer. Cleared (set
  /// back to 0, both locally and in storage) by whichever comes first:
  /// [DashboardNotifier.useStreakFreeze], [DashboardNotifier.acknowledgeComeback],
  /// or simply earning a fresh streak day for real — see
  /// [DashboardNotifier.completeHabit]'s `clearsPendingComeback`.
  final int previousStreak;

  /// Whether the "you lost your streak" card should show — always exactly
  /// [previousStreak] > 0, so this can never drift out of sync with the
  /// value it's describing the way a separately-tracked bool could.
  bool get showComebackBonus => previousStreak > 0;

  final int? milestoneCelebration;
  final bool intentionsSetToday;

  /// Lifetime count of green (complete/bonus) squares ever colored on the
  /// Victory Grid — the "100 green squares completed" style achievements.
  final int totalGreenSquares;

  /// Whether *today* has already earned its once-per-day streak point.
  /// Streak means a day at or above [kStreakDayCompletionThreshold] of
  /// today's scheduled habits done (see [willCompleteAllHabitsToday]) —
  /// not just "did something today", so this is only ever set the instant
  /// that threshold is first reached. It's the single explicit gate
  /// [completeHabit] checks before bumping the streak, replacing what used
  /// to be three separate places each re-guessing "did today already
  /// count" from [completions]/grid state; one persisted boolean can't be
  /// fooled by reload timing the way an inferred guess could, and —
  /// because it can only flip false→true once per calendar day — it's
  /// also what guarantees the streak can never climb by more than 1 per
  /// day (so, e.g., 7 real days can never produce more than a 7-day
  /// streak). Deliberately sticky: once true, adding a *new* habit later
  /// today (which lowers today's completion percentage back below the
  /// threshold) does not revoke it — see [completeHabit]'s doc comment for
  /// why that's the intended behavior, not a bug.
  final bool streakEarnedToday;

  /// dateKey ('YYYY-MM-DD') → green squares colored that day, across all
  /// history. Kept as a flat rollup on the user doc so the monthly heatmap
  /// loads instantly regardless of how many years of data exist.
  final Map<String, int> dailyGreenCounts;

  /// Lifetime completions per habit category (e.g. 'quran' → 42), used to
  /// evaluate [AchievementTrigger.habitMastery] achievements.
  final Map<String, int> categoryCompletions;

  // ── Per-habit streaks ────────────────────────────────────────
  //
  // habitId → streak count as of habitLastCompletedDate[habitId]. This is
  // the *raw* persisted value — it only ever changes when that habit is
  // completed, so a habit that's gone stale (missed a day since) would keep
  // showing its old streak forever if read directly. Always read
  // [habitStreak] instead, which corrects for that.
  final Map<String, int> habitStreakCounts;
  final Map<String, int> habitLongestStreaks;
  final Map<String, int> habitTotalCompletions;
  // habitId → 'YYYY-MM-DD' of that habit's most recent completion.
  final Map<String, String> habitLastCompletedDate;

  /// Set the instant a per-habit streak crosses a milestone (see
  /// [GameConstants.habitStreakBonuses]); cleared once the celebration
  /// dialog is dismissed. Not persisted — this is a one-shot UI cue, not
  /// data worth remembering across app restarts.
  final HabitMilestoneEvent? habitMilestoneCelebration;

  /// Bonus XP/Gold from the most recent completion's surprise-bonus roll
  /// (see [GameConstants.surpriseBonusChance]) — 0 when that completion
  /// didn't roll a bonus. Transient, like [lastCompletedId]: read once by
  /// the completion toast, then irrelevant until the next completion.
  final int lastCompletionBonusXp;
  final int lastCompletionBonusGold;

  /// When this account was created (Firestore's 'createdAt' field, set once
  /// by AuthNotifier._createUserDoc at sign-up) — the "day one" anchor
  /// JourneyPage renders as a synthetic first entry ahead of the real
  /// MilestoneEvent log, and the "member since" line on the Profile Legacy
  /// Shelf. Null while loading, and permanently null for a guest: local
  /// (Hive) storage never stamps a creation date today, so there's nothing
  /// to read — both surfaces above just omit their "since" framing rather
  /// than showing a wrong or made-up date.
  final DateTime? accountCreatedAt;

  const DashboardState({
    this.displayName = '',
    required this.level,
    required this.currentLevelXp,
    required this.cumulativeXp,
    required this.gold,
    required this.streak,
    this.longestStreak = 0,
    this.totalCompletions = 0,
    this.streakFreezes = 1,
    required this.completions,
    this.unlockedAchievements = const [],
    this.newlyUnlocked = const [],
    this.didJustLevelUp = false,
    this.didUseStreakFreeze = false,
    this.perfectDayCelebration = false,
    this.lastCompletedId,
    this.isLoading = false,
    this.loadFailed = false,
    this.previousStreak = 0,
    this.milestoneCelebration,
    this.intentionsSetToday = false,
    this.totalGreenSquares = 0,
    this.streakEarnedToday = false,
    this.dailyGreenCounts = const {},
    this.categoryCompletions = const {},
    this.habitStreakCounts = const {},
    this.habitLongestStreaks = const {},
    this.habitTotalCompletions = const {},
    this.habitLastCompletedDate = const {},
    this.habitMilestoneCelebration,
    this.lastCompletionBonusXp = 0,
    this.lastCompletionBonusGold = 0,
    this.accountCreatedAt,
  });

  factory DashboardState.initial() => const DashboardState(
        level: 1,
        currentLevelXp: 0,
        cumulativeXp: 0,
        gold: 0,
        streak: 0,
        longestStreak: 0,
        totalCompletions: 0,
        streakFreezes: 1,
        completions: {},
        unlockedAchievements: [],
        newlyUnlocked: [],
        isLoading: true,
      );

  double get levelProgress =>
      XpCalculator.levelProgressRatio(currentLevelXp, level);
  int get xpToNext => XpCalculator.xpToNextLevel(level);
  bool isCompleted(String habitId, int target) =>
      (completions[habitId] ?? 0) >= target;

  /// The live current streak for a single habit — unlike reading
  /// [habitStreakCounts] directly, this returns 0 once more than a day has
  /// passed since [habitLastCompletedDate], so a habit that's actually been
  /// abandoned never keeps showing an inflated, stale streak.
  int habitStreak(String habitId) {
    final lastKey = habitLastCompletedDate[habitId];
    if (lastKey == null) return 0;
    final last = DateTime.tryParse(lastKey);
    if (last == null) return 0;
    final gap = DateTime.now()
        .effectiveDay
        .difference(DateTime(last.year, last.month, last.day))
        .inDays;
    return gap <= 1 ? (habitStreakCounts[habitId] ?? 0) : 0;
  }

  DashboardState copyWith({
    String? displayName,
    int? level,
    int? currentLevelXp,
    int? cumulativeXp,
    int? gold,
    int? streak,
    int? longestStreak,
    int? totalCompletions,
    int? streakFreezes,
    Map<String, int>? completions,
    List<String>? unlockedAchievements,
    List<AchievementModel>? newlyUnlocked,
    bool didJustLevelUp = false,
    bool didUseStreakFreeze = false,
    bool perfectDayCelebration = false,
    String? lastCompletedId,
    bool? isLoading,
    bool? loadFailed,
    int? previousStreak,
    int? setMilestone,
    bool clearMilestone = false,
    bool? intentionsSetToday,
    int? totalGreenSquares,
    bool? streakEarnedToday,
    Map<String, int>? dailyGreenCounts,
    Map<String, int>? categoryCompletions,
    Map<String, int>? habitStreakCounts,
    Map<String, int>? habitLongestStreaks,
    Map<String, int>? habitTotalCompletions,
    Map<String, String>? habitLastCompletedDate,
    HabitMilestoneEvent? setHabitMilestone,
    bool clearHabitMilestone = false,
    int? lastCompletionBonusXp,
    int? lastCompletionBonusGold,
    DateTime? accountCreatedAt,
  }) =>
      DashboardState(
        displayName: displayName ?? this.displayName,
        level: level ?? this.level,
        currentLevelXp: currentLevelXp ?? this.currentLevelXp,
        cumulativeXp: cumulativeXp ?? this.cumulativeXp,
        gold: gold ?? this.gold,
        streak: streak ?? this.streak,
        longestStreak: longestStreak ?? this.longestStreak,
        totalCompletions: totalCompletions ?? this.totalCompletions,
        streakFreezes: streakFreezes ?? this.streakFreezes,
        completions: completions ?? this.completions,
        unlockedAchievements:
            unlockedAchievements ?? this.unlockedAchievements,
        newlyUnlocked: newlyUnlocked ?? this.newlyUnlocked,
        didJustLevelUp: didJustLevelUp,
        didUseStreakFreeze: didUseStreakFreeze,
        perfectDayCelebration: perfectDayCelebration,
        lastCompletedId: lastCompletedId ?? this.lastCompletedId,
        isLoading: isLoading ?? this.isLoading,
        loadFailed: loadFailed ?? this.loadFailed,
        previousStreak: previousStreak ?? this.previousStreak,
        milestoneCelebration:
            clearMilestone ? null : (setMilestone ?? this.milestoneCelebration),
        intentionsSetToday: intentionsSetToday ?? this.intentionsSetToday,
        totalGreenSquares: totalGreenSquares ?? this.totalGreenSquares,
        streakEarnedToday: streakEarnedToday ?? this.streakEarnedToday,
        dailyGreenCounts: dailyGreenCounts ?? this.dailyGreenCounts,
        categoryCompletions: categoryCompletions ?? this.categoryCompletions,
        habitStreakCounts: habitStreakCounts ?? this.habitStreakCounts,
        habitLongestStreaks: habitLongestStreaks ?? this.habitLongestStreaks,
        habitTotalCompletions:
            habitTotalCompletions ?? this.habitTotalCompletions,
        habitLastCompletedDate:
            habitLastCompletedDate ?? this.habitLastCompletedDate,
        habitMilestoneCelebration: clearHabitMilestone
            ? null
            : (setHabitMilestone ?? this.habitMilestoneCelebration),
        lastCompletionBonusXp:
            lastCompletionBonusXp ?? this.lastCompletionBonusXp,
        lastCompletionBonusGold:
            lastCompletionBonusGold ?? this.lastCompletionBonusGold,
        accountCreatedAt: accountCreatedAt ?? this.accountCreatedAt,
      );
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  static const int streakFreezeCost = 100;
  static const int maxStreakFreezes = 3;
  static const int comebackBonusXp = 50;
  /// Max length for a user-chosen display name — generous enough for most
  /// real names while keeping the Profile hero header from wrapping.
  static const int maxDisplayNameLength = 24;

  final String? _uid;
  // Injectable for tests; defaults to a real Random in production — same
  // pattern QuickWinsNotifier already uses for its own randomized picks.
  final Random _random;

  /// habitId → snapshot of that habit's per-habit fields from the instant
  /// before its most recent [completeHabit] call touched them — see
  /// [_HabitCompletionSnapshot]. Deliberately in-memory only, never
  /// persisted: it exists purely so a same-session [uncompleteHabit] can
  /// reverse a completion precisely, and survives a plain app
  /// background/resume (this notifier instance isn't recreated for that —
  /// only a full app restart clears it), which is exactly the window a
  /// mis-tap correction actually happens in.
  final Map<String, _HabitCompletionSnapshot> _lastHabitCompletion = {};

  DashboardNotifier(this._uid, {Random? random})
      : _random = random ?? Random(),
        super(DashboardState.initial()) {
    if (_uid != null) {
      _loadToday();
    } else {
      _loadGuestToday();
    }
  }

  // ── Helpers ─────────────────────────────────────────────────

  static String get _todayKey => DateTime.now().effectiveDay.toDateKey();

  static String get _weekKey {
    final today = DateTime.now().effectiveDay;
    final monday = today.subtract(Duration(days: today.weekday - DateTime.monday));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  DocumentReference<Map<String, dynamic>> get _dailyRef =>
      _userRef.collection('daily').doc(_todayKey);

  /// The shared, append-only history behind Journey Page / Monthly Story /
  /// Legacy Shelf — see MilestoneEvent's own doc comment. completeHabit is
  /// the only writer today; it appends directly to the same batch as the
  /// reward write below rather than going through the standalone
  /// logMilestoneEvent() helper (milestone_notifier.dart), so a level-up
  /// and its milestone entry either both land or both don't.
  CollectionReference<Map<String, dynamic>> get _milestonesRef =>
      _userRef.collection('milestones');
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return DashboardNotifier(uid);
});
