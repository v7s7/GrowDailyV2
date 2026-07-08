import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/victory_burst.dart';
import '../../achievements/models/achievement_model.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../notifiers/dashboard_notifier.dart';

/// The RPG feedback moments (level up, achievement unlock, streak milestone,
/// streak-freeze protection, first-load intention prompt) are all reactions
/// to [dashboardProvider] state changes. Both GridScreen (the app's home) and
/// DashboardScreen register this so a square colored on the grid celebrates
/// exactly like a habit completed the old way — progression is progression
/// no matter which screen the player is looking at.
void registerDashboardReactions(
  BuildContext context,
  WidgetRef ref, {
  bool routeToIntentionOnFirstLoad = false,
}) {
  ref.listen<DashboardState>(dashboardProvider, (prev, next) {
    if (prev == null) return;

    // Brand-new users (no habits yet) skip the intention prompt — the empty
    // grid with its "browse plans" call-to-action is the better first hello.
    if (routeToIntentionOnFirstLoad &&
        prev.isLoading &&
        !next.isLoading &&
        !next.intentionsSetToday &&
        ref.read(habitListProvider).isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.pushNamed(context, '/intention');
        }
      });
      return;
    }

    if (next.didUseStreakFreeze && !prev.didUseStreakFreeze) {
      HapticFeedback.mediumImpact();
      showStreakFreezeProtectedSnackBar(context, next.streakFreezes);
    }
    if (next.didJustLevelUp) {
      HapticFeedback.heavyImpact();
      showLevelUpSnackBar(context, next.level);
    }
    if (next.newlyUnlocked.isNotEmpty && prev.newlyUnlocked.isEmpty) {
      ref.read(dashboardProvider.notifier).acknowledgeAchievements();
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 250), () {
        if (context.mounted) {
          showAchievementUnlockSheet(context, next.newlyUnlocked.first);
        }
      });
    }
    if (next.milestoneCelebration != null &&
        prev.milestoneCelebration == null) {
      final m = next.milestoneCelebration!;
      Future.delayed(const Duration(milliseconds: 350), () {
        if (context.mounted) showMilestoneCelebration(context, m, ref);
      });
    }
  });
}

void showStreakFreezeProtectedSnackBar(BuildContext context, int remaining) {
  final gp = context.gp;
  final s = S.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(children: [
        Icon(Icons.ac_unit_rounded, color: GameColors.xpBlue, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            s.streakFreezeProtected(remaining),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: gp.textPrimary,
            ),
          ),
        ),
      ]),
      backgroundColor: gp.surfaceHigh,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

void showLevelUpSnackBar(BuildContext context, int level) {
  final gp = context.gp;
  final s = S.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.arrow_upward_rounded,
              color: GameColors.gold, size: 18),
          const SizedBox(width: 8),
          Text('${s.levelUpMsg}  —  LVL $level',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: GameColors.gold,
                  letterSpacing: 1)),
        ],
      ),
      backgroundColor: gp.surface,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: GameColors.gold, width: 1),
      ),
    ),
  );
}

void showAchievementUnlockSheet(BuildContext context, AchievementModel a) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AchievementUnlockSheet(achievement: a),
  );
}

void showMilestoneCelebration(
    BuildContext context, int milestone, WidgetRef ref) {
  HapticFeedback.heavyImpact();
  showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.85),
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (_, __, ___) =>
        MilestoneCelebration(milestone: milestone, ref: ref),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  ).then((_) => ref.read(dashboardProvider.notifier).acknowledgeMilestone());
}

// ─── Milestone Celebration ────────────────────────────────────────────────

class MilestoneCelebration extends StatelessWidget {
  final int milestone;
  final WidgetRef ref;
  const MilestoneCelebration(
      {super.key, required this.milestone, required this.ref});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final bonus = milestoneXpBonus(milestone);
    final title = milestoneTitle(milestone);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: GameColors.streakOrange.withOpacity(0.16),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: GameColors.streakOrange.withOpacity(0.35),
                      blurRadius: 50,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: Icon(Icons.local_fire_department_rounded,
                    size: 56, color: GameColors.streakOrange),
              )
                  .animate()
                  .scale(
                      begin: const Offset(0.3, 0.3),
                      curve: Curves.elasticOut,
                      duration: 800.ms)
                  .fadeIn(duration: 300.ms),
              const SizedBox(height: 28),
              Text(
                s.streakMilestoneLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: GameColors.streakOrange,
                  letterSpacing: 3,
                ),
              ).animate(delay: 250.ms).fadeIn(),
              const SizedBox(height: 10),
              Text(
                s.daysCount(milestone),
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.5,
                  height: 1,
                ),
              ).animate(delay: 320.ms).fadeIn().slideY(begin: 0.2),
              const SizedBox(height: 8),
              Text(
                s.nowWarrior(title),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.85),
                ),
                textAlign: TextAlign.center,
              ).animate(delay: 380.ms).fadeIn(),
              const SizedBox(height: 8),
              Text(
                s.consistencyBuildsCharacter,
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5)),
                textAlign: TextAlign.center,
              ).animate(delay: 420.ms).fadeIn(),
              const SizedBox(height: 24),
              if (bonus > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: GameColors.xpBlue.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: GameColors.xpBlue.withOpacity(0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded, size: 16, color: GameColors.xpBlue),
                      const SizedBox(width: 6),
                      Text(s.milestoneBonusXp(bonus),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: GameColors.xpBlue)),
                    ],
                  ),
                ).animate(delay: 480.ms).fadeIn().slideY(begin: 0.2),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    ref.read(dashboardProvider.notifier).acknowledgeMilestone();
                    Navigator.of(context).pop();
                  },
                  child: Text(s.keepGrowing),
                ),
              ).animate(delay: 560.ms).fadeIn().slideY(begin: 0.2),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Achievement Unlock Sheet ──────────────────────────────────────────────

class AchievementUnlockSheet extends StatelessWidget {
  final AchievementModel achievement;
  const AchievementUnlockSheet({super.key, required this.achievement});

  Color get _color => switch (achievement.rarity) {
        AchievementRarity.common => GameColors.rarityCommon,
        AchievementRarity.uncommon => GameColors.rarityUncommon,
        AchievementRarity.rare => GameColors.rarityRare,
        AchievementRarity.epic => GameColors.rarityEpic,
        AchievementRarity.legendary => GameColors.rarityLegendary,
      };

  IconData get _icon => switch (achievement.trigger) {
        AchievementTrigger.streak =>
          Icons.local_fire_department_rounded,
        AchievementTrigger.level => Icons.bolt_rounded,
        AchievementTrigger.totalCompletions =>
          Icons.check_circle_rounded,
        AchievementTrigger.habitMastery => Icons.menu_book_rounded,
        AchievementTrigger.greenSquares => Icons.grid_view_rounded,
        _ => Icons.stars_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final c = _color;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: c.withOpacity(0.4), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: gp.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 28),
            VictoryBurstOnMount(
              colors: [c, GameColors.gold, Colors.white],
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: c.withOpacity(0.14),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: c.withOpacity(0.28),
                        blurRadius: 28,
                        spreadRadius: 4),
                  ],
                ),
                child: Icon(_icon, size: 34, color: c),
              )
                  .animate()
                  .scale(
                      begin: const Offset(0.4, 0.4),
                      curve: Curves.elasticOut,
                      duration: 700.ms)
                  .fadeIn(duration: 300.ms),
            ),
            const SizedBox(height: 18),
            Builder(builder: (ctx) => Text(
              S.of(ctx).achievementUnlocked,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: c,
                  letterSpacing: 2),
            )).animate(delay: 200.ms).fadeIn(),
            const SizedBox(height: 8),
            Text(
              achievement.name,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                  letterSpacing: -0.3),
              textAlign: TextAlign.center,
            ).animate(delay: 280.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 6),
            Text(
              achievement.description,
              style: TextStyle(fontSize: 14, color: gp.textSec),
              textAlign: TextAlign.center,
            ).animate(delay: 320.ms).fadeIn(),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (achievement.xpReward > 0) ...[
                  _RewardChip(
                    icon: Icons.bolt_rounded,
                    label: '+${achievement.xpReward} XP',
                    color: GameColors.xpBlue,
                  ),
                  const SizedBox(width: 10),
                ],
                if (achievement.goldReward > 0)
                  _RewardChip(
                    icon: Icons.toll_rounded,
                    label: '+${achievement.goldReward} Gold',
                    color: GameColors.gold,
                  ),
              ],
            ).animate(delay: 380.ms).fadeIn(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: Builder(
                builder: (ctx) => FilledButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(ctx);
                  },
                  child: Text(S.of(ctx).claimReward),
                ),
              ),
            ).animate(delay: 460.ms).fadeIn().slideY(begin: 0.2),
          ],
        ),
      ),
    );
  }
}

class _RewardChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _RewardChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(100),
        border:
            Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}
