import 'package:flutter/material.dart';

import '../../../core/theme/game_theme.dart';

/// One rung of the Level Prestige ladder — a title plus a matching visual
/// treatment (banner tint + nameplate accent), unlocked purely by
/// [DashboardState.level] reaching [minLevel]. Deliberately a *separate*
/// lane from [AccessoryCatalog]/[CharacterCatalog]: characters stay free
/// forever, Premium themes stay Premium, and gold still buys the character
/// closet's accessories exactly as it does today — nothing here is gated by
/// gold or Premium, and nothing here touches [CharacterState.
/// ownedAccessoryIds]. See [PrestigeNotifier] for why "unlocked" needs no
/// persisted ownership list at all (unlike a gold purchase, it's just
/// `state.level >= minLevel`, recomputed live from data already loaded).
///
/// One bundled tier rather than three independently-unlocked slots (title /
/// banner / nameplate) on purpose: a player reaching Level 35 wants "my
/// Level 35 look," not three separate shop aisles to shop in — see
/// PrestigeNotifier's own doc comment for the equip model this enables.
/// [icon] and [color] are what [PrestigePickerSheet] and the Profile hero
/// header both render from, so the two surfaces can never drift out of
/// sync with each other.
class PrestigeTier {
  final String id;
  final int minLevel;
  final String titleEn;
  final String titleAr;
  final Color color;
  final IconData icon;

  const PrestigeTier({
    required this.id,
    required this.minLevel,
    required this.titleEn,
    required this.titleAr,
    required this.color,
    required this.icon,
  });

  String title(bool isAr) => isAr ? titleAr : titleEn;
}

/// Static catalog, evaluated client-side against [DashboardState.level] —
/// same "static list + level threshold" shape [AchievementCatalog] already
/// uses for its own level family (level_10/25/50/100), just for cosmetic
/// display instead of an XP/gold reward. 8 rungs spread across the full
/// 1-100 level range (see [GameConstants.maxLevel]) so there's a new title
/// to reach every so often without every single level bumping it.
abstract final class PrestigeCatalog {
  // final, not const: most GameColors tokens below (tierBronze, tierSilver,
  // tierPlatinum, iconXp, iconStreak) are genuine compile-time constants,
  // but the luminous and eternal_light tiers use GameColors.emerald and
  // GameColors.gold, which are mutable `static Color` fields swapped at
  // runtime by the theme-preset system — see BUILD_LESSONS.md #6
  // (victory_burst.dart's showVictoryBurst hit the exact same thing). One
  // non-const entry is enough to force the whole list non-const, so this
  // stays `static final` rather than trying to const individual entries.
  static final List<PrestigeTier> tiers = [
    PrestigeTier(
      id: 'seeker',
      minLevel: 1,
      titleEn: 'Seeker',
      titleAr: 'الباحث',
      color: GameColors.tierBronze,
      icon: Icons.explore_outlined,
    ),
    PrestigeTier(
      id: 'devoted',
      minLevel: 5,
      titleEn: 'Devoted',
      titleAr: 'الملتزم',
      color: GameColors.tierSilver,
      icon: Icons.favorite_outline_rounded,
    ),
    // Title/color/icon swapped with the 'radiant' tier below - dictionary
    // definitions put diligence (active, ongoing effort) a step before
    // steadfastness (already-proven, unwavering consistency), so "trying"
    // now sits at the lower level and "steady" at the higher one. [id] and
    // [minLevel] deliberately left untouched on both tiers - only which
    // title/color/icon appears at each already-fixed unlock threshold
    // changed, so no account's persisted equippedPrestigeTierId (which
    // points at an id, not a level) is affected by the reorder.
    PrestigeTier(
      id: 'steadfast',
      minLevel: 10,
      titleEn: 'Diligent',
      titleAr: 'المجتهد',
      color: GameColors.tierPlatinum,
      icon: Icons.wb_sunny_outlined,
    ),
    // Renamed from 'Radiant'/'المشرق' - not one of the 99 Names itself, but
    // light/glow imagery sits close enough to An-Nur that the whole ladder
    // is moving away from it (see the 'eternal_light' tier's own comment
    // below). Now carries the 'Steadfast' title/color/icon that used to sit
    // at the tier above - see that tier's own comment for why.
    PrestigeTier(
      id: 'radiant',
      minLevel: 20,
      titleEn: 'Steadfast',
      titleAr: 'الثابت',
      color: GameColors.tierGold,
      icon: Icons.shield_outlined,
    ),
    // Renamed from 'Luminous'/'المنير' - same light-imagery reasoning as
    // 'radiant' above.
    PrestigeTier(
      id: 'luminous',
      minLevel: 35,
      titleEn: 'Accomplished',
      titleAr: 'المنجز',
      color: GameColors.emerald,
      icon: Icons.auto_awesome_rounded,
    ),
    // titleEn/titleAr renamed from the original 'Exalted'/'الرفيع' - too
    // close to Ar-Rafi' (one of Allah's 99 Names) for a cosmetic game-tier
    // label. [id] deliberately untouched: it's what PrestigeNotifier
    // persists as equippedPrestigeTierId, so renaming it would silently
    // orphan any account that already had this tier equipped.
    PrestigeTier(
      id: 'exalted',
      minLevel: 50,
      titleEn: 'Distinguished',
      titleAr: 'المتميز',
      color: GameColors.iconXp,
      icon: Icons.diamond_outlined,
    ),
    // Renamed from 'Venerable'/'الجليل' - Al-Jaleel is literally one of the
    // 99 Names of Allah (see Surah Ar-Rahman's "Dhul-Jalali wal-Ikram").
    // Same [id]-preservation reasoning as the tier above.
    PrestigeTier(
      id: 'venerable',
      minLevel: 75,
      titleEn: 'Honored',
      titleAr: 'المكرَّم',
      color: GameColors.iconStreak,
      icon: Icons.local_fire_department_rounded,
    ),
    // Renamed from 'Eternal Light'/'النور الأبدي' (itself briefly 'Crown'/
    // 'التاج' mid-revision) - An-Nur (The Light) is literally one of the 99
    // Names ("Allah is the Light of the heavens and the earth", Surah
    // An-Nur 24:35), and pairing it with "eternal" only strengthened the
    // echo. 'Legacy' frames the max rank as what a habit-building journey
    // leaves behind, not just "on top." Same [id]-preservation reasoning as
    // every tier above.
    PrestigeTier(
      id: 'eternal_light',
      minLevel: 100,
      titleEn: 'Legacy',
      titleAr: 'الإرث',
      color: GameColors.gold,
      icon: Icons.wb_twilight_rounded,
    ),
  ];

  static PrestigeTier? findById(String? id) {
    if (id == null) return null;
    for (final t in tiers) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Every tier [level] has actually reached, in ascending order — what the
  /// picker sheet renders as available, and what [highestFor] picks its
  /// default from.
  static List<PrestigeTier> unlockedFor(int level) =>
      tiers.where((t) => t.minLevel <= level).toList();

  /// The tier a level-up would show off by default — always the highest one
  /// reached. Never null: [tiers] starts at minLevel 1, and level is always
  /// >= 1 (see DashboardState/GameConstants), so at least "Seeker" always
  /// qualifies.
  static PrestigeTier highestFor(int level) => unlockedFor(level).last;
}
