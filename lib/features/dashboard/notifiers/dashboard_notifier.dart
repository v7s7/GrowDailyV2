import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/game_constants.dart';
import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/xp_calculator.dart';
import '../../../features/achievements/models/achievement_model.dart';
import '../../auth/notifiers/auth_notifier.dart';

/// Streak-day thresholds that trigger a milestone celebration, derived from
/// [GameConstants.streakBonuses] so the thresholds and their XP payouts
/// can't drift apart into two different lists.
final List<int> kStreakMilestones = GameConstants.streakBonuses.keys.toList();

/// One-time XP bonus for reaching [milestone] days — delegates to
/// [XpCalculator.streakMilestoneBonus] (backed by [GameConstants]) so this
/// isn't a second, independently-editable copy of the same numbers.
int milestoneXpBonus(int milestone) =>
    XpCalculator.streakMilestoneBonus(milestone);

/// Whether completing [habitId] (today, toward [frequencyTarget]) leaves
/// *every* one of today's scheduled habits done — the "100%" moment that
/// earns the day's streak point (see [DashboardState.streakEarnedToday]
/// and [DashboardNotifier.completeHabit]).
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
  for (final h in todayHabits) {
    final isTarget = h.id == habitId;
    if (isTarget) sawTarget = true;
    final done = isTarget
        ? (state.completions[h.id] ?? 0) + 1 >= frequencyTarget
        : state.isCompleted(h.id, h.frequencyTarget);
    if (!done) return false;
  }
  // An empty (or habitId-missing) list is never "100%" — a day with
  // nothing scheduled isn't a completed day, it's a day off.
  return sawTarget;
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
  /// Streak means a full day — every one of today's scheduled habits done
  /// (see [willCompleteAllHabitsToday]) — not just "did something today",
  /// so this is only ever set the instant that 100% is first reached. It's
  /// the single explicit gate [completeHabit] checks before bumping the
  /// streak, replacing what used to be three separate places each
  /// re-guessing "did today already count" from [completions]/grid state;
  /// one persisted boolean can't be fooled by reload timing the way an
  /// inferred guess could, and — because it can only flip false→true once
  /// per calendar day — it's also what guarantees the streak can never
  /// climb by more than 1 per day (so, e.g., 7 real days can never produce
  /// more than a 7-day streak). Deliberately sticky: once true, adding a
  /// *new* habit later today (which lowers today's completion percentage
  /// back below 100%) does not revoke it — see [completeHabit]'s doc
  /// comment for why that's the intended behavior, not a bug.
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
      );
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  static const int streakFreezeCost = 100;
  static const int maxStreakFreezes = 3;
  static const int comebackBonusXp = 50;

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

  // ── Load ─────────────────────────────────────────────────────


  Future<void> _loadGuestToday() async {
    try {
      final saved = await LocalStoreService.getSettingsMap(
        LocalStoreService.guestDashboardKey,
      );
      final daily = await LocalStoreService.getDailyMap(_todayKey);
      final rawCompletions =
          (daily['habitCompletions'] as Map?)?.cast<String, dynamic>() ?? {};
      final completions = rawCompletions.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      );
      final streakEarnedToday = (daily['streakEarnedToday'] as bool?) ?? false;
      final intentionsSetToday = (daily['intentionsSet'] as bool?) ?? false;
      final rawGreenCounts =
          (saved['dailyGreenCounts'] as Map?)?.cast<String, dynamic>() ?? {};
      final dailyGreenCounts = rawGreenCounts.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      );
      final rawCategoryCompletions =
          (saved['categoryCompletions'] as Map?)?.cast<String, dynamic>() ??
              {};
      final categoryCompletions = rawCategoryCompletions.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      );
      final rawHabitStreakCounts =
          (saved['habitStreakCounts'] as Map?)?.cast<String, dynamic>() ??
              {};
      final habitStreakCounts = rawHabitStreakCounts.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      );
      final rawHabitLongestStreaks =
          (saved['habitLongestStreaks'] as Map?)?.cast<String, dynamic>() ??
              {};
      final habitLongestStreaks = rawHabitLongestStreaks.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      );
      final rawHabitTotalCompletions =
          (saved['habitTotalCompletions'] as Map?)?.cast<String, dynamic>() ??
              {};
      final habitTotalCompletions = rawHabitTotalCompletions.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      );
      final habitLastCompletedDate = (saved['habitLastCompletedDate'] as Map?)
              ?.cast<String, dynamic>()
              .map((key, value) => MapEntry(key, value as String)) ??
          {};

      int streak = (saved['currentStreak'] as int?) ?? 0;
      int streakFreezes = (saved['streakFreezes'] as int?) ?? 1;
      // Persisted, not re-derived — see DashboardState.previousStreak's doc
      // comment for why this can no longer be a fresh-every-load local.
      int previousStreak = (saved['previousStreak'] as int?) ?? 0;
      bool didUseStreakFreeze = false;
      final lastActive = DateTime.tryParse(saved['lastActiveDate'] as String? ?? '');

      if (lastActive != null) {
        final today = DateTime.now().effectiveDay;
        final lastDay = _dateOnly(lastActive);
        final yesterday = today.subtract(const Duration(days: 1));
        final gapDays = today.difference(lastDay).inDays;
        if (gapDays > 1) {
          if (gapDays == 2 && streak > 0 && streakFreezes > 0) {
            streakFreezes -= 1;
            didUseStreakFreeze = true;
            saved['streakFreezes'] = streakFreezes;
            saved['lastActiveDate'] = yesterday.toIso8601String();
            await LocalStoreService.putSettingsMap(
              LocalStoreService.guestDashboardKey,
              saved,
            );
          } else {
            if (streak > 0) {
              previousStreak = streak;
              saved['previousStreak'] = previousStreak;
            }
            streak = 0;
            saved['currentStreak'] = 0;
            await LocalStoreService.putSettingsMap(
              LocalStoreService.guestDashboardKey,
              saved,
            );
          }
        }
      }

      if (!mounted) return;
      state = DashboardState(
        displayName: (saved['displayName'] as String?) ?? '',
        level: (saved['level'] as int?) ?? 1,
        currentLevelXp: (saved['currentLevelXp'] as int?) ?? 0,
        cumulativeXp: (saved['cumulativeXp'] as int?) ?? 0,
        gold: (saved['gold'] as int?) ?? 0,
        streak: streak,
        longestStreak: (saved['longestStreak'] as int?) ?? 0,
        totalCompletions: (saved['totalHabitCompletions'] as int?) ?? 0,
        streakFreezes: streakFreezes,
        completions: completions,
        unlockedAchievements:
            List<String>.from(saved['unlockedAchievements'] as List? ?? []),
        didUseStreakFreeze: didUseStreakFreeze,
        previousStreak: previousStreak,
        isLoading: false,
        intentionsSetToday: intentionsSetToday,
        totalGreenSquares: (saved['totalGreenSquares'] as int?) ?? 0,
        streakEarnedToday: streakEarnedToday,
        dailyGreenCounts: dailyGreenCounts,
        categoryCompletions: categoryCompletions,
        habitStreakCounts: habitStreakCounts,
        habitLongestStreaks: habitLongestStreaks,
        habitTotalCompletions: habitTotalCompletions,
        habitLastCompletedDate: habitLastCompletedDate,
      );
    } catch (_) {
      if (mounted) state = DashboardState.initial().copyWith(isLoading: false);
    }
  }

  Future<void> _saveGuestState({DateTime? lastActiveDate}) async {
    final saved = await LocalStoreService.getSettingsMap(
      LocalStoreService.guestDashboardKey,
    );
    await LocalStoreService.putSettingsMap(
      LocalStoreService.guestDashboardKey,
      {
        ...saved,
        'displayName': state.displayName,
        'level': state.level,
        'currentLevelXp': state.currentLevelXp,
        'cumulativeXp': state.cumulativeXp,
        'gold': state.gold,
        'currentStreak': state.streak,
        'longestStreak': state.longestStreak,
        'totalHabitCompletions': state.totalCompletions,
        'streakFreezes': state.streakFreezes,
        'previousStreak': state.previousStreak,
        'unlockedAchievements': state.unlockedAchievements,
        'totalGreenSquares': state.totalGreenSquares,
        'dailyGreenCounts': state.dailyGreenCounts,
        'categoryCompletions': state.categoryCompletions,
        'habitStreakCounts': state.habitStreakCounts,
        'habitLongestStreaks': state.habitLongestStreaks,
        'habitTotalCompletions': state.habitTotalCompletions,
        'habitLastCompletedDate': state.habitLastCompletedDate,
        if (lastActiveDate != null)
          'lastActiveDate': lastActiveDate.toIso8601String(),
      },
    );
  }

  Future<void> _saveGuestDaily(
    Map<String, int> completions, {
    bool? streakEarnedToday,
  }) async {
    final existing = await LocalStoreService.getDailyMap(_todayKey);
    await LocalStoreService.putDailyMap(
      _todayKey,
      {
        ...existing,
        'habitCompletions': completions,
        'date': DateTime.now().effectiveDay.toIso8601String(),
        if (streakEarnedToday != null) 'streakEarnedToday': streakEarnedToday,
      },
    );
  }

  // Fields left over from the old GrowDaily v1 schema (this project reused
  // an existing Firebase database) — confirmed by a full search of this
  // codebase that nothing anywhere reads any of these anymore. Kept as an
  // explicit, named list rather than just deleting-and-forgetting so it's
  // obvious later *why* a user doc briefly gets an extra merge-write on
  // load: 'streak'/'name' in particular used to sit right next to the
  // still-live 'currentStreak'/'displayName' and are exactly the kind of
  // near-duplicate that misleads whoever reads this data next. See
  // _scrubLegacyV1Fields below for how this list gets used.
  static const _legacyV1Keys = [
    'name', 'streak', 'totalPoints', 'availablePoints', 'lastStreakDate',
    'plan', 'todoTasks', 'taskRepeats', 'completedTasks',
    'dailyPointsEarned', 'dailySubmissions', 'eisenhowerColors',
    'eisenhowerTasks', 'gym', 'gymPoints', 'quran', 'quranPoints', 'study',
    'hydration', 'waterPoints', 'waterSubmissions', 'showerPoints',
    'phonePoints', 'masaa_athkar', 'masaa_athkarPoints', 'sabah_athkar',
    'sabah_athkarPoints',
  ];

  /// One-time cleanup, called from [_loadToday] right after reading the
  /// user doc. Self-healing rather than a bulk migration script: every
  /// signed-in user's next normal app open checks their own doc for any
  /// of [_legacyV1Keys] and — only if at least one is actually still
  /// present — fires a single merge-write deleting just those keys.
  /// Nothing to do (and nothing written) once a doc's already been
  /// cleaned, so this naturally stops costing anything after the first
  /// successful run per user. Fire-and-forget like every other background
  /// write in this method (streak-freeze grants, streak reset) — a v1
  /// field lingering one extra app open because this particular write
  /// failed isn't worth blocking the load over.
  void _scrubLegacyV1Fields(Map<String, dynamic> d) {
    final present = _legacyV1Keys.where(d.containsKey);
    if (present.isEmpty) return;
    _userRef.set({
      for (final key in present) key: FieldValue.delete(),
    }, SetOptions(merge: true)).ignore();
  }

  Future<void> _loadToday() async {
    if (_uid == null) return;
    try {
      final results = await Future.wait([_userRef.get(), _dailyRef.get()]);
      final userSnap = results[0];
      final dailySnap = results[1];

      String displayName = '';
      int level = 1,
          currentLevelXp = 0,
          cumulativeXp = 0,
          gold = 0,
          streak = 0,
          longestStreak = 0,
          totalCompletions = 0,
          streakFreezes = 1,
          previousStreak = 0;
      bool didUseStreakFreeze = false;
      List<String> unlockedAchievements = [];
      Map<String, int> completions = {};
      bool intentionsSetToday = false;
      bool streakEarnedToday = false;
      int totalGreenSquares = 0;
      Map<String, int> dailyGreenCounts = {};
      Map<String, int> categoryCompletions = {};
      Map<String, int> habitStreakCounts = {};
      Map<String, int> habitLongestStreaks = {};
      Map<String, int> habitTotalCompletions = {};
      Map<String, String> habitLastCompletedDate = {};

      if (userSnap.exists) {
        final d = userSnap.data()!;
        _scrubLegacyV1Fields(d);
        displayName = (d['displayName'] as String?) ?? '';
        level = (d['level'] as int?) ?? 1;
        currentLevelXp = (d['currentLevelXp'] as int?) ?? 0;
        cumulativeXp = (d['cumulativeXp'] as int?) ?? 0;
        gold = (d['gold'] as int?) ?? 0;
        streak = (d['currentStreak'] as int?) ?? 0;
        longestStreak = (d['longestStreak'] as int?) ?? 0;
        totalCompletions = (d['totalHabitCompletions'] as int?) ?? 0;
        streakFreezes = (d['streakFreezes'] as int?) ?? 1;
        // Persisted, not re-derived — see DashboardState.previousStreak's
        // doc comment for why this can no longer be a fresh-every-load
        // local.
        previousStreak = (d['previousStreak'] as int?) ?? 0;
        final lastFreezeGrantWeek = d['lastFreezeGrantWeek'] as String?;
        unlockedAchievements =
            List<String>.from(d['unlockedAchievements'] as List? ?? []);
        totalGreenSquares = (d['totalGreenSquares'] as int?) ?? 0;
        final rawGreenCounts =
            (d['dailyGreenCounts'] as Map?)?.cast<String, dynamic>() ?? {};
        dailyGreenCounts = rawGreenCounts.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
        // ── One-time repair of the dotted-key heatmap bug ─────────
        // dailyGreenCounts increments used to be written as
        // 'dailyGreenCounts.<dateKey>' string keys inside set(merge:
        // true) — but dot notation is only a field *path* in update();
        // in set() it's a literal field name. So every completion landed
        // on a junk top-level field literally named
        // "dailyGreenCounts.2026-07-17" while the real map stayed empty,
        // which is why the Monthly Heatmap blanked on every restart. The
        // counts themselves are intact in those junk fields (the atomic
        // increments worked fine, just against the wrong field name) —
        // fold them back into the real map and delete the junk, healing
        // the doc in place. After one pass this finds nothing and costs
        // a single keys scan. FieldValue.delete() is valid inside
        // set(merge: true), and set()'s literal-key handling is exactly
        // what lets each delete target its dotted-name junk field.
        final junkGreenKeys =
            d.keys.where((k) => k.startsWith('dailyGreenCounts.')).toList();
        if (junkGreenKeys.isNotEmpty) {
          for (final junkKey in junkGreenKeys) {
            final dateKey = junkKey.substring('dailyGreenCounts.'.length);
            final junkCount = (d[junkKey] as num?)?.toInt() ?? 0;
            final merged = (dailyGreenCounts[dateKey] ?? 0) + junkCount;
            dailyGreenCounts[dateKey] = merged < 0 ? 0 : merged;
          }
          _userRef.set({
            'dailyGreenCounts': dailyGreenCounts,
            for (final junkKey in junkGreenKeys)
              junkKey: FieldValue.delete(),
          }, SetOptions(merge: true)).ignore();
        }
        final rawCategoryCompletions =
            (d['categoryCompletions'] as Map?)?.cast<String, dynamic>() ?? {};
        categoryCompletions = rawCategoryCompletions.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
        final rawHabitStreakCounts =
            (d['habitStreakCounts'] as Map?)?.cast<String, dynamic>() ?? {};
        habitStreakCounts = rawHabitStreakCounts.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
        final rawHabitLongestStreaks =
            (d['habitLongestStreaks'] as Map?)?.cast<String, dynamic>() ?? {};
        habitLongestStreaks = rawHabitLongestStreaks.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
        final rawHabitTotalCompletions =
            (d['habitTotalCompletions'] as Map?)?.cast<String, dynamic>() ??
                {};
        habitTotalCompletions = rawHabitTotalCompletions.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
        habitLastCompletedDate = (d['habitLastCompletedDate'] as Map?)
                ?.cast<String, dynamic>()
                .map((key, value) => MapEntry(key, value as String)) ??
            {};

        final lastActiveTs = d['lastActiveDate'] as Timestamp?;
        if (lastActiveTs != null) {
          final today = DateTime.now().effectiveDay;
          final lastDay = _dateOnly(lastActiveTs.toDate());
          final yesterday = today.subtract(const Duration(days: 1));
          final gapDays = today.difference(lastDay).inDays;
          if (gapDays > 1) {
            if (gapDays == 2 && streak > 0 && streakFreezes > 0) {
              streakFreezes -= 1;
              didUseStreakFreeze = true;
              _userRef.set({
                'streakFreezes': streakFreezes,
                'lastActiveDate': Timestamp.fromDate(yesterday),
              }, SetOptions(merge: true)).ignore();
            } else {
              if (streak > 0) {
                previousStreak = streak;
              }
              streak = 0;
              _userRef.set({
                'currentStreak': 0,
                if (previousStreak > 0) 'previousStreak': previousStreak,
              }, SetOptions(merge: true)).ignore();
            }
          }
        }

        if (level >= 5 &&
            streakFreezes < maxStreakFreezes &&
            lastFreezeGrantWeek != _weekKey) {
          streakFreezes += 1;
          _userRef.set({
            'streakFreezes': streakFreezes,
            'lastFreezeGrantWeek': _weekKey,
          }, SetOptions(merge: true)).ignore();
        }
      }

      if (dailySnap.exists) {
        final d = dailySnap.data()!;
        final raw =
            (d['habitCompletions'] as Map<String, dynamic>?) ?? {};
        completions =
            raw.map((k, v) => MapEntry(k, (v as num).toInt()));
        intentionsSetToday = (d['intentionsSet'] as bool?) ?? false;
        streakEarnedToday = (d['streakEarnedToday'] as bool?) ?? false;
      }

      if (mounted) {
        state = DashboardState(
          displayName: displayName,
          level: level,
          currentLevelXp: currentLevelXp,
          cumulativeXp: cumulativeXp,
          gold: gold,
          streak: streak,
          longestStreak: longestStreak,
          totalCompletions: totalCompletions,
          streakFreezes: streakFreezes,
          completions: completions,
          unlockedAchievements: unlockedAchievements,
          newlyUnlocked: const [],
          didUseStreakFreeze: didUseStreakFreeze,
          isLoading: false,
          previousStreak: previousStreak,
          intentionsSetToday: intentionsSetToday,
          totalGreenSquares: totalGreenSquares,
          streakEarnedToday: streakEarnedToday,
          dailyGreenCounts: dailyGreenCounts,
          categoryCompletions: categoryCompletions,
          habitStreakCounts: habitStreakCounts,
          habitLongestStreaks: habitLongestStreaks,
          habitTotalCompletions: habitTotalCompletions,
          habitLastCompletedDate: habitLastCompletedDate,
        );
      }
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  // ── Streak helper ────────────────────────────────────────────

  /// Advances the day-streak by one and reports any milestone crossed.
  /// The only caller is [completeHabit], at the exact moment today's
  /// habits first reach 100% — see [DashboardState.streakEarnedToday].
  ({int streak, int longestStreak, int? milestone, int milestoneBonusXp})
      _computeStreakBump() {
    final newStreak = state.streak + 1;
    final newLongest =
        newStreak > state.longestStreak ? newStreak : state.longestStreak;
    int? newMilestone;
    for (final m in kStreakMilestones) {
      if (newStreak == m && state.streak < m) {
        newMilestone = m;
        break;
      }
    }
    final bonus = newMilestone != null ? milestoneXpBonus(newMilestone) : 0;
    return (
      streak: newStreak,
      longestStreak: newLongest,
      milestone: newMilestone,
      milestoneBonusXp: bonus,
    );
  }

  // ── Actions ──────────────────────────────────────────────────

  /// Completes a habit for today — the single canonical reward path for
  /// "a habit was done today", called from both Today's habit list and
  /// Grid's square tap (see [markCompleteFromHabit] on `WeeklyGridNotifier`
  /// for the visual-only mirror the other screen uses).
  ///
  /// Returns whether this call just finished a *single-tap*
  /// (`frequencyTarget == 1`) habit. This is narrower than "did it
  /// succeed" — Today's own button and the notification action handler
  /// use it to decide whether *their* completion should also paint
  /// today's Grid square green, which only makes sense for single-tap
  /// habits: a multi-tap (`frequencyTarget > 1`, e.g. "3x this week")
  /// habit finishing one tap from Today shouldn't turn the square fully
  /// green, since a single square can't cleanly represent "2 of 3 this
  /// week". Grid's own square tap (grid_screen.dart) doesn't read this
  /// return value at all — it already knows the user just painted that
  /// exact square, for any frequencyTarget, so it mirrors unconditionally
  /// once its own pre-check confirms the completion isn't a no-op. Also
  /// returns `false` if the habit was already done today (no new
  /// completion registered at all).
  ///
  /// [allHabitsDoneAfter] answers "once this completion lands, will every
  /// one of today's scheduled habits be done?" — the caller computes this
  /// (see [willCompleteAllHabitsToday]) because only it has today's full
  /// habit list; this method only ever sees one habit at a time. That
  /// answer is what decides whether *today* just earned its once-per-day
  /// streak point (see [DashboardState.streakEarnedToday] for the full
  /// reasoning) — completing your 1st of 3 habits today no longer bumps
  /// the streak, only completing your 3rd does.
  Future<bool> completeHabit({
    required String habitId,
    required int xpReward,
    required int goldReward,
    required int frequencyTarget,
    required bool allHabitsDoneAfter,
    String? category,
    String? habitName,
  }) async {
    final current = state.completions[habitId] ?? 0;
    if (current >= frequencyTarget) return false;

    final newCompletions = Map<String, int>.from(state.completions)
      ..[habitId] = current + 1;

    // ── Per-habit streak bump ────────────────────────────────
    //
    // Fires once per habit per day — `current == 0` means this is the
    // first completion of *this specific habit* today. Unlike the
    // app-wide streak bump below (which needs *every* habit done), this
    // per-habit one only cares about this one habit, so it still fires on
    // habit 1 of 3. A weekly habit tapped 3 separate days still bumps 3
    // times; nothing here double-counts a same-day multi-tap because
    // current is already > 0 by the second tap.
    final newHabitStreakCounts = {...state.habitStreakCounts};
    final newHabitLongestStreaks = {...state.habitLongestStreaks};
    final newHabitTotalCompletions = {...state.habitTotalCompletions};
    final newHabitLastCompletedDate = {...state.habitLastCompletedDate};
    // Set only when this completion just crossed one of
    // GameConstants.habitStreakBonuses' thresholds — see below.
    HabitMilestoneEvent? newHabitMilestoneEvent;
    int habitMilestoneBonusXp = 0;
    if (current == 0) {
      final lastKey = state.habitLastCompletedDate[habitId];
      final last = lastKey == null ? null : DateTime.tryParse(lastKey);
      final gap = last == null
          ? null
          : DateTime.now().effectiveDay.difference(_dateOnly(last)).inDays;
      final prevStreak = state.habitStreakCounts[habitId] ?? 0;
      // Only a same-day-yesterday completion continues the streak; a gap of
      // 0 (shouldn't happen given the `current == 0` guard, but defensive),
      // 2+, or no prior completion at all all restart it at 1.
      final newHabitStreak = gap == 1 ? prevStreak + 1 : 1;
      newHabitStreakCounts[habitId] = newHabitStreak;
      final prevLongest = state.habitLongestStreaks[habitId] ?? 0;
      newHabitLongestStreaks[habitId] =
          newHabitStreak > prevLongest ? newHabitStreak : prevLongest;
      newHabitTotalCompletions[habitId] =
          (state.habitTotalCompletions[habitId] ?? 0) + 1;
      newHabitLastCompletedDate[habitId] = _todayKey;

      // ── Per-habit milestone ──────────────────────────────────
      final habitBonus = GameConstants.habitStreakBonuses[newHabitStreak];
      if (habitBonus != null) {
        habitMilestoneBonusXp = habitBonus;
        newHabitMilestoneEvent = HabitMilestoneEvent(
          habitId: habitId,
          habitName: habitName ?? habitId,
          milestone: newHabitStreak,
          bonusXp: habitBonus,
        );
      }
    }

    // ── Surprise bonus ───────────────────────────────────────────
    //
    // A small, independent chance on *every* completion (not gated to the
    // day's first, unlike the streak logic above — this rewards the single
    // action, not "did something today"). Always additive on top of the
    // normal reward, capped at half again its size — see
    // GameConstants.surpriseBonusChance for the reasoning.
    final rolledBonus = _random.nextDouble() < GameConstants.surpriseBonusChance;
    final surpriseBonusXp = rolledBonus
        ? (xpReward * GameConstants.surpriseBonusMultiplier).ceil()
        : 0;
    final surpriseBonusGold = rolledBonus
        ? (goldReward * GameConstants.surpriseBonusMultiplier).ceil()
        : 0;

    // ── Same-day-undo snapshot ───────────────────────────────────
    //
    // Only meaningful on the tap that actually changed the per-habit
    // fields above (current == 0) — a later same-day tap on a multi-tap
    // habit leaves them untouched, so it leaves whatever snapshot the
    // day's first tap already recorded in place. uncompleteHabit's
    // .remove() wipes the whole day's taps at once regardless of how many
    // there were, so that first-tap snapshot is still the right one to
    // reverse against — see uncompleteHabit's doc comment.
    if (current == 0) {
      _lastHabitCompletion[habitId] = _HabitCompletionSnapshot(
        hadPrior: state.habitLastCompletedDate.containsKey(habitId),
        prevStreak: state.habitStreakCounts[habitId] ?? 0,
        prevLongest: state.habitLongestStreaks[habitId] ?? 0,
        prevTotal: state.habitTotalCompletions[habitId] ?? 0,
        prevLastCompletedDate: state.habitLastCompletedDate[habitId],
        bonusXp: habitMilestoneBonusXp + surpriseBonusXp,
        bonusGold: surpriseBonusGold,
      );
    }

    // Only single-tap habits are synced with the Grid in this phase — see
    // the doc comment above.
    final isGridSyncable = frequencyTarget == 1;

    // ── App-wide streak bump ─────────────────────────────────────
    //
    // See [DashboardState.streakEarnedToday] for the full reasoning; in
    // short, this only fires the instant today's habits go from "not all
    // done" to "all done" (never on the 1st of N, only the Nth), it can
    // only ever fire once per calendar day, and once it fires it stays
    // earned for the rest of the day even if a new habit gets added later.
    final justReachedAllDone =
        allHabitsDoneAfter && !state.streakEarnedToday;
    final newStreakEarnedToday = state.streakEarnedToday || justReachedAllDone;
    // A real, freshly-earned streak day supersedes any stale "restore your
    // old streak with a freeze" offer still sitting around from a past
    // loss — see DashboardState.previousStreak's doc comment. Without
    // this, someone who ignores the comeback card and just starts
    // completing habits again would keep the offer dangling indefinitely,
    // and using it later would clobber the real progress they've since
    // rebuilt.
    final clearsPendingComeback = justReachedAllDone && state.previousStreak > 0;
    final bump = justReachedAllDone
        ? _computeStreakBump()
        : (
            streak: state.streak,
            longestStreak: state.longestStreak,
            milestone: null,
            milestoneBonusXp: 0,
          );
    final newStreak = bump.streak;
    final newLongest = bump.longestStreak;
    final newMilestone = bump.milestone;
    final milestoneBonusXp = bump.milestoneBonusXp;

    final result = XpCalculator.applyXpGain(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpGained:
          xpReward + milestoneBonusXp + habitMilestoneBonusXp + surpriseBonusXp,
    );
    final newGold = state.gold + goldReward + surpriseBonusGold;
    final newTotal = state.totalCompletions + 1;

    final newCategoryCompletions = {...state.categoryCompletions};
    if (category != null) {
      newCategoryCompletions[category] =
          (newCategoryCompletions[category] ?? 0) + 1;
    }

    // Every completion counts toward the heatmap and the lifetime
    // green-squares total — regardless of isGridSyncable. isGridSyncable
    // only answers "can this mirror onto a *specific Grid square's
    // color*" (a single square can't cleanly represent "2 of 3 this
    // week" for a multi-tap habit — see the doc comment above); it was
    // never meant to also gate whether the day *happened* at all. Gating
    // this increment on it too was a real bug: a habit tracked purely
    // through Today (never touching its Grid square directly) with a
    // frequencyTarget > 1 silently never showed up on the Monthly
    // Heatmap, on any day, ever — "I did my habits but the heatmap is
    // blank" with no obvious cause. Forward-only: this only ever touches
    // today's dateKey, never rewrites or backfills earlier days. The
    // guard above (`current >= frequencyTarget`) already makes this at
    // most a one-time bump per habit per day, same as everything else in
    // this method.
    final newTotalGreenSquares = state.totalGreenSquares + 1;
    final newDailyGreenCounts = {...state.dailyGreenCounts};
    newDailyGreenCounts[_todayKey] =
        (newDailyGreenCounts[_todayKey] ?? 0) + 1;

    // ── Achievement check ────────────────────────────────────
    final newly = AchievementCatalog.locked(state.unlockedAchievements)
        .where((a) => switch (a.trigger) {
              AchievementTrigger.streak => newStreak >= a.threshold,
              AchievementTrigger.level =>
                result.newLevel >= a.threshold,
              AchievementTrigger.totalCompletions =>
                newTotal >= a.threshold,
              AchievementTrigger.habitMastery => a.targetCategory != null &&
                  (newCategoryCompletions[a.targetCategory] ?? 0) >=
                      a.threshold,
              AchievementTrigger.greenSquares =>
                newTotalGreenSquares >= a.threshold,
              _ => false,
            })
        .toList();

    final newUnlockedIds = [
      ...state.unlockedAchievements,
      ...newly.map((a) => a.id),
    ];

    // XP + gold bonus from achievements
    int bonusXp = newly.fold(0, (s, a) => s + a.xpReward);
    int bonusGold = newly.fold(0, (s, a) => s + a.goldReward);
    final bonusResult = bonusXp > 0
        ? XpCalculator.applyXpGain(
            currentLevel: result.newLevel,
            currentLevelXp: result.newCurrentLevelXp,
            cumulativeXp: result.newCumulativeXp,
            xpGained: bonusXp,
          )
        : (
            newLevel: result.newLevel,
            newCurrentLevelXp: result.newCurrentLevelXp,
            newCumulativeXp: result.newCumulativeXp,
          );

    AnalyticsService.instance.track('habit_completed', props: {
      'habitId': habitId,
      'streak': newStreak,
      'allHabitsDoneAfter': allHabitsDoneAfter,
      'streakJustEarned': justReachedAllDone,
      'milestone': newMilestone,
    });

    final didLevelUp = bonusResult.newLevel > state.level;

    state = state.copyWith(
      level: bonusResult.newLevel,
      currentLevelXp: bonusResult.newCurrentLevelXp,
      cumulativeXp: bonusResult.newCumulativeXp,
      gold: newGold + bonusGold,
      streak: newStreak,
      longestStreak: newLongest,
      streakEarnedToday: newStreakEarnedToday,
      previousStreak: clearsPendingComeback ? 0 : null,
      totalCompletions: newTotal,
      completions: newCompletions,
      unlockedAchievements: newUnlockedIds,
      newlyUnlocked: newly,
      didJustLevelUp: didLevelUp,
      // The exact completion that finished today's whole list — same
      // justReachedAllDone moment that earns the streak point, so this can
      // fire at most once per day and never from a backfilled past square.
      perfectDayCelebration: justReachedAllDone,
      lastCompletedId: habitId,
      setMilestone: newMilestone,
      categoryCompletions: newCategoryCompletions,
      totalGreenSquares: newTotalGreenSquares,
      dailyGreenCounts: newDailyGreenCounts,
      habitStreakCounts: newHabitStreakCounts,
      habitLongestStreaks: newHabitLongestStreaks,
      habitTotalCompletions: newHabitTotalCompletions,
      habitLastCompletedDate: newHabitLastCompletedDate,
      setHabitMilestone: newHabitMilestoneEvent,
      lastCompletionBonusXp: surpriseBonusXp,
      lastCompletionBonusGold: surpriseBonusGold,
    );

    _fireCompletionNotifications(
      habitId: habitName ?? habitId,
      xpEarned: xpReward +
          milestoneBonusXp +
          habitMilestoneBonusXp +
          surpriseBonusXp,
      goldEarned: goldReward + surpriseBonusGold,
      didLevelUp: didLevelUp,
      newLevel: bonusResult.newLevel,
      newlyUnlocked: newly,
    );

    if (_uid == null) {
      await _saveGuestDaily(newCompletions, streakEarnedToday: newStreakEarnedToday);
      await _saveGuestState(lastActiveDate: DateTime.now().effectiveDay);
      return isGridSyncable;
    }

    try {
      // .effectiveDay, not the raw instant — this feeds 'lastActiveDate',
      // which the streak-gap comparisons above (habitStreak,
      // completeHabit's per-habit gap, _loadToday/_loadGuestToday's
      // app-wide gap) all read back assuming it's already day-cutoff
      // aligned. See DateTimeGameExt.effectiveDay's doc comment.
      final now = DateTime.now().effectiveDay;
      final batch = FirebaseFirestore.instance.batch();

      batch.set(
        _dailyRef,
        {
          'habitCompletions': newCompletions,
          'date': Timestamp.fromDate(now),
          'streakEarnedToday': newStreakEarnedToday,
        },
        SetOptions(merge: true),
      );

      batch.set(
        _userRef,
        {
          'level': bonusResult.newLevel,
          'currentLevelXp': bonusResult.newCurrentLevelXp,
          'cumulativeXp': bonusResult.newCumulativeXp,
          'gold': newGold + bonusGold,
          'currentStreak': newStreak,
          'longestStreak': newLongest,
          if (clearsPendingComeback) 'previousStreak': 0,
          'totalHabitCompletions': newTotal,
          'unlockedAchievements': newUnlockedIds,
          'categoryCompletions': newCategoryCompletions,
          'lastActiveDate': Timestamp.fromDate(now),
          'habitStreakCounts': newHabitStreakCounts,
          'habitLongestStreaks': newHabitLongestStreaks,
          'habitTotalCompletions': newHabitTotalCompletions,
          'habitLastCompletedDate': newHabitLastCompletedDate,
          // Same fields Grid's own applyGridSquareChange writes — no new
          // schema, just a second writer here. Unconditional (every
          // completion, not just isGridSyncable ones — see the doc
          // comment above newTotalGreenSquares) so a multi-tap habit
          // tracked only through Today still shows up on the heatmap.
          //
          // A nested map, NOT a dotted 'dailyGreenCounts.$_todayKey' key:
          // dot notation is only a field *path* in update() — inside
          // set(merge: true) it's a literal field name, so the dotted
          // form was creating junk top-level fields named
          // "dailyGreenCounts.2026-07-17" that the loader (which reads
          // the real map) never saw. That was the whole "heatmap is
          // empty after every restart" bug; _load's one-time repair
          // folds the stranded junk fields back in. merge: true merges
          // maps per-leaf-field, so this increments just today's entry
          // without touching other days.
          'totalGreenSquares': FieldValue.increment(1),
          'dailyGreenCounts': {_todayKey: FieldValue.increment(1)},
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (_) {}
    return isGridSyncable;
  }

  /// Reverses a same-day completion made via [completeHabit] — the "I
  /// completed this by mistake" correction available from Grid's
  /// long-press editor on a synced, completed-today square, and from
  /// quit-habit's affirm→slip mis-tap correction. Always operates on
  /// *today* (there's no "edit yesterday's completion" concept anywhere in
  /// this app).
  ///
  /// Reverses what's safe to reverse: the base XP/gold the caller passes
  /// in, plus — via [_lastHabitCompletion], when a same-session record of
  /// this exact completion exists — the surprise-bonus/per-habit-milestone
  /// XP/Gold it awarded, and the `habitStreakCounts` /
  /// `habitLongestStreaks` / `habitTotalCompletions` /
  /// `habitLastCompletedDate` bump for this one habit. Also always
  /// reverses `completions[habitId]` (back to not-done so Today un-checks
  /// it too), `categoryCompletions`, `totalCompletions`, and the
  /// `totalGreenSquares`/`dailyGreenCounts` counters this phase added for
  /// synced completions.
  ///
  /// Without a snapshot (the app was fully restarted between the
  /// completion and the undo, so [_lastHabitCompletion] lost it) the
  /// per-habit streak fields and their bonus are left untouched rather
  /// than guessed at — guessing wrong would silently corrupt a real streak
  /// count (e.g. resetting a 6-day streak to 1 because "completed again
  /// today" looks identical to "completed for the first time"), which is
  /// worse than occasionally leaving a few stray XP/gold uncorrected.
  ///
  /// Deliberately does **not** touch `unlockedAchievements` — nothing in
  /// this app ever revokes an unlocked achievement, the same way a real
  /// trophy doesn't get taken back once earned — or
  /// `streak`/`longestStreak`/`streakEarnedToday`/its milestone bonus:
  /// once today has been credited as a full 100% day, undoing one habit
  /// again is left alone rather than un-crediting it. This is the same
  /// one-way, conservative bias [DashboardState.streakEarnedToday]
  /// documents for the "add a new habit after 100%" case — today's
  /// *whole-day* credit only ever moves forward, even though this one
  /// habit's own reward and per-habit streak now reverse precisely.
  Future<void> uncompleteHabit({
    required String habitId,
    required int xpReward,
    required int goldReward,
    String? category,
  }) async {
    final current = state.completions[habitId] ?? 0;
    if (current <= 0) return;

    final newCompletions = Map<String, int>.from(state.completions)
      ..remove(habitId);

    final snapshot = _lastHabitCompletion.remove(habitId);

    Map<String, int>? newHabitStreakCounts;
    Map<String, int>? newHabitLongestStreaks;
    Map<String, int>? newHabitTotalCompletions;
    Map<String, String>? newHabitLastCompletedDate;
    if (snapshot != null) {
      newHabitStreakCounts = {...state.habitStreakCounts};
      newHabitLongestStreaks = {...state.habitLongestStreaks};
      newHabitTotalCompletions = {...state.habitTotalCompletions};
      newHabitLastCompletedDate = {...state.habitLastCompletedDate};
      if (snapshot.hadPrior) {
        newHabitStreakCounts[habitId] = snapshot.prevStreak;
        newHabitLongestStreaks[habitId] = snapshot.prevLongest;
        newHabitTotalCompletions[habitId] = snapshot.prevTotal;
        final prevDate = snapshot.prevLastCompletedDate;
        if (prevDate != null) {
          newHabitLastCompletedDate[habitId] = prevDate;
        } else {
          newHabitLastCompletedDate.remove(habitId);
        }
      } else {
        newHabitStreakCounts.remove(habitId);
        newHabitLongestStreaks.remove(habitId);
        newHabitTotalCompletions.remove(habitId);
        newHabitLastCompletedDate.remove(habitId);
      }
    }

    final totalXpReward = xpReward + (snapshot?.bonusXp ?? 0);
    final totalGoldReward = goldReward + (snapshot?.bonusGold ?? 0);

    final xpResult = XpCalculator.applyXpDelta(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpDelta: -totalXpReward,
    );
    final rawGold = state.gold - totalGoldReward;
    final newGold = rawGold < 0 ? 0 : rawGold;

    final newCategoryCompletions = {...state.categoryCompletions};
    if (category != null) {
      final rawCategory = (newCategoryCompletions[category] ?? 0) - 1;
      newCategoryCompletions[category] = rawCategory < 0 ? 0 : rawCategory;
    }
    final rawTotal = state.totalCompletions - 1;
    final newTotal = rawTotal < 0 ? 0 : rawTotal;

    final rawTotalGreen = state.totalGreenSquares - 1;
    final newTotalGreenSquares = rawTotalGreen < 0 ? 0 : rawTotalGreen;
    final newDailyGreenCounts = {...state.dailyGreenCounts};
    final rawDay = (newDailyGreenCounts[_todayKey] ?? 0) - 1;
    newDailyGreenCounts[_todayKey] = rawDay < 0 ? 0 : rawDay;

    state = state.copyWith(
      level: xpResult.newLevel,
      currentLevelXp: xpResult.newCurrentLevelXp,
      cumulativeXp: xpResult.newCumulativeXp,
      gold: newGold,
      totalCompletions: newTotal,
      completions: newCompletions,
      categoryCompletions: newCategoryCompletions,
      totalGreenSquares: newTotalGreenSquares,
      dailyGreenCounts: newDailyGreenCounts,
      habitStreakCounts: newHabitStreakCounts,
      habitLongestStreaks: newHabitLongestStreaks,
      habitTotalCompletions: newHabitTotalCompletions,
      habitLastCompletedDate: newHabitLastCompletedDate,
    );

    if (_uid == null) {
      await _saveGuestDaily(newCompletions);
      // No lastActiveDate here — undoing isn't "new activity" and
      // shouldn't disturb the streak-gap-detection logic that field feeds.
      await _saveGuestState();
      return;
    }

    try {
      final batch = FirebaseFirestore.instance.batch();

      batch.set(
        _dailyRef,
        {'habitCompletions': newCompletions},
        SetOptions(merge: true),
      );

      batch.set(
        _userRef,
        {
          'level': xpResult.newLevel,
          'currentLevelXp': xpResult.newCurrentLevelXp,
          'cumulativeXp': xpResult.newCumulativeXp,
          'gold': newGold,
          'totalHabitCompletions': newTotal,
          'categoryCompletions': newCategoryCompletions,
          // Atomic increments, matching completeHabit's own writes to
          // these same two fields — both Grid's applyGridSquareChange and
          // this method can touch them, so an absolute local value would
          // risk a lost update. Nested map, not a dotted key — see
          // completeHabit's identical write for why (dot notation is a
          // literal field name inside set(merge: true), not a path).
          'totalGreenSquares': FieldValue.increment(-1),
          'dailyGreenCounts': {_todayKey: FieldValue.increment(-1)},
          if (snapshot != null) ...{
            'habitStreakCounts': newHabitStreakCounts,
            'habitLongestStreaks': newHabitLongestStreaks,
            'habitTotalCompletions': newHabitTotalCompletions,
            'habitLastCompletedDate': newHabitLastCompletedDate,
          },
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (_) {}
  }

  /// Fires local notifications for a habit completion — a habit-completed
  /// ping, plus a level-up / achievement-unlocked ping if either happened in
  /// the same action. These are on-device local notifications (no push
  /// server), so they show even if the in-app celebration overlay was
  /// dismissed or the app is backgrounded.
  void _fireCompletionNotifications({
    required String habitId,
    required int xpEarned,
    required int goldEarned,
    required bool didLevelUp,
    required int newLevel,
    required List<AchievementModel> newlyUnlocked,
  }) {
    NotificationService.instance.showHabitCompleted(
      habitName: habitId,
      xpEarned: xpEarned,
      goldEarned: goldEarned,
    );
    if (didLevelUp) {
      NotificationService.instance.showLevelUp(newLevel);
    }
    for (final a in newlyUnlocked) {
      NotificationService.instance.showAchievementUnlocked(a.name);
    }
  }

  /// Applies the progression fallout of a single Victory Grid square
  /// changing color: fixed XP per the color (see [SquareState.xpValue]), a
  /// lifetime green-square counter that drives grid achievements, and a
  /// daily rollup for the monthly heatmap.
  ///
  /// Deliberately does **not** touch the streak. Streak means a full,
  /// 100%-of-today's-habits day (see [DashboardState.streakEarnedToday]),
  /// and that's only knowable from the real habit list, which this
  /// habit-agnostic, color-only method never sees — a lone bonus-colored
  /// square, a partial mark, or a multi-tap habit's Grid-only progress
  /// isn't "today done", so none of those should hand out the day's streak
  /// point on their own. The one case that legitimately *should* streak —
  /// finishing a real single-tap habit's square to `complete` — is already
  /// special-cased at the call site to go through [completeHabit] instead
  /// (see grid_screen.dart's `_handleSquareTap`/`_handlePaletteTap`), so by
  /// the time a color change reaches here, it was never going to be the
  /// day's 100% moment.
  Future<void> applyGridSquareChange({
    required int xpDelta,
    required int greenDelta,
    required String dateKey,
  }) async {
    var newLevel = state.level;
    var newCurrentLevelXp = state.currentLevelXp;
    var newCumulativeXp = state.cumulativeXp;

    if (xpDelta != 0) {
      final result = XpCalculator.applyXpDelta(
        currentLevel: state.level,
        currentLevelXp: state.currentLevelXp,
        cumulativeXp: state.cumulativeXp,
        xpDelta: xpDelta,
      );
      newLevel = result.newLevel;
      newCurrentLevelXp = result.newCurrentLevelXp;
      newCumulativeXp = result.newCumulativeXp;
    }

    final rawTotalGreen = state.totalGreenSquares + greenDelta;
    final newTotalGreen = rawTotalGreen < 0 ? 0 : rawTotalGreen;
    final newDailyGreenCounts = {...state.dailyGreenCounts};
    if (greenDelta != 0) {
      final rawDay = (newDailyGreenCounts[dateKey] ?? 0) + greenDelta;
      newDailyGreenCounts[dateKey] = rawDay < 0 ? 0 : rawDay;
    }

    // ── Achievement check ────────────────────────────────────
    final newly = AchievementCatalog.locked(state.unlockedAchievements)
        .where((a) => switch (a.trigger) {
              AchievementTrigger.level => newLevel >= a.threshold,
              AchievementTrigger.greenSquares =>
                newTotalGreen >= a.threshold,
              _ => false,
            })
        .toList();

    final newUnlockedIds = [
      ...state.unlockedAchievements,
      ...newly.map((a) => a.id),
    ];

    int bonusXp = newly.fold(0, (s, a) => s + a.xpReward);
    int bonusGold = newly.fold(0, (s, a) => s + a.goldReward);
    if (bonusXp > 0) {
      final bonusResult = XpCalculator.applyXpGain(
        currentLevel: newLevel,
        currentLevelXp: newCurrentLevelXp,
        cumulativeXp: newCumulativeXp,
        xpGained: bonusXp,
      );
      newLevel = bonusResult.newLevel;
      newCurrentLevelXp = bonusResult.newCurrentLevelXp;
      newCumulativeXp = bonusResult.newCumulativeXp;
    }
    final newGold = state.gold + bonusGold;
    final didLevelUp = newLevel > state.level;

    state = state.copyWith(
      level: newLevel,
      currentLevelXp: newCurrentLevelXp,
      cumulativeXp: newCumulativeXp,
      gold: newGold,
      totalGreenSquares: newTotalGreen,
      dailyGreenCounts: newDailyGreenCounts,
      unlockedAchievements: newUnlockedIds,
      newlyUnlocked: newly,
      didJustLevelUp: didLevelUp,
    );

    if (didLevelUp) NotificationService.instance.showLevelUp(newLevel);
    for (final a in newly) {
      NotificationService.instance.showAchievementUnlocked(a.name);
    }

    if (_uid == null) {
      await _saveGuestState();
      return;
    }

    try {
      // .effectiveDay, not the raw instant — this feeds 'lastActiveDate',
      // which the streak-gap comparisons above (habitStreak,
      // completeHabit's per-habit gap, _loadToday/_loadGuestToday's
      // app-wide gap) all read back assuming it's already day-cutoff
      // aligned. See DateTimeGameExt.effectiveDay's doc comment.
      final now = DateTime.now().effectiveDay;
      final batch = FirebaseFirestore.instance.batch();

      final userUpdate = <String, dynamic>{
        'level': newLevel,
        'currentLevelXp': newCurrentLevelXp,
        'cumulativeXp': newCumulativeXp,
        'gold': newGold,
        'unlockedAchievements': newUnlockedIds,
        'lastActiveDate': Timestamp.fromDate(now),
      };
      if (greenDelta != 0) {
        userUpdate['totalGreenSquares'] = FieldValue.increment(greenDelta);
        // Nested map, not a dotted key — see completeHabit's identical
        // write for why (dot notation is a literal field name inside
        // set(merge: true), not a path).
        userUpdate['dailyGreenCounts'] = {
          dateKey: FieldValue.increment(greenDelta),
        };
      }
      batch.set(_userRef, userUpdate, SetOptions(merge: true));

      await batch.commit();
    } catch (_) {}
  }

  /// Keeps the heatmap's day rollup honest when a *past* day's square is
  /// backfilled. WeeklyGridNotifier.setSquare intentionally never calls
  /// [applyGridSquareChange] for a non-today day — that guard exists so
  /// navigating to an old week and coloring squares green can't farm real
  /// XP, gold, streak, or achievement progress for a day that wasn't
  /// actually lived through. But the Monthly Heatmap (see
  /// MonthlyHeatmapScreen) reads *only* from [dailyGreenCounts], so
  /// skipping that field too meant a backfilled square colored correctly
  /// on the Grid itself but silently never showed up on the heatmap — the
  /// exact "doesn't save the previous days" gap. This method updates
  /// *only* dailyGreenCounts, nothing else: no XP, no gold, no streak, no
  /// totalGreenSquares, no achievement checks. It's deliberately the
  /// narrowest possible fix, so the anti-farming guard everywhere else
  /// stays exactly as strict as it already was.
  void recordPastDayGreenDelta(String dateKey, int greenDelta) {
    if (greenDelta == 0) return;
    final newDailyGreenCounts = {...state.dailyGreenCounts};
    final raw = (newDailyGreenCounts[dateKey] ?? 0) + greenDelta;
    newDailyGreenCounts[dateKey] = raw < 0 ? 0 : raw;
    state = state.copyWith(dailyGreenCounts: newDailyGreenCounts);

    if (_uid == null) {
      _saveGuestState().ignore();
      return;
    }
    // Nested map, not a dotted key — see completeHabit's identical write
    // for why (dot notation is a literal field name inside
    // set(merge: true), not a path).
    _userRef.set(
      {
        'dailyGreenCounts': {dateKey: FieldValue.increment(greenDelta)},
      },
      SetOptions(merge: true),
    ).ignore();
  }

  /// Spends gold for an extra streak freeze. Returns whether the purchase
  /// actually persisted — previously this always returned `true` once the
  /// affordability check passed, even if the Firestore write below failed,
  /// which showed the player a success toast for a purchase that silently
  /// never saved (they'd lose the gold and the freeze on next launch, with
  /// no error and nothing to point to why). Now a failed write rolls the
  /// optimistic gold/freeze deduction back and reports failure so the UI can
  /// tell the user to retry instead of celebrating a purchase that didn't
  /// happen.
  Future<bool> buyStreakFreeze() async {
    if (state.gold < streakFreezeCost ||
        state.streakFreezes >= maxStreakFreezes) {
      return false;
    }
    final previousGold = state.gold;
    final previousFreezes = state.streakFreezes;
    final newGold = previousGold - streakFreezeCost;
    final newFreezes = previousFreezes + 1;
    state = state.copyWith(gold: newGold, streakFreezes: newFreezes);
    if (_uid == null) {
      try {
        await _saveGuestState();
      } catch (_) {
        state = state.copyWith(gold: previousGold, streakFreezes: previousFreezes);
        return false;
      }
      AnalyticsService.instance.track('streak_freeze_bought');
      return true;
    }
    try {
      await _userRef.set({
        'gold': newGold,
        'streakFreezes': newFreezes,
      }, SetOptions(merge: true));
    } catch (_) {
      state = state.copyWith(gold: previousGold, streakFreezes: previousFreezes);
      return false;
    }
    AnalyticsService.instance.track('streak_freeze_bought');
    return true;
  }

  /// Generic gold spend for purchases outside the dashboard's own gold sinks
  /// (currently just the character closet's accessory shop) — same
  /// optimistic-update + rollback-on-failed-write pattern as
  /// [buyStreakFreeze], minus the second field that one also touches.
  /// Returns whether the spend actually persisted; callers should only apply
  /// their own side effect (unlocking the item) once this returns true, so a
  /// failed write can't grant an item the player didn't actually pay for.
  Future<bool> spendGold(int amount) async {
    if (amount <= 0 || state.gold < amount) return false;
    final previousGold = state.gold;
    final newGold = previousGold - amount;
    state = state.copyWith(gold: newGold);
    if (_uid == null) {
      try {
        await _saveGuestState();
      } catch (_) {
        state = state.copyWith(gold: previousGold);
        return false;
      }
      return true;
    }
    try {
      await _userRef.set({'gold': newGold}, SetOptions(merge: true));
    } catch (_) {
      state = state.copyWith(gold: previousGold);
      return false;
    }
    return true;
  }

  /// Max length for a user-chosen display name — generous enough for most
  /// real names while keeping the Profile hero header from wrapping.
  static const int maxDisplayNameLength = 24;

  /// Sets the stored display name (see [DashboardState.displayName]).
  /// No-ops on an empty/whitespace name — same "don't let an edit blank
  /// this out" guard MatrixNotifier.rename uses for task titles. Same
  /// optimistic-update + rollback-on-failed-write shape as [spendGold].
  Future<bool> setDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final clamped = trimmed.length > maxDisplayNameLength
        ? trimmed.substring(0, maxDisplayNameLength)
        : trimmed;

    final previous = state.displayName;
    state = state.copyWith(displayName: clamped);
    if (_uid == null) {
      try {
        await _saveGuestState();
      } catch (_) {
        state = state.copyWith(displayName: previous);
        return false;
      }
      return true;
    }
    try {
      await _userRef.set({'displayName': clamped}, SetOptions(merge: true));
    } catch (_) {
      state = state.copyWith(displayName: previous);
      return false;
    }
    return true;
  }

  /// Spend a streak freeze to restore the streak that was lost on a missed day.
  Future<void> useStreakFreeze() async {
    if (state.streakFreezes <= 0 || state.previousStreak <= 0) return;
    final newFreezes = state.streakFreezes - 1;
    final restoredStreak = state.previousStreak;
    final newLongest = restoredStreak > state.longestStreak
        ? restoredStreak
        : state.longestStreak;

    state = state.copyWith(
      streak: restoredStreak,
      longestStreak: newLongest,
      streakFreezes: newFreezes,
      previousStreak: 0,
    );

    if (_uid == null) {
      // This was previously missing entirely — the restore only ever
      // updated in-memory state and guests would see their streak silently
      // revert to lost on next launch. Same guest-save-on-mutation pattern
      // every other method in this class already follows.
      await _saveGuestState();
      return;
    }
    _userRef.set({
      'currentStreak': restoredStreak,
      'longestStreak': newLongest,
      'streakFreezes': newFreezes,
      'previousStreak': 0,
      'lastActiveDate': Timestamp.fromDate(DateTime.now().effectiveDay),
    }, SetOptions(merge: true)).ignore();
  }

  /// Dismiss the "you're back" card and grant the comeback XP bonus.
  Future<void> acknowledgeComeback() async {
    if (!state.showComebackBonus) return;
    final result = XpCalculator.applyXpGain(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpGained: comebackBonusXp,
    );
    AnalyticsService.instance.track('comeback_bonus_claimed');
    state = state.copyWith(
      previousStreak: 0,
      level: result.newLevel,
      currentLevelXp: result.newCurrentLevelXp,
      cumulativeXp: result.newCumulativeXp,
      didJustLevelUp: result.newLevel > state.level,
    );
    if (_uid == null) {
      await _saveGuestState();
      return;
    }
    try {
      await _userRef.set({
        'level': result.newLevel,
        'currentLevelXp': result.newCurrentLevelXp,
        'cumulativeXp': result.newCumulativeXp,
        'previousStreak': 0,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void acknowledgeMilestone() {
    state = state.copyWith(clearMilestone: true);
  }

  void acknowledgeHabitMilestone() {
    state = state.copyWith(clearHabitMilestone: true);
  }

  Future<void> setIntentionsDone({
    required List<String> priorities,
    required String anchor,
    required String intention,
  }) async {
    state = state.copyWith(intentionsSetToday: true);
    if (_uid == null) {
      // Persist for guests too, so the prompt shows once per day — not on
      // every cold start.
      final existing = await LocalStoreService.getDailyMap(_todayKey);
      await LocalStoreService.putDailyMap(_todayKey, {
        ...existing,
        'intentionsSet': true,
        'priorities': priorities,
        'intentionAnchor': anchor,
        'intentionAction': intention,
        'date': DateTime.now().effectiveDay.toIso8601String(),
      });
      return;
    }
    _dailyRef.set({
      'intentionsSet': true,
      'priorities': priorities,
      'intentionAnchor': anchor,
      'intentionAction': intention,
    }, SetOptions(merge: true)).ignore();
  }

  /// Generic XP/Gold award used by Focus Timer sessions and Weekly Challenges.
  Future<void> awardBonus({required int xp, required int gold}) async {
    final result = XpCalculator.applyXpGain(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpGained: xp,
    );
    final newGold = state.gold + gold;
    state = state.copyWith(
      level: result.newLevel,
      currentLevelXp: result.newCurrentLevelXp,
      cumulativeXp: result.newCumulativeXp,
      gold: newGold,
      didJustLevelUp: result.newLevel > state.level,
    );
    if (_uid == null) {
      // Guests reach this from the Focus timer and Weekly Challenges — it
      // was returning here without persisting, so the XP/gold shown on
      // screen silently vanished on next launch. Save it like every other
      // guest-facing mutation does.
      await _saveGuestState();
      return;
    }
    try {
      await _userRef.set({
        'level': result.newLevel,
        'currentLevelXp': result.newCurrentLevelXp,
        'cumulativeXp': result.newCumulativeXp,
        'gold': newGold,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void acknowledgeAchievements() {
    if (state.newlyUnlocked.isEmpty) return;
    state = state.copyWith(newlyUnlocked: []);
  }

  /// Re-reads gold/XP/level/streak/achievements/dailyGreenCounts from
  /// Firestore/local storage. [_loadToday]/[_loadGuestToday] only ever run
  /// once, at construction — every other change flows through this app's
  /// own optimistic-update methods, so nothing normally calls this again.
  /// It's what picks up a change made *outside* that path, e.g. a field
  /// like `gold` edited by hand in the Firebase console while testing —
  /// without it, the app just keeps showing whatever it last loaded until
  /// a full restart. Called on app resume — see main.dart.
  ///
  /// This also matters for the day-cutoff feature (see
  /// DateTimeGameExt.effectiveDay): if the app is simply left open and
  /// backgrounded across the cutoff hour, `state` would otherwise keep
  /// showing yesterday's `_todayKey` document — streakEarnedToday,
  /// intentionsSetToday, completions — until a full restart. Routing
  /// guests through [_loadGuestToday] here too (previously this only ever
  /// called the signed-in path, silently no-op-ing for guests) means an
  /// app-resume after the cutoff correctly picks up the new day for both.
  Future<void> refresh() => _uid != null ? _loadToday() : _loadGuestToday();
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return DashboardNotifier(uid);
});
