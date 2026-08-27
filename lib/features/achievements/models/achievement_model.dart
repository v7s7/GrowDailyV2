import 'package:flutter/material.dart';

/// Shared rarity scale — still used by AccessoryModel (character/models/
/// accessory.dart) for shop-item rarity, which is why this enum itself
/// isn't going anywhere even though [AchievementModel] no longer reads it
/// for its own presentation (see [AchievementTier] for what replaced that).
enum AchievementRarity {
  common,
  uncommon,
  rare,
  epic,
  legendary;

  /// Locale-aware rarity label for the achievement-card badge (e.g.
  /// "RARE"/"نادر") — was English-only before, showing untranslated even
  /// with the app set to Arabic.
  String localizedName(bool isAr) => isAr
      ? switch (this) {
          common => 'شائع',
          uncommon => 'غير شائع',
          rare => 'نادر',
          epic => 'ملحمي',
          legendary => 'أسطوري',
        }
      : switch (this) {
          common => 'Common',
          uncommon => 'Uncommon',
          rare => 'Rare',
          epic => 'Epic',
          legendary => 'Legendary',
        };
}

/// Bronze → Platinum: the medal a single achievement represents. Every
/// family in [AchievementCatalog] climbs through all four in order, from
/// its easiest unlock (bronze) to its hardest (platinum) — this is the
/// primary visual signal an achievement carries now, replacing the old
/// bare [AchievementRarity] label on achievement cards.
enum AchievementTier {
  bronze,
  silver,
  gold,
  platinum;

  /// I → IV, painted inside the medal itself. Colour alone used to be the
  /// only thing separating the four rungs of a family, and since every
  /// medal in a family also carries the *same* trigger icon (see
  /// [achievementIconFor]), a ladder read as one glyph repeated four times
  /// in four shades — unreadable at a glance for anyone who doesn't already
  /// know bronze-silver-gold-platinum by hue, and outright ambiguous for
  /// the ~8% of men with a red-green deficiency. The numeral carries the
  /// ordering on its own, with colour as reinforcement rather than the
  /// sole signal.
  String get numeral => switch (this) {
        bronze => 'I',
        silver => 'II',
        gold => 'III',
        platinum => 'IV',
      };

  String localizedName(bool isAr) => isAr
      ? switch (this) {
          bronze => 'برونزية',
          silver => 'فضية',
          gold => 'ذهبية',
          platinum => 'بلاتينية',
        }
      : switch (this) {
          bronze => 'Bronze',
          silver => 'Silver',
          gold => 'Gold',
          platinum => 'Platinum',
        };
}

enum AchievementTrigger {
  streak, // currentStreak reaches threshold
  level, // level reaches threshold
  totalCompletions, // total lifetime completions (any habit)
  habitMastery, // single habit totalCompletions reaches threshold
  greenSquares, // lifetime green/bonus grid squares + every habit
  // completion that doesn't get its own square (multi-tap habits — see
  // DashboardNotifier.completeHabit's doc comment on newTotalGreenSquares)
  special; // manually awarded
}

class AchievementModel {
  final String id;

  /// Groups this achievement with the other tiers of the same chain (e.g.
  /// every streak achievement shares familyId 'streak') — see
  /// [AchievementCatalog.families] and [AchievementCatalog.tiersFor]. Every
  /// family climbs bronze → silver → gold → platinum via [tier].
  final String familyId;

  final String name;
  // Arabic counterpart to [name] — read through [localName], which falls
  // back to the English string for anything not yet translated (there
  // shouldn't be any; every entry in the catalog below sets both).
  final String nameAr;
  final String description;
  final String descriptionAr;
  final AchievementTier tier;
  final AchievementTrigger trigger;
  final int threshold;
  final int xpReward;
  final int goldReward;

  /// Only used by [AchievementTrigger.habitMastery] — the habit-category
  /// name (e.g. 'quran') whose lifetime completions must reach [threshold].
  final String? targetCategory;

  const AchievementModel({
    required this.id,
    required this.familyId,
    required this.name,
    this.nameAr = '',
    required this.description,
    this.descriptionAr = '',
    required this.tier,
    required this.trigger,
    required this.threshold,
    required this.xpReward,
    required this.goldReward,
    this.targetCategory,
  });

  String localName(bool isAr) =>
      isAr && nameAr.trim().isNotEmpty ? nameAr : name;

  String localDescription(bool isAr) =>
      isAr && descriptionAr.trim().isNotEmpty ? descriptionAr : description;
}

/// One achievement chain's shared identity — the icon and title shown once
/// per family (see AchievementsScreen's family-ladder cards), not repeated
/// per tier the way [AchievementModel.name] is.
class AchievementFamily {
  final String id;
  final String title;
  final String titleAr;
  final IconData icon;

  const AchievementFamily({
    required this.id,
    required this.title,
    required this.titleAr,
    required this.icon,
  });

  String localTitle(bool isAr) => isAr ? titleAr : title;
}

/// Static catalog — evaluated client-side against UserAccount state.
abstract final class AchievementCatalog {
  static const List<AchievementFamily> families = [
    AchievementFamily(
      id: 'streak',
      title: 'Unbroken',
      titleAr: 'بدون انقطاع',
      icon: Icons.local_fire_department_rounded,
    ),
    AchievementFamily(
      id: 'level',
      title: 'The Climb',
      titleAr: 'الصعود',
      icon: Icons.bolt_rounded,
    ),
    AchievementFamily(
      id: 'completions',
      title: 'Steady',
      titleAr: 'الثبات',
      icon: Icons.check_circle_rounded,
    ),
    AchievementFamily(
      id: 'grid',
      title: 'The Grid',
      titleAr: 'الشبكة',
      icon: Icons.grid_view_rounded,
    ),
    AchievementFamily(
      id: 'quran',
      title: 'Daily Quran',
      titleAr: 'ورد القرآن',
      icon: Icons.menu_book_rounded,
    ),
    // Appended, never inserted beside their sibling ladders:
    // achievements_screen.dart renders `families` in list order, so slotting
    // 'ascent' next to 'level' would silently reorder a shipped screen.
    //
    // النَفَس carries the fatha on purpose: undiacritised نفس reads as نَفْس
    // (self) rather than نَفَس (breath).
    AchievementFamily(
      id: 'ascent',
      title: 'Thin Air',
      titleAr: 'المرتفعات',
      icon: Icons.terrain_rounded,
    ),
    AchievementFamily(
      id: 'endurance',
      title: 'The Long Haul',
      titleAr: 'النَفَس الطويل',
      icon: Icons.hourglass_bottom_rounded,
    ),
  ];

  static const List<AchievementModel> all = [
    // ── Streak ──────────────────────────────────────────────────
    AchievementModel(
      id: 'streak_7',
      familyId: 'streak',
      tier: AchievementTier.bronze,
      name: 'A Full Week',
      nameAr: 'أسبوع كامل',
      description: 'A 7-day streak',
      descriptionAr: 'سلسلة 7 أيام متواصلة',
      trigger: AchievementTrigger.streak,
      threshold: 7,
      xpReward: 100,
      goldReward: 25,
    ),
    AchievementModel(
      id: 'streak_30',
      familyId: 'streak',
      tier: AchievementTier.silver,
      name: 'A Month Straight',
      nameAr: 'شهر ما انقطع',
      description: 'A 30-day streak',
      descriptionAr: 'سلسلة 30 يوم متواصلة',
      trigger: AchievementTrigger.streak,
      threshold: 30,
      xpReward: 500,
      goldReward: 100,
    ),
    AchievementModel(
      id: 'streak_100',
      familyId: 'streak',
      tier: AchievementTier.gold,
      name: 'A Hundred Days',
      nameAr: 'مية يوم',
      description: 'A 100-day streak',
      descriptionAr: 'سلسلة 100 يوم متواصلة',
      trigger: AchievementTrigger.streak,
      threshold: 100,
      xpReward: 2000,
      goldReward: 500,
    ),
    AchievementModel(
      id: 'streak_365',
      familyId: 'streak',
      tier: AchievementTier.platinum,
      name: 'A Year, No Gaps',
      nameAr: 'سنة ما فاتها يوم',
      description: 'A 365-day streak',
      descriptionAr: 'سلسلة 365 يوم متواصلة',
      trigger: AchievementTrigger.streak,
      threshold: 365,
      xpReward: 6000,
      goldReward: 1500,
    ),
    // ── Level ───────────────────────────────────────────────────
    AchievementModel(
      id: 'level_10',
      familyId: 'level',
      tier: AchievementTier.bronze,
      name: 'First Rung',
      nameAr: 'أول درجة',
      description: 'Reach level 10',
      descriptionAr: 'الوصول للمستوى 10',
      trigger: AchievementTrigger.level,
      threshold: 10,
      xpReward: 0,
      goldReward: 50,
    ),
    AchievementModel(
      id: 'level_25',
      familyId: 'level',
      tier: AchievementTier.silver,
      name: 'Halfway Up',
      nameAr: 'نص السلّم',
      description: 'Reach level 25',
      descriptionAr: 'الوصول للمستوى 25',
      trigger: AchievementTrigger.level,
      threshold: 25,
      xpReward: 0,
      goldReward: 150,
    ),
    AchievementModel(
      id: 'level_50',
      familyId: 'level',
      tier: AchievementTier.gold,
      name: 'Top of the Ladder',
      nameAr: 'فوق السلّم',
      description: 'Reach level 50',
      descriptionAr: 'الوصول للمستوى 50',
      trigger: AchievementTrigger.level,
      threshold: 50,
      xpReward: 0,
      goldReward: 300,
    ),
    AchievementModel(
      id: 'level_100',
      familyId: 'level',
      tier: AchievementTier.platinum,
      name: 'The Summit',
      nameAr: 'القمة',
      description: 'Reach level 100, the maximum',
      descriptionAr: 'الوصول لأعلى مستوى: 100',
      trigger: AchievementTrigger.level,
      threshold: 100,
      xpReward: 0,
      goldReward: 1000,
    ),
    // ── Consistency (total lifetime completions) ───────────────
    AchievementModel(
      id: 'completions_50',
      familyId: 'completions',
      tier: AchievementTier.bronze,
      name: 'Now a Habit',
      nameAr: 'صار عادة',
      description: 'Any habit, 50 times',
      descriptionAr: 'أي عادة، 50 مرة',
      trigger: AchievementTrigger.totalCompletions,
      threshold: 50,
      xpReward: 150,
      goldReward: 30,
    ),
    AchievementModel(
      id: 'completions_500',
      familyId: 'completions',
      tier: AchievementTier.silver,
      name: 'Steady',
      nameAr: 'ثابت',
      description: 'Habits, 500 times',
      descriptionAr: 'العادات، 500 مرة',
      trigger: AchievementTrigger.totalCompletions,
      threshold: 500,
      xpReward: 750,
      goldReward: 200,
    ),
    AchievementModel(
      id: 'completions_2000',
      familyId: 'completions',
      tier: AchievementTier.gold,
      name: 'Nothing Stops It',
      nameAr: 'ما يوقفه شي',
      description: 'Habits, 2,000 times',
      descriptionAr: 'العادات، 2000 مرة',
      trigger: AchievementTrigger.totalCompletions,
      threshold: 2000,
      xpReward: 2500,
      goldReward: 600,
    ),
    AchievementModel(
      id: 'completions_5000',
      familyId: 'completions',
      tier: AchievementTier.platinum,
      name: 'Legend',
      nameAr: 'أسطورة',
      description: 'Habits, 5,000 times',
      descriptionAr: 'العادات، 5000 مرة',
      trigger: AchievementTrigger.totalCompletions,
      threshold: 5000,
      xpReward: 6000,
      goldReward: 1500,
    ),
    // ── Quran Devotion ───────────────────────────────────────────
    AchievementModel(
      id: 'quran_25',
      familyId: 'quran',
      tier: AchievementTier.bronze,
      name: 'Never Misses a Reading',
      nameAr: 'ما يفوته ورد',
      description: 'A Quran habit, 25 times',
      descriptionAr: 'عادة قرآن، 25 مرة',
      trigger: AchievementTrigger.habitMastery,
      threshold: 25,
      xpReward: 150,
      goldReward: 40,
      targetCategory: 'quran',
    ),
    AchievementModel(
      id: 'quran_100',
      familyId: 'quran',
      tier: AchievementTier.silver,
      name: 'Keeper of the Reading',
      nameAr: 'صاحب الورد',
      description: 'A Quran habit, 100 times',
      descriptionAr: 'عادة قرآن، 100 مرة',
      trigger: AchievementTrigger.habitMastery,
      threshold: 100,
      xpReward: 750,
      goldReward: 200,
      targetCategory: 'quran',
    ),
    AchievementModel(
      id: 'quran_300',
      familyId: 'quran',
      tier: AchievementTier.gold,
      name: 'Companion of the Mushaf',
      nameAr: 'رفيق المصحف',
      description: 'A Quran habit, 300 times',
      descriptionAr: 'عادة قرآن، 300 مرة',
      trigger: AchievementTrigger.habitMastery,
      threshold: 300,
      xpReward: 2000,
      goldReward: 500,
      targetCategory: 'quran',
    ),
    AchievementModel(
      id: 'quran_1000',
      familyId: 'quran',
      tier: AchievementTier.platinum,
      name: 'Light upon Light',
      nameAr: 'نور على نور',
      description: 'A Quran habit, 1,000 times',
      descriptionAr: 'عادة قرآن، 1000 مرة',
      trigger: AchievementTrigger.habitMastery,
      threshold: 1000,
      xpReward: 5000,
      goldReward: 1200,
      targetCategory: 'quran',
    ),
    // ── Victory Grid ────────────────────────────────────────────
    AchievementModel(
      id: 'green_1',
      familyId: 'grid',
      tier: AchievementTier.bronze,
      name: 'First Square',
      nameAr: 'أول مربّع',
      description: 'The first colored square on the Grid',
      descriptionAr: 'أول مربّع ملوّن في الشبكة',
      trigger: AchievementTrigger.greenSquares,
      threshold: 1,
      xpReward: 25,
      goldReward: 10,
    ),
    AchievementModel(
      id: 'green_100',
      familyId: 'grid',
      tier: AchievementTier.silver,
      name: 'A Hundred Squares',
      nameAr: 'مية مربّع',
      description: '100 colored squares on the Grid',
      descriptionAr: '100 مربّع ملوّن في الشبكة',
      trigger: AchievementTrigger.greenSquares,
      threshold: 100,
      xpReward: 200,
      goldReward: 50,
    ),
    AchievementModel(
      id: 'green_500',
      familyId: 'grid',
      tier: AchievementTier.gold,
      name: 'Colored In',
      nameAr: 'شبكة ملوّنة',
      description: '500 colored squares on the Grid',
      descriptionAr: '500 مربّع ملوّن في الشبكة',
      trigger: AchievementTrigger.greenSquares,
      threshold: 500,
      xpReward: 600,
      goldReward: 150,
    ),
    AchievementModel(
      id: 'green_2000',
      familyId: 'grid',
      tier: AchievementTier.platinum,
      name: 'A Full Canvas',
      nameAr: 'لوحة كاملة',
      description: '2,000 colored squares on the Grid',
      descriptionAr: '2000 مربّع ملوّن في الشبكة',
      trigger: AchievementTrigger.greenSquares,
      threshold: 2000,
      xpReward: 2500,
      goldReward: 600,
    ),
    // ── Ascent: the level rungs above 35 ────────────────────────
    //
    // A SEPARATE family rather than extra rungs on 'level'. The catalog test
    // indexes tiersFor('level') by position and requires exactly four, so
    // extending it would break two assertions at once.
    //
    // xpReward is 0 on all four for the same reason it is 0 on the shipped
    // level medals: _resolveUnlocks feeds achievement XP back through
    // applyXpGain inside its own fixed-point loop, so a level medal paying
    // XP would advance the very ladder that granted it.
    AchievementModel(
      id: 'ascent_40',
      familyId: 'ascent',
      tier: AchievementTier.bronze,
      name: 'Above the Foothills',
      nameAr: 'السفح صار تحت',
      description: 'Reach level 40',
      descriptionAr: 'الوصول للمستوى 40',
      trigger: AchievementTrigger.level,
      threshold: 40,
      xpReward: 0,
      goldReward: 75,
    ),
    AchievementModel(
      id: 'ascent_60',
      familyId: 'ascent',
      tier: AchievementTier.silver,
      name: 'Past the Clouds',
      nameAr: 'فوق الغيم',
      description: 'Reach level 60',
      descriptionAr: 'الوصول للمستوى 60',
      trigger: AchievementTrigger.level,
      threshold: 60,
      xpReward: 0,
      goldReward: 125,
    ),
    AchievementModel(
      id: 'ascent_75',
      familyId: 'ascent',
      tier: AchievementTier.gold,
      name: 'Three Quarters Up',
      nameAr: 'باقي الربع',
      description: 'Reach level 75',
      descriptionAr: 'الوصول للمستوى 75',
      trigger: AchievementTrigger.level,
      threshold: 75,
      xpReward: 0,
      goldReward: 175,
    ),
    AchievementModel(
      id: 'ascent_90',
      familyId: 'ascent',
      tier: AchievementTier.platinum,
      name: 'The Summit in Sight',
      nameAr: 'القمة بانت',
      description: 'Reach level 90',
      descriptionAr: 'الوصول للمستوى 90',
      trigger: AchievementTrigger.level,
      threshold: 90,
      xpReward: 0,
      goldReward: 250,
    ),
    // ── Endurance: the streak rungs past 100 ────────────────────
    //
    // Thresholds match the four long rungs of GameConstants.streakBonuses,
    // so the medal and the milestone XP land on the same day: one
    // celebration rather than two drifting out of sync.
    //
    // goldReward is 0 on all four, and that is a design call. A 300-day
    // unbroken streak means this player has never needed a streak freeze and
    // will never buy freeze capacity, so paying them gold aims the largest
    // payout in the cycle at the one segment its only sink cannot reach. It
    // would also read as a demotion: each rung would pay less than the 500
    // gold already collected at streak_100, for fifty more days of work. A
    // family that pays no gold reads as its own kind of medal, exactly as
    // the level family already reads paying no XP.
    //
    // The ids deliberately do NOT begin with 'streak_':
    // achievement_reconciliation_test.dart filters on that literal prefix.
    AchievementModel(
      id: 'endurance_150',
      familyId: 'endurance',
      tier: AchievementTier.bronze,
      name: 'Past the Hundred',
      nameAr: 'عدّت المية',
      description: 'A 150-day streak',
      descriptionAr: 'سلسلة 150 يوم متواصلة',
      trigger: AchievementTrigger.streak,
      threshold: 150,
      xpReward: 1500,
      goldReward: 0,
    ),
    AchievementModel(
      id: 'endurance_200',
      familyId: 'endurance',
      tier: AchievementTier.silver,
      name: 'Two Hundred Down',
      nameAr: 'ميتين يوم',
      description: 'A 200-day streak',
      descriptionAr: 'سلسلة 200 يوم متواصلة',
      trigger: AchievementTrigger.streak,
      threshold: 200,
      xpReward: 2000,
      goldReward: 0,
    ),
    AchievementModel(
      id: 'endurance_250',
      familyId: 'endurance',
      tier: AchievementTier.gold,
      name: 'Still Not Stopping',
      nameAr: 'ما وقفت لي الحين',
      description: 'A 250-day streak',
      descriptionAr: 'سلسلة 250 يوم متواصلة',
      trigger: AchievementTrigger.streak,
      threshold: 250,
      xpReward: 2500,
      goldReward: 0,
    ),
    AchievementModel(
      id: 'endurance_300',
      familyId: 'endurance',
      tier: AchievementTier.platinum,
      name: 'Three Hundred Straight',
      nameAr: 'ثلاثمية يوم',
      description: 'A 300-day streak',
      descriptionAr: 'سلسلة 300 يوم متواصلة',
      trigger: AchievementTrigger.streak,
      threshold: 300,
      xpReward: 3000,
      goldReward: 0,
    ),
  ];

  static AchievementModel? findById(String id) {
    try {
      return all.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  static AchievementFamily? familyById(String id) {
    try {
      return families.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Every tier of [familyId], bronze → platinum in order — what the
  /// family-ladder card (AchievementsScreen) renders as one row of medals.
  static List<AchievementModel> tiersFor(String familyId) {
    final tiers = all.where((a) => a.familyId == familyId).toList()
      ..sort((a, b) => a.tier.index.compareTo(b.tier.index));
    return tiers;
  }

  /// Returns all achievements that [unlockedIds] has NOT yet unlocked.
  static List<AchievementModel> locked(List<String> unlockedIds) =>
      all.where((a) => !unlockedIds.contains(a.id)).toList();

  /// The lowest tier of [familyId] still locked, or `null` once the whole
  /// ladder is climbed.
  ///
  /// Looks the tier up by *identity* (first tier whose id isn't in
  /// [unlockedIds]) rather than by counting how many are unlocked and
  /// indexing that far into the list. Those two agree only while unlocks
  /// arrive in strict bronze→platinum order, which isn't guaranteed:
  /// `totalGreenSquares` and `categoryCompletions` both go *down* again in
  /// uncompleteHabit, while `unlockedAchievements` is deliberately never
  /// pruned, so a counter can cross a higher threshold, fall back, and
  /// leave a gap in the ladder. Counting would then describe one tier while
  /// the medal row highlighted another. AchievementsScreen used to count and
  /// ProgressHubScreen used to search — same concept, two implementations,
  /// one of them wrong; both now call this.
  static AchievementModel? nextLockedIn(
    String familyId,
    List<String> unlockedIds,
  ) {
    for (final t in tiersFor(familyId)) {
      if (!unlockedIds.contains(t.id)) return t;
    }
    return null;
  }

  /// How many medals of each tier [unlockedIds] holds — the trophy-case
  /// header's bronze/silver/gold/platinum tally.
  static Map<AchievementTier, int> tierCounts(List<String> unlockedIds) {
    final counts = {for (final t in AchievementTier.values) t: 0};
    for (final a in all) {
      if (unlockedIds.contains(a.id)) counts[a.tier] = counts[a.tier]! + 1;
    }
    return counts;
  }

  /// Every still-locked achievement that [stats] now qualifies for.
  ///
  /// The single source of truth for "has this been earned" — completeHabit,
  /// applyGridSquareChange and the post-load reconciliation sweep all call
  /// this instead of each open-coding the same switch over
  /// [AchievementTrigger]. They used to, and they didn't agree:
  /// applyGridSquareChange only ever tested `level` and `greenSquares`, so a
  /// habit-mastery or total-completions threshold crossed on that path sat
  /// unrecognised until the next habit completion happened to re-check it.
  static List<AchievementModel> newlyUnlocked(
    AchievementStats stats,
    List<String> unlockedIds,
  ) =>
      locked(unlockedIds).where(stats.meets).toList();
}

/// The five running totals every achievement trigger is measured against,
/// in one object so the check can be written once (see
/// [AchievementCatalog.newlyUnlocked]) instead of once per call site.
///
/// Deliberately a plain snapshot rather than a read of `DashboardState`:
/// the unlock check inside completeHabit has to run against the values the
/// completion is *about to* produce, which don't exist in state yet.
class AchievementStats {
  final int streak;
  final int level;
  final int totalCompletions;
  final int greenSquares;
  final Map<String, int> categoryCompletions;

  const AchievementStats({
    required this.streak,
    required this.level,
    required this.totalCompletions,
    required this.greenSquares,
    required this.categoryCompletions,
  });

  /// The number that counts toward [a] — the numerator of its progress bar
  /// and the left side of its unlock comparison.
  int currentFor(AchievementModel a) => switch (a.trigger) {
        AchievementTrigger.streak => streak,
        AchievementTrigger.level => level,
        AchievementTrigger.totalCompletions => totalCompletions,
        AchievementTrigger.greenSquares => greenSquares,
        AchievementTrigger.habitMastery =>
          categoryCompletions[a.targetCategory] ?? 0,
        AchievementTrigger.special => 0,
      };

  /// Whether [a] is earned at these numbers. `special` achievements are
  /// awarded by hand and never qualify through a counter, so they're
  /// excluded here rather than silently comparing 0 against a threshold.
  bool meets(AchievementModel a) =>
      a.trigger != AchievementTrigger.special &&
      currentFor(a) >= a.threshold;

  /// 0..1 progress toward [a], clamped — the shared source for every
  /// progress ring and bar on the achievements surfaces.
  double progressFor(AchievementModel a) => a.threshold <= 0
      ? 0
      : (currentFor(a) / a.threshold).clamp(0.0, 1.0);
}
