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
      title: 'Streak Keeper',
      titleAr: 'حارس السلسلة',
      icon: Icons.local_fire_department_rounded,
    ),
    AchievementFamily(
      id: 'level',
      title: 'Level Climber',
      titleAr: 'متسلّق المستويات',
      icon: Icons.bolt_rounded,
    ),
    AchievementFamily(
      id: 'completions',
      title: 'Consistency',
      titleAr: 'الثبات',
      icon: Icons.check_circle_rounded,
    ),
    AchievementFamily(
      id: 'grid',
      title: 'Victory Grid',
      titleAr: 'شبكة الانتصار',
      icon: Icons.grid_view_rounded,
    ),
    AchievementFamily(
      id: 'quran',
      title: 'Quran Devotion',
      titleAr: 'التزام القرآن',
      icon: Icons.menu_book_rounded,
    ),
  ];

  static const List<AchievementModel> all = [
    // ── Streak ──────────────────────────────────────────────────
    AchievementModel(
      id: 'streak_7',
      familyId: 'streak',
      tier: AchievementTier.bronze,
      name: 'Seven Days Strong',
      nameAr: 'سبعة أيام بقوة',
      description: 'Maintain a 7-day streak',
      descriptionAr: 'حافظ على سلسلة ٧ أيام',
      trigger: AchievementTrigger.streak,
      threshold: 7,
      xpReward: 100,
      goldReward: 25,
    ),
    AchievementModel(
      id: 'streak_30',
      familyId: 'streak',
      tier: AchievementTier.silver,
      name: 'Month of Mastery',
      nameAr: 'شهر من الإتقان',
      description: 'Maintain a 30-day streak',
      descriptionAr: 'حافظ على سلسلة ٣٠ يومًا',
      trigger: AchievementTrigger.streak,
      threshold: 30,
      xpReward: 500,
      goldReward: 100,
    ),
    AchievementModel(
      id: 'streak_100',
      familyId: 'streak',
      tier: AchievementTier.gold,
      name: 'Century Champion',
      nameAr: 'بطل المئة',
      description: 'Maintain a 100-day streak',
      descriptionAr: 'حافظ على سلسلة ١٠٠ يوم',
      trigger: AchievementTrigger.streak,
      threshold: 100,
      xpReward: 2000,
      goldReward: 500,
    ),
    AchievementModel(
      id: 'streak_365',
      familyId: 'streak',
      tier: AchievementTier.platinum,
      name: 'Unbroken Year',
      nameAr: 'سنة بلا انقطاع',
      description: 'Maintain a 365-day streak',
      descriptionAr: 'حافظ على سلسلة ٣٦٥ يومًا',
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
      name: 'Awakened',
      nameAr: 'المستيقظ',
      description: 'Reach Level 10',
      descriptionAr: 'وصول للمستوى ١٠',
      trigger: AchievementTrigger.level,
      threshold: 10,
      xpReward: 0,
      goldReward: 50,
    ),
    AchievementModel(
      id: 'level_25',
      familyId: 'level',
      tier: AchievementTier.silver,
      name: 'Ascendant',
      nameAr: 'الصاعد',
      description: 'Reach Level 25',
      descriptionAr: 'وصول للمستوى ٢٥',
      trigger: AchievementTrigger.level,
      threshold: 25,
      xpReward: 0,
      goldReward: 150,
    ),
    AchievementModel(
      id: 'level_50',
      familyId: 'level',
      tier: AchievementTier.gold,
      name: 'Transcendent',
      nameAr: 'المتسامي',
      description: 'Reach Level 50',
      descriptionAr: 'وصول للمستوى ٥٠',
      trigger: AchievementTrigger.level,
      threshold: 50,
      xpReward: 0,
      goldReward: 300,
    ),
    AchievementModel(
      id: 'level_100',
      familyId: 'level',
      tier: AchievementTier.platinum,
      name: 'Enlightened',
      nameAr: 'المستنير',
      description: 'Reach the maximum Level 100',
      descriptionAr: 'وصول لأعلى مستوى، ١٠٠',
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
      name: 'Consistent',
      nameAr: 'الملتزم',
      description: 'Complete any habit 50 times total',
      descriptionAr: 'أكمل أي عادة ٥٠ مرة',
      trigger: AchievementTrigger.totalCompletions,
      threshold: 50,
      xpReward: 150,
      goldReward: 30,
    ),
    AchievementModel(
      id: 'completions_500',
      familyId: 'completions',
      tier: AchievementTier.silver,
      name: 'Devoted',
      nameAr: 'المتفاني',
      description: 'Complete habits 500 times total',
      descriptionAr: 'أكمل عاداتك ٥٠٠ مرة',
      trigger: AchievementTrigger.totalCompletions,
      threshold: 500,
      xpReward: 750,
      goldReward: 200,
    ),
    AchievementModel(
      id: 'completions_2000',
      familyId: 'completions',
      tier: AchievementTier.gold,
      name: 'Unstoppable',
      nameAr: 'الذي لا يُوقَف',
      description: 'Complete habits 2,000 times total',
      descriptionAr: 'أكمل عاداتك ٢٠٠٠ مرة',
      trigger: AchievementTrigger.totalCompletions,
      threshold: 2000,
      xpReward: 2500,
      goldReward: 600,
    ),
    AchievementModel(
      id: 'completions_5000',
      familyId: 'completions',
      tier: AchievementTier.platinum,
      name: 'Living Legend',
      nameAr: 'أسطورة حية',
      description: 'Complete habits 5,000 times total',
      descriptionAr: 'أكمل عاداتك ٥٠٠٠ مرة',
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
      name: 'Steady Reciter',
      nameAr: 'التالي المواظب',
      description: 'Complete a Quran habit 25 times',
      descriptionAr: 'أكمل عادة قرآن ٢٥ مرة',
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
      name: 'Keeper of the Word',
      nameAr: 'حافظ الكلمة',
      description: 'Complete a Quran habit 100 times',
      descriptionAr: 'أكمل عادة قرآن ١٠٠ مرة',
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
      name: 'Companion of the Book',
      nameAr: 'رفيق الكتاب',
      description: 'Complete a Quran habit 300 times',
      descriptionAr: 'أكمل عادة قرآن ٣٠٠ مرة',
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
      name: 'Vessel of Light',
      nameAr: 'وعاء النور',
      description: 'Complete a Quran habit 1,000 times',
      descriptionAr: 'أكمل عادة قرآن ١٠٠٠ مرة',
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
      name: 'First Victory',
      nameAr: 'أول انتصار',
      description: 'Color your very first square on the Victory Grid',
      descriptionAr: 'لوّن أول مربع في شبكة الانتصار',
      trigger: AchievementTrigger.greenSquares,
      threshold: 1,
      xpReward: 25,
      goldReward: 10,
    ),
    AchievementModel(
      id: 'green_100',
      familyId: 'grid',
      tier: AchievementTier.silver,
      name: 'Grid Painter',
      nameAr: 'رسّام الشبكة',
      description: 'Color 100 squares on your Victory Grid',
      descriptionAr: 'لوّن ١٠٠ مربع في شبكة الانتصار',
      trigger: AchievementTrigger.greenSquares,
      threshold: 100,
      xpReward: 200,
      goldReward: 50,
    ),
    AchievementModel(
      id: 'green_500',
      familyId: 'grid',
      tier: AchievementTier.gold,
      name: 'Grid Master',
      nameAr: 'سيد الشبكة',
      description: 'Color 500 squares on your Victory Grid',
      descriptionAr: 'لوّن ٥٠٠ مربع في شبكة الانتصار',
      trigger: AchievementTrigger.greenSquares,
      threshold: 500,
      xpReward: 600,
      goldReward: 150,
    ),
    AchievementModel(
      id: 'green_2000',
      familyId: 'grid',
      tier: AchievementTier.platinum,
      name: 'Living Canvas',
      nameAr: 'لوحة حية',
      description: 'Color 2000 squares on your Victory Grid',
      descriptionAr: 'لوّن ٢٠٠٠ مربع في شبكة الانتصار',
      trigger: AchievementTrigger.greenSquares,
      threshold: 2000,
      xpReward: 2500,
      goldReward: 600,
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
}
