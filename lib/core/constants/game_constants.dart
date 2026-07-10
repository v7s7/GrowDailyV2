abstract final class GameConstants {
  // XP scaling: xpToNextLevel = level * xpPerLevel
  static const int xpPerLevel = 100;
  static const int maxLevel = 100;

  // Streak milestone bonuses (one-time XP awarded the day a streak first
  // reaches each threshold). This is the single source of truth for
  // milestone XP — read by XpCalculator.streakMilestoneBonus, which
  // DashboardNotifier calls instead of keeping its own copy.
  //
  // Reconciled 2026: this map previously held different (lower) values than
  // what DashboardNotifier actually paid out via a private duplicate
  // switch. The numbers below are the ones that were actually live in the
  // app; the stale duplicate has been removed rather than the reverse, per
  // the rule of not silently changing an economy players are already in.
  static const Map<int, int> streakBonuses = {
    3: 25,
    7: 75,
    14: 150,
    30: 300,
    60: 600,
    100: 1500,
  };

  // Default XP/Gold rewards by habit category, keyed by HabitCategory.name.
  // Used as the reward for a user-created custom habit (catalog/preset
  // habits carry their own hand-tuned per-habit reward instead — see
  // IslamicHabitCatalog). Single source of truth: CustomHabitsNotifier reads
  // these instead of keeping its own copy.
  //
  // Reconciled 2026: 'custom' previously disagreed with the value actually
  // being paid out (10/5 here vs. 20/8 live) — kept the live value.
  static const Map<String, int> categoryXpRewards = {
    'quran': 30,
    'athkar': 15,
    'fitness': 20,
    'fasting': 40,
    'sadaqah': 25,
    'sleep': 15,
    'custom': 20,
    'faith': 20,
    'health': 20,
    'learning': 20,
    'focus': 20,
    'money': 20,
    'mind': 20,
    'social': 20,
  };

  static const Map<String, int> categoryGoldRewards = {
    'quran': 10,
    'athkar': 5,
    'fitness': 8,
    'fasting': 15,
    'sadaqah': 10,
    'sleep': 5,
    'custom': 8,
    'faith': 8,
    'health': 8,
    'learning': 8,
    'focus': 8,
    'money': 8,
    'mind': 8,
    'social': 8,
  };

  // Flat XP/Gold reward for completing a Matrix (Tasks) item, regardless of
  // quadrant. Matches the 'custom' habit-category tier above — a task is an
  // uncategorized user action, same standing as a custom habit with no
  // matched category. Read by MatrixNotifier.toggle(); paid out once per
  // task (tracked by MatrixTask.rewarded) and never reversed on
  // un-complete, unlike habit XP — see MatrixNotifier.toggle for why.
  static const int matrixTaskXpReward = 20;
  static const int matrixTaskGoldReward = 8;

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
