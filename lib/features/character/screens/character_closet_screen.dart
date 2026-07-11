import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../models/accessory.dart';
import '../models/character_option.dart';
import '../notifiers/character_notifier.dart';
import '../widgets/accessory_shop_tile.dart';
import '../widgets/character_avatar.dart';

/// Shop/closet screen reached from Profile — pick a character, browse
/// accessories by category, buy locked ones with gold, tap an owned one to
/// equip/unequip it. Chrome mirrors AchievementsScreen (same AppBar style,
/// CustomScrollView + slivers) so it feels native to the rest of Profile.
class CharacterClosetScreen extends ConsumerWidget {
  const CharacterClosetScreen({super.key});

  Future<void> _handleTap(
    BuildContext context,
    WidgetRef ref,
    Accessory accessory,
    CharacterState charState,
  ) async {
    final s = S.of(context);
    final notifier = ref.read(characterProvider.notifier);
    HapticFeedback.selectionClick();

    if (charState.owns(accessory.id)) {
      final isEquipped = charState.equippedAccessoryId == accessory.id;
      notifier.equipAccessory(isEquipped ? null : accessory.id);
      return;
    }

    final gold = ref.read(dashboardProvider).gold;
    final gp = context.gp;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: gp.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        ),
        title: Text(s.closetBuyConfirmTitle,
            style: TextStyle(color: gp.textPrimary, fontWeight: FontWeight.w800)),
        content: Text(
          s.closetBuyConfirmBody(accessory.goldCost),
          style: TextStyle(color: gp.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(s.closetCancel, style: TextStyle(color: gp.textTert)),
          ),
          TextButton(
            onPressed: gold >= accessory.goldCost
                ? () => Navigator.pop(dialogContext, true)
                : null,
            child: Text(
              gold >= accessory.goldCost ? s.closetBuy : s.closetNotEnoughGold,
              style: TextStyle(
                color: gold >= accessory.goldCost ? GameColors.gold : gp.textTert,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final success = await notifier.buyAccessory(accessory.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? s.closetPurchased : s.closetPurchaseFailed),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final charState = ref.watch(characterProvider);
    final gold = ref.watch(dashboardProvider).gold;

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(s.closetTitle,
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: gp.textPrimary)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: GameColors.gold.withOpacity(0.12),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: GameColors.gold.withOpacity(0.3), width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.toll_rounded, size: 13, color: GameColors.gold),
                const SizedBox(width: 4),
                Text('$gold',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: GameColors.gold)),
              ],
            ),
          ),
        ],
      ),
      body: charState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _PreviewCard(state: charState),
                  ).animate().fadeIn(duration: 400.ms),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                    child: Text(s.closetCharacterSection,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: gp.textSec,
                            letterSpacing: 1.5)),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _CharacterPicker(state: charState),
                ),
                for (final category in AccessoryCategory.values) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                      child: Row(
                        children: [
                          Icon(category.icon, size: 15, color: gp.textSec),
                          const SizedBox(width: 6),
                          Text(category.label(s.isAr).toUpperCase(),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: gp.textSec,
                                  letterSpacing: s.isAr ? 0 : 1.2)),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 108,
                        mainAxisExtent: 128,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final accessory = AccessoryCatalog.byCategory(category)[i];
                          return AccessoryShopTile(
                            accessory: accessory,
                            owned: charState.owns(accessory.id),
                            equipped: charState.equippedAccessoryId == accessory.id,
                            onTap: () => _handleTap(context, ref, accessory, charState),
                          ).animate(delay: (i * 40).ms).fadeIn(duration: 300.ms).slideY(begin: 0.08);
                        },
                        childCount: AccessoryCatalog.byCategory(category).length,
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
    );
  }
}

// ─── Preview Card ────────────────────────────────────────────────────────────

class _PreviewCard extends StatelessWidget {
  final CharacterState state;
  const _PreviewCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      // Without this, Container doesn't center a child smaller than itself —
      // it sits flush at the top-left of the card instead, which is exactly
      // why the whole character+accessory looked shifted off to one side.
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: CharacterAvatar(
        character: state.character,
        accessory: state.equippedAccessory,
        height: 190,
      ),
    );
  }
}

// ─── Character Picker ────────────────────────────────────────────────────────

class _CharacterPicker extends ConsumerWidget {
  final CharacterState state;
  const _CharacterPicker({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: CharacterCatalog.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final option = CharacterCatalog.all[i];
          final selected = option.id == state.characterId;
          return InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(characterProvider.notifier).selectCharacter(option.id);
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 78,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: selected ? GameColors.gold.withOpacity(0.12) : gp.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? GameColors.gold : gp.border,
                  width: selected ? 1.4 : 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: Image.asset(option.assetPath, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    option.name(S.of(context).isAr),
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? GameColors.gold : gp.textTert),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
