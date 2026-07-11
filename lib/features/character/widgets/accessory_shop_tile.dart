import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../achievements/models/achievement_model.dart';
import '../models/accessory.dart';

/// One accessory grid cell in the closet — visual grammar matches
/// AchievementsScreen's _AchievementCard (same surface/border/radius,
/// opacity-for-locked, rarity-colored accents) so this reads as the same
/// app rather than a bolted-on import.
class AccessoryShopTile extends StatelessWidget {
  final Accessory accessory;
  final bool owned;
  final bool equipped;
  final VoidCallback onTap;

  const AccessoryShopTile({
    super.key,
    required this.accessory,
    required this.owned,
    required this.equipped,
    required this.onTap,
  });

  Color _rarityColor() => switch (accessory.rarity) {
        AchievementRarity.common => GameColors.rarityCommon,
        AchievementRarity.uncommon => GameColors.rarityUncommon,
        AchievementRarity.rare => GameColors.rarityRare,
        AchievementRarity.epic => GameColors.rarityEpic,
        AchievementRarity.legendary => GameColors.rarityLegendary,
      };

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final c = _rarityColor();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: equipped ? c.withOpacity(0.10) : gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(
            color: equipped ? c : (owned ? c.withOpacity(0.5) : gp.border),
            width: equipped ? 1.4 : (owned ? 1 : 0.5),
          ),
        ),
        child: Opacity(
          opacity: owned ? 1.0 : 0.6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset(accessory.imagePath, fit: BoxFit.contain),
                    if (!owned)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Icon(Icons.lock_rounded, size: 14, color: gp.textTert),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                accessory.name(s.isAr),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: gp.textPrimary,
                    height: 1.2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              if (equipped)
                Text(
                  s.closetEquipped,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c),
                )
              else if (owned)
                Text(
                  s.closetOwned,
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600, color: gp.textTert),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.toll_rounded, size: 11, color: GameColors.gold),
                    const SizedBox(width: 2),
                    Text(
                      '${accessory.goldCost}',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: GameColors.gold),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
