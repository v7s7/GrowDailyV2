import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../achievements/models/achievement_model.dart';
import '../models/accessory.dart';
import 'gold_coin.dart';

/// One accessory in the closet grid.
///
/// Two columns, not three or four. The art *is* the product here, and at
/// the old 82.75pt width it was a thumbnail with a caption under it. At
/// ~170pt the piece is something you want to look at, which is most of
/// what separates a shop from a settings list.
///
/// The tile carries exactly four things: the art, a rarity wash behind it,
/// the full name (two lines, never truncated — this used to ellipsize
/// "شارة طالب علم", the only place in the whole app an accessory name is
/// shown), and one status chip. Everything else the old tile carried
/// (rarity bar, lock corner, owned/equipped micro-caption) collapsed into
/// that single chip or moved to the detail sheet.
class AccessoryShopTile extends StatelessWidget {
  final Accessory accessory;
  final bool owned;
  final bool equipped;

  /// Whether the current balance covers [Accessory.goldCost]. Only read
  /// when the item is unowned and its requirement is already met.
  final bool affordable;

  /// False when [Accessory.unlock] is not satisfied yet. Checked *after*
  /// ownership, so an item bought before requirements existed never shows
  /// as locked.
  final bool requirementMet;

  final VoidCallback onTap;

  const AccessoryShopTile({
    super.key,
    required this.accessory,
    required this.owned,
    required this.equipped,
    required this.affordable,
    required this.requirementMet,
    required this.onTap,
  });

  Color _rarityColor() => switch (accessory.rarity) {
        AchievementRarity.common => GameColors.rarityCommon,
        AchievementRarity.uncommon => GameColors.rarityUncommon,
        AchievementRarity.rare => GameColors.rarityRare,
        AchievementRarity.epic => GameColors.rarityEpic,
        AchievementRarity.legendary => GameColors.rarityLegendary,
      };

  bool get _locked => !owned && !requirementMet;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final c = _rarityColor();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: gp.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: equipped
                  ? GameColors.gold
                  : (owned ? c.withOpacity(0.4) : gp.border),
              width: equipped ? 1.4 : (owned ? 1 : 0.5),
            ),
            boxShadow: equipped
                ? [
                    BoxShadow(
                      color: GameColors.gold.withOpacity(0.16),
                      blurRadius: 22,
                      spreadRadius: -4,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                // Rarity as a soft wash behind the art rather than a hard
                // 2.5px bar across the top: at two columns there is room to
                // say it quietly, and the old bar was one more line of
                // chrome on a screen that had too many.
                Positioned(
                  top: -26,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            c.withOpacity(_locked ? 0.06 : 0.20),
                            c.withOpacity(0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(9, 9, 9, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 58,
                        child: Opacity(
                          opacity: _locked ? 0.32 : 1,
                          child: _locked
                              ? ColorFiltered(
                                  colorFilter: const ColorFilter.matrix(
                                    _greyscale,
                                  ),
                                  child: Image.asset(accessory.imagePath,
                                      fit: BoxFit.contain),
                                )
                              : Image.asset(accessory.imagePath,
                                  fit: BoxFit.contain),
                        ),
                      ),
                      const SizedBox(height: 7),
                      SizedBox(
                        height: 30,
                        child: Center(
                          child: Text(
                            accessory.name(s.isAr),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                              color: _locked ? gp.textSec : gp.textPrimary,
                            ),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      _status(
                        c,
                        s,
                        textTert: gp.textTert,
                        border: gp.border,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _status(
    Color c,
    S s, {
    required Color textTert,
    required Color border,
  }) {
    if (equipped) {
      return _chip(
        text: s.closetEquipped,
        fg: GameColors.gold,
        bg: GameColors.gold.withOpacity(0.15),
      );
    }
    if (owned) {
      return _chip(
        text: s.closetOwned,
        fg: textTert,
        bg: Colors.transparent,
        border: border,
      );
    }
    if (!requirementMet) {
      return _chip(
        text: accessory.unlock!.shortLabel(s.isAr),
        fg: GameColors.rarityEpic,
        bg: GameColors.rarityEpic.withOpacity(0.13),
        icon: Icons.lock_rounded,
      );
    }
    return GoldPrice(
      amount: accessory.goldCost,
      affordable: affordable,
      dense: true,
    );
  }

  Widget _chip({
    required String text,
    required Color fg,
    required Color bg,
    Color? border,
    IconData? icon,
  }) =>
      Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
          border: border == null
              ? null
              : Border.all(color: border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 10, color: fg),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}

/// Luminance-weighted desaturation, for art behind a requirement.
const List<double> _greyscale = <double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
];
