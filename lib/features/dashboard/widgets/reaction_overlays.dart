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
/// streak-freeze protection) are all reactions to [dashboardProvider] state
/// changes. Both GridScreen (the app's home) and DashboardScreen register
/// this so a square colored on the grid celebrates exactly like a habit
/// completed the old way — progression is progression no matter which
/// screen the player is looking at.
void registerDashboardReactions(
  BuildContext context,
  WidgetRef ref,
) {
  ref.listen<DashboardState>(dashboardProvider, (prev, next) {
    if (prev == null) return;

    if (next.didUseStreakFreeze && !prev.didUseStreakFreeze) {
      HapticFeedback.mediumImpact();
      showStreakFreezeProtectedSnackBar(context, next.streakFreezes);
    }
    if (next.perfectDayCelebration && !prev.perfectDayCelebration) {
      HapticFeedback.heavyImpact();
      // Small beat after the completing square's own confetti so the two
      // moments read as separate: "that square" ... "and that's the whole
      // day". If a level-up/achievement also lands this tick, those still
      // take over afterwards (the achievement sheet clears snackbars).
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!context.mounted) return;
        final size = MediaQuery.of(context).size;
        showVictoryBurst(
          context,
          Offset(size.width / 2, size.height * 0.35),
        );
        showPerfectDaySnackBar(context);
      });
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
          // A level-up or streak-freeze snackbar may already be on screen
          // from earlier in this same reaction batch — clear it so the
          // achievement sheet (the bigger celebration) doesn't visually
          // collide with a toast sitting at the same bottom edge.
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          showAchievementUnlockSheet(context, next.newlyUnlocked.first);
        }
      });
    }
    if (next.milestoneCelebration != null &&
        prev.milestoneCelebration == null) {
      final m = next.milestoneCelebration!;
      Future.delayed(const Duration(milliseconds: 350), () {
        if (context.mounted) {
          // Same reasoning as the achievement sheet above: a milestone is
          // the biggest celebration in the app, so it should never appear
          // stacked on top of a leftover snackbar.
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          showMilestoneCelebration(context, m, ref);
        }
      });
    }
    if (next.habitMilestoneCelebration != null &&
        prev.habitMilestoneCelebration == null) {
      final event = next.habitMilestoneCelebration!;
      // Slightly longer delay than the app-wide milestone above so that on
      // the rare tick both fire together, this one settles in after it
      // rather than the two dialogs racing.
      Future.delayed(const Duration(milliseconds: 400), () {
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          showHabitMilestoneCelebration(context, event, ref);
        }
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
        Icon(Icons.ac_unit_rounded, color: GameColors.iconXp, size: 18),
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

/// "Every habit green today" — the day's own completion moment, distinct
/// from level/achievement rewards: emerald (the grid's color), not gold,
/// because what's being celebrated is the colored board itself.
void showPerfectDaySnackBar(BuildContext context) {
  final gp = context.gp;
  final s = S.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome_rounded,
              color: GameColors.emerald, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              s.perfectDayMsg,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: GameColors.emerald,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: gp.surface,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: GameColors.emerald, width: 1),
      ),
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
    final title = s.milestoneTitle(milestone);
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
                  color: GameColors.iconStreak.withOpacity(0.16),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: GameColors.iconStreak.withOpacity(0.35),
                      blurRadius: 50,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: Icon(Icons.local_fire_department_rounded,
                    size: 56, color: GameColors.iconStreak),
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
                  color: GameColors.iconStreak,
                  // Wide/negative letter-spacing is a Latin-typography trick
                  // (all-caps eyebrow labels, tight display numerals) — on
                  // Arabic's cursive, joined script it forces gaps between
                  // letters that should connect, reading as a broken font.
                  // Zero it out for Arabic instead.
                  letterSpacing: s.isAr ? 0 : 3,
                ),
              ).animate(delay: 250.ms).fadeIn(),
              const SizedBox(height: 10),
              Text(
                s.daysCount(milestone),
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: s.isAr ? 0 : -1.5,
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
                    color: GameColors.iconXp.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: GameColors.iconXp.withOpacity(0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded, size: 16, color: GameColors.iconXp),
                      const SizedBox(width: 6),
                      Text(s.milestoneBonusXp(bonus),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: GameColors.iconXp)),
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

// ─── Habit Milestone Celebration ───────────────────────────────────────────
//
// The per-habit sibling of MilestoneCelebration above. Deliberately a
// lighter, centered card rather than a full-Scaffold takeover — this can
// fire once per habit per threshold (multiple times across a user's habit
// list), so it needs to read as "special" without competing with the
// app-wide streak milestone for the title of biggest celebration in the app.

void showHabitMilestoneCelebration(
    BuildContext context, HabitMilestoneEvent event, WidgetRef ref) {
  HapticFeedback.heavyImpact();
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.7),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => HabitMilestoneCelebration(event: event),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.9, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  ).then((_) => ref.read(dashboardProvider.notifier).acknowledgeHabitMilestone());
}

class HabitMilestoneCelebration extends StatelessWidget {
  final HabitMilestoneEvent event;
  const HabitMilestoneCelebration({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          decoration: BoxDecoration(
            color: gp.surfaceHigh,
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            border: Border.all(
                color: GameColors.iconStreak.withOpacity(0.4), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VictoryBurstOnMount(
                colors: [
                  GameColors.iconStreak,
                  GameColors.gold,
                  Colors.white,
                ],
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: GameColors.iconStreak.withOpacity(0.16),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: GameColors.iconStreak.withOpacity(0.32),
                        blurRadius: 36,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: Icon(Icons.local_fire_department_rounded,
                      size: 40, color: GameColors.iconStreak),
                )
                    .animate()
                    .scale(
                        begin: const Offset(0.3, 0.3),
                        curve: Curves.elasticOut,
                        duration: 700.ms)
                    .fadeIn(duration: 250.ms),
              ),
              const SizedBox(height: 18),
              Text(
                s.streakMilestoneLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: GameColors.iconStreak,
                  letterSpacing: s.isAr ? 0 : 2.5,
                ),
              ).animate(delay: 120.ms).fadeIn(),
              const SizedBox(height: 8),
              Text(
                s.daysCount(event.milestone),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: gp.textPrimary,
                  letterSpacing: s.isAr ? 0 : -1,
                  height: 1,
                ),
              ).animate(delay: 180.ms).fadeIn().slideY(begin: 0.2),
              const SizedBox(height: 6),
              Text(
                event.habitName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: gp.textSec,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ).animate(delay: 240.ms).fadeIn(),
              const SizedBox(height: 22),
              if (event.bonusXp > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: GameColors.iconXp.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(100),
                    border:
                        Border.all(color: GameColors.iconXp.withOpacity(0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded,
                          size: 16, color: GameColors.iconXp),
                      const SizedBox(width: 6),
                      Text(s.milestoneBonusXp(event.bonusXp),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: GameColors.iconXp)),
                    ],
                  ),
                ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.2),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pop();
                  },
                  child: Text(s.keepGrowing),
                ),
              ).animate(delay: 360.ms).fadeIn().slideY(begin: 0.2),
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
                    color: GameColors.iconXp,
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
