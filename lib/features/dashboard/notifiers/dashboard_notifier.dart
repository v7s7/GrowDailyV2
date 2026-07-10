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

class DashboardState {
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
  final String? lastCompletedId;
  final bool isLoading;
  final bool showComebackBonus;
  final int previousStreak;
  final int? milestoneCelebration;
  final bool intentionsSetToday;

  /// Lifetime count of green (complete/bonus) squares ever colored on the
  /// Victory Grid — the "100 green squares completed" style achievements.
  final int totalGreenSquares;

  /// Whether the day's streak has already been credited by grid activity
  /// (kept alongside [completions].isEmpty so a habit-card completion and a
  /// grid square never double-count the same day's streak).
  final bool gridActivityToday;

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
    this.lastCompletedId,
    this.isLoading = false,
    this.showComebackBonus = false,
    this.previousStreak = 0,
    this.milestoneCelebration,
    this.intentionsSetToday = false,
    this.totalGreenSquares = 0,
    this.gridActivityToday = false,
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
    final today = DateTime.now();
    final gap = DateTime(today.year, today.month, today.day)
        .difference(DateTime(last.year, last.month, last.day))
        .inDays;
    return gap <= 1 ? (habitStreakCounts[habitId] ?? 0) : 0;
  }

  DashboardState copyWith({
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
    String? lastCompletedId,
    bool? isLoading,
    bool? showComebackBonus,
    int? previousStreak,
    int? setMilestone,
    bool clearMilestone = false,
    bool? intentionsSetToday,
    int? totalGreenSquares,
    bool? gridActivityToday,
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
        lastCompletedId: lastCompletedId ?? this.lastCompletedId,
        isLoading: isLoading ?? this.isLoading,
        showComebackBonus: showComebackBonus ?? this.showComebackBonus,
        previousStreak: previousStreak ?? this.previousStreak,
        milestoneCelebration:
            clearMilestone ? null : (setMilestone ?? this.milestoneCelebration),
        intentionsSetToday: intentionsSetToday ?? this.intentionsSetToday,
        totalGreenSquares: totalGreenSquares ?? this.totalGreenSquares,
        gridActivityToday: gridActivityToday ?? this.gridActivityToday,
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

  static String get _todayKey => DateTime.now().toDateKey();

  static String get _weekKey {
    final today = _dateOnly(DateTime.now());
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
      final gridActivityToday = (daily['gridActivityLogged'] as bool?) ?? false;
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
      int previousStreak = 0;
      bool didUseStreakFreeze = false;
      bool showComebackBonus = false;
      final lastActive = DateTime.tryParse(saved['lastActiveDate'] as String? ?? '');

      if (lastActive != null) {
        final today = _dateOnly(DateTime.now());
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
              showComebackBonus = true;
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
        showComebackBonus: showComebackBonus,
        previousStreak: previousStreak,
        isLoading: false,
        intentionsSetToday: intentionsSetToday,
        totalGreenSquares: (saved['totalGreenSquares'] as int?) ?? 0,
        gridActivityToday: gridActivityToday,
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
        'level': state.level,
        'currentLevelXp': state.currentLevelXp,
        'cumulativeXp': state.cumulativeXp,
        'gold': state.gold,
        'currentStreak': state.streak,
        'longestStreak': state.longestStreak,
        'totalHabitCompletions': state.totalCompletions,
        'streakFreezes': state.streakFreezes,
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

  Future<void> _saveGuestDaily(Map<String, int> completions) async {
    final existing = await LocalStoreService.getDailyMap(_todayKey);
    await LocalStoreService.putDailyMap(
      _todayKey,
      {
        ...existing,
        'habitCompletions': completions,
        'date': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> _setGuestGridActivityLogged(bool value) async {
    final existing = await LocalStoreService.getDailyMap(_todayKey);
    await LocalStoreService.putDailyMap(_todayKey, {
      ...existing,
      'gridActivityLogged': value,
      'date': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _loadToday() async {
    if (_uid == null) return;
    try {
      final results = await Future.wait([_userRef.get(), _dailyRef.get()]);
      final userSnap = results[0];
      final dailySnap = results[1];

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
      bool showComebackBonus = false;
      bool intentionsSetToday = false;
      bool gridActivityToday = false;
      int totalGreenSquares = 0;
      Map<String, int> dailyGreenCounts = {};
      Map<String, int> categoryCompletions = {};
      Map<String, int> habitStreakCounts = {};
      Map<String, int> habitLongestStreaks = {};
      Map<String, int> habitTotalCompletions = {};
      Map<String, String> habitLastCompletedDate = {};

      if (userSnap.exists) {
        final d = userSnap.data()!;
        level = (d['level'] as int?) ?? 1;
        currentLevelXp = (d['currentLevelXp'] as int?) ?? 0;
        cumulativeXp = (d['cumulativeXp'] as int?) ?? 0;
        gold = (d['gold'] as int?) ?? 0;
        streak = (d['currentStreak'] as int?) ?? 0;
        longestStreak = (d['longestStreak'] as int?) ?? 0;
        totalCompletions = (d['totalHabitCompletions'] as int?) ?? 0;
        streakFreezes = (d['streakFreezes'] as int?) ?? 1;
        final lastFreezeGrantWeek = d['lastFreezeGrantWeek'] as String?;
        unlockedAchievements =
            List<String>.from(d['unlockedAchievements'] as List? ?? []);
        totalGreenSquares = (d['totalGreenSquares'] as int?) ?? 0;
        final rawGreenCounts =
            (d['dailyGreenCounts'] as Map?)?.cast<String, dynamic>() ?? {};
        dailyGreenCounts = rawGreenCounts.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
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
          final today = _dateOnly(DateTime.now());
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
                showComebackBonus = true;
              }
              streak = 0;
              _userRef
                  .set({'currentStreak': 0}, SetOptions(merge: true))
                  .ignore();
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
        gridActivityToday = (d['gridActivityLogged'] as bool?) ?? false;
      }

      if (mounted) {
        state = DashboardState(
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
          showComebackBonus: showComebackBonus,
          previousStreak: previousStreak,
          intentionsSetToday: intentionsSetToday,
          totalGreenSquares: totalGreenSquares,
          gridActivityToday: gridActivityToday,
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
  /// Shared by [completeHabit] and [applyGridSquareChange] so both entry
  /// points to "did something today" agree on milestone semantics.
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
  /// (`frequencyTarget == 1`) habit — the signal callers use to decide
  /// whether to mirror today's Grid square to green. Multi-tap
  /// (`frequencyTarget > 1`, e.g. "3x this week") habits intentionally
  /// return `false` here even on their final completing tap: a single
  /// day's Grid square can't cleanly represent "2 of 3 this week" yet, so
  /// Grid/Today sync is deferred for those and this always reports
  /// "nothing to mirror". Returns `false` if the habit was already done
  /// today (no new completion registered at all).
  Future<bool> completeHabit({
    required String habitId,
    required int xpReward,
    required int goldReward,
    required int frequencyTarget,
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
    // first completion of *this specific habit* today (mirrors the
    // app-wide isFirstToday check below, just scoped to one habit id
    // instead of "any habit"). A weekly habit tapped 3 separate days still
    // bumps 3 times; nothing here double-counts a same-day multi-tap
    // because current is already > 0 by the second tap.
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
          : _dateOnly(DateTime.now()).difference(_dateOnly(last)).inDays;
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

    // Only single-tap habits are synced with the Grid in this phase — see
    // the doc comment above.
    final isGridSyncable = frequencyTarget == 1;

    final isFirstToday = state.completions.isEmpty && !state.gridActivityToday;
    final bump = isFirstToday
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

    // A synced single-tap completion counts exactly like Grid's own green
    // square, using the same existing fields Grid already writes — no new
    // schema. Forward-only: this only ever touches today's dateKey, never
    // rewrites or backfills earlier days. The guard above (`current >=
    // frequencyTarget`) already makes this at most a one-time bump per
    // habit per day, same as everything else in this method.
    final newTotalGreenSquares = isGridSyncable
        ? state.totalGreenSquares + 1
        : state.totalGreenSquares;
    final newDailyGreenCounts = {...state.dailyGreenCounts};
    if (isGridSyncable) {
      newDailyGreenCounts[_todayKey] =
          (newDailyGreenCounts[_todayKey] ?? 0) + 1;
    }

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
      'isFirstToday': isFirstToday,
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
      totalCompletions: newTotal,
      completions: newCompletions,
      unlockedAchievements: newUnlockedIds,
      newlyUnlocked: newly,
      didJustLevelUp: didLevelUp,
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
      await _saveGuestDaily(newCompletions);
      await _saveGuestState(lastActiveDate: DateTime.now());
      return isGridSyncable;
    }

    try {
      final now = DateTime.now();
      final batch = FirebaseFirestore.instance.batch();

      batch.set(
        _dailyRef,
        {'habitCompletions': newCompletions, 'date': Timestamp.fromDate(now)},
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
          'totalHabitCompletions': newTotal,
          'unlockedAchievements': newUnlockedIds,
          'categoryCompletions': newCategoryCompletions,
          'lastActiveDate': Timestamp.fromDate(now),
          'habitStreakCounts': newHabitStreakCounts,
          'habitLongestStreaks': newHabitLongestStreaks,
          'habitTotalCompletions': newHabitTotalCompletions,
          'habitLastCompletedDate': newHabitLastCompletedDate,
          // Same fields Grid's own applyGridSquareChange writes — no new
          // schema, just a second (mutually-exclusive, see isGridSyncable
          // above) writer for the synced single-tap case.
          if (isGridSyncable) 'totalGreenSquares': FieldValue.increment(1),
          if (isGridSyncable) 'dailyGreenCounts.$_todayKey': FieldValue.increment(1),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (_) {}
    return isGridSyncable;
  }

  /// Reverses a same-day completion made via [completeHabit] — the "I
  /// completed this by mistake" correction available from Grid's
  /// long-press editor on a synced, completed-today square. Always
  /// operates on *today* (there's no "edit yesterday's completion"
  /// concept anywhere in this app).
  ///
  /// Reverses what's safe to reverse: XP, gold, `completions[habitId]`
  /// (back to not-done so Today un-checks it too), `categoryCompletions`,
  /// `totalCompletions`, and the `totalGreenSquares`/`dailyGreenCounts`
  /// counters this phase added for synced completions.
  ///
  /// Deliberately does **not** touch `unlockedAchievements` — nothing in
  /// this app ever revokes an unlocked achievement, the same way a real
  /// trophy doesn't get taken back once earned — or
  /// `streak`/`longestStreak`/`gridActivityToday`: safely re-deriving
  /// "was this really the day's only source of today's streak point" is
  /// fragile, so an already-earned streak day is left alone. Both are the
  /// same conservative bias `completeHabit` already takes.
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

    final xpResult = XpCalculator.applyXpDelta(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpDelta: -xpReward,
    );
    final rawGold = state.gold - goldReward;
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
          // risk a lost update.
          'totalGreenSquares': FieldValue.increment(-1),
          'dailyGreenCounts.$_todayKey': FieldValue.increment(-1),
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
  /// changing color: fixed XP per the color (see [SquareState.xpValue]),
  /// a lifetime green-square counter that drives grid achievements, a daily
  /// rollup for the monthly heatmap, and — only for a green mark logged on
  /// *today* — the same once-per-day streak bump [completeHabit] uses.
  ///
  /// [stillGreenToday] tells us whether any square is still green today
  /// *after* this change — needed to catch the inverse case: a user marks
  /// today's only green square (streak bumps +1), then un-marks that same
  /// square. Nothing here used to roll that streak point back, so tapping a
  /// square and immediately un-tapping it was a free, repeatable +1 to the
  /// streak with none of the actual daily activity it's supposed to
  /// represent.
  Future<void> applyGridSquareChange({
    required int xpDelta,
    required int greenDelta,
    required bool isToday,
    required String dateKey,
    bool stillGreenToday = true,
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

    var newStreak = state.streak;
    var newLongest = state.longestStreak;
    var newGridActivityToday = state.gridActivityToday;
    int? newMilestone;

    final earnsStreakToday = isToday &&
        greenDelta > 0 &&
        state.completions.isEmpty &&
        !state.gridActivityToday;
    // The mirror image of earnsStreakToday: this grid action was the only
    // reason today's streak point was earned (no habit-list completions
    // today either), and after this change there's no green square left
    // today to justify keeping it.
    final losesStreakToday = isToday &&
        greenDelta < 0 &&
        !stillGreenToday &&
        state.completions.isEmpty &&
        state.gridActivityToday &&
        state.streak > 0;
    if (earnsStreakToday) {
      final bump = _computeStreakBump();
      newStreak = bump.streak;
      newLongest = bump.longestStreak;
      newMilestone = bump.milestone;
      newGridActivityToday = true;
      if (bump.milestoneBonusXp > 0) {
        final bumped = XpCalculator.applyXpGain(
          currentLevel: newLevel,
          currentLevelXp: newCurrentLevelXp,
          cumulativeXp: newCumulativeXp,
          xpGained: bump.milestoneBonusXp,
        );
        newLevel = bumped.newLevel;
        newCurrentLevelXp = bumped.newCurrentLevelXp;
        newCumulativeXp = bumped.newCumulativeXp;
      }
    } else if (losesStreakToday) {
      newStreak = state.streak - 1;
      // If the current streak was tied with the record, that record was
      // set by the very point we're now taking back — pull it back too.
      // Otherwise the record was earned on a previous, already-broken
      // streak and stays put.
      newLongest = state.longestStreak == state.streak
          ? state.longestStreak - 1
          : state.longestStreak;
      newGridActivityToday = false;
    }

    // ── Achievement check ────────────────────────────────────
    final newly = AchievementCatalog.locked(state.unlockedAchievements)
        .where((a) => switch (a.trigger) {
              AchievementTrigger.streak => newStreak >= a.threshold,
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
      streak: newStreak,
      longestStreak: newLongest,
      totalGreenSquares: newTotalGreen,
      gridActivityToday: newGridActivityToday,
      dailyGreenCounts: newDailyGreenCounts,
      unlockedAchievements: newUnlockedIds,
      newlyUnlocked: newly,
      didJustLevelUp: didLevelUp,
      setMilestone: newMilestone,
    );

    if (didLevelUp) NotificationService.instance.showLevelUp(newLevel);
    for (final a in newly) {
      NotificationService.instance.showAchievementUnlocked(a.name);
    }

    if (_uid == null) {
      await _saveGuestState();
      if (earnsStreakToday) await _setGuestGridActivityLogged(true);
      if (losesStreakToday) await _setGuestGridActivityLogged(false);
      return;
    }

    try {
      final now = DateTime.now();
      final batch = FirebaseFirestore.instance.batch();

      final userUpdate = <String, dynamic>{
        'level': newLevel,
        'currentLevelXp': newCurrentLevelXp,
        'cumulativeXp': newCumulativeXp,
        'gold': newGold,
        'currentStreak': newStreak,
        'longestStreak': newLongest,
        'unlockedAchievements': newUnlockedIds,
        'lastActiveDate': Timestamp.fromDate(now),
      };
      if (greenDelta != 0) {
        userUpdate['totalGreenSquares'] = FieldValue.increment(greenDelta);
        userUpdate['dailyGreenCounts.$dateKey'] =
            FieldValue.increment(greenDelta);
      }
      batch.set(_userRef, userUpdate, SetOptions(merge: true));

      if (earnsStreakToday) {
        batch.set(
          _dailyRef,
          {'gridActivityLogged': true},
          SetOptions(merge: true),
        );
      } else if (losesStreakToday) {
        batch.set(
          _dailyRef,
          {'gridActivityLogged': false},
          SetOptions(merge: true),
        );
      }

      await batch.commit();
    } catch (_) {}
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
      showComebackBonus: false,
      previousStreak: 0,
    );

    if (_uid == null) return;
    _userRef.set({
      'currentStreak': restoredStreak,
      'longestStreak': newLongest,
      'streakFreezes': newFreezes,
      'lastActiveDate': Timestamp.fromDate(DateTime.now()),
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
      showComebackBonus: false,
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
        'date': DateTime.now().toIso8601String(),
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

  Future<void> refresh() => _loadToday();
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return DashboardNotifier(uid);
});
