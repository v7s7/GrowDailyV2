import 'package:flutter/material.dart';

import '../../achievements/models/achievement_model.dart' show AchievementRarity;

/// The six accessory slots a character can wear. Each category has exactly
/// one hand-anchor placement (see CharacterAvatar), so every accessory in a
/// category renders in the same spot regardless of which one is equipped.
enum AccessoryCategory {
  misbah,
  umbrella,
  frame,
  badge,
  lantern,
  notebook;

  String label(bool isAr) => isAr
      ? switch (this) {
          misbah => 'مسباح',
          umbrella => 'مظلة',
          frame => 'إطار',
          badge => 'شارة',
          lantern => 'فانوس',
          notebook => 'دفتر',
        }
      : switch (this) {
          misbah => 'Tasbih',
          umbrella => 'Umbrella',
          frame => 'Frame',
          badge => 'Badge',
          lantern => 'Lantern',
          notebook => 'Notebook',
        };

  IconData get icon => switch (this) {
        misbah => Icons.fiber_manual_record_outlined,
        umbrella => Icons.beach_access_outlined,
        frame => Icons.photo_size_select_actual_outlined,
        badge => Icons.workspace_premium_outlined,
        lantern => Icons.light_outlined,
        notebook => Icons.menu_book_outlined,
      };
}

/// What a top-tier accessory demands *besides* gold.
///
/// The closet used to be gold-only, which made it a race rather than a
/// reward: the whole catalog totals 3,230 gold against roughly 60 a day
/// from six habits, so it emptied in under two months and gold became
/// inert afterwards. Requiring real progress on the rarer half moves the
/// wall out and, more importantly, changes what a locked tile *means* —
/// a price tag says "come back when you've grinded", a requirement says
/// "come back when you've done the thing this app exists for".
///
/// Deliberately checked *after* ownership everywhere, so anyone who
/// already bought an item keeps it. This is never applied retroactively.
enum UnlockMetric { level, streak, completedDays }

class UnlockRequirement {
  final UnlockMetric metric;
  final int amount;

  const UnlockRequirement(this.metric, this.amount);

  /// How far along the user is against this requirement right now.
  int progressFrom({
    required int level,
    required int streak,
    required int completedDays,
  }) =>
      switch (metric) {
        UnlockMetric.level => level,
        UnlockMetric.streak => streak,
        UnlockMetric.completedDays => completedDays,
      };

  bool isMetBy({
    required int level,
    required int streak,
    required int completedDays,
  }) =>
      progressFrom(
        level: level,
        streak: streak,
        completedDays: completedDays,
      ) >=
      amount;

  /// The tile version. A three-column cell gives a chip about 95pt, and
  /// the full label overflows it: "100 يوم مكتمل" truncated to
  /// "100 يوم مكت..." and "سلسلة 30 يومًا" to "سلسلة 30 ي...". The unit
  /// word is the redundant part (the band is already titled
  /// "تحتاج تقدمًا" and the sheet spells the requirement out in full), so
  /// it is what gets dropped rather than the number.
  String shortLabel(bool isAr) => isAr
      ? switch (metric) {
          UnlockMetric.level => 'المستوى $amount',
          UnlockMetric.streak => 'سلسلة $amount',
          UnlockMetric.completedDays => '$amount يوم',
        }
      : switch (metric) {
          UnlockMetric.level => 'Level $amount',
          UnlockMetric.streak => 'Streak $amount',
          UnlockMetric.completedDays => '$amount days',
        };

  /// The full sentence, for the detail sheet. Arabic avoids second-person
  /// verbs entirely (the app is used by men and women alike), so these are
  /// noun phrases rather than commands.
  String label(bool isAr) => isAr
      ? switch (metric) {
          UnlockMetric.level => 'المستوى $amount',
          UnlockMetric.streak => 'سلسلة $amount يومًا',
          UnlockMetric.completedDays => '$amount يوم مكتمل',
        }
      : switch (metric) {
          UnlockMetric.level => 'Level $amount',
          UnlockMetric.streak => '$amount day streak',
          UnlockMetric.completedDays => '$amount days done',
        };
}

/// A single cosmetic accessory. Unlike the character catalog, accessories
/// are gated by [goldCost] — spend once via CharacterNotifier.buyAccessory
/// to own it forever, then equip/unequip freely at no further cost. This
/// gives the app's gold currency an actual long-term sink beyond the single
/// existing streak-freeze purchase.
class Accessory {
  final String id;
  final AccessoryCategory category;
  final String nameEn;
  final String nameAr;
  final String descriptionEn;
  final String descriptionAr;
  final String imagePath;
  final Color color;
  final AchievementRarity rarity;
  final int goldCost;

  /// Null means gold alone unlocks it. See [UnlockRequirement].
  final UnlockRequirement? unlock;

  const Accessory({
    required this.id,
    required this.category,
    required this.nameEn,
    required this.nameAr,
    required this.descriptionEn,
    required this.descriptionAr,
    required this.imagePath,
    required this.color,
    required this.rarity,
    required this.goldCost,
    this.unlock,
  });

  String name(bool isAr) => isAr ? nameAr : nameEn;
  String description(bool isAr) => isAr ? descriptionAr : descriptionEn;
}

/// Static catalog — 10 accessories across the 6 categories, ported from the
/// same art used elsewhere, re-priced in gold instead of the XP/streak gates
/// the source used. [amberMisbah] is free and owned by every account from
/// the start so the closet never opens completely empty.
abstract final class AccessoryCatalog {
  static const amberMisbah = Accessory(
    id: 'misbah_amber',
    category: AccessoryCategory.misbah,
    nameEn: 'Amber Tasbih',
    nameAr: 'مسباح كهرمان',
    descriptionEn: 'A calm companion that shines with your daily practice.',
    descriptionAr: 'رفيق هادئ يلمع مع وردك اليومي.',
    imagePath: 'assets/images/accessories/misbah_amber.png',
    color: Color(0xFFD69A2D),
    rarity: AchievementRarity.common,
    goldCost: 0,
  );

  static const woodMisbah = Accessory(
    id: 'misbah_wood',
    category: AccessoryCategory.misbah,
    nameEn: 'Wooden Tasbih',
    nameAr: 'مسباح خشبي',
    descriptionEn: 'Simple and warm, for steady daily habits.',
    descriptionAr: 'بسيط ودافئ للمداومة اليومية.',
    imagePath: 'assets/images/accessories/misbah_wood.png',
    color: Color(0xFF8B5E3C),
    rarity: AchievementRarity.common,
    goldCost: 90,
  );

  static const blackMisbah = Accessory(
    id: 'misbah_black',
    category: AccessoryCategory.misbah,
    nameEn: 'Black Tasbih',
    nameAr: 'مسباح أسود',
    descriptionEn: 'Sleek and elegant, for long streaks.',
    descriptionAr: 'هادئ وأنيق لأصحاب السلاسل الطويلة.',
    imagePath: 'assets/images/accessories/misbah_black.png',
    color: Color(0xFF20242A),
    rarity: AchievementRarity.rare,
    goldCost: 260,
    unlock: const UnlockRequirement(UnlockMetric.streak, 14),
  );

  static const blueUmbrella = Accessory(
    id: 'umbrella_blue',
    category: AccessoryCategory.umbrella,
    nameEn: 'Blue Umbrella',
    nameAr: 'مظلة زرقاء',
    descriptionEn: 'A gentle touch to match the blue ghutra.',
    descriptionAr: 'لمسة لطيفة تناسب الغترة الزرقاء.',
    imagePath: 'assets/images/accessories/umbrella_blue.png',
    color: Color(0xFF5D8CCB),
    rarity: AchievementRarity.common,
    goldCost: 120,
  );

  static const goldUmbrella = Accessory(
    id: 'umbrella_gold',
    category: AccessoryCategory.umbrella,
    nameEn: 'Gold Umbrella',
    nameAr: 'مظلة ذهبية',
    descriptionEn: 'A luxurious touch to match the gold bisht.',
    descriptionAr: 'لمسة فاخرة تناسب البشت الذهبي.',
    imagePath: 'assets/images/accessories/umbrella_gold.png',
    color: Color(0xFFD6AA4A),
    rarity: AchievementRarity.rare,
    goldCost: 320,
    unlock: const UnlockRequirement(UnlockMetric.level, 10),
  );

  static const redUmbrella = Accessory(
    id: 'umbrella_red',
    category: AccessoryCategory.umbrella,
    nameEn: 'Red Umbrella',
    nameAr: 'مظلة حمراء',
    descriptionEn: 'A bold touch to match the red shemagh.',
    descriptionAr: 'لمسة جريئة تناسب الشماغ الأحمر.',
    imagePath: 'assets/images/accessories/umbrella_red.png',
    color: Color(0xFFBE3F35),
    rarity: AchievementRarity.rare,
    goldCost: 240,
    unlock: const UnlockRequirement(UnlockMetric.level, 5),
  );

  static const goldFrame = Accessory(
    id: 'frame_gold',
    category: AccessoryCategory.frame,
    nameEn: 'Golden Frame',
    nameAr: 'إطار ذهبي',
    descriptionEn: 'A radiant frame around your companion.',
    descriptionAr: 'إطار نوراني يظهر حول رفيقك.',
    imagePath: 'assets/images/accessories/frame_gold.png',
    color: Color(0xFFD6AA4A),
    rarity: AchievementRarity.epic,
    goldCost: 550,
    unlock: const UnlockRequirement(UnlockMetric.completedDays, 100),
  );

  static const knowledgeBadge = Accessory(
    id: 'badge_knowledge',
    category: AccessoryCategory.badge,
    nameEn: "Scholar's Badge",
    nameAr: 'شارة طالب علم',
    descriptionEn: 'A small badge for those who keep learning.',
    descriptionAr: 'شارة صغيرة لمن يثبت على التعلم.',
    imagePath: 'assets/images/accessories/badge_knowledge.png',
    color: Color(0xFF1F6F5C),
    rarity: AchievementRarity.legendary,
    goldCost: 450,
    unlock: const UnlockRequirement(UnlockMetric.streak, 30),
  );

  static const goldLantern = Accessory(
    id: 'lantern_gold',
    category: AccessoryCategory.lantern,
    nameEn: 'Golden Lantern',
    nameAr: 'فانوس ذهبي',
    descriptionEn: 'A steady light for a long journey.',
    descriptionAr: 'نور دائم لمن واصل رحلة العلم.',
    imagePath: 'assets/images/accessories/lantern_gold.png',
    color: Color(0xFFD6AA4A),
    rarity: AchievementRarity.rare,
    goldCost: 500,
    unlock: const UnlockRequirement(UnlockMetric.level, 20),
  );

  static const tealNotebook = Accessory(
    id: 'notebook_teal',
    category: AccessoryCategory.notebook,
    nameEn: 'Teal Notebook',
    nameAr: 'دفتر مميز',
    descriptionEn: 'An elegant notebook for very long streaks.',
    descriptionAr: 'دفتر أنيق لأصحاب السلاسل الطويلة جدًا.',
    imagePath: 'assets/images/accessories/notebook_teal.png',
    color: Color(0xFF36645B),
    rarity: AchievementRarity.epic,
    goldCost: 700,
    unlock: const UnlockRequirement(UnlockMetric.level, 30),
  );

  static const blueMisbah = Accessory(
    id: 'misbah_blue',
    category: AccessoryCategory.misbah,
    nameEn: 'Blue Tasbih',
    nameAr: 'مسباح أزرق',
    descriptionEn: 'Sea-calm, for the quiet part of the day.',
    descriptionAr: 'أزرق هادئ، يريّح العين.',
    imagePath: 'assets/images/accessories/misbah_blue.png',
    color: Color(0xFF3D6FA8),
    rarity: AchievementRarity.uncommon,
    goldCost: 180,
    unlock: const UnlockRequirement(UnlockMetric.level, 8),
  );

  static const redMisbah = Accessory(
    id: 'misbah_red',
    category: AccessoryCategory.misbah,
    nameEn: 'Red Tasbih',
    nameAr: 'مسباح أحمر',
    descriptionEn: 'Warmth to keep the evening adhkar company.',
    descriptionAr: 'لون دافئ يناسب أذكار المساء.',
    imagePath: 'assets/images/accessories/misbah_red.png',
    color: Color(0xFFB23A3A),
    rarity: AchievementRarity.rare,
    goldCost: 300,
    unlock: const UnlockRequirement(UnlockMetric.streak, 21),
  );

  static const List<Accessory> all = [
    amberMisbah,
    woodMisbah,
    blackMisbah,
    blueMisbah,
    redMisbah,
    blueUmbrella,
    goldUmbrella,
    redUmbrella,
    goldFrame,
    knowledgeBadge,
    goldLantern,
    tealNotebook,
  ];

  /// The one accessory every account owns from the start — see [amberMisbah].
  static const String defaultOwnedId = 'misbah_amber';

  static Accessory? findById(String? id) {
    if (id == null) return null;
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }

  static List<Accessory> byCategory(AccessoryCategory category) =>
      all.where((a) => a.category == category).toList();
}
