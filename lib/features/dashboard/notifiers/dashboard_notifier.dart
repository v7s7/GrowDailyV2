import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/xp_calculator.dart';

class DashboardState {
  final int level;
  final int currentLevelXp;
  final int cumulativeXp;
  final int gold;
  final int streak;
  final Map<String, int> completions;
  final bool didJustLevelUp;
  final String? lastCompletedId;

  const DashboardState({
    required this.level,
    required this.currentLevelXp,
    required this.cumulativeXp,
    required this.gold,
    required this.streak,
    required this.completions,
    this.didJustLevelUp = false,
    this.lastCompletedId,
  });

  factory DashboardState.initial() => const DashboardState(
        level: 1,
        currentLevelXp: 0,
        cumulativeXp: 0,
        gold: 0,
        streak: 0,
        completions: {},
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
    Map<String, int>? completions,
    bool didJustLevelUp = false,
    String? lastCompletedId,
  }) =>
      DashboardState(
        level: level ?? this.level,
        currentLevelXp: currentLevelXp ?? this.currentLevelXp,
        cumulativeXp: cumulativeXp ?? this.cumulativeXp,
        gold: gold ?? this.gold,
        streak: streak ?? this.streak,
        completions: completions ?? this.completions,
        didJustLevelUp: didJustLevelUp,
        lastCompletedId: lastCompletedId ?? this.lastCompletedId,
      );
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  DashboardNotifier() : super(DashboardState.initial());

  void completeHabit({
    required String habitId,
    required int xpReward,
    required int goldReward,
    required int frequencyTarget,
  }) {
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

    state = state.copyWith(
      level: result.newLevel,
      currentLevelXp: result.newCurrentLevelXp,
      cumulativeXp: result.newCumulativeXp,
      gold: state.gold + goldReward,
      completions: newCompletions,
      didJustLevelUp: result.newLevel > state.level,
      lastCompletedId: habitId,
    );
  }
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>(
  (ref) => DashboardNotifier(),
);
