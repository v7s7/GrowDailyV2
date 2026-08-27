import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../notifiers/custom_rewards_notifier.dart';
import '../screens/custom_rewards_screen.dart';

/// The one door into My Rewards, and the only thing this feature adds to a
/// screen that already existed.
///
/// It lives in the closet because the codebase already settled this exact
/// question when the streak freeze was moved there: a gold-spending purchase
/// belongs in the shop with everything else gold buys. The closet is also
/// the only screen that shows the balance, and it is where the "nothing left
/// to buy" problem physically shows up.
///
/// Cloned from _StreakFreezeShopCard so it reads as that card's sibling
/// rather than as a different app bolted on. The one deliberate difference
/// is the trailing chevron instead of a price pill: the freeze card's pill
/// IS the buy button, while this card navigates, and every navigating row in
/// the app ends in a chevron.
///
/// No progress gate. The freeze card's `streak >= 3` exists because every
/// account starts with a freeze already banked; there is no analogue here,
/// and gating the only gold sink behind progress would be backwards.
class CustomRewardsEntryCard extends ConsumerWidget {
  const CustomRewardsEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final dash = ref.watch(dashboardProvider);
    final rewards = ref.watch(customRewardsProvider);

    // Live, and this is the whole anti-staleness mechanism: the card sits on
    // the one screen a person opens with gold in hand, so it can say
    // something true about their list without any nagging elsewhere.
    //
    // Order matters. Affordability is only claimed when both numbers are
    // real: a failed or in-flight load renders the balance as a confident 0,
    // and "closest one is 400 gold away" against a fake 0 is a lie told to
    // someone who has 4,000.
    final String subtitle;
    if (rewards.isLoading) {
      subtitle = s.rewardsCardTitle;
    } else if (rewards.rewards.isEmpty) {
      subtitle = s.rewardsCardEmpty;
    } else if (!dash.statsAreReal || rewards.loadFailed) {
      subtitle = s.rewardsCardCount(rewards.rewards.length);
    } else {
      final ready = rewards.affordableCount(dash.gold);
      if (ready > 0) {
        subtitle = s.rewardsCardReady(ready);
      } else {
        final short = rewards.closestShortfall(dash.gold);
        subtitle = short == null
            ? s.rewardsCardCount(rewards.rewards.length)
            : s.rewardsCardClosest(short);
      }
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const CustomRewardsScreen(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                // The fixed metal, not GameColors.gold, which is a preset
                // accent role and resolves to teal on Ocean and rose on Rose.
                color: GameColors.iconGold.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.card_giftcard_rounded,
                color: GameColors.iconGold,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.rewardsCardTitle,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: gp.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11.5, color: gp.textSec),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right_rounded, size: 18, color: gp.textTert),
          ],
        ),
      ),
    );
  }
}
