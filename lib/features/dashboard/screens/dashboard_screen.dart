import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../features/auth/notifiers/auth_notifier.dart';
import '../../../features/grid/notifiers/weekly_grid_notifier.dart';
import '../../../features/habits/catalog/habit_plans.dart';
import '../../../features/habits/catalog/islamic_habit_catalog.dart';
import '../../../features/habits/notifiers/custom_habits_notifier.dart';
import '../../../features/habits/widgets/add_habit_hub_sheet.dart';
import '../../../features/habits/widgets/add_habit_sheet.dart';
import '../../../features/quick_wins/widgets/quick_wins_card.dart';
import '../../../shared/widgets/game_nav_bar.dart';
import '../../../shared/widgets/habit_card.dart';
import '../../../shared/widgets/victory_burst.dart';
import '../notifiers/dashboard_notifier.dart';
import '../widgets/reaction_overlays.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);

    registerDashboardReactions(context, ref);
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
    });

    final state = ref.watch(dashboardProvider);
    final today = DateTime.now();
    final habits = ref.watch(habitListProvider).where((h) => h.isScheduledFor(today)).toList();
    final customHabits = ref.watch(customHabitsProvider);
    final customIds = customHabits.map((h) => h.id).toSet();
    final allDone = habits.isNotEmpty &&
        habits.every((t) => state.isCompleted(t.id, t.frequencyTarget));

    return Scaffold(
      backgroundColor: gp.bg,
      bottomNavigationBar: const GameNavBar(currentIndex: 1),
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
                    child: const QuickWinsCard()
                        .animate(delay: 80.ms)
                        .fadeIn(duration: 400.ms),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                          onComplete:
                              done ? null : () => _completeHabit(ref, t),
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
                      onBrowsePlans: () =>
                          showAddHabitHub(context, ref, initialTab: HubTab.plans),
                      onAddCustom: () =>
                          showAddHabitHub(context, ref, initialTab: HubTab.quick),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 110)),
              ],
            ),
      // One "+" entry point into the Add Habit Hub (Quick Add / Plans /
      // Custom tabs) — previously this was two separate FABs (a small
      // "Plans" button plus this one), which made a first-time user choose
      // between two buttons before seeing what either did.
      floatingActionButton: habits.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: 'add',
              onPressed: () =>
                  showAddHabitHub(context, ref, initialTab: HubTab.quick),
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
    );
  }

  /// Completes a habit from Today, then — if that just finished a
  /// single-tap habit — mirrors today's Grid square to green. The mirror
  /// is visual/state only (`markCompleteFromHabit`), never a second
  /// reward: `completeHabit` already granted the one canonical reward for
  /// this habit-day. Multi-tap habits report `false` here and are left
  /// exactly as they behave today (see `completeHabit`'s doc comment).
  Future<void> _completeHabit(WidgetRef ref, IslamicHabitTemplate t) async {
    final justFinishedSingleTap =
        await ref.read(dashboardProvider.notifier).completeHabit(
              habitId: t.id,
              xpReward: t.xpReward,
              goldReward: t.goldReward,
              frequencyTarget: t.frequencyTarget,
              category: t.category.name,
              habitName: t.name,
            );
    if (justFinishedSingleTap) {
      ref
          .read(weeklyGridProvider.notifier)
          .markCompleteFromHabit(t.id, DateTime.now());
    }
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

  void _showDone(
      BuildContext context, String name, int xp, int gold) {
    final gp = context.gp;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(Icons.check_circle_rounded,
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
                    style: TextStyle(
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
          side: BorderSide(color: GameColors.gold, width: 0.5),
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
            ClipRRect(
              borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
              child: Container(
                width: 180,
                height: 180,
                color: const Color(0xFFFEFAF0),
                child: Image.asset(
                  'assets/images/empty_state_no_habits.png',
                  fit: BoxFit.cover,
                ),
              ),
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
                child: Icon(Icons.wb_twilight_rounded,
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
                Icon(Icons.bolt_rounded, size: 14, color: GameColors.xpBlue),
                const SizedBox(width: 6),
                Text(s.comebackBonusHint,
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
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 52,
              height: 52,
              color: const Color(0xFFFEFAF0),
              child: Image.asset(
                'assets/images/empty_state_all_done.png',
                fit: BoxFit.cover,
              ),
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(
                  begin: 0.92,
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
                  style: TextStyle(
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

  @override
  void didUpdateWidget(_SwipeableHabitRow old) {
    super.didUpdateWidget(old);
    // Fires for either completion path (tap the button inside HabitCard,
    // or swipe the row) since both land here as the same isDone flip —
    // reuses the app's existing "reward moment" language (the same burst
    // Grid fires on a square turning green) instead of building a second
    // celebration effect just for Today.
    //
    // didUpdateWidget runs mid-build, and showVictoryBurst inserts into
    // the root Overlay (setState on an unrelated ancestor) — deferring to
    // a post-frame callback is required, not optional: doing this inline
    // throws "setState() or markNeedsBuild() called during build."
    if (!old.isDone && widget.isDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && box.attached) {
          showVictoryBurst(
            context,
            box.localToGlobal(box.size.center(Offset.zero)),
          );
        }
      });
    }
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
