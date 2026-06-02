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
