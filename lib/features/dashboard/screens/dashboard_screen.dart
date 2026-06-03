import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/game_theme.dart';
import '../../../features/auth/notifiers/auth_notifier.dart';
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
              ref
                  .read(customHabitsProvider)
                  .firstWhere((h) => h.id == entry.key,
                      orElse: () => IslamicHabitCatalog.templates.first);
          HapticFeedback.mediumImpact();
          _showDone(context, t.name, t.xpReward, t.goldReward);
        }
      }
      if (next.didJustLevelUp) {
        HapticFeedback.heavyImpact();
        _showLevelUp(context, next.level);
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
                  color: GameColors.gold,
                  strokeWidth: 2))
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
                          child: Row(
                            children: [
                              Icon(Icons.logout_rounded,
                                  size: 18, color: gp.textSec),
                              const SizedBox(width: 10),
                              Text('Sign Out',
                                  style: TextStyle(
                                      color: gp.textPrimary,
                                      fontWeight:
                                          FontWeight.w500)),
                            ],
                          ),
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
                    padding:
                        const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _StatsCard(state: state)
                        .animate()
                        .fadeIn(duration: 500.ms)
                        .slideY(
                            begin: -0.04, curve: Curves.easeOut),
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
                            letterSpacing: 2,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${habits.length} active',
                          style: TextStyle(
                            fontSize: 11,
                            color: gp.textTert,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16),
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
                          completions:
                              state.completions[t.id] ?? 0,
                          isDone: done,
                          onComplete: done
                              ? null
                              : () => ref
                                  .read(
                                      dashboardProvider.notifier)
                                  .completeHabit(
                                    habitId: t.id,
                                    xpReward: t.xpReward,
                                    goldReward: t.goldReward,
                                    frequencyTarget:
                                        t.frequencyTarget,
                                  ),
                        ),
                      )
                          .animate(delay: (i * 55).ms)
                          .fadeIn(duration: 400.ms)
                          .slideY(
                              begin: 0.12, curve: Curves.easeOut);
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

  void _showDone(
      BuildContext context, String name, int xp, int gold) {
    final gp = context.gp;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
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
          ],
        ),
        backgroundColor: gp.surfaceHigh,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(
              color: GameColors.gold, width: 0.5),
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
          side:
              const BorderSide(color: GameColors.gold, width: 1),
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
              letterSpacing: 1.5,
            ),
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
                      letterSpacing: -2,
                    ),
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
          Row(
            children: [
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
            ],
          ),
        ],
      ),
    );
  }
}
