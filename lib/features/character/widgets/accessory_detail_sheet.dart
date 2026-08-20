import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../achievements/models/achievement_model.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../models/accessory.dart';
import '../notifiers/character_notifier.dart';
import 'gold_coin.dart';

/// The screen this feature never had.
///
/// Everything an accessory knows about itself used to be unreachable: the
/// buy dialog was a fixed "شراء هذه القطعة؟" that could not name the item
/// (its string interpolates only the cost), never showed the balance, and
/// never showed the piece. `Accessory.description` had zero call sites in
/// the whole repo — ten written, translated Arabic lines shipping in every
/// build that no user had ever read.
///
/// One sheet now carries all of it: the art large, the name in full, the
/// description, and a single button whose label states the actual next
/// step rather than a generic verb.
Future<void> showAccessoryDetailSheet(
  BuildContext context,
  Accessory accessory,
) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AccessoryDetailSheet(accessory: accessory),
    );

class _AccessoryDetailSheet extends ConsumerWidget {
  final Accessory accessory;
  const _AccessoryDetailSheet({required this.accessory});

  Color _rarityColor() => switch (accessory.rarity) {
        AchievementRarity.common => GameColors.rarityCommon,
        AchievementRarity.uncommon => GameColors.rarityUncommon,
        AchievementRarity.rare => GameColors.rarityRare,
        AchievementRarity.epic => GameColors.rarityEpic,
        AchievementRarity.legendary => GameColors.rarityLegendary,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final c = _rarityColor();
    final charState = ref.watch(characterProvider);
    final dash = ref.watch(dashboardProvider);

    final owned = charState.owns(accessory.id);
    final equipped = charState.equippedAccessoryId == accessory.id;
    final requirementMet = accessory.unlock == null ||
        accessory.unlock!.isMetBy(
          level: dash.level,
          streak: dash.streak,
          completedDays: dash.totalCompletions,
        );
    final affordable = dash.gold >= accessory.goldCost;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: gp.surfaceHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: gp.border, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        10,
        22,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: gp.border,
              borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 126,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [c.withOpacity(0.26), c.withOpacity(0)],
                    ),
                  ),
                ),
                SizedBox(
                  width: 100,
                  height: 100,
                  child: Image.asset(accessory.imagePath, fit: BoxFit.contain),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            accessory.name(s.isAr),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: gp.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            accessory.description(s.isAr),
            style: TextStyle(
              fontSize: 13.5,
              height: 1.65,
              color: gp.textSec,
            ),
            textAlign: TextAlign.center,
          ),
          if (!owned && !requirementMet) ...[
            const SizedBox(height: 16),
            RequirementBar(
              requirement: accessory.unlock!,
              level: dash.level,
              streak: dash.streak,
              completedDays: dash.totalCompletions,
            ),
          ],
          const SizedBox(height: 16),
          _cta(context, ref, s, c,
              owned: owned,
              equipped: equipped,
              requirementMet: requirementMet,
              affordable: affordable,
              gold: dash.gold),
          // Only where money is actually involved. On an owned item the
          // balance is just a number with nothing to do with the decision
          // in front of you.
          if (!owned) ...[
            const SizedBox(height: 11),
            Text(
              _balanceLine(s,
                  requirementMet: requirementMet,
                  affordable: affordable,
                  gold: dash.gold),
              style: TextStyle(fontSize: 12, color: gp.textTert),
            ),
          ],
        ],
      ),
    );
  }

  String _balanceLine(
    S s, {
    required bool requirementMet,
    required bool affordable,
    required int gold,
  }) {
    if (!requirementMet) return s.closetPriceLater(accessory.goldCost);
    if (!affordable) return s.closetBalanceOf(gold, accessory.goldCost);
    return s.closetBalanceAfter(gold - accessory.goldCost);
  }

  Widget _cta(
    BuildContext context,
    WidgetRef ref,
    S s,
    Color c, {
    required bool owned,
    required bool equipped,
    required bool requirementMet,
    required bool affordable,
    required int gold,
  }) {
    final gp = context.gp;

    if (owned) {
      // The preset accent, not the rarity color. Three colors are doing
      // three different jobs on this screen and they must not blur: rarity
      // tints the halo and the tile border, fixed gold means currency, and
      // the app's own accent means "this is the primary action". A common
      // item's rarity is #8C9A92, and a grey-green primary button reads as
      // disabled.
      return _button(
        label: equipped ? s.closetUnequip : s.closetEquip,
        fg: equipped ? gp.textSec : GameColors.onGold,
        bg: equipped ? Colors.transparent : GameColors.gold,
        border: equipped ? gp.border : null,
        onTap: () {
          HapticFeedback.selectionClick();
          ref
              .read(characterProvider.notifier)
              .equipAccessory(equipped ? null : accessory.id);
        },
      );
    }

    if (!requirementMet) {
      return _button(
        label: s.closetUnlockedByProgress,
        fg: gp.textTert,
        bg: gp.surface,
        border: gp.border,
        onTap: null,
      );
    }

    if (!affordable) {
      return _button(
        label: s.closetShortBy(accessory.goldCost - gold),
        fg: gp.textTert,
        bg: gp.surface,
        border: gp.border,
        coin: true,
        coinDim: true,
        onTap: null,
      );
    }

    // The metal, not the preset accent: the coin on this button is fixed
    // gold (see GoldCoin), and a teal button carrying a gold coin reads as
    // two different currencies. Ink is fixed dark for the same reason —
    // GameColors.onGold is computed against the *preset* gold.
    return _button(
      label: '${s.closetBuy} ${accessory.goldCost}',
      fg: const Color(0xFF18251F),
      bg: GameColors.iconGold,
      coin: true,
      onTap: () async {
        HapticFeedback.mediumImpact();
        final ok =
            await ref.read(characterProvider.notifier).buyAccessory(accessory.id);
        if (!context.mounted) return;
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context).closetPurchaseFailed),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
  }

  Widget _button({
    required String label,
    required Color fg,
    required Color bg,
    Color? border,
    bool coin = false,
    bool coinDim = false,
    VoidCallback? onTap,
  }) =>
      SizedBox(
        width: double.infinity,
        height: 52,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: border == null
                    ? null
                    : Border.all(color: border, width: 0.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (coin) ...[
                    GoldCoin(size: 21, dim: coinDim),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// How far along you are toward a requirement. Shared by the accessory
/// sheet and the locked-character sheet, so both read identically.
///
/// How far along you are toward a requirement. The number matters more
/// than the bar here: "7 / 30" tells you what to do, a bar only tells you
/// roughly how far off you are.
class RequirementBar extends StatelessWidget {
  final UnlockRequirement requirement;
  final int level;
  final int streak;
  final int completedDays;

  const RequirementBar({
    required this.requirement,
    required this.level,
    required this.streak,
    required this.completedDays,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final have = requirement.progressFrom(
      level: level,
      streak: streak,
      completedDays: completedDays,
    );
    final ratio = (have / requirement.amount).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  requirement.label(S.of(context).isAr),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: gp.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: ratio),
                    duration: GameMotion.slow,
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      minHeight: 5,
                      backgroundColor: gp.surfaceHL,
                      valueColor: AlwaysStoppedAnimation(GameColors.rarityEpic),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            S.of(context).closetProgress(have, requirement.amount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: GameColors.rarityEpic,
            ),
          ),
        ],
      ),
    );
  }
}
