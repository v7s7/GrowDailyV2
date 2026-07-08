import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/game_nav_bar.dart';
import '../../../shared/widgets/habit_limit_gate.dart';
import '../../../shared/widgets/victory_burst.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../dashboard/widgets/reaction_overlays.dart';
import '../../habits/catalog/habit_plans.dart';
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../habits/models/habit_model.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../../habits/widgets/add_habit_sheet.dart';
import '../../habits/widgets/plan_picker_sheet.dart';
import '../../night_review/notifiers/night_review_notifier.dart';
import '../models/square_state.dart';
import '../notifiers/weekly_grid_notifier.dart';

/// Opens the starter-plan picker. Shared by the empty state and the grid's
/// floating action button so there's exactly one code path for it.
void showPlanPickerSheet(BuildContext context) {
  HapticFeedback.lightImpact();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => const PlanPickerSheet(),
  );
}

/// Opens the add-habit sheet, gated by the account's habit limit. Shared by
/// the empty state and the grid's floating action button.
void showAddHabitSheet(BuildContext context, WidgetRef ref) {
  if (!canAddHabits(ref)) {
    showHabitLimitGate(context, ref);
    return;
  }
  HapticFeedback.lightImpact();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const AddHabitSheet(),
  );
}

/// Themed tint color for a habit row's category chip. The IconData half of
/// this tuple is legacy — actual rendering goes through [CategoryIcon],
/// which prefers the custom glyph art and only falls back to a Material
/// icon for categories without custom art. Kept here since callers still
/// destructure the color.
(IconData, Color) categoryVisual(HabitCategory category) => switch (category) {
      HabitCategory.faith || HabitCategory.quran || HabitCategory.athkar =>
        (Icons.menu_book_rounded, GameColors.emerald),
      HabitCategory.health || HabitCategory.fitness =>
        (Icons.fitness_center_rounded, GameColors.streakOrange),
      HabitCategory.learning => (Icons.school_rounded, GameColors.xpBlue),
      HabitCategory.focus || HabitCategory.fasting =>
        (Icons.center_focus_strong_rounded, GameColors.xpBlue),
      HabitCategory.money || HabitCategory.sadaqah =>
        (Icons.savings_rounded, GameColors.warning),
      HabitCategory.mind => (Icons.psychology_rounded, GameColors.rarityEpic),
      HabitCategory.social => (Icons.groups_rounded, GameColors.gold),
      HabitCategory.sleep => (Icons.bedtime_rounded, GameColors.rarityEpic),
      HabitCategory.custom => (Icons.star_rounded, GameColors.gold),
    };

/// The Weekly Victory Grid — the flagship "color your life" experience.
///
/// Rows are habits, columns are the seven days of the week (Sat → Fri).
/// Tapping a square cycles white → yellow → green → white; a long-press opens
/// the full palette plus a daily reflection note.
class GridScreen extends ConsumerWidget {
  const GridScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    registerDashboardReactions(context, ref, routeToIntentionOnFirstLoad: true);

    final gp = context.gp;
    final s = S.of(context);
    final habits = ref.watch(habitListProvider);
    final grid = ref.watch(weeklyGridProvider);

    return Scaffold(
      backgroundColor: gp.bg,
      bottomNavigationBar: const GameNavBar(currentIndex: 0),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: _GridHeader(state: grid)),
            if (habits.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _GridEmptyState(),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: _SummaryCard(habits: habits, state: grid)
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: -0.05, curve: Curves.easeOut),
                ),
              ),
              const SliverToBoxAdapter(child: _StreakAtRiskBanner()),
              const SliverToBoxAdapter(child: _NightReviewPromptCard()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  // Keyed on the visible week so navigating weeks slides the
                  // whole board in, rather than snapping cell colors.
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0.04, 0),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: grid.isLoading
                        ? const _GridSkeleton()
                        : KeyedSubtree(
                            key: ValueKey(grid.weekStart),
                            child: _GridTable(habits: habits, state: grid),
                          ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: const _Legend()
                      .animate()
                      .fadeIn(duration: 400.ms, delay: 140.ms),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: Text(
                    s.gridSlogan,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                      color: gp.textTert,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
      // Today is the primary place to add/browse habits (its FAB offers both
      // "Plans" and "Add Habit" at full size). Grid only needs a secondary,
      // smaller way back into "add a habit" for when the grid isn't empty —
      // the empty state's own "Browse Plans" button covers the zero-habit
      // case, so this single small icon FAB is deliberately the *lesser*
      // affordance, not a duplicate of Today's.
      floatingActionButton: habits.isEmpty
          ? null
          : FloatingActionButton.small(
              heroTag: 'grid-add',
              onPressed: () => showAddHabitSheet(context, ref),
              backgroundColor: gp.surfaceHigh,
              foregroundColor: gp.textPrimary,
              elevation: 0,
              tooltip: s.addHabit,
              // Not `const` — GameColors.gold is a mutable `static Color`
              // (theme-preset system), not a compile-time constant. See
              // BUILD_LESSONS.md #6.
              child: Icon(Icons.add_rounded,
                  size: 20, color: GameColors.gold),
            ).animate(delay: 500.ms).fadeIn().slideY(begin: 0.4),
    );
  }
}

// ─── Header (title + week navigation) ─────────────────────────────────────────

class _GridHeader extends ConsumerWidget {
  final WeeklyGridState state;
  const _GridHeader({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final notifier = ref.read(weeklyGridProvider.notifier);
    final start = state.weekStart;
    final end = start.add(const Duration(days: 6));
    final range = state.isCurrentWeek
        ? s.gridThisWeek
        : '${DateFormat('MMM d', locale).format(start)} – '
            '${DateFormat('MMM d', locale).format(end)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.gridTitle,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: gp.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.insights_rounded, color: gp.textSec),
                tooltip: s.heatmapTitle,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.pushNamed(context, '/heatmap');
                },
              ),
              IconButton(
                icon: Icon(Icons.nightlight_round, color: gp.textSec),
                tooltip: s.nightReviewTitle,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.pushNamed(context, '/night-review');
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _NavArrow(
                icon: Icons.chevron_left_rounded,
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.previousWeek();
                },
              ),
              Expanded(
                child: GestureDetector(
                  onTap: state.isCurrentWeek
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          notifier.goToCurrentWeek();
                        },
                  child: Column(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Text(
                          range,
                          key: ValueKey(range),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: gp.textPrimary,
                          ),
                        ),
                      ),
                      if (!state.isCurrentWeek)
                        Text(
                          s.gridThisWeek,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: GameColors.gold,
                            letterSpacing: 0.5,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _NavArrow(
                icon: Icons.chevron_right_rounded,
                enabled: state.canGoForward,
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.nextWeek();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  const _NavArrow(
      {required this.icon, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: Material(
        color: gp.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: gp.border, width: 0.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: gp.textSec, size: 24),
          ),
        ),
      ),
    );
  }
}

// ─── Summary card (green squares, points, completion) ─────────────────────────

class _SummaryCard extends StatelessWidget {
  final List<IslamicHabitTemplate> habits;
  final WeeklyGridState state;
  const _SummaryCard({required this.habits, required this.state});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final habitIds = habits.map((h) => h.id).toList();
    final greens = state.greenSquares(habitIds);
    final ratio = state.todayCompletionRatio(habitIds);

    // Only today's marks are reward-eligible. Past-day marks remain visual
    // history, but the summary must not present them as earned XP.
    final points = state.rewardEligiblePoints(habitIds);

    final greensToday = () {
      final today = DateTime.now();
      if (!state.days.any((d) => d.isSameDayAs(today))) return 0;
      final row = state.states[today.toDateKey()];
      if (row == null) return 0;
      return habitIds
          .where((id) => (row[id] ?? SquareState.none).isGreen)
          .length;
    }();
    final perfectDay = habits.isNotEmpty && greensToday >= habits.length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            GameColors.emerald.withOpacity(gp.dark ? 0.14 : 0.10),
            gp.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(
          color: GameColors.emerald.withOpacity(perfectDay ? 0.6 : 0.28),
          width: perfectDay ? 1.2 : 0.8,
        ),
      ),
      child: Row(
        children: [
          _RingStat(ratio: ratio),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    // Count up to the current total so each new green square
                    // visibly ticks the score.
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: greens.toDouble()),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) => Text(
                        '${v.round()}',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          color: GameColors.emerald,
                          height: 1,
                          letterSpacing: -1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        s.gridGreenSquares,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: gp.textSec,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    perfectDay
                        ? s.gridPerfectDay
                        : greensToday > 0
                            ? s.gridGreensToday(greensToday)
                            : s.gridTapHint,
                    key: ValueKey(
                      '$perfectDay-$greensToday-${(ratio * 100).round()}',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: perfectDay ? GameColors.emerald : gp.textTert,
                      fontWeight:
                          perfectDay ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _MiniStat(
                      icon: Icons.bolt_rounded,
                      value: '$points',
                      label: s.gridPoints,
                      color: GameColors.gold,
                    ),
                    const SizedBox(width: 20),
                    _MiniStat(
                      icon: Icons.percent_rounded,
                      value: '${(ratio * 100).round()}%',
                      label: s.gridComplete,
                      color: GameColors.xpBlue,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    )
        // A single celebratory sweep the moment today goes fully green.
        .animate(target: perfectDay ? 1 : 0)
        .shimmer(
          duration: 900.ms,
          color: GameColors.emerald.withOpacity(0.30),
        );
  }
}

class _RingStat extends StatelessWidget {
  final double ratio;
  const _RingStat({required this.ratio});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => CircularProgressIndicator(
                value: v,
                strokeWidth: 6,
                backgroundColor: gp.surfaceHL,
                valueColor:
                    const AlwaysStoppedAnimation(GameColors.emerald),
                strokeCap: StrokeCap.round,
              ),
            ),
          ),
          Icon(
            ratio >= 1.0
                ? Icons.emoji_events_rounded
                : Icons.grid_view_rounded,
            color: GameColors.emerald,
            size: 24,
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _MiniStat(
      {required this.icon,
      required this.value,
      required this.label,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: gp.textTert),
        ),
      ],
    );
  }
}

// ─── Streak-at-risk nudge ──────────────────────────────────────────────────

/// The retention loop's most important message: from 6pm, if the user has a
/// live streak and hasn't colored anything green today, warn them warmly —
/// one square keeps the streak alive. Disappears the moment they earn green.
class _StreakAtRiskBanner extends ConsumerWidget {
  const _StreakAtRiskBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(dashboardProvider);
    final grid = ref.watch(weeklyGridProvider);
    final habits = ref.watch(habitListProvider);

    final isEvening = DateTime.now().hour >= 18;
    if (!isEvening || dash.streak <= 0 || habits.isEmpty || grid.isLoading) {
      return const SizedBox.shrink();
    }
    final today = DateTime.now();
    final row = grid.states[today.toDateKey()];
    final hasGreenToday = row != null &&
        habits.any((h) => (row[h.id] ?? SquareState.none).isGreen);
    if (hasGreenToday || dash.gridActivityToday || dash.completions.isNotEmpty) {
      return const SizedBox.shrink();
    }

    final gp = context.gp;
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GameColors.streakOrange.withOpacity(gp.dark ? 0.10 : 0.08),
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border:
              Border.all(color: GameColors.streakOrange.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.local_fire_department_rounded,
                    color: GameColors.streakOrange, size: 26)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(
                  begin: 0.88,
                  end: 1.05,
                  duration: 900.ms,
                  curve: Curves.easeInOut,
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.streakAtRiskTitle(dash.streak),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: GameColors.streakOrange,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.streakAtRiskBody,
                    style: TextStyle(fontSize: 12, color: gp.textSec),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08);
  }
}

// ─── Night Review prompt ───────────────────────────────────────────────────

/// A gentle evening nudge toward Night Review — visible any time after 6pm
/// until tonight's check-in is saved. Dismissible via the Grid header's moon
/// icon at any hour; this card just makes the invitation hard to miss when
/// it matters most.
class _NightReviewPromptCard extends ConsumerWidget {
  const _NightReviewPromptCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = ref.watch(nightReviewProvider);
    final isEvening = DateTime.now().hour >= 18;
    if (review.isLoading || review.saved || !isEvening) {
      return const SizedBox.shrink();
    }
    final gp = context.gp;
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.pushNamed(context, '/night-review');
        },
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
                child: Icon(Icons.nightlight_round,
                    color: GameColors.xpBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.nightReviewPromptTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      s.nightReviewPromptDesc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: gp.textSec),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: GameColors.xpBlue),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08);
  }
}

// ─── The grid table itself ────────────────────────────────────────────────────

class _GridTable extends ConsumerWidget {
  final List<IslamicHabitTemplate> habits;
  final WeeklyGridState state;
  const _GridTable({required this.habits, required this.state});

  static const double _habitCol = 112;
  static const double _gap = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final avail = constraints.maxWidth;
          double cell = (avail - _habitCol - 7 * _gap) / 7;
          bool scroll = false;
          if (cell < 32) {
            cell = 32;
            scroll = true;
          } else {
            cell = cell.clamp(32, 54);
          }
          final table = _buildTable(context, ref, cell);
          if (!scroll) return table;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: table,
          );
        },
      ),
    );
  }

  Widget _buildTable(BuildContext context, WidgetRef ref, double cell) {
    final days = state.days;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerRow(context, days, cell),
        const SizedBox(height: 8),
        // Rows cascade in on entrance; effects play once per screen visit
        // (rebuilds on square taps reuse the same elements, so no replay).
        for (var i = 0; i < habits.length; i++) ...[
          _habitRow(context, ref, habits[i], days, cell)
              .animate(delay: (i * 45).ms)
              .fadeIn(duration: 320.ms)
              .slideX(begin: 0.04, curve: Curves.easeOut),
          if (i != habits.length - 1) const SizedBox(height: _gap),
        ],
      ],
    );
  }

  Widget _headerRow(BuildContext context, List<DateTime> days, double cell) {
    final gp = context.gp;
    final locale = Localizations.localeOf(context).languageCode;
    return Row(
      children: [
        SizedBox(width: _habitCol),
        for (final day in days)
          Padding(
            padding: const EdgeInsets.only(left: _gap),
            child: SizedBox(
              width: cell,
              child: Column(
                children: [
                  Text(
                    DateFormat('EEE', locale).format(day),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: day.isToday ? GameColors.gold : gp.textTert,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: day.isToday
                        ? BoxDecoration(
                            color: GameColors.gold.withOpacity(0.16),
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            day.isToday ? FontWeight.w800 : FontWeight.w600,
                        color: day.isToday ? GameColors.gold : gp.textSec,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _habitRow(BuildContext context, WidgetRef ref,
      IslamicHabitTemplate habit, List<DateTime> days, double cell) {
    final gp = context.gp;
    final today = DateTime.now();
    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () => _showHabitActionsSheet(context, ref, habit),
          child: SizedBox(
            width: _habitCol,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Builder(builder: (_) {
                    final (_, color) = categoryVisual(habit.category);
                    return Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: CategoryIcon(
                        category: habit.category,
                        size: 13,
                        color: color,
                      ),
                    );
                  }),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      habit.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: gp.textPrimary,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        for (final day in days)
          Padding(
            padding: const EdgeInsets.only(left: _gap),
            child: _SquareCell(
              size: cell,
              day: day,
              isToday: day.isToday,
              isFuture: day.startOfDay.isAfter(today.startOfDay),
              square: state.squareFor(habit.id, day),
              hasNote: state.noteFor(habit.id, day).isNotEmpty,
              onTap: () => _handleSquareTap(ref, habit, day),
              onLongPress: () {
                HapticFeedback.mediumImpact();
                _openEditor(context, ref, habit, day);
              },
            ),
          ),
      ],
    );
  }

  /// Handles a plain tap on a habit's square.
  ///
  /// Today's square reaching "complete" for a real single-tap habit is
  /// special-cased to route through the exact same canonical reward path
  /// Today's own "Done" button uses (`DashboardNotifier.completeHabit`),
  /// instead of Grid's own flat per-square XP — one reward, ever, for a
  /// given habit-day, regardless of which screen it's completed from.
  /// Everything else (other days, other colors, multi-tap habits) falls
  /// through to the original flat-rate tap-cycle, unchanged.
  Future<void> _handleSquareTap(
      WidgetRef ref, IslamicHabitTemplate habit, DateTime day) async {
    final current = state.squareFor(habit.id, day);
    final next = current.next;
    final isSyncable = day.isToday && habit.frequencyTarget == 1;

    if (isSyncable && next == SquareState.complete) {
      final alreadyDoneToday = ref
          .read(dashboardProvider)
          .isCompleted(habit.id, habit.frequencyTarget);
      HapticFeedback.mediumImpact();
      if (alreadyDoneToday) {
        // Already rewarded (e.g. completed from Today and the mirror
        // hasn't caught up) — just repair the visual state, no reward call.
        ref.read(weeklyGridProvider.notifier).markCompleteFromHabit(habit.id, day);
      } else {
        // Canonical reward first. Only mirror the square if it actually
        // succeeded — a failed or no-op completeHabit call must never
        // leave the Grid square green while Today/rewards/streak didn't
        // update.
        final justCompleted =
            await ref.read(dashboardProvider.notifier).completeHabit(
                  habitId: habit.id,
                  xpReward: habit.xpReward,
                  goldReward: habit.goldReward,
                  frequencyTarget: habit.frequencyTarget,
                  category: habit.category.name,
                  habitName: habit.name,
                );
        if (justCompleted) {
          ref
              .read(weeklyGridProvider.notifier)
              .markCompleteFromHabit(habit.id, day);
        }
      }
      return;
    }

    if (isSyncable &&
        current == SquareState.complete &&
        ref.read(dashboardProvider).isCompleted(habit.id, habit.frequencyTarget)) {
      // Today's completed, synced squares should still behave like every
      // other editable square: tapping green cycles it back to empty, and
      // long-press still opens the explicit palette. Because this green
      // state was rewarded through DashboardNotifier.completeHabit, undo
      // that canonical completion first so Today un-checks the task and
      // XP/gold/green counters are refunded before the visual square is
      // cleared.
      HapticFeedback.selectionClick();
      await ref.read(dashboardProvider.notifier).uncompleteHabit(
            habitId: habit.id,
            xpReward: habit.xpReward,
            goldReward: habit.goldReward,
            category: habit.category.name,
          );
      ref
          .read(weeklyGridProvider.notifier)
          .setSquareStateOnly(habit.id, day, next);
      return;
    }

    // A square turning green is the app's core reward moment — it gets a
    // heavier thump than the intermediate colors.
    if (next.isGreen) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    ref.read(weeklyGridProvider.notifier).cycleSquare(habit.id, day);
  }

  void _openEditor(BuildContext context, WidgetRef ref,
      IslamicHabitTemplate habit, DateTime day) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CellEditorSheet(habit: habit, day: day),
    );
  }

  /// Long-press on a habit's name/icon opens edit/remove for that habit —
  /// Grid previously had no way to manage habits at all (add-only, via the
  /// FAB), even though Today's habit list has supported this for a while.
  /// Reuses the exact same notifiers Today's own menu uses, just adds the
  /// missing entry point here.
  void _showHabitActionsSheet(
      BuildContext context, WidgetRef ref, IslamicHabitTemplate habit) {
    HapticFeedback.mediumImpact();
    final s = S.of(context);
    final isCustom =
        ref.read(customHabitsProvider).any((h) => h.id == habit.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final gp = ctx.gp;
        return Padding(
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
                    habit.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: gp.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Divider(height: 1, color: gp.divider),
                // Preset/catalog habits are shared immutable templates —
                // only custom habits (created via AddHabitSheet) can be
                // edited, matching Today's own onEdit gating exactly.
                if (isCustom)
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
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => AddHabitSheet(existing: habit),
                      );
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
                    // Custom habits are deleted outright; preset habits are
                    // deactivated (reversible via Plans/the catalog) rather
                    // than destroyed, matching Today's own onDelete exactly.
                    if (isCustom) {
                      ref.read(customHabitsProvider.notifier).remove(habit.id);
                    } else {
                      ref
                          .read(activeCatalogProvider.notifier)
                          .toggle(habit.id);
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SquareCell extends StatelessWidget {
  final double size;
  final DateTime day;
  final bool isToday;
  final bool isFuture;
  final SquareState square;
  final bool hasNote;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SquareCell({
    required this.size,
    required this.day,
    required this.isToday,
    required this.isFuture,
    required this.square,
    required this.hasNote,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final dark = context.gp.dark;
    // Keying the pulse on the square state replays it on every color change:
    // marked cells get a satisfying pop, clearing back to white stays quiet.
    Widget cell = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: square.fill(dark),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isToday
              ? GameColors.gold.withOpacity(0.9)
              : square.border(dark),
          width: isToday ? 1.4 : 0.8,
        ),
      ),
      child: Stack(
        children: [
          if (square.icon != null)
            Center(
              child: Icon(
                square.icon,
                size: size * 0.5,
                color: square.accent,
              ),
            ),
          if (hasNote)
            Positioned(
              right: 3,
              bottom: 3,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: square.isMarked
                      ? square.accent
                      : context.gp.textTert,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
    if (square.isGreen) {
      // Green is the reward moment: elastic pop + a quick light sweep.
      cell = cell
          .animate(key: ValueKey(square))
          .scale(
            begin: const Offset(0.7, 0.7),
            end: const Offset(1, 1),
            duration: 320.ms,
            curve: Curves.elasticOut,
          )
          .shimmer(
            delay: 80.ms,
            duration: 450.ms,
            color: Colors.white.withOpacity(0.55),
          );
    } else if (square.isMarked) {
      cell = cell
          .animate(key: ValueKey(square))
          .scale(
            begin: const Offset(0.82, 0.82),
            end: const Offset(1, 1),
            duration: 220.ms,
            curve: Curves.easeOutBack,
          );
    }
    return GestureDetector(
      onTap: isFuture
          ? null
          : () {
              // Confetti fires from the cell itself the instant the tap
              // will turn it green — the market-standard completion moment.
              if (square.next.isGreen) {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null && box.attached) {
                  showVictoryBurst(
                    context,
                    box.localToGlobal(box.size.center(Offset.zero)),
                  );
                }
              }
              onTap();
            },
      onLongPress: isFuture ? null : onLongPress,
      child: Opacity(
        opacity: isFuture ? 0.35 : 1,
        child: cell,
      ),
    );
  }
}

// ─── Long-press cell editor (palette + reflection note) ───────────────────────

class _CellEditorSheet extends ConsumerStatefulWidget {
  final IslamicHabitTemplate habit;
  final DateTime day;
  const _CellEditorSheet({required this.habit, required this.day});

  @override
  ConsumerState<_CellEditorSheet> createState() => _CellEditorSheetState();
}

class _CellEditorSheetState extends ConsumerState<_CellEditorSheet> {
  late final TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    final note = ref
        .read(weeklyGridProvider)
        .noteFor(widget.habit.id, widget.day);
    _noteCtrl = TextEditingController(text: note);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final locale = Localizations.localeOf(context).languageCode;
    final current =
        ref.watch(weeklyGridProvider).squareFor(widget.habit.id, widget.day);
    // Whether this square is a synced completion (rewarded via the
    // canonical completeHabit path) — shown with a note above the palette
    // instead of hiding it, since picking a different color here is a
    // deliberate "I completed this by mistake" correction (see
    // _handlePaletteTap), not an accidental undo. Pre-existing green
    // squares from before this sync existed aren't caught by this check
    // (never recorded in `completions`) and behave via the plain
    // flat-rate palette path below, unaffected.
    final isLocked = widget.day.isToday &&
        widget.habit.frequencyTarget == 1 &&
        current == SquareState.complete &&
        ref
            .watch(dashboardProvider)
            .isCompleted(widget.habit.id, widget.habit.frequencyTarget);
    final palette = [
      SquareState.complete,
      SquareState.partial,
      SquareState.bonus,
      SquareState.failed,
      SquareState.skipped,
      SquareState.none,
    ];

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Builder(builder: (_) {
                  final (_, color) = categoryVisual(widget.habit.category);
                  return Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: CategoryIcon(
                      category: widget.habit.category,
                      size: 18,
                      color: color,
                    ),
                  );
                }),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.habit.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: gp.textPrimary,
                        ),
                      ),
                      Text(
                        DateFormat('EEEE, MMM d', locale).format(widget.day),
                        style: TextStyle(fontSize: 12, color: gp.textSec),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (isLocked) ...[
              Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: gp.textTert, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.gridSquareDoneFromToday,
                      style: TextStyle(fontSize: 12, color: gp.textSec),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            if (!widget.day.isToday) ...[
              Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: gp.textTert, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.gridPastDayHint,
                      style: TextStyle(fontSize: 12, color: gp.textSec),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            Text(
              s.gridEditSquare.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: gp.textTert,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < palette.length; i++)
                  _PaletteSwatch(
                    state: palette[i],
                    selected: palette[i] == current,
                    label: isAr ? palette[i].labelAr : palette[i].label,
                    onTap: () => _handlePaletteTap(isLocked, palette[i]),
                  )
                      .animate(delay: (i * 35).ms)
                      .fadeIn(duration: 220.ms)
                      .scale(
                        begin: const Offset(0.8, 0.8),
                        curve: Curves.easeOutBack,
                      ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              s.gridNoteLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              maxLines: 3,
              minLines: 2,
              textInputAction: TextInputAction.newline,
              style: TextStyle(fontSize: 14, color: gp.textPrimary),
              decoration: InputDecoration(hintText: s.gridNoteHint),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ref.read(weeklyGridProvider.notifier).setNote(
                        widget.habit.id,
                        widget.day,
                        _noteCtrl.text,
                      );
                  Navigator.pop(context);
                },
                child: Text(s.gridSave),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Handles tapping a palette swatch for [picked].
  ///
  /// - If the square is currently a synced, reward-locked completion
  ///   (`isLocked`) and [picked] isn't `complete`, this is a correction:
  ///   reverse the canonical reward first (`uncompleteHabit`), then
  ///   update the visual state only.
  /// - If the square isn't done yet and [picked] is `complete` for a
  ///   real, single-tap, today's habit, this is the same canonical
  ///   completion tapping the square or Today's button would do — reward
  ///   first, then mirror the visual state only if the reward actually
  ///   landed, so a failed/no-op reward never leaves the square green.
  /// - Everything else falls through to the original flat-rate
  ///   `setSquare` path, unchanged.
  Future<void> _handlePaletteTap(bool isLocked, SquareState picked) async {
    HapticFeedback.selectionClick();
    final habit = widget.habit;
    final day = widget.day;

    if (isLocked && picked != SquareState.complete) {
      ref.read(dashboardProvider.notifier).uncompleteHabit(
            habitId: habit.id,
            xpReward: habit.xpReward,
            goldReward: habit.goldReward,
            category: habit.category.name,
          );
      ref
          .read(weeklyGridProvider.notifier)
          .setSquareStateOnly(habit.id, day, picked);
      return;
    }

    final isSyncable = day.isToday && habit.frequencyTarget == 1;
    final alreadyDoneToday = ref
        .read(dashboardProvider)
        .isCompleted(habit.id, habit.frequencyTarget);
    if (isSyncable && picked == SquareState.complete && !alreadyDoneToday) {
      final justCompleted =
          await ref.read(dashboardProvider.notifier).completeHabit(
                habitId: habit.id,
                xpReward: habit.xpReward,
                goldReward: habit.goldReward,
                frequencyTarget: habit.frequencyTarget,
                category: habit.category.name,
                habitName: habit.name,
              );
      if (justCompleted) {
        ref
            .read(weeklyGridProvider.notifier)
            .setSquareStateOnly(habit.id, day, SquareState.complete);
      }
      return;
    }

    ref.read(weeklyGridProvider.notifier).setSquare(habit.id, day, picked);
  }
}

class _PaletteSwatch extends StatelessWidget {
  final SquareState state;
  final bool selected;
  final String label;
  final VoidCallback onTap;
  const _PaletteSwatch({
    required this.state,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final dark = gp.dark;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: state.fill(dark),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? state.accent : state.border(dark),
                width: selected ? 2 : 0.8,
              ),
            ),
            child: Icon(
              state.icon ?? Icons.circle_outlined,
              size: 20,
              color: state == SquareState.none ? gp.textTert : state.accent,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: selected ? state.accent : gp.textSec,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Legend ───────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final dark = gp.dark;
    // Only the three states a plain tap actually cycles through — the
    // "advanced" colors (bonus/failed/skipped) are already labeled in the
    // long-press editor's own palette, so repeating all six here just
    // forced this onto a second line for no real benefit.
    final items = [SquareState.none, SquareState.partial, SquareState.complete];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final st in items)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: st.fill(dark),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: st.border(dark), width: 0.8),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.isAr ? st.labelAr : st.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: gp.textSec,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            s.gridRewardHint,
            style: TextStyle(fontSize: 10.5, color: gp.textTert, height: 1.3),
          ),
        ],
      ),
    );
  }
}

// ─── Loading skeleton ─────────────────────────────────────────────────────────

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: GameColors.emerald),
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _GridEmptyState extends ConsumerWidget {
  const _GridEmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                color: GameColors.emerald.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.grid_view_rounded,
                  size: 36, color: GameColors.emerald),
            )
                .animate()
                .scale(curve: Curves.elasticOut, duration: 700.ms)
                .fadeIn(duration: 300.ms),
            const SizedBox(height: 20),
            Text(
              s.gridEmptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 8),
            Text(
              s.gridEmptyDesc,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: gp.textSec, height: 1.4),
            ).animate(delay: 220.ms).fadeIn(),
            const SizedBox(height: 28),
            SizedBox(
              width: 260,
              child: FilledButton.icon(
                onPressed: () => showPlanPickerSheet(context),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(s.browsePlans),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => showAddHabitSheet(context, ref),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(s.addHabit),
            ).animate(delay: 380.ms).fadeIn(),
          ],
        ),
      ),
    );
  }
}
