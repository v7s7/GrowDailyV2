abstract final class FirebaseConstants {
  // Top-level collections
  static const String colUsers = 'users';

  // Sub-collections under users/{uid}/
  static const String subHabits = 'habits';
  static const String subDaily = 'daily';

  // Firestore path builders
  static String userDoc(String uid) => '$colUsers/$uid';
  static String habitDoc(String uid, String habitId) =>
      '$colUsers/$uid/$subHabits/$habitId';
  static String dailyLogDoc(String uid, String dateKey) =>
      '$colUsers/$uid/$subDaily/$dateKey';

  // UserAccount field names
  static const String fDisplayName = 'displayName';
  static const String fAvatarUrl = 'avatarUrl';
  static const String fLevel = 'level';
  static const String fCumulativeXp = 'cumulativeXp';
  static const String fCurrentLevelXp = 'currentLevelXp';
  static const String fGold = 'gold';
  static const String fCurrentStreak = 'currentStreak';
  static const String fLongestStreak = 'longestStreak';
  static const String fLastActiveDate = 'lastActiveDate';
  static const String fUnlockedAchievements = 'unlockedAchievements';
  static const String fEquippedHabitIds = 'equippedHabitIds';
  static const String fCreatedAt = 'createdAt';

  // HabitModel field names
  static const String fHabitName = 'name';
  static const String fHabitCategory = 'category';
  static const String fFrequencyType = 'frequencyType';
  static const String fFrequencyTarget = 'frequencyTarget';
  static const String fIsPreset = 'isPreset';
  static const String fCatalogId = 'catalogId';
  static const String fHasTimer = 'hasTimer';
  static const String fTimerDurationSeconds = 'timerDurationSeconds';
  static const String fXpReward = 'xpReward';
  static const String fGoldReward = 'goldReward';
  static const String fTotalCompletions = 'totalCompletions';
  static const String fIsArchived = 'isArchived';

  // DailyLogModel field names
  static const String fHabitCompletions = 'habitCompletions';
  static const String fTimerSeconds = 'timerSeconds';
  static const String fTotalXpEarned = 'totalXpEarned';
  static const String fTotalGoldEarned = 'totalGoldEarned';
  static const String fLastUpdated = 'lastUpdated';
}
