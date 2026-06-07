import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final String? lastCompletedId;
  final bool isLoading;
  final bool showComebackBonus;
  final int previousStreak;
  final int? milestoneCelebration;
  final bool intentionsSetToday;

  const DashboardState({
    required this.level,
    required this.currentLevelXp,
    required this.cumulativeXp,
    required this.gold,
    required this.streak,
    this.longestStreak = 0,
    this.totalCompletions = 0,
    this.streakFreezes = 0,
    required this.completions,
    this.unlockedAchievements = const [],
    this.newlyUnlocked = const [],
    this.didJustLevelUp = false,
    this.lastCompletedId,
    this.isLoading = false,
    this.showComebackBonus = false,
    this.previousStreak = 0,
    this.milestoneCelebration,
    this.intentionsSetToday = false,
  });

  factory DashboardState.initial() => const DashboardState(
        level: 1,
        currentLevelXp: 0,
        cumulativeXp: 0,
        gold: 0,
        streak: 0,
        longestStreak: 0,
        totalCompletions: 0,
        streakFreezes: 0,
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
    String? lastCompletedId,
    bool? isLoading,
    bool? showComebackBonus,
    int? previousStreak,
    int? setMilestone,
    bool clearMilestone = false,
    bool? intentionsSetToday,
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
        lastCompletedId: lastCompletedId ?? this.lastCompletedId,
        isLoading: isLoading ?? this.isLoading,
        showComebackBonus: showComebackBonus ?? this.showComebackBonus,
        previousStreak: previousStreak ?? this.previousStreak,
        milestoneCelebration:
            clearMilestone ? null : (setMilestone ?? this.milestoneCelebration),
        intentionsSetToday: intentionsSetToday ?? this.intentionsSetToday,
      );
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  final String? _uid;

  DashboardNotifier(this._uid) : super(DashboardState.initial()) {
    if (_uid != null) {
      _loadToday();
    } else {
      state = DashboardState.initial().copyWith(isLoading: false);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────

  static String get _todayKey {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  DocumentReference<Map<String, dynamic>> get _dailyRef =>
      _userRef.collection('daily').doc(_todayKey);

  // ── Load ─────────────────────────────────────────────────────

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
          streakFreezes = 0,
          previousStreak = 0;
      List<String> unlockedAchievements = [];
      Map<String, int> completions = {};
      bool showComebackBonus = false;
      bool intentionsSetToday = false;

      if (userSnap.exists) {
        final d = userSnap.data()!;
        level = (d['level'] as int?) ?? 1;
        currentLevelXp = (d['currentLevelXp'] as int?) ?? 0;
        cumulativeXp = (d['cumulativeXp'] as int?) ?? 0;
        gold = (d['gold'] as int?) ?? 0;
        streak = (d['currentStreak'] as int?) ?? 0;
        longestStreak = (d['longestStreak'] as int?) ?? 0;
        totalCompletions = (d['totalHabitCompletions'] as int?) ?? 0;
        streakFreezes = (d['streakFreezes'] as int?) ?? 0;
        unlockedAchievements =
            List<String>.from(d['unlockedAchievements'] as List? ?? []);

        // One free streak freeze per week at Level 5+
        if (level >= 5) {
          final lastGrantTs = d['lastFreezeGrantDate'] as Timestamp?;
          final now = DateTime.now();
          final shouldGrant = lastGrantTs == null ||
              now.difference(lastGrantTs.toDate()).inDays >= 7;
          if (shouldGrant) {
            streakFreezes += 1;
            _userRef.set({
              'streakFreezes': streakFreezes,
              'lastFreezeGrantDate': Timestamp.fromDate(now),
            }, SetOptions(merge: true)).ignore();
          }
        }

        final lastActiveTs = d['lastActiveDate'] as Timestamp?;
        if (lastActiveTs != null) {
          final lastDay = _dateOnly(lastActiveTs.toDate());
          final yesterday = _dateOnly(
              DateTime.now().subtract(const Duration(days: 1)));
          if (lastDay.isBefore(yesterday)) {
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

      if (dailySnap.exists) {
        final d = dailySnap.data()!;
        final raw =
            (d['habitCompletions'] as Map<String, dynamic>?) ?? {};
        completions =
            raw.map((k, v) => MapEntry(k, (v as num).toInt()));
        intentionsSetToday = (d['intentionsSet'] as bool?) ?? false;
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
          isLoading: false,
          showComebackBonus: showComebackBonus,
          previousStreak: previousStreak,
          intentionsSetToday: intentionsSetToday,
        );
      }
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  // ── Actions ──────────────────────────────────────────────────

  Future<void> completeHabit({
    required String habitId,
    required int xpReward,
    required int goldReward,
    required int frequencyTarget,
  }) async {
    final current = state.completions[habitId] ?? 0;
    if (current >= frequencyTarget) return;

    final newCompletions = Map<String, int>.from(state.completions)
      ..[habitId] = current + 1;

    final result = XpCalculator.applyXpGain(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpGained: xpReward,
    );

    final isFirstToday = state.completions.isEmpty;
    final newStreak = isFirstToday ? state.streak + 1 : state.streak;
    final newLongest =
        newStreak > state.longestStreak ? newStreak : state.longestStreak;
    final newGold = state.gold + goldReward;
    final newTotal = state.totalCompletions + 1;

    // ── Streak milestone check ───────────────────────────────
    int? newMilestone;
    for (final m in kStreakMilestones) {
      if (newStreak == m && state.streak < m) {
        newMilestone = m;
        break;
      }
    }
    final milestoneBonusXp =
        newMilestone != null ? milestoneXpBonus(newMilestone) : 0;

    // ── Achievement check ────────────────────────────────────
    final newly = AchievementCatalog.locked(state.unlockedAchievements)
        .where((a) => switch (a.trigger) {
              AchievementTrigger.streak => newStreak >= a.threshold,
              AchievementTrigger.level =>
                result.newLevel >= a.threshold,
              AchievementTrigger.totalCompletions =>
                newTotal >= a.threshold,
              _ => false,
            })
        .toList();

    final newUnlockedIds = [
      ...state.unlockedAchievements,
      ...newly.map((a) => a.id),
    ];

    // XP + gold bonus from achievements + milestone
    int bonusXp =
        newly.fold(0, (s, a) => s + a.xpReward) + milestoneBonusXp;
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
      didJustLevelUp:
          bonusResult.newLevel > state.level,
      lastCompletedId: habitId,
      setMilestone: newMilestone,
    );

    if (_uid == null) return;

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
          'lastActiveDate': Timestamp.fromDate(now),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (_) {}
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

  /// Dismiss the "you're back" card and grant the +50 XP comeback bonus.
  Future<void> acknowledgeComeback() async {
    if (!state.showComebackBonus) return;
    final result = XpCalculator.applyXpGain(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpGained: 50,
    );
    state = state.copyWith(
      showComebackBonus: false,
      level: result.newLevel,
      currentLevelXp: result.newCurrentLevelXp,
      cumulativeXp: result.newCumulativeXp,
      didJustLevelUp: result.newLevel > state.level,
    );
    if (_uid == null) return;
    _userRef.set({
      'level': result.newLevel,
      'currentLevelXp': result.newCurrentLevelXp,
      'cumulativeXp': result.newCumulativeXp,
    }, SetOptions(merge: true)).ignore();
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
    if (_uid == null) return;
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
    if (_uid == null) return;
    _userRef.set({
      'level': result.newLevel,
      'currentLevelXp': result.newCurrentLevelXp,
      'cumulativeXp': result.newCumulativeXp,
      'gold': newGold,
    }, SetOptions(merge: true)).ignore();
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
