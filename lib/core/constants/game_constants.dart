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
  //
  // Extended 2026-08 to close the two worst gaps in the ladder. The original
  // six stopped at 100 while the achievement ladder ran to 365, so a person
  // on day 101 faced 264 CONSECUTIVE days of unbroken effort with no
  // recognition of any kind: the single worst spacing failure in the app.
  // 21 was added for the opposite reason, it was the one streak threshold
  // that already gated something (misbah_red at 300 gold) while paying
  // nothing, an orphan gate that existed only because an accessory was
  // priced there.
  //
  // The six original values are untouched, per the same rule that governs
  // this map's own history: never silently change an economy players are
  // already inside. Growth at the top is additive and can only ever feel
  // generous.
  static const Map<int, int> streakBonuses = {
    3: 25,
    7: 75,
    14: 150,
    21: 200,
    30: 300,
    60: 600,
    100: 1500,
    150: 2500,
    200: 3000,
    250: 3500,
    300: 4000,
    365: 6000,
  };

  // Per-habit streak milestone bonuses — same thresholds as [streakBonuses]
  // for a consistent "meaningful day counts" vocabulary across the app, but
  // scaled to roughly a third of the app-wide payout. A user can have many
  // habits each independently crossing these thresholds, so paying the full
  // app-wide amount per habit would inflate the XP economy fast; this keeps
  // each one feeling like a genuine bonus without dwarfing everything else.
  //
  // Only 21 was added when [streakBonuses] was extended, and the long rungs
  // (150 through 365) deliberately were NOT. This map is paid PER HABIT, so
  // an account whose habits were all created together crosses every
  // threshold on the same day: five habits reaching 365 would have paid
  // 8,250 XP in one afternoon. The long-run recognition belongs on the
  // app-wide ladder, which fires once.
  static const Map<int, int> habitStreakBonuses = {
    3: 10,
    7: 25,
    14: 50,
    21: 65,
    30: 100,
    60: 200,
    100: 500,
  };

  // Chance (per habit completion, independent of streaks/milestones) of an
  // occasional surprise bonus — the "variable reward" moment habit trackers
  // like Duolingo/Habitica use to make completing something feel exciting
  // rather than administrative. Deliberately modest on both axes: ~1-in-7
  // completions (not rare enough to never show up, not common enough to
  // become the expected baseline), capped at half again the habit's normal
  // reward (see DashboardNotifier.completeHabit) — always a bonus on top of
  // the real reward, never a substitute for it, and never a loss.
  static const double surpriseBonusChance = 0.15;
  static const double surpriseBonusMultiplier = 0.5;

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
  // quadrant. Read by MatrixNotifier.toggle(); paid out once per task
  // (tracked by MatrixTask.rewarded) and never reversed on un-complete,
  // unlike habit XP, see MatrixNotifier.toggle for why.
  //
  // Priced BELOW the cheapest habit tier (athkar, 15 XP / 5 gold), where it
  // used to match 'custom' at 20/8. A task is the cheapest thing in the app
  // to manufacture: one non-whitespace character and one tap, with no
  // creation limit and no premium gate, while a habit is capped per tier and
  // carries a category, a streak ladder, a green square and a room
  // multiplier that a task carries none of. At the old rate a full day of
  // tasks paid 1.8x a full day of habits, so the cheapest thing to make
  // outearned the thing the app exists to encourage. At 10/4 a maximal task
  // day sits just under a five-habit day, which is the correct ordering and
  // the whole point.
  static const int matrixTaskXpReward = 10;
  static const int matrixTaskGoldReward = 4;

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
