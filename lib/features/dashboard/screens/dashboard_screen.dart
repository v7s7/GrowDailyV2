import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../features/achievements/models/achievement_model.dart';
import '../../../features/auth/notifiers/auth_notifier.dart';
import '../../../features/focus/notifiers/focus_plan_notifier.dart';
import '../../../features/habits/catalog/habit_plans.dart';
import '../../../features/habits/catalog/islamic_habit_catalog.dart';
import '../../../features/habits/notifiers/custom_habits_notifier.dart';
import '../../../features/habits/widgets/add_habit_sheet.dart';
import '../../../features/habits/widgets/plan_picker_sheet.dart';
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
    final s = S.of(context);

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
      if (next.didUseStreakFreeze && !prev.didUseStreakFreeze) {
        HapticFeedback.mediumImpact();
        _showFreezeProtected(context, next.streakFreezes);
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
    final customHabits = ref.watch(customHabitsProvider);
    final customIds = customHabits.map((h) => h.id).toSet();
    final allDone = habits.isNotEmpty &&
        habits.every((t) => state.isCompleted(t.id, t.frequencyTarget));

    return Scaffold(
      backgroundColor: gp.bg,
      bottomNavigationBar: const GameNavBar(currentIndex: 0),
      body: state.isLoading
          ? Center(
              child: CircularProgressIndicator(
                  color: GameColors.gold, strokeWidth: 2))
          : CustomScrollView(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
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
                            Text(s.signOut,
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
                          s.todaysHabits,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: gp.textSec,
                              letterSpacing: 1.5),
                        ),
                        const Spacer(),
                        Text(
                          s.activeCount(habits.length),
                          style: TextStyle(
                              fontSize: 11,
                              color: gp.textTert,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
                if (allDone)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _AllDoneBanner(),
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
                        child: _SwipeableHabitRow(
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
                          onDelete: () {
                            if (customIds.contains(t.id)) {
                              ref
                                  .read(customHabitsProvider.notifier)
                                  .remove(t.id);
                            } else {
                              ref
                                  .read(activeCatalogProvider.notifier)
                                  .toggle(t.id);
                            }
                          },
                          onEdit: customIds.contains(t.id)
                              ? () => _showEditHabit(context, t)
                              : null,
                        ),
                      )
                          .animate(delay: (i * 55).ms)
                          .fadeIn(duration: 400.ms)
                          .slideY(begin: 0.12, curve: Curves.easeOut);
                    },
                  ),
                ),
                // Empty state when no habits
                if (habits.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyHabitsState(
                      onBrowsePlans: () => _showPlanPicker(context),
                      onAddCustom: () => _showAddHabit(context),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 110)),
              ],
            ),
      floatingActionButton: habits.isEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Plans button
                FloatingActionButton.small(
                  heroTag: 'plans',
                  onPressed: () => _showPlanPicker(context),
                  backgroundColor: gp.surfaceHigh,
                  foregroundColor: gp.textPrimary,
                  elevation: 0,
                  child: const Icon(Icons.auto_awesome_rounded,
                      size: 18, color: GameColors.gold),
                ).animate(delay: 600.ms).fadeIn().slideY(begin: 0.4),
                const SizedBox(height: 10),
                // Add habit button
                FloatingActionButton.extended(
                  heroTag: 'add',
                  onPressed: () => _showAddHabit(context),
                  backgroundColor: GameColors.gold,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(
                    s.addHabit,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0),
                  ),
                ).animate(delay: 700.ms).fadeIn().slideY(begin: 0.4),
              ],
            ),
    );
  }

  void _showFreezeProtected(BuildContext context, int remaining) {
    final gp = context.gp;
    final s = S.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.ac_unit_rounded, color: GameColors.xpBlue, size: 18),
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

  void _showAddHabit(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddHabitSheet(),
    );
  }

  void _showEditHabit(BuildContext context, IslamicHabitTemplate habit) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddHabitSheet(existing: habit),
    );
  }

  void _showPlanPicker(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => const PlanPickerSheet(),
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
    final s = S.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.arrow_upward_rounded,
                color: GameColors.gold, size: 18),
            const SizedBox(width: 8),
            Text('${s.levelUpMsg}  —  LVL $level',
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

// ─── Empty Habits State ───────────────────────────────────────────────────

class _EmptyHabitsState extends StatelessWidget {
  final VoidCallback onBrowsePlans;
  final VoidCallback onAddCustom;
  const _EmptyHabitsState(
      {required this.onBrowsePlans, required this.onAddCustom});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: GameColors.gold.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  size: 36, color: GameColors.gold),
            )
                .animate()
                .scale(curve: Curves.elasticOut, duration: 700.ms)
                .fadeIn(duration: 300.ms),
            const SizedBox(height: 20),
            Text(
              s.noHabitsYet,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 8),
            Text(
              s.noHabitsDesc,
              style: TextStyle(
                  fontSize: 14, color: gp.textSec, height: 1.4),
              textAlign: TextAlign.center,
            ).animate(delay: 200.ms).fadeIn(),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onBrowsePlans,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(s.browsePlans),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onAddCustom,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(s.addHabit),
            ).animate(delay: 380.ms).fadeIn(),
          ],
        ),
      ),
    );
  }
}

// ─── Today Intention Card ─────────────────────────────────────────────────

class _TodayIntentionCard extends ConsumerWidget {
  const _TodayIntentionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
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
                    hasPlan ? s.todaysIntention : s.pickTinyWin,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasPlan ? plan.topTask : s.pickOneGoal,
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
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final today = DateFormat('EEEE, MMMM d', locale).format(DateTime.now());
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
                  Text(s.level,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: gp.textSec,
                          letterSpacing: 1.5)),
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
                    '${state.cumulativeXp} ${s.totalXp}',
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
              label: s.streak,
              color: GameColors.streakOrange,
            ),
            const SizedBox(width: 10),
            StatChip(
              icon: Icons.ac_unit_rounded,
              value: state.streakFreezes,
              label: s.freeze,
              color: GameColors.xpBlue,
            ),
            const SizedBox(width: 10),
            StatChip(
              icon: Icons.stars_rounded,
              value: state.gold,
              label: s.gold,
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
    final s = S.of(context);
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
                    Text(s.welcomeBack(name),
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: gp.textPrimary,
                            letterSpacing: -0.2)),
                    const SizedBox(height: 2),
                    Text(s.comebackNoErase,
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
              children: [
                const Icon(Icons.bolt_rounded, size: 14, color: GameColors.xpBlue),
                const SizedBox(width: 6),
                Text(s.comebackBonusHint,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: GameColors.xpBlue)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (state.streakFreezes > 0 && state.previousStreak > 0) ...[
            Text(
              s.restoreStreakOffer(state.previousStreak),
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
                    label: Text(s.restoreStreakCta(state.streakFreezes)),
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
                child: Text(s.freshStreakInstead),
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
                child: Text(s.claimComeback),
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
              Text(
                s.streakMilestoneLabel,
                style: const TextStyle(
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
                      const Icon(Icons.bolt_rounded, size: 16, color: GameColors.xpBlue),
                      const SizedBox(width: 6),
                      Text(s.milestoneBonusXp(bonus),
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

// ─── All Done Banner ──────────────────────────────────────────────────────────

class _AllDoneBanner extends StatelessWidget {
  const _AllDoneBanner();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            GameColors.gold.withOpacity(0.14),
            GameColors.success.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.gold.withOpacity(0.35), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: GameColors.gold.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: GameColors.gold, size: 20),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(
                  begin: 0.88,
                  end: 1.0,
                  duration: 1100.ms,
                  curve: Curves.easeInOut),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.allDoneTitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: GameColors.gold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.allDoneSubtitle,
                  style: TextStyle(fontSize: 12, color: gp.textSec),
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms, delay: 150.ms)
        .slideY(begin: 0.12, curve: Curves.easeOut);
  }
}

// ─── Swipeable Habit Row ──────────────────────────────────────────────────────

class _SwipeableHabitRow extends StatefulWidget {
  final IslamicHabitTemplate template;
  final int completions;
  final bool isDone;
  final VoidCallback? onComplete;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const _SwipeableHabitRow({
    required this.template,
    required this.completions,
    required this.isDone,
    this.onComplete,
    this.onDelete,
    this.onEdit,
  });

  @override
  State<_SwipeableHabitRow> createState() => _SwipeableHabitRowState();
}

class _SwipeableHabitRowState extends State<_SwipeableHabitRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _xAnim;
  double _liveX = 0;
  bool _dragging = false;
  bool _triggered = false;

  static const double _kThresh = 80;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..addListener(() => setState(() {}));
    _xAnim = const AlwaysStoppedAnimation(0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double get _x => _dragging ? _liveX : _xAnim.value;

  void _onDragStart(DragStartDetails _) {
    if (widget.isDone || widget.onComplete == null) return;
    _ctrl.stop();
    setState(() {
      _dragging = true;
      _liveX = 0;
      _triggered = false;
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    setState(() {
      _liveX = (_liveX + d.delta.dx).clamp(0.0, _kThresh * 1.12);
    });
    if (_liveX >= _kThresh && !_triggered) {
      _triggered = true;
      HapticFeedback.mediumImpact();
    }
  }

  void _onDragEnd(DragEndDetails _) {
    if (!_dragging) return;
    final startX = _liveX;
    setState(() => _dragging = false);
    if (_triggered) widget.onComplete?.call();
    _triggered = false;
    _xAnim = Tween<double>(begin: startX, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    _ctrl.forward(from: 0);
  }

  void _showDeleteMenu(BuildContext context) {
    HapticFeedback.mediumImpact();
    final s = S.of(context);
    final gp = context.gp;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            12, 0, 12, 24 + MediaQuery.of(ctx).padding.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: gp.surfaceHigh,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Text(
                  widget.template.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: gp.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Divider(height: 1, color: gp.divider),
              if (widget.onEdit != null)
                ListTile(
                  leading: Icon(Icons.edit_outlined, color: gp.textSec),
                  title: Text(
                    s.editHabitAction,
                    style: TextStyle(
                        color: gp.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    HapticFeedback.selectionClick();
                    widget.onEdit?.call();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: GameColors.error),
                title: Text(
                  s.removeHabit,
                  style: const TextStyle(
                      color: GameColors.error, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  HapticFeedback.mediumImpact();
                  widget.onDelete?.call();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final x = _x;
    final progress = (x / _kThresh).clamp(0.0, 1.0);

    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onLongPress: widget.onDelete != null ? () => _showDeleteMenu(context) : null,
      child: Stack(
        children: [
          // Green reveal behind the card
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: GameColors.success.withOpacity(0.12 * progress),
                borderRadius:
                    BorderRadius.circular(GameSpacing.cardRadius),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 18),
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.5 + 0.5 * progress,
                  child: const Icon(Icons.check_rounded,
                      color: GameColors.success, size: 22),
                ),
              ),
            ),
          ),
          // The card slides right
          Transform.translate(
            offset: Offset(x, 0),
            child: HabitCard(
              template: widget.template,
              completions: widget.completions,
              isDone: widget.isDone,
              onComplete: widget.onComplete,
            ),
          ),
        ],
      ),
    );
  }
}
