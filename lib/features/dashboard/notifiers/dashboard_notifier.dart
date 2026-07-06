import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/analytics_service.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/xp_calculator.dart';
import '../../../features/achievements/models/achievement_model.dart';
import '../../auth/notifiers/auth_notifier.dart';

const List<int> kStreakMilestones = [3, 7, 14, 30, 60, 100];

int milestoneXpBonus(int milestone) => switch (milestone) {
      3 => 25,
      7 => 75,
      14 => 150,
      30 => 300,
      60 => 600,
      100 => 1500,
      _ => 0,
    };

String milestoneTitle(int milestone) => switch (milestone) {
      3 => '3-Day Starter',
      7 => '7-Day Warrior',
      14 => '2-Week Champion',
      30 => 'Month Master',
      60 => '60-Day Devotee',
      100 => 'Century Legend',
      _ => 'Streak Milestone',
    };

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
      );
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  static const int streakFreezeCost = 100;
  static const int maxStreakFreezes = 3;
  static const int comebackBonusXp = 50;
  static const List<int> streakMilestones = [3, 7, 14, 30, 60, 100];

  final String? _uid;

  DashboardNotifier(this._uid) : super(DashboardState.initial()) {
    if (_uid != null) {
      _loadToday();
    } else {
      _loadGuestToday();
    }
  }

  // ── Helpers ─────────────────────────────────────────────────

  static String get _todayKey {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

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

  Future<void> completeHabit({
    required String habitId,
    required int xpReward,
    required int goldReward,
    required int frequencyTarget,
    String? category,
    String? habitName,
  }) async {
    final current = state.completions[habitId] ?? 0;
    if (current >= frequencyTarget) return;

    final newCompletions = Map<String, int>.from(state.completions)
      ..[habitId] = current + 1;

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
      xpGained: xpReward + milestoneBonusXp,
    );
    final newGold = state.gold + goldReward;
    final newTotal = state.totalCompletions + 1;

    final newCategoryCompletions = {...state.categoryCompletions};
    if (category != null) {
      newCategoryCompletions[category] =
          (newCategoryCompletions[category] ?? 0) + 1;
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
    );

    _fireCompletionNotifications(
      habitId: habitName ?? habitId,
      xpEarned: xpReward + milestoneBonusXp,
      goldEarned: goldReward,
      didLevelUp: didLevelUp,
      newLevel: bonusResult.newLevel,
      newlyUnlocked: newly,
    );

    if (_uid == null) {
      await _saveGuestDaily(newCompletions);
      await _saveGuestState(lastActiveDate: DateTime.now());
      return;
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
