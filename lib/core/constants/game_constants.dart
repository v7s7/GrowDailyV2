abstract final class GameConstants {
  // XP scaling: xpToNextLevel = level * xpPerLevel
  static const int xpPerLevel = 100;
  static const int maxLevel = 100;

  // Streak milestone bonuses (XP awarded at threshold)
  static const Map<int, int> streakBonuses = {
    7: 50,
    30: 200,
    100: 1000,
  };

  // Default XP rewards by habit category
  static const Map<String, int> categoryXpRewards = {
    'quran': 30,
    'athkar': 15,
    'fitness': 20,
    'fasting': 40,
    'sadaqah': 25,
    'sleep': 15,
    'custom': 10,
  };

  // Default Gold rewards by habit category
  static const Map<String, int> categoryGoldRewards = {
    'quran': 10,
    'athkar': 5,
    'fitness': 8,
    'fasting': 15,
    'sadaqah': 10,
    'sleep': 5,
    'custom': 5,
  };

  // Hive box names
  static const String boxUserAccount = 'box_user_account';
  static const String boxHabits = 'box_habits';
  static const String boxDailyLogs = 'box_daily_logs';
  static const String boxSettings = 'box_settings';

  // Hive type IDs (must be unique across entire app)
  static const int hiveTypeUserAccount = 0;
  static const int hiveTypeHabitModel = 1;
  static const int hiveTypeDailyLogModel = 2;
  static const int hiveTypeAchievementModel = 3;
}
