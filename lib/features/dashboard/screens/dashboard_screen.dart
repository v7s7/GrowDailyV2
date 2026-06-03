import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/game_theme.dart';
import '../../../core/utils/xp_calculator.dart';
import '../../../features/achievements/models/achievement_model.dart';
import '../../../features/auth/notifiers/auth_notifier.dart';
import '../../../features/focus/notifiers/focus_plan_notifier.dart';
import '../../../features/habits/catalog/islamic_habit_catalog.dart';
import '../../../features/habits/notifiers/custom_habits_notifier.dart';
import '../../../features/habits/widgets/add_habit_sheet.dart';
import '../../../shared/widgets/game_nav_bar.dart';
import '../../../shared/widgets/habit_card.dart';
import '../../../shared/widgets/stat_chip.dart';
import '../../../shared/widgets/xp_bar.dart';
import '../notifiers/dashboard_notifier.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;

    ref.listen<DashboardState>(dashboardProvider, (prev, next) {
      if (prev == null) return;
      for (final entry in next.completions.entries) {
        if ((prev.completions[entry.key] ?? 0) < entry.value) {
          final t = IslamicHabitCatalog.findById(entry.key) ??
              ref.read(customHabitsProvider).firstWhere(
                    (h) => h.id == entry.key,
                    orElse: () => IslamicHabitCatalog.templates.first,
                  );
          HapticFeedback.mediumImpact();
          _showDone(context, t.name, t.xpReward, t.goldReward);
        }
      }
      if (next.didUseStreakFreeze && !prev.didUseStreakFreeze) {
        HapticFeedback.mediumImpact();
        _showFreezeProtected(context, next.streakFreezes);
      }
      if (next.showRecoveryPrompt && !prev.showRecoveryPrompt) {
        HapticFeedback.mediumImpact();
        _showComeback(context, ref);
      }
      if (next.streakMilestone != null &&
          next.streakMilestone != prev.streakMilestone) {
        HapticFeedback.heavyImpact();
        _showStreakMilestone(context, next.streakMilestone!);
      }
      if (next.didJustLevelUp) {
        HapticFeedback.heavyImpact();
        _showLevelUp(context, next.level);
      }
      if (next.newlyUnlocked.isNotEmpty && prev.newlyUnlocked.isEmpty) {
        _showAchievementUnlock(
            context, next.newlyUnlocked.first, ref);
      }
    });

    final state = ref.watch(dashboardProvider);
    final habits = ref.watch(habitListProvider);

    return Scaffold(
      backgroundColor: gp.bg,
      bottomNavigationBar: const GameNavBar(currentIndex: 0),
      body: state.isLoading
          ? Center(
              child: CircularProgressIndicator(
                  color: GameColors.gold, strokeWidth: 2))
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: gp.bg,
                  surfaceTintColor: Colors.transparent,
                  scrolledUnderElevation: 0,
                  title: Text(
                    'GrowDaily',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  actions: [
                    PopupMenuButton<String>(
                      icon: Icon(Icons.person_rounded,
                          color: gp.textSec, size: 22),
                      color: gp.surfaceHigh,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'signout',
                          child: Row(children: [
                            Icon(Icons.logout_rounded,
                                size: 18, color: gp.textSec),
                            const SizedBox(width: 10),
                            Text('Sign Out',
                                style: TextStyle(
                                    color: gp.textPrimary,
                                    fontWeight: FontWeight.w500)),
                          ]),
                        ),
                      ],
                      onSelected: (v) async {
                        if (v == 'signout') {
                          await ref
                              .read(authNotifierProvider.notifier)
                              .signOut();
                          if (context.mounted) {
                            Navigator.pushNamedAndRemoveUntil(
                                context, '/', (_) => false);
                          }
                        }
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _StatsCard(state: state)
                        .animate()
                        .fadeIn(duration: 500.ms)
                        .slideY(begin: -0.04, curve: Curves.easeOut),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: const _TodayIntentionCard()
                        .animate(delay: 120.ms)
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.08),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 28, 16, 12),
                    child: Row(
                      children: [
                        Text(
                          "TODAY'S HABITS",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: gp.textSec,
                              letterSpacing: 2),
                        ),
                        const Spacer(),
                        Text(
                          '${habits.length} active',
                          style: TextStyle(
                              fontSize: 11,
                              color: gp.textTert,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: habits.length,
                    itemBuilder: (context, i) {
                      final t = habits[i];
                      final done =
                          state.isCompleted(t.id, t.frequencyTarget);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: HabitCard(
                          template: t,
                          completions: state.completions[t.id] ?? 0,
                          isDone: done,
                          onComplete: done
                              ? null
                              : () => ref
                                  .read(dashboardProvider.notifier)
                                  .completeHabit(
                                    habitId: t.id,
                                    xpReward: t.xpReward,
                                    goldReward: t.goldReward,
                                    frequencyTarget: t.frequencyTarget,
                                  ),
                        ),
                      )
                          .animate(delay: (i * 55).ms)
                          .fadeIn(duration: 400.ms)
                          .slideY(begin: 0.12, curve: Curves.easeOut);
                    },
                  ),
                ),
                const SliverToBoxAdapter(
                    child: SizedBox(height: 110)),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddHabit(context),
        backgroundColor: GameColors.gold,
        foregroundColor: Colors.black,
        elevation: 0,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text(
          'ADD HABIT',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2),
        ),
      ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.4),
    );
  }

  void _showFreezeProtected(BuildContext context, int remaining) {
    final gp = context.gp;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.ac_unit_rounded, color: GameColors.xpBlue, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Streak Freeze protected you. $remaining left.',
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

  void _showComeback(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ComebackSheet(
        onClaim: () {
          ref.read(dashboardProvider.notifier).claimComebackBonus();
          Navigator.pop(context);
        },
        onDismiss: () {
          ref.read(dashboardProvider.notifier).dismissRecoveryPrompt();
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showStreakMilestone(BuildContext context, int streak) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StreakMilestoneSheet(streak: streak),
    );
  }

  void _showAddHabit(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddHabitSheet(),
    );
  }

  void _showAchievementUnlock(
      BuildContext context, AchievementModel a, WidgetRef ref) {
    ref.read(dashboardProvider.notifier).acknowledgeAchievements();
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 250), () {
      if (context.mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _AchievementUnlockSheet(achievement: a),
        );
      }
    });
  }

  void _showDone(
      BuildContext context, String name, int xp, int gold) {
    final gp = context.gp;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded,
              color: GameColors.gold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: gp.textPrimary)),
                Text('+$xp XP  ·  +$gold Gold',
                    style: const TextStyle(
                        fontSize: 11,
                        color: GameColors.gold,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ]),
        backgroundColor: gp.surfaceHigh,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: GameColors.gold, width: 0.5),
        ),
      ),
    );
  }

  void _showLevelUp(BuildContext context, int level) {
    final gp = context.gp;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.arrow_upward_rounded,
                color: GameColors.gold, size: 18),
            const SizedBox(width: 8),
            Text('LEVEL UP  —  LVL $level',
                style: const TextStyle(
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
          side: const BorderSide(color: GameColors.gold, width: 1),
        ),
      ),
    );
  }
}

// ─── Compassionate Comeback / Streak Milestones ───────────────────────────

class _ComebackSheet extends StatelessWidget {
  final VoidCallback onClaim;
  final VoidCallback onDismiss;
  const _ComebackSheet({required this.onClaim, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: GameColors.success.withOpacity(0.35)),
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
            const SizedBox(height: 26),
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: GameColors.success.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_rounded,
                  size: 34, color: GameColors.success),
            ).animate().scale(curve: Curves.elasticOut, duration: 650.ms),
            const SizedBox(height: 18),
            Text(
              "YOU\'RE BACK",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: GameColors.success,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No guilt. Just restart.',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: gp.textPrimary,
                letterSpacing: -0.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Missing a day is normal. Take a comeback bonus and complete one tiny habit today.',
              style: TextStyle(fontSize: 14, color: gp.textSec, height: 1.35),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onClaim,
              icon: const Icon(Icons.bolt_rounded, size: 18),
              label: const Text('Claim +50 XP comeback'),
            ),
            TextButton(
              onPressed: onDismiss,
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreakMilestoneSheet extends StatelessWidget {
  final int streak;
  const _StreakMilestoneSheet({required this.streak});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final bonus = XpCalculator.streakMilestoneBonus(streak);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: GameColors.streakOrange.withOpacity(0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_fire_department_rounded,
                size: 72, color: GameColors.streakOrange),
            const SizedBox(height: 14),
            Text(
              '$streak-DAY WARRIOR',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: GameColors.streakOrange,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your consistency is becoming identity.',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: gp.textPrimary,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              bonus > 0 ? '+$bonus bonus XP awarded' : 'Milestone reached',
              style: const TextStyle(
                fontSize: 13,
                color: GameColors.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep growing'),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.12);
  }
}

// ─── Today Intention Card ─────────────────────────────────────────────────

class _TodayIntentionCard extends ConsumerWidget {
  const _TodayIntentionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final plan = ref.watch(focusPlanProvider).plan;
    final hasPlan = plan.topTask.trim().isNotEmpty;
    return InkWell(
      onTap: () => Navigator.pushReplacementNamed(context, '/focus'),
      borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: GameColors.xpBlue.withOpacity(0.22)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: GameColors.xpBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.flag_rounded, color: GameColors.xpBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasPlan ? "Today's intention" : 'Pick one tiny win',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasPlan
                        ? plan.topTask
                        : 'Choose one goal for your deen, work, or health.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: gp.textSec),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: GameColors.xpBlue),
          ],
        ),
      ),
    );
  }
}

// ─── Stats Card ───────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final DashboardState state;
  const _StatsCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final today = DateFormat('EEEE, MMMM d').format(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            today.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: gp.textTert,
                letterSpacing: 1.5),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LEVEL',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: gp.textSec,
                          letterSpacing: 2)),
                  Text(
                    '${state.level}',
                    style: const TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w900,
                        color: GameColors.gold,
                        height: 1,
                        letterSpacing: -2),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${state.currentLevelXp} / ${state.xpToNext} XP',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: gp.textSec),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${state.cumulativeXp} TOTAL XP',
                    style: TextStyle(
                        fontSize: 10,
                        color: gp.textTert,
                        letterSpacing: 0.5),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          XpBar(progress: state.levelProgress),
          const SizedBox(height: 18),
          Container(height: 0.5, color: gp.border),
          const SizedBox(height: 16),
          Row(children: [
            StatChip(
              icon: Icons.local_fire_department_rounded,
              value: state.streak,
              label: 'STREAK',
              color: GameColors.streakOrange,
            ),
            const SizedBox(width: 10),
            StatChip(
              icon: Icons.ac_unit_rounded,
              value: state.streakFreezes,
              label: 'FREEZE',
              color: GameColors.xpBlue,
            ),
            const SizedBox(width: 10),
            StatChip(
              icon: Icons.stars_rounded,
              value: state.gold,
              label: 'GOLD',
              color: GameColors.gold,
            ),
          ]),
        ],
      ),
    );
  }
}

// ─── Achievement Unlock Sheet ──────────────────────────────────────────────

class _AchievementUnlockSheet extends StatelessWidget {
  final AchievementModel achievement;
  const _AchievementUnlockSheet({required this.achievement});

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
            Container(
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
            const SizedBox(height: 18),
            Text(
              'ACHIEVEMENT UNLOCKED',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: c,
                  letterSpacing: 2),
            ).animate(delay: 200.ms).fadeIn(),
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
              child: FilledButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                },
                child: const Text('CLAIM REWARD'),
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
