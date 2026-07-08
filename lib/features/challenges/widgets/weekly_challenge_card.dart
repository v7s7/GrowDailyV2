import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/game_theme.dart';
import '../notifiers/weekly_challenge_notifier.dart';

IconData _challengeIcon(String type) => switch (type) {
      'quran' => Icons.menu_book_rounded,
      'fast' => Icons.no_food_rounded,
      'pray' => Icons.self_improvement_rounded,
      'charity' => Icons.volunteer_activism_rounded,
      'night' => Icons.nightlight_round,
      _ => Icons.flag_rounded,
    };

class WeeklyChallengeCard extends ConsumerWidget {
  const WeeklyChallengeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final state = ref.watch(weeklyChallengeProvider);
    if (state.isLoading) return const SizedBox.shrink();

    final c = state.challenge;
    final progress = (state.progress / c.target).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(
          color: state.isCompleted
              ? GameColors.success.withOpacity(0.4)
              : gp.border,
          width: state.isCompleted ? 1 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: GameColors.xpBlue.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_challengeIcon(c.iconType),
                    size: 18, color: GameColors.xpBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WEEKLY CHALLENGE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: gp.textSec,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.isCompleted)
                Icon(Icons.verified_rounded,
                    size: 18,
                    color: state.rewardClaimed
                        ? GameColors.success
                        : GameColors.gold),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            c.description,
            style: TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.4),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: gp.border,
              valueColor: AlwaysStoppedAnimation(
                  state.isCompleted ? GameColors.success : GameColors.xpBlue),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${state.progress} / ${c.target}',
                style: TextStyle(
                    fontSize: 11,
                    color: gp.textTert,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Icon(Icons.bolt_rounded, size: 12, color: GameColors.xpBlue),
              const SizedBox(width: 2),
              Text('+${c.xpReward}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: GameColors.xpBlue)),
              const SizedBox(width: 8),
              Icon(Icons.toll_rounded, size: 12, color: GameColors.gold),
              const SizedBox(width: 2),
              Text('+${c.goldReward}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: GameColors.gold)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: state.rewardClaimed
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: gp.surfaceHL,
                      borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 16, color: GameColors.success),
                        const SizedBox(width: 6),
                        Text('REWARD CLAIMED',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: gp.textSec,
                                letterSpacing: 1)),
                      ],
                    ),
                  )
                : state.isCompleted
                    ? FilledButton(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          ref.read(weeklyChallengeProvider.notifier).claimReward();
                        },
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                        child: const Text('CLAIM REWARD'),
                      )
                    : OutlinedButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          ref.read(weeklyChallengeProvider.notifier).logProgress();
                        },
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                        child: const Text('LOG PROGRESS'),
                      ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.06, curve: Curves.easeOut);
  }
}
