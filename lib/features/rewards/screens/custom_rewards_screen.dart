import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../character/widgets/gold_coin.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../catalog/starter_rewards.dart';
import '../models/custom_reward.dart';
import '../notifiers/custom_rewards_notifier.dart';
import '../widgets/custom_reward_sheet.dart';

/// The gold sink: a list the user writes and prices for themselves.
///
/// Reached only from [CustomRewardsEntryCard] in the closet. Nothing else in
/// the app links here, and no named route is registered, because main.dart's
/// routes map exists for deep links and a screen one push below the closet
/// has no deep-link caller.
class CustomRewardsScreen extends ConsumerWidget {
  const CustomRewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final dash = ref.watch(dashboardProvider);
    final rewards = ref.watch(customRewardsProvider);

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          s.rewardsTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
        actions: [
          // Hidden rather than zeroed when the load failed. A failed or
          // in-flight load renders as a confident 0, and a confident 0 above
          // a list of prices tells someone with 4,000 real gold they are
          // broke. Directional inset, not a physical one: a physical inset
          // put the gap on the wrong side in this RTL-first app.
          if (dash.statsAreReal)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: Center(child: GoldPurse(gold: dash.gold)),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _body(context, ref, s, dash, rewards)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: FilledButton.icon(
                // Anchored rather than a FAB or a list item, so it sits in
                // the same place whether the list holds zero rewards or
                // nine. That is what lets the empty-state copy point at it.
                onPressed: rewards.loadFailed
                    ? null
                    : () {
                        if (rewards.rewards.length >= kCustomRewardListMax) {
                          ScaffoldMessenger.of(context).showOne(
                            SnackBar(
                              content: Text(s.rewardsLimitReached),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        unawaited(showCustomRewardSheet(context, ref));
                      },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(s.rewardsAdd),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    S s,
    DashboardState dash,
    CustomRewardsState rewards,
  ) {
    if (rewards.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final notices = <Widget>[
      if (rewards.loadFailed) _notice(context, s.rewardsListUnavailable),
      if (!dash.statsAreReal) _notice(context, s.rewardsBalanceUnavailable),
    ];

    final content = rewards.rewards.isEmpty
        ? _EmptyRewards(
            onPick: (name, price) => unawaited(
              showCustomRewardSheet(
                context,
                ref,
                prefillName: name,
                prefillPrice: price,
              ),
            ),
          )
        : ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            itemCount: rewards.rewards.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _RewardRow(reward: rewards.rewards[i]),
          ).animate().fadeIn(duration: GameMotion.relaxed);

    if (notices.isEmpty) return content;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(
            children: [
              for (final n in notices) ...[n, const SizedBox(height: 14)],
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget _notice(BuildContext context, String text) {
    final gp = context.gp;
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 20, color: gp.textTert),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12.5,
                  color: gp.textSec,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
  }
}

class _EmptyRewards extends StatelessWidget {
  final void Function(String name, int price) onPick;
  const _EmptyRewards({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.card_giftcard_rounded, size: 44, color: gp.textTert),
            const SizedBox(height: 14),
            Text(
              s.rewardsEmptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.rewardsEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.4),
            ),
            const SizedBox(height: 22),
            Text(
              s.rewardsStarterTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: gp.textSec,
                letterSpacing: s.isAr ? 0 : 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final starter in StarterRewardCatalog.all)
                  _StarterChip(starter: starter, onPick: onPick),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StarterChip extends StatelessWidget {
  final StarterReward starter;
  final void Function(String name, int price) onPick;
  const _StarterChip({required this.starter, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final price = priceForDays(starter.days);

    return Material(
      color: gp.surface,
      borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
        onTap: () {
          HapticFeedback.selectionClick();
          // Opens the editor prefilled. It never silently adds: accepting is
          // one more tap on Save, so nobody ends up with a list they did not
          // write.
          onPick(starter.name(s.isAr), price);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                starter.name(s.isAr),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: gp.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              GoldPrice(amount: price, dense: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _RewardRow extends ConsumerWidget {
  final CustomReward reward;
  const _RewardRow({required this.reward});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final dash = ref.watch(dashboardProvider);
    final rewards = ref.watch(customRewardsProvider);

    final canClaim = dash.statsAreReal &&
        !rewards.loadFailed &&
        rewards.claimingId == null &&
        dash.gold >= reward.priceGold;

    // Only drawn when both numbers are real. When the balance has not
    // loaded, no shortfall is claimed at all rather than one computed
    // against a placeholder zero.
    final showShortfall = dash.statsAreReal &&
        !rewards.loadFailed &&
        dash.gold < reward.priceGold;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: rewards.loadFailed
                  ? null
                  : () => unawaited(
                        showCustomRewardSheet(context, ref, existing: reward),
                      ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    reward.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: gp.textPrimary,
                    ),
                  ),
                  if (showShortfall) ...[
                    const SizedBox(height: 3),
                    Text(
                      s.closetShortBy(reward.priceGold - dash.gold),
                      style: TextStyle(fontSize: 11.5, color: gp.textSec),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: canClaim ? () => _confirmClaim(context, ref, dash) : null,
            child: GoldPrice(amount: reward.priceGold, affordable: canClaim),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClaim(
    BuildContext context,
    WidgetRef ref,
    DashboardState dash,
  ) async {
    final s = S.of(context);
    unawaited(HapticFeedback.mediumImpact());

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.rewardsClaimTitle),
        content: Text(
          '${s.rewardsClaimBody(reward.name, reward.priceGold)}\n'
          '${s.closetBalanceAfter(dash.gold - reward.priceGold)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.rewardsCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.rewardsClaimConfirm),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;

    final paid = reward.priceGold;
    final ok = await ref.read(customRewardsProvider.notifier).claim(reward.id);
    if (!context.mounted) return;

    if (!ok) {
      // Affordability was pre-gated on canClaim, so a false here can only be
      // a write failure. That is what makes this message honest rather than
      // telling someone the network broke when they were simply short.
      ScaffoldMessenger.of(context).showOne(
        SnackBar(
          content: Text(s.rewardsFailed),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    await _celebrate(context, ref, paid);
  }

  /// A claim is a moment, not a silent debit. A sink where spending feels
  /// like nothing teaches people to hoard, which is exactly the behaviour
  /// this feature exists to undo.
  Future<void> _celebrate(
    BuildContext context,
    WidgetRef ref,
    int paid,
  ) async {
    final s = S.of(context);
    final gp = context.gp;
    final left = ref.read(dashboardProvider).gold;
    unawaited(HapticFeedback.mediumImpact());

    await showDialog<void>(
      context: context,
      builder: (ctx) => Semantics(
        label: s.rewardsSemantic(reward.name),
        child: AlertDialog(
          backgroundColor: gp.surfaceHigh,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: GameColors.iconGold.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.card_giftcard_rounded,
                  size: 30,
                  color: GameColors.iconGold,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                s.rewardsClaimedEyebrow,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: gp.textSec,
                  letterSpacing: s.isAr ? 0 : 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                reward.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${s.rewardsPaid(paid)}\n${s.rewardsBalanceNow(left)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: gp.textSec,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                s.rewardsEarnedIt,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: gp.textPrimary,
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.rewardsGoEnjoy),
            ),
          ],
        ),
      ),
    );
  }
}
