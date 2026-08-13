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
    final dashState = ref.watch(dashboardProvider);

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
              borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
              border: Border.all(color: GameColors.gold.withOpacity(0.3), width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.toll_rounded, size: 13, color: GameColors.gold),
                const SizedBox(width: 4),
                Text('${dashState.gold}',
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
                // Relocated from the old Dashboard/Progress page — a
                // gold-spending purchase belongs in the shop, not on a
                // "look back at your progress" stats screen. Same 3-day
                // streak gate as before (see _StreakFreezeShopCard's doc
                // comment for why that threshold).
                if (dashState.streak >= 3)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                      child: _StreakFreezeShopCard(state: dashState),
                    ),
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

// ─── Streak Freeze shop card ────────────────────────────────────────────────

/// Relocated here from the old Dashboard/Progress page — this is a
/// gold-spending purchase, so it belongs in the shop with everything else
/// gold buys, not on a page whose whole job is now "look back at your
/// progress". Same design and same 3-day-streak gate as before: every
/// account starts with one free freeze already banked (see
/// DashboardNotifier's `?? 1` default), so surfacing this before there's a
/// real streak worth protecting was pitching insurance before there was
/// anything to insure.
class _StreakFreezeShopCard extends ConsumerWidget {
  final DashboardState state;
  const _StreakFreezeShopCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final canBuy = state.gold >= DashboardNotifier.streakFreezeCost &&
        state.streakFreezes < DashboardNotifier.maxStreakFreezes;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.iconXp.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: GameColors.iconXp.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.ac_unit_rounded, color: GameColors.iconXp),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.streakFreeze,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  s.streakFreezeStatus(
                      state.streakFreezes, DashboardNotifier.maxStreakFreezes),
                  style: TextStyle(fontSize: 12, color: gp.textSec),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: FilledButton.tonalIcon(
              onPressed: canBuy
                  ? () async {
                      HapticFeedback.mediumImpact();
                      final ok = await ref
                          .read(dashboardProvider.notifier)
                          .buyStreakFreeze();
                      if (context.mounted) {
                        final s2 = S.of(context);
                        // `canBuy` already gated this button on having enough
                        // gold and free slots, so a `false` result here means
                        // the purchase failed to save (e.g. no network) —
                        // not that funds were insufficient.
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text(ok ? s2.streakFreeze : s2.errGeneric),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.toll_rounded, size: 16),
              label: Text('${DashboardNotifier.streakFreezeCost}'),
            ),
          ),
        ],
      ),
    );
  }
}
