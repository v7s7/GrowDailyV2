import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/xp_calculator.dart';
import '../../auth/notifiers/auth_notifier.dart';

class DashboardState {
  final int level;
  final int currentLevelXp;
  final int cumulativeXp;
  final int gold;
  final int streak;
  final int longestStreak;
  final Map<String, int> completions;
  final bool didJustLevelUp;
  final String? lastCompletedId;
  final bool isLoading;

  const DashboardState({
    required this.level,
    required this.currentLevelXp,
    required this.cumulativeXp,
    required this.gold,
    required this.streak,
    this.longestStreak = 0,
    required this.completions,
    this.didJustLevelUp = false,
    this.lastCompletedId,
    this.isLoading = false,
  });

  factory DashboardState.initial() => const DashboardState(
        level: 1,
        currentLevelXp: 0,
        cumulativeXp: 0,
        gold: 0,
        streak: 0,
        longestStreak: 0,
        completions: {},
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
    Map<String, int>? completions,
    bool didJustLevelUp = false,
    String? lastCompletedId,
    bool? isLoading,
  }) =>
      DashboardState(
        level: level ?? this.level,
        currentLevelXp: currentLevelXp ?? this.currentLevelXp,
        cumulativeXp: cumulativeXp ?? this.cumulativeXp,
        gold: gold ?? this.gold,
        streak: streak ?? this.streak,
        longestStreak: longestStreak ?? this.longestStreak,
        completions: completions ?? this.completions,
        didJustLevelUp: didJustLevelUp,
        lastCompletedId: lastCompletedId ?? this.lastCompletedId,
        isLoading: isLoading ?? this.isLoading,
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
          longestStreak = 0;
      Map<String, int> completions = {};

      if (userSnap.exists) {
        final d = userSnap.data()!;
        level = (d['level'] as int?) ?? 1;
        currentLevelXp = (d['currentLevelXp'] as int?) ?? 0;
        cumulativeXp = (d['cumulativeXp'] as int?) ?? 0;
        gold = (d['gold'] as int?) ?? 0;
        streak = (d['currentStreak'] as int?) ?? 0;
        longestStreak = (d['longestStreak'] as int?) ?? 0;

        // Reset streak if last active day was before yesterday
        final lastActiveTs = d['lastActiveDate'] as Timestamp?;
        if (lastActiveTs != null) {
          final lastDay = _dateOnly(lastActiveTs.toDate());
          final yesterday = _dateOnly(
              DateTime.now().subtract(const Duration(days: 1)));
          if (lastDay.isBefore(yesterday)) {
            streak = 0;
            // Write reset back so it's correct next open
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
      }

      if (mounted) {
        state = DashboardState(
          level: level,
          currentLevelXp: currentLevelXp,
          cumulativeXp: cumulativeXp,
          gold: gold,
          streak: streak,
          longestStreak: longestStreak,
          completions: completions,
          isLoading: false,
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

    // First completion of today increments streak
    final isFirstToday = state.completions.isEmpty;
    final newStreak = isFirstToday ? state.streak + 1 : state.streak;
    final newLongest = newStreak > state.longestStreak
        ? newStreak
        : state.longestStreak;
    final newGold = state.gold + goldReward;

    state = state.copyWith(
      level: result.newLevel,
      currentLevelXp: result.newCurrentLevelXp,
      cumulativeXp: result.newCumulativeXp,
      gold: newGold,
      streak: newStreak,
      longestStreak: newLongest,
      completions: newCompletions,
      didJustLevelUp: result.newLevel > state.level,
      lastCompletedId: habitId,
    );

    if (_uid == null) return;

    try {
      final now = DateTime.now();
      final batch = FirebaseFirestore.instance.batch();

      // Daily log (create or merge)
      batch.set(
        _dailyRef,
        {
          'habitCompletions': newCompletions,
          'date': Timestamp.fromDate(now),
        },
        SetOptions(merge: true),
      );

      // User stats
      batch.set(
        _userRef,
        {
          'level': result.newLevel,
          'currentLevelXp': result.newCurrentLevelXp,
          'cumulativeXp': result.newCumulativeXp,
          'gold': newGold,
          'currentStreak': newStreak,
          'longestStreak': newLongest,
          'lastActiveDate': Timestamp.fromDate(now),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (_) {
      // Local state already updated — silent fail keeps UX smooth
    }
  }

  Future<void> refresh() => _loadToday();
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  // Recreates when auth state changes (sign-in / sign-out)
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return DashboardNotifier(uid);
});
