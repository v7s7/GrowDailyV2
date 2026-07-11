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
    rarity: AchievementRarity.uncommon,
    goldCost: 240,
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
  );

  static const List<Accessory> all = [
    amberMisbah,
    woodMisbah,
    blackMisbah,
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
