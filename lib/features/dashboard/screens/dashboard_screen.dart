import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/game_theme.dart';
import '../../../features/achievements/models/achievement_model.dart';
import '../../../features/auth/notifiers/auth_notifier.dart';
import '../../../features/habits/catalog/islamic_habit_catalog.dart';
import '../../../features/habits/notifiers/custom_habits_notifier.dart';
import '../../../features/habits/widgets/add_habit_sheet.dart';
import '../../../features/challenges/widgets/weekly_challenge_card.dart';
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

      // First-load: route to the daily intention prompt before anything else.
      if (prev.isLoading && !next.isLoading && !next.intentionsSetToday) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            Navigator.pushNamed(context, '/intention');
          }
        });
        return;
      }

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
      if (next.didJustLevelUp) {
        HapticFeedback.heavyImpact();
        _showLevelUp(context, next.level);
      }
      if (next.newlyUnlocked.isNotEmpty && prev.newlyUnlocked.isEmpty) {
        _showAchievementUnlock(context, next.newlyUnlocked.first, ref);
      }
      if (next.milestoneCelebration != null && prev.milestoneCelebration == null) {
        final m = next.milestoneCelebration!;
        Future.delayed(const Duration(milliseconds: 350), () {
          if (context.mounted) _showMilestone(context, m, ref);
        });
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
                if (state.showComebackBonus)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _ComebackCard(state: state),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: const WeeklyChallengeCard()
                        .animate(delay: 80.ms)
                        .fadeIn(duration: 450.ms),
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

  void _showMilestone(BuildContext context, int milestone, WidgetRef ref) {
    HapticFeedback.heavyImpact();
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.85),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) =>
          _MilestoneCelebration(milestone: milestone, ref: ref),
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
              icon: Icons.stars_rounded,
              value: state.gold,
              label: 'GOLD',
              color: GameColors.gold,
            ),
          ]),
          if (state.streakFreezes > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.ac_unit_rounded,
                    size: 13, color: GameColors.xpBlue),
                const SizedBox(width: 6),
                Text(
                  '${state.streakFreezes} streak freeze${state.streakFreezes > 1 ? 's' : ''} ready to protect your streak',
                  style: const TextStyle(
                      fontSize: 11,
                      color: GameColors.xpBlue,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Comeback Card ("You're Back") ────────────────────────────────────────

class _ComebackCard extends ConsumerWidget {
  final DashboardState state;
  const _ComebackCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.email?.split('@').first ?? 'Warrior';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.xpBlue.withOpacity(0.35), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: GameColors.xpBlue.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wb_twilight_rounded,
                    color: GameColors.xpBlue, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome back, $name',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: gp.textPrimary,
                            letterSpacing: -0.2)),
                    const SizedBox(height: 2),
                    Text('A missed day doesn\'t erase your progress.',
                        style: TextStyle(fontSize: 12.5, color: gp.textSec)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: GameColors.xpBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.bolt_rounded, size: 14, color: GameColors.xpBlue),
                SizedBox(width: 6),
                Text('+50 XP comeback bonus when you continue',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: GameColors.xpBlue)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (state.streakFreezes > 0 && state.previousStreak > 0) ...[
            Text(
              'Use a streak freeze to restore your ${state.previousStreak}-day streak instead of starting over.',
              style: TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      ref.read(dashboardProvider.notifier).useStreakFreeze();
                    },
                    icon: const Icon(Icons.ac_unit_rounded, size: 16),
                    label: Text('Restore Streak (${state.streakFreezes} left)'),
                    style: FilledButton.styleFrom(
                        backgroundColor: GameColors.xpBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ref.read(dashboardProvider.notifier).acknowledgeComeback();
                },
                child: const Text('Start a fresh streak instead'),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  ref.read(dashboardProvider.notifier).acknowledgeComeback();
                },
                child: const Text('CONTINUE'),
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.08, curve: Curves.easeOut);
  }
}

// ─── Milestone Celebration ────────────────────────────────────────────────

class _MilestoneCelebration extends StatelessWidget {
  final int milestone;
  final WidgetRef ref;
  const _MilestoneCelebration({required this.milestone, required this.ref});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
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
                child: const Icon(Icons.local_fire_department_rounded,
                    size: 56, color: GameColors.streakOrange),
              )
                  .animate()
                  .scale(
                      begin: const Offset(0.3, 0.3),
                      curve: Curves.elasticOut,
                      duration: 800.ms)
                  .fadeIn(duration: 300.ms),
              const SizedBox(height: 28),
              const Text(
                'STREAK MILESTONE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: GameColors.streakOrange,
                  letterSpacing: 3,
                ),
              ).animate(delay: 250.ms).fadeIn(),
              const SizedBox(height: 10),
              Text(
                '$milestone Days',
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
                'You are now a $title.',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.85),
                ),
                textAlign: TextAlign.center,
              ).animate(delay: 380.ms).fadeIn(),
              const SizedBox(height: 8),
              Text(
                'Consistency builds character — keep showing up.',
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
                      const Icon(Icons.bolt_rounded, size: 16, color: GameColors.xpBlue),
                      const SizedBox(width: 6),
                      Text('+$bonus XP milestone bonus',
                          style: const TextStyle(
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
                    Navigator.of(context).pop();
                  },
                  child: const Text('KEEP GOING'),
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
