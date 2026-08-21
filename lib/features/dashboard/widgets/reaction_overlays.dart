import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/victory_burst.dart';
import '../../achievements/models/achievement_model.dart';
import '../../achievements/widgets/achievement_medal.dart';
import '../../achievements/widgets/tier_palette.dart';
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
      // Capture before acknowledging — acknowledgeAchievements clears
      // state.newlyUnlocked right away, so the list has to be saved here or
      // everything after the first sheet would have nothing left to show.
      final unlocked = next.newlyUnlocked;
      ref.read(dashboardProvider.notifier).acknowledgeAchievements();
      Future.delayed(const Duration(milliseconds: 250), () async {
        if (!context.mounted) return;
        // A level-up or streak-freeze snackbar may already be on screen
        // from earlier in this same reaction batch — clear it so the
        // achievement sheet (the bigger celebration) doesn't visually
        // collide with a toast sitting at the same bottom edge.
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        // One completion can cross more than one threshold at once (say,
        // the same tap that hits a streak milestone is also the habit's
        // 50th-ever completion) — celebrate every one of them in turn
        // instead of just the first, so nobody's medal unlocks silently.
        for (final a in unlocked) {
          if (!context.mounted) return;
          HapticFeedback.heavyImpact();
          await showAchievementUnlockSheet(context, a);
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius)),
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
        borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
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
          Text('${s.levelUpMsg}  ·  LVL $level',
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
        borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
        side: BorderSide(color: GameColors.gold, width: 1),
      ),
    ),
  );
}

/// Returns the sheet's dismissal Future (resolves on Claim tap or swipe-
/// down) so callers queuing several unlocks in a row can await each one
/// before showing the next instead of stacking them.
Future<void> showAchievementUnlockSheet(BuildContext context, AchievementModel a) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // Without this, the sheet ignores the iPhone home-indicator inset and
    // its Claim button can render flush with (or under) the gesture bar.
    useSafeArea: true,
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
                    borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
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
    // Transparent Material so descendant Text widgets have a real
    // DefaultTextStyle to inherit from. Unlike MilestoneCelebration above
    // (which gets one free from its Scaffold), this is a bare card handed
    // straight to showGeneralDialog, so it lands on the Navigator's overlay
    // with no Material anywhere above it. Without this, every Text here
    // inherits MaterialApp's `_errorTextStyle` fallback — red 48px monospace
    // with a yellow double underline. The explicit color/fontSize on each
    // style below override the red and the size but never the *decoration*,
    // so the yellow lines survive and are all you actually see. Note this is
    // NOT debug-only: MaterialApp passes _errorTextStyle to WidgetsApp
    // unconditionally, so it ships to users. See also VoiceNotePlayer, which
    // needs the same wrapper for the same reason.
    return Material(
      type: MaterialType.transparency,
      child: Center(
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
                      borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
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
      ),
    );
  }
}

// ─── Achievement Unlock Sheet ──────────────────────────────────────────────

class AchievementUnlockSheet extends StatelessWidget {
  final AchievementModel achievement;
  const AchievementUnlockSheet({super.key, required this.achievement});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    // The tier's on-surface ink, not its fill — this color is used for the
    // sheet's border, caption and reward text, all of which sit on
    // `gp.surfaceHigh`. Reading the fill shade here (which is what the
    // inlined switch this replaced returned) put Silver's #B8C0C8 on a
    // white sheet at roughly 1.6:1. See TierPalette.
    final c = TierPalette.from(context, achievement.tier).ink;
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
                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
              ),
            ),
            const SizedBox(height: 28),
            VictoryBurstOnMount(
              colors: [c, GameColors.gold, Colors.white],
              child: AchievementMedal(
                tier: achievement.tier,
                icon: achievementIconFor(achievement.trigger),
                size: 88,
                state: MedalState.unlocked,
                loopShimmer: true,
                // No numeral here alone: the tier's full name is printed as
                // its own pill directly below this medal, so the stamped
                // "III" would just be the same fact twice.
                showNumeral: false,
                semanticLabel: medalSemanticLabel(
                  achievement: achievement,
                  state: MedalState.unlocked,
                  current: achievement.threshold,
                  isAr: isAr,
                ),
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
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.withOpacity(0.15),
                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
              ),
              child: Text(
                achievement.tier.localizedName(isAr).toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: c,
                    letterSpacing: isAr ? 0 : 1.5),
              ),
            ).animate(delay: 240.ms).fadeIn(),
            const SizedBox(height: 12),
            Text(
              achievement.localName(isAr),
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                  letterSpacing: -0.3),
              textAlign: TextAlign.center,
            ).animate(delay: 280.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 6),
            Text(
              achievement.localDescription(isAr),
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
                    label: '+${achievement.goldReward} ${s.gold}',
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
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
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
