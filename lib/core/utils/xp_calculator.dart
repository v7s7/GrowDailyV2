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
}
