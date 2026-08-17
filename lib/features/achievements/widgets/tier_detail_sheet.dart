import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/bidi_fraction.dart';
import '../models/achievement_model.dart';
import 'achievement_medal.dart';
import 'tier_palette.dart';

/// Opens [_TierDetailSheet] for one achievement.
///
/// Lives here rather than privately inside AchievementsScreen because both
/// achievement surfaces need it: the full screen's family ladders and
/// ProgressHubScreen's preview strip show the *same* medals, and having only
/// one of them respond to a tap made the other look broken.
Future<void> showTierDetailSheet(
  BuildContext context,
  AchievementModel achievement,
  AchievementStats stats, {
  required bool unlocked,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _TierDetailSheet(
      achievement: achievement,
      stats: stats,
      unlocked: unlocked,
    ),
  );
}

/// What one tier is, what it costs, and exactly how close this account is.
///
/// The reason every medal is tappable: a family ladder card can only afford
/// to name one tier, so without this the description and reward of the other
/// three simply aren't in the app.
class _TierDetailSheet extends StatelessWidget {
  final AchievementModel achievement;
  final AchievementStats stats;
  final bool unlocked;

  const _TierDetailSheet({
    required this.achievement,
    required this.stats,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final a = achievement;
    final p = TierPalette.from(context, a.tier);
    final family = AchievementCatalog.familyById(a.familyId);
    final current = stats.currentFor(a);
    final progress = stats.progressFor(a);
    final remaining = (a.threshold - current).clamp(0, a.threshold);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          GameSpacing.lg, 0, GameSpacing.lg, GameSpacing.xxxl),
      child: Container(
        padding: const EdgeInsets.fromLTRB(GameSpacing.xxl, GameSpacing.md,
            GameSpacing.xxl, GameSpacing.xxl),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: p.ink.withOpacity(0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: gp.border,
                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
              ),
            ),
            const SizedBox(height: GameSpacing.xl),
            AchievementMedal(
              tier: a.tier,
              icon: achievementIconFor(a.trigger),
              size: 76,
              state: unlocked
                  ? MedalState.unlocked
                  : progress > 0
                      ? MedalState.inProgress
                      : MedalState.locked,
              progress: progress,
              loopShimmer: unlocked,
              semanticLabel: medalSemanticLabel(
                achievement: a,
                state: unlocked ? MedalState.unlocked : MedalState.inProgress,
                current: current,
                isAr: isAr,
              ),
            )
                .animate()
                .scale(
                    begin: const Offset(0.6, 0.6),
                    curve: Curves.easeOutBack,
                    duration: 420.ms)
                .fadeIn(duration: 240.ms),
            const SizedBox(height: GameSpacing.md),
            Text(
              s.achievementsTierOf(
                a.tier.localizedName(isAr),
                family?.localTitle(isAr) ?? '',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: p.ink,
                  letterSpacing: isAr ? 0 : 1),
            ),
            const SizedBox(height: 6),
            Text(
              a.localName(isAr),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                  letterSpacing: -0.2),
            ),
            const SizedBox(height: 6),
            Text(
              a.localDescription(isAr),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: gp.textSec),
            ),
            const SizedBox(height: GameSpacing.xl),
            if (unlocked)
              _StatusPill(
                icon: Icons.verified_rounded,
                label: s.achievementsEarned,
                color: p.ink,
              )
            else ...[
              Row(
                children: [
                  Text(
                    progressFraction(current, a.threshold),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary),
                  ),
                  const Spacer(),
                  Text(
                    s.achievementsRemaining(remaining),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: p.ink),
                  ),
                ],
              ),
              const SizedBox(height: GameSpacing.sm),
              AchievementProgressBar(
                  value: progress, color: p.ink, height: 6),
            ],
            if (a.xpReward > 0 || a.goldReward > 0) ...[
              const SizedBox(height: GameSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (a.xpReward > 0) ...[
                    _RewardChip(
                      icon: Icons.bolt_rounded,
                      label: '+${a.xpReward} XP',
                      color: GameColors.iconXp,
                    ),
                    const SizedBox(width: GameSpacing.sm),
                  ],
                  if (a.goldReward > 0)
                    _RewardChip(
                      icon: Icons.toll_rounded,
                      label: '+${a.goldReward}',
                      color: GameColors.iconGold,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusPill(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: GameSpacing.md, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ],
        ),
      );
}

class _RewardChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _RewardChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: GameSpacing.md, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Text(label,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ],
        ),
      );
}

/// A progress bar that tweens to its value instead of snapping there, so a
/// completion visibly *moves* the bar rather than teleporting it, and every
/// bar draws itself on first paint.
///
/// The track is `textTert` at low opacity rather than `gp.border`: the border
/// shade is tuned to be nearly invisible (it's a hairline between surfaces),
/// which left a bar at 4% looking like an empty box with a speck in it.
class AchievementProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;

  const AchievementProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 5,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return ClipRRect(
      borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: 900.ms,
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => LinearProgressIndicator(
          value: v,
          backgroundColor: gp.textTert.withOpacity(0.18),
          valueColor: AlwaysStoppedAnimation(color),
          minHeight: height,
        ),
      ),
    );
  }
}
