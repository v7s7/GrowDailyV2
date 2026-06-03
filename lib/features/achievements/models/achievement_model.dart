enum AchievementRarity {
  common,
  uncommon,
  rare,
  epic,
  legendary;

  String get displayName => switch (this) {
        common => 'Common',
        uncommon => 'Uncommon',
        rare => 'Rare',
        epic => 'Epic',
        legendary => 'Legendary',
      };
}

enum AchievementTrigger {
  streak, // currentStreak reaches threshold
  level, // level reaches threshold
  totalCompletions, // total lifetime completions (any habit)
  habitMastery, // single habit totalCompletions reaches threshold
  special; // manually awarded
}

class AchievementModel {
  final String id;
  final String name;
  final String description;
  final String iconEmoji;
  final AchievementRarity rarity;
  final AchievementTrigger trigger;
  final int threshold;
  final int xpReward;
  final int goldReward;

  const AchievementModel({
    required this.id,
    required this.name,
    required this.description,
    required this.iconEmoji,
    required this.rarity,
    required this.trigger,
    required this.threshold,
    required this.xpReward,
    required this.goldReward,
  });
}

/// Static catalog — evaluated client-side against UserAccount state.
abstract final class AchievementCatalog {
  static const List<AchievementModel> all = [
    // ── Streak ──────────────────────────────────────────────────
    AchievementModel(
      id: 'streak_7',
      name: 'Seven Days Strong',
      description: 'Maintain a 7-day streak',
      iconEmoji: '🔥',
      rarity: AchievementRarity.common,
      trigger: AchievementTrigger.streak,
      threshold: 7,
      xpReward: 100,
      goldReward: 25,
    ),
    AchievementModel(
      id: 'streak_30',
      name: 'Month of Mastery',
      description: 'Maintain a 30-day streak',
      iconEmoji: '💪',
      rarity: AchievementRarity.uncommon,
      trigger: AchievementTrigger.streak,
      threshold: 30,
      xpReward: 500,
      goldReward: 100,
    ),
    AchievementModel(
      id: 'streak_100',
      name: 'Century Champion',
      description: 'Maintain a 100-day streak',
      iconEmoji: '👑',
      rarity: AchievementRarity.legendary,
      trigger: AchievementTrigger.streak,
      threshold: 100,
      xpReward: 2000,
      goldReward: 500,
    ),
    // ── Level ───────────────────────────────────────────────────
    AchievementModel(
      id: 'level_10',
      name: 'Awakened',
      description: 'Reach Level 10',
      iconEmoji: '⚡',
      rarity: AchievementRarity.common,
      trigger: AchievementTrigger.level,
      threshold: 10,
      xpReward: 0,
      goldReward: 50,
    ),
    AchievementModel(
      id: 'level_25',
      name: 'Ascendant',
      description: 'Reach Level 25',
      iconEmoji: '🌟',
      rarity: AchievementRarity.rare,
      trigger: AchievementTrigger.level,
      threshold: 25,
      xpReward: 0,
      goldReward: 150,
    ),
    AchievementModel(
      id: 'level_50',
      name: 'Transcendent',
      description: 'Reach Level 50',
      iconEmoji: '🔮',
      rarity: AchievementRarity.epic,
      trigger: AchievementTrigger.level,
      threshold: 50,
      xpReward: 0,
      goldReward: 300,
    ),
    AchievementModel(
      id: 'level_100',
      name: 'Enlightened',
      description: 'Reach the maximum Level 100',
      iconEmoji: '✨',
      rarity: AchievementRarity.legendary,
      trigger: AchievementTrigger.level,
      threshold: 100,
      xpReward: 0,
      goldReward: 1000,
    ),
    // ── Habit Mastery ───────────────────────────────────────────
    AchievementModel(
      id: 'completions_50',
      name: 'Consistent',
      description: 'Complete any habit 50 times total',
      iconEmoji: '🎯',
      rarity: AchievementRarity.common,
      trigger: AchievementTrigger.totalCompletions,
      threshold: 50,
      xpReward: 150,
      goldReward: 30,
    ),
    AchievementModel(
      id: 'completions_500',
      name: 'Devoted',
      description: 'Complete habits 500 times total',
      iconEmoji: '🏆',
      rarity: AchievementRarity.rare,
      trigger: AchievementTrigger.totalCompletions,
      threshold: 500,
      xpReward: 750,
      goldReward: 200,
    ),
    // ── Islamic-specific ────────────────────────────────────────
    AchievementModel(
      id: 'quran_100',
      name: 'Keeper of the Word',
      description: 'Complete a Quran habit 100 times',
      iconEmoji: '📖',
      rarity: AchievementRarity.rare,
      trigger: AchievementTrigger.habitMastery,
      threshold: 100,
      xpReward: 750,
      goldReward: 200,
    ),
  ];

  static AchievementModel? findById(String id) {
    try {
      return all.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Returns all achievements that [unlockedIds] has NOT yet unlocked.
  static List<AchievementModel> locked(List<String> unlockedIds) =>
      all.where((a) => !unlockedIds.contains(a.id)).toList();
}
