import '../constants/game_constants.dart';

abstract final class XpCalculator {
  /// XP needed to advance from [level] to [level + 1].
  static int xpToNextLevel(int level) =>
      (level * GameConstants.xpPerLevel).clamp(100, 9999);

  /// Applies an XP gain and returns the new level state, handling multi-level-ups.
  static ({
    int newLevel,
    int newCurrentLevelXp,
    int newCumulativeXp,
  }) applyXpGain({
    required int currentLevel,
    required int currentLevelXp,
    required int cumulativeXp,
    required int xpGained,
  }) {
    int level = currentLevel;
    int levelXp = currentLevelXp + xpGained;
    final int cumXp = cumulativeXp + xpGained;

    while (levelXp >= xpToNextLevel(level) &&
        level < GameConstants.maxLevel) {
      levelXp -= xpToNextLevel(level);
      level++;
    }

    return (
      newLevel: level,
      newCurrentLevelXp: levelXp,
      newCumulativeXp: cumXp,
    );
  }

  /// Applies an XP change that may be negative (e.g. a red "failed" square).
  /// Gains delegate to [applyXpGain] for multi-level-up handling. Losses only
  /// trim progress within the current level and never de-level the player or
  /// push cumulative XP negative — losing a square should sting, not undo
  /// genuine earned progress.
  static ({
    int newLevel,
    int newCurrentLevelXp,
    int newCumulativeXp,
  }) applyXpDelta({
    required int currentLevel,
    required int currentLevelXp,
    required int cumulativeXp,
    required int xpDelta,
  }) {
    if (xpDelta >= 0) {
      return applyXpGain(
        currentLevel: currentLevel,
        currentLevelXp: currentLevelXp,
        cumulativeXp: cumulativeXp,
        xpGained: xpDelta,
      );
    }
    final trimmedLevelXp = currentLevelXp + xpDelta;
    final trimmedCumulative = cumulativeXp + xpDelta;
    return (
      newLevel: currentLevel,
      newCurrentLevelXp: trimmedLevelXp < 0 ? 0 : trimmedLevelXp,
      newCumulativeXp: trimmedCumulative < 0 ? 0 : trimmedCumulative,
    );
  }

  /// One-time streak bonus XP at a milestone (returns 0 if not a milestone).
  static int streakMilestoneBonus(int streak) {
    return GameConstants.streakBonuses[streak] ?? 0;
  }

  /// Human-readable level progress percentage, e.g. 0.75 → "75%".
  static double levelProgressRatio(int currentLevelXp, int level) {
    final needed = xpToNextLevel(level);
    return (currentLevelXp / needed).clamp(0.0, 1.0);
  }

  /// One tap's share of a reward that is priced per DAY, not per tap.
  ///
  /// A habit counted N times a day is still worth exactly what it was worth
  /// when it was worth one tap: the day's whole [total] is split across the
  /// N taps rather than paid N times over. Paying per tap would have made
  /// "4 times a day" a 4x XP printer for anyone who noticed, and the number
  /// people actually chose would have been decided by the payout instead of
  /// by the habit.
  ///
  /// [tapIndex] is 0-based and is the count BEFORE this tap, so the tap that
  /// takes a habit from 2 done to 3 done passes 2.
  ///
  /// The floor-difference (rather than total ~/ target) is what makes the
  /// slices sum to exactly [total] with nothing lost to rounding: 10 XP over
  /// 4 taps pays 2, 3, 2, 3 — never 2, 2, 2, 2 with 2 XP quietly evaporating.
  /// A [target] of 1 returns [total] unchanged, so every habit that existed
  /// before this feature pays precisely what it always did.
  static int rewardSliceForTap({
    required int total,
    required int target,
    required int tapIndex,
  }) {
    if (target <= 1) return total;
    final i = tapIndex.clamp(0, target - 1);
    return (total * (i + 1)) ~/ target - (total * i) ~/ target;
  }

  /// What a day's worth of taps has actually paid out by the time [done]
  /// of [target] are done — the sum of every slice already handed over.
  ///
  /// This is what an undo has to give back: clearing a half-finished day
  /// must refund what that day earned, not the full day's price.
  static int rewardPaidSoFar({
    required int total,
    required int target,
    required int done,
  }) {
    if (target <= 1) return done > 0 ? total : 0;
    final d = done.clamp(0, target);
    return (total * d) ~/ target;
  }
}
