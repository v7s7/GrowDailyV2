import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../models/square_state.dart';
import '../notifiers/weekly_grid_notifier.dart';

/// The week's numbers, computed purely from [DashboardState.dailyGreenCounts]
/// so the card costs zero reads and is trivially unit-testable — see
/// test/features/grid/weekly_recap_test.dart.
class WeeklyRecapData {
  final int thisWeekTotal;
  final int lastWeekTotal;

  /// The strongest day of the current week, or null when nothing was
  /// colored at all. Ties resolve to the earliest such day, so the result
  /// is deterministic.
  final DateTime? bestDay;

  const WeeklyRecapData({
    required this.thisWeekTotal,
    required this.lastWeekTotal,
    required this.bestDay,
  });

  int get delta => thisWeekTotal - lastWeekTotal;
}

WeeklyRecapData computeWeeklyRecap({
  required Map<String, int> dailyGreenCounts,
  required DateTime weekStart,
}) {
  var thisTotal = 0;
  var lastTotal = 0;
  DateTime? bestDay;
  var best = 0;
  for (var i = 0; i < 7; i++) {
    final day = weekStart.add(Duration(days: i));
    final count = dailyGreenCounts[day.toDateKey()] ?? 0;
    thisTotal += count;
    if (count > best) {
      best = count;
      bestDay = day;
    }
    final prev = weekStart.subtract(Duration(days: 7 - i));
    lastTotal += dailyGreenCounts[prev.toDateKey()] ?? 0;
  }
  return WeeklyRecapData(
    thisWeekTotal: thisTotal,
    lastWeekTotal: lastTotal,
    bestDay: bestDay,
  );
}

/// Totals for the last [weeks] grid weeks, oldest first, ending with the
/// week that starts at [currentWeekStart] — the Premium trend bars' data.
/// Pure; see test/features/grid/weekly_recap_test.dart.
List<int> weeklyTotals({
  required Map<String, int> dailyGreenCounts,
  required DateTime currentWeekStart,
  int weeks = 4,
}) {
  return [
    for (var w = weeks - 1; w >= 0; w--)
      () {
        final start = currentWeekStart.subtract(Duration(days: 7 * w));
        var total = 0;
        for (var i = 0; i < 7; i++) {
          total += dailyGreenCounts[
                  start.add(Duration(days: i)).toDateKey()] ??
              0;
        }
        return total;
      }(),
  ];
}

/// The Friday "حصاد الأسبوع" card on the Grid — the grid week runs Sat→Fri,
/// so its last day doubles as the natural reflection moment (and the Gulf
/// weekend). Renders nothing at all on any other day, or when there's
/// nothing to recap yet, so it costs the layout nothing 6 days out of 7.
///
/// Everything on it comes from state that's already in memory
/// (dailyGreenCounts + the loaded current week's squares): total greens vs
/// last week with a delta chip, the week's best day, the habit that got
/// missed the most (only when it actually needs the attention), and one
/// calm line of encouragement picked by how the week compares.
class WeeklyRecapCard extends ConsumerWidget {
  const WeeklyRecapCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now().effectiveDay;
    if (today.weekday != DateTime.friday) return const SizedBox.shrink();

    // allHabitsEverProvider: the "most missed" scan below walks the whole
    // visible week day by day, so a habit archived partway through it
    // should still count for the days before it was archived, not vanish
    // from the tally the instant it's gone from the active list.
    final habits = ref.watch(allHabitsEverProvider);
    if (habits.isEmpty) return const SizedBox.shrink();

    final counts = ref.watch(dashboardProvider).dailyGreenCounts;
    final weekStart = startOfGridWeek(today);
    final recap = computeWeeklyRecap(
      dailyGreenCounts: counts,
      weekStart: weekStart,
    );
    // Two silent weeks in a row = nothing to say; a recap of zeros would
    // only rub it in. The regular empty-state/nudge surfaces handle that.
    if (recap.thisWeekTotal == 0 && recap.lastWeekTotal == 0) {
      return const SizedBox.shrink();
    }

    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;

    // The habit most missed this week — from the already-loaded visible
    // week, and only when the grid is actually showing the current week
    // (browsing a past week mustn't misattribute its squares to "this
    // week"). Skipped squares don't count as misses: a deliberate skip is
    // a decision, not a slip. Shown only at 2+ misses — one miss is life.
    final grid = ref.watch(weeklyGridProvider);
    String? mostMissedName;
    if (grid.isCurrentWeek && !grid.isLoading) {
      var worst = 1; // require >= 2, so start the bar above 1
      for (final h in habits) {
        var misses = 0;
        for (final day in grid.days) {
          if (!h.isScheduledFor(day)) continue;
          if (day.startOfDay.isAfter(today)) continue;
          final sq = grid.squareFor(h.id, day);
          if (!sq.isGreen && sq != SquareState.skipped) misses++;
        }
        if (misses > worst) {
          worst = misses;
          mostMissedName = h.localName(s.isAr);
        }
      }
    }

    final delta = recap.delta;
    final encouragement = recap.lastWeekTotal == 0
        ? s.weeklyRecapFirst
        : delta > 0
            ? s.weeklyRecapUp
            : delta < 0
                ? s.weeklyRecapDown
                : s.weeklyRecapSame;
    final deltaColor = delta > 0
        ? GameColors.emerald
        : delta < 0
            ? GameColors.warning
            : gp.textTert;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: GameColors.gold.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: GameColors.gold.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.insights_rounded,
                      size: 16, color: GameColors.gold),
                ),
                const SizedBox(width: 10),
                Text(
                  s.weeklyRecapTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _RecapStat(
                  value: '${recap.thisWeekTotal}',
                  label: s.weeklyRecapThisWeek,
                  trailing: delta == 0
                      ? null
                      : Text(
                          delta > 0 ? '+$delta' : '$delta',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: deltaColor,
                          ),
                        ),
                ),
                _RecapDivider(),
                _RecapStat(
                  value: '${recap.lastWeekTotal}',
                  label: s.weeklyRecapLastWeek,
                ),
                _RecapDivider(),
                _RecapStat(
                  value: recap.bestDay == null
                      ? '—'
                      : DateFormat('EEEE', locale).format(recap.bestDay!),
                  label: s.heatmapBestDay,
                  small: true,
                ),
              ],
            ),
            if (mostMissedName != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.favorite_border_rounded,
                      size: 13, color: gp.textTert),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.weeklyRecapNeedsLove(mostMissedName),
                      style: TextStyle(fontSize: 12, color: gp.textSec),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(
              encouragement,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: gp.textTert,
                height: 1.35,
              ),
            ),
            // ── Premium depth: per-habit week rows + 4-week trend ─────
            // The free card above stays complete on its own (it drives
            // retention, so it's deliberately not crippled); Premium adds
            // the receipts underneath. Free users see one quiet teaser
            // line instead — an offer, not a hole.
            if (ref.watch(premiumProvider)) ...[
              if (grid.isCurrentWeek && !grid.isLoading) ...[
                const SizedBox(height: 12),
                Container(height: 0.5, color: gp.border),
                const SizedBox(height: 10),
                Text(
                  s.weeklyRecapPerHabit,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: gp.textSec,
                  ),
                ),
                const SizedBox(height: 8),
                for (final h in habits)
                  // Skip a habit that's both gone (archived, not the
                  // current active one) AND had nothing real to show this
                  // week — exactly the shape a mistake/test habit that got
                  // hard-deleted-should-have-been-but-was-still-lingering
                  // leaves behind: zero completions, ever, and now
                  // archived. A currently-active habit always shows, even
                  // at 0/7 — that's a real miss worth seeing, not clutter.
                  // A now-archived habit with at least one real green day
                  // this week also still shows — it was genuinely used,
                  // not a mistake, so its receipt stays. See
                  // _weekDoneCount's own doc comment.
                  if (h.archivedAt == null ||
                      _weekDoneCount(h, grid, today) > 0)
                    _HabitWeekRow(
                      habit: h,
                      grid: grid,
                      today: today,
                      isAr: s.isAr,
                    ),
              ],
              const SizedBox(height: 10),
              Text(
                s.weeklyRecapTrend,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: gp.textSec,
                ),
              ),
              const SizedBox(height: 6),
              _TrendBars(
                totals: weeklyTotals(
                  dailyGreenCounts: counts,
                  currentWeekStart: weekStart,
                ),
                currentWeekStart: weekStart,
                thisWeekLabel: s.weeklyRecapThisWeek,
              ),
            ] else ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.pushNamed(context, '/premium');
                },
                child: Row(
                  children: [
                    Icon(Icons.lock_rounded,
                        size: 13, color: GameColors.gold),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        s.weeklyRecapPremiumTeaser,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: GameColors.gold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ).animate().fadeIn(duration: 400.ms),
    );
  }
}

/// How many of [habit]'s scheduled, non-future days in [grid] are actually
/// green — its real completions this week. Used to decide whether an
/// archived habit is worth a row at all (see the filter above) — the exact
/// same scheduled-and-not-future-and-green condition [_HabitWeekRow] uses
/// for its own n/scheduled count below, just computed standalone here so
/// the filter can run *before* that row ever gets built.
int _weekDoneCount(
  IslamicHabitTemplate habit,
  WeeklyGridState grid,
  DateTime today,
) {
  var done = 0;
  for (final day in grid.days) {
    if (day.startOfDay.isAfter(today)) continue;
    if (!habit.isScheduledFor(day)) continue;
    if (grid.squareFor(habit.id, day).isGreen) done++;
  }
  return done;
}

/// One habit's week at a glance inside the Premium recap: name, seven day
/// dots in grid-week order (green done, red slipped, gray skipped, hollow
/// missed, dim future/unscheduled), and its n/scheduled count.
class _HabitWeekRow extends StatelessWidget {
  final IslamicHabitTemplate habit;
  final WeeklyGridState grid;
  final DateTime today;
  final bool isAr;
  const _HabitWeekRow({
    required this.habit,
    required this.grid,
    required this.today,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    var done = 0;
    var scheduled = 0;
    final dots = <Widget>[];
    for (final day in grid.days) {
      final isFuture = day.startOfDay.isAfter(today);
      final isScheduled = habit.isScheduledFor(day);
      final sq = grid.squareFor(habit.id, day);
      if (isScheduled && !isFuture) {
        scheduled++;
        if (sq.isGreen) done++;
      }
      final Color color;
      if (!isScheduled || isFuture) {
        color = gp.border.withOpacity(0.45);
      } else if (sq.isGreen) {
        color = GameColors.emerald;
      } else if (sq == SquareState.failed) {
        color = GameColors.error;
      } else if (sq == SquareState.skipped) {
        color = gp.textTert;
      } else if (sq == SquareState.partial) {
        color = GameColors.warning;
      } else {
        color = Colors.transparent;
      }
      dots.add(Container(
        width: 7,
        height: 7,
        margin: const EdgeInsetsDirectional.only(end: 3),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: color == Colors.transparent
              ? Border.all(color: gp.border, width: 1)
              : null,
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              habit.localName(isAr),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: gp.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ...dots,
          const SizedBox(width: 6),
          Text(
            '$done/$scheduled',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: gp.textTert,
            ),
          ),
        ],
      ),
    );
  }
}

/// Four bars, oldest to newest, current week in gold — enough to see
/// direction without pretending to be a chart screen. Each bar sits on a
/// dim full-height track so a quiet week still reads as "a bar with
/// little in it" rather than a stray sliver floating with nothing to
/// anchor it against, and every column is [Expanded] so the whole row
/// fills exactly the width it's given instead of drifting to one side
/// with fixed-width bars. The current week gets both its usual gold color
/// and an explicit "This week" tag underneath — the color alone was easy
/// to miss.
class _TrendBars extends StatelessWidget {
  final List<int> totals;
  final DateTime currentWeekStart;
  final String thisWeekLabel;
  const _TrendBars({
    required this.totals,
    required this.currentWeekStart,
    required this.thisWeekLabel,
  });

  static const _trackHeight = 52.0;
  static const _barWidth = 28.0;
  static const _minBarHeight = 6.0;

  @override
  Widget build(BuildContext context) {
    final max = totals.fold<int>(0, (m, v) => v > m ? v : m);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < totals.length; i++)
          Expanded(
            child: _TrendBar(
              value: totals[i],
              max: max,
              isCurrent: i == totals.length - 1,
              // weeks-old count from the end: last bar (current) is 0
              // weeks back, the one before it is 1 week back, etc.
              weekStart: currentWeekStart
                  .subtract(Duration(days: 7 * (totals.length - 1 - i))),
              thisWeekLabel: thisWeekLabel,
              trackHeight: _trackHeight,
              barWidth: _barWidth,
              minBarHeight: _minBarHeight,
            ),
          ),
      ],
    );
  }
}

class _TrendBar extends StatelessWidget {
  final int value;
  final int max;
  final bool isCurrent;
  final DateTime weekStart;
  final String thisWeekLabel;
  final double trackHeight;
  final double barWidth;
  final double minBarHeight;
  const _TrendBar({
    required this.value,
    required this.max,
    required this.isCurrent,
    required this.weekStart,
    required this.thisWeekLabel,
    required this.trackHeight,
    required this.barWidth,
    required this.minBarHeight,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final barColor = isCurrent ? GameColors.gold : GameColors.emerald;
    final barHeight = max == 0
        ? minBarHeight
        : minBarHeight + (trackHeight - minBarHeight) * (value / max);
    final weekEnd = weekStart.add(const Duration(days: 6));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: trackHeight,
          child: Center(
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  width: barWidth,
                  height: trackHeight,
                  decoration: BoxDecoration(
                    color: gp.border.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                Container(
                  width: barWidth,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: isCurrent ? barColor : barColor.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: GameColors.gold.withOpacity(0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 12,
            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w700,
            color: isCurrent ? GameColors.gold : gp.textPrimary,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          isCurrent ? thisWeekLabel : '${weekStart.day}-${weekEnd.day}',
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            color: isCurrent ? GameColors.gold : gp.textTert,
          ),
        ),
      ],
    );
  }
}

class _RecapStat extends StatelessWidget {
  final String value;
  final String label;
  final Widget? trailing;
  final bool small;
  const _RecapStat({
    required this.value,
    required this.label,
    this.trailing,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: small ? 13 : 18,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9.5, color: gp.textTert),
          ),
        ],
      ),
    );
  }
}

class _RecapDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.5,
      height: 30,
      color: context.gp.border,
      margin: const EdgeInsets.symmetric(horizontal: 6),
    );
  }
}
