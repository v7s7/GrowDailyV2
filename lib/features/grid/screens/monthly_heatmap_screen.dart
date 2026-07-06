import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../models/square_state.dart';
import '../notifiers/weekly_grid_notifier.dart' show startOfGridWeek;

/// A GitHub-style contribution heatmap of green squares colored across
/// months. Reads straight from [DashboardState.dailyGreenCounts] — a rollup
/// already loaded with the rest of the dashboard — so this screen opens
/// instantly regardless of how many years of history the account holds; no
/// extra reads, no per-day document fetches.
///
/// Free accounts see the last [_freeWeeksToShow] weeks (~3 months) — plenty
/// to see your recent pattern. Premium unlocks the full rolling year. The
/// underlying data is already loaded either way (see the class doc above),
/// so this is purely a display cap, not a data-access restriction.
class MonthlyHeatmapScreen extends ConsumerWidget {
  const MonthlyHeatmapScreen({super.key});

  static const int _freeWeeksToShow = 12;
  static const int _premiumWeeksToShow = 52;
  static const double _cell = 12;
  static const double _gap = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final dark = gp.dark;
    final isPremium = ref.watch(premiumProvider);
    final weeksToShow = isPremium ? _premiumWeeksToShow : _freeWeeksToShow;
    final counts = ref.watch(dashboardProvider).dailyGreenCounts;
    // A day's green count only means something next to how many habits the
    // user actually tracks — 2 greens is a perfect day at 2 habits but a
    // quiet one at 8. Color by percentage of today's habit list, not the
    // raw count, so a 100% day is always the deepest green regardless of
    // how many habits someone keeps.
    final totalHabits = ref.watch(habitListProvider).length;

    final currentWeekStart = startOfGridWeek(DateTime.now());
    final firstWeekStart = currentWeekStart
        .subtract(Duration(days: 7 * (weeksToShow - 1)));
    final weekStarts = List.generate(
      weeksToShow,
      (i) => firstWeekStart.add(Duration(days: 7 * i)),
    );

    var total = 0;
    var activeDays = 0;
    var best = 0;
    DateTime? bestDay;
    for (final week in weekStarts) {
      for (var d = 0; d < 7; d++) {
        final day = week.add(Duration(days: d));
        final count = counts[day.toDateKey()] ?? 0;
        if (count <= 0) continue;
        total += count;
        activeDays++;
        if (count > best) {
          best = count;
          bestDay = day;
        }
      }
    }

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        title: Text(s.heatmapTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.heatmapSubtitle,
                style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.4),
              ).animate().fadeIn(duration: 350.ms),
              const SizedBox(height: 16),
              Row(
                children: [
                  _StatTile(label: s.heatmapTotalGreen, value: '$total'),
                  const SizedBox(width: 10),
                  _StatTile(label: s.heatmapActiveDays, value: '$activeDays'),
                  const SizedBox(width: 10),
                  _StatTile(
                    label: s.heatmapBestDay,
                    value: bestDay == null
                        ? '—'
                        : '$best',
                  ),
                ],
              ).animate(delay: 60.ms).fadeIn(duration: 350.ms),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: gp.surface,
                  borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
                  border: Border.all(color: gp.border, width: 0.5),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: _ContributionGraph(
                    weekStarts: weekStarts,
                    counts: counts,
                    totalHabits: totalHabits,
                    dark: dark,
                    cell: _cell,
                    gap: _gap,
                    onTapDay: (day, count) => _showDayInfo(context, day, count),
                  ),
                ),
              ).animate(delay: 120.ms).fadeIn(duration: 400.ms),
              const SizedBox(height: 16),
              _HeatLegend(dark: dark),
              if (!isPremium) ...[
                const SizedBox(height: 18),
                _UpgradeForFullHistoryCard(
                  freeWeeks: _freeWeeksToShow,
                ).animate(delay: 160.ms).fadeIn(duration: 350.ms),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDayInfo(BuildContext context, DateTime day, int count) {
    HapticFeedback.selectionClick();
    final locale = Localizations.localeOf(context).languageCode;
    final label = DateFormat('EEEE, MMM d', locale).format(day);
    final s = S.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(count > 0 ? '$label — ${s.gridGreensToday(count)}' : label),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }
}

/// Buckets a day's green count by what fraction of the user's current habit
/// list it represents — 100% is always the deepest green, 80%+ the next
/// shade down, and so on — rather than an absolute count that would never
/// reach full green for someone tracking only 2-3 habits.
int heatLevel(int count, int totalHabits) {
  if (count <= 0) return 0;
  if (totalHabits <= 0) {
    // No habits currently tracked (e.g. all archived) — fall back to a
    // plain count scale so old green history still renders something.
    if (count <= 2) return 1;
    if (count <= 4) return 2;
    if (count <= 7) return 3;
    return 4;
  }
  final pct = count / totalHabits;
  if (pct >= 1.0) return 4;
  if (pct >= 0.8) return 3;
  if (pct >= 0.5) return 2;
  return 1;
}

Color heatColor(int level, bool dark) {
  if (level <= 0) return SquareState.none.fill(dark);
  const opacities = [0.0, 0.30, 0.50, 0.70, 0.92];
  return GameColors.emerald.withOpacity(opacities[level.clamp(1, 4)]);
}

// ─── Contribution graph ────────────────────────────────────────────────────

class _ContributionGraph extends StatelessWidget {
  final List<DateTime> weekStarts;
  final Map<String, int> counts;
  final int totalHabits;
  final bool dark;
  final double cell;
  final double gap;
  final void Function(DateTime day, int count) onTapDay;

  const _ContributionGraph({
    required this.weekStarts,
    required this.counts,
    required this.totalHabits,
    required this.dark,
    required this.cell,
    required this.gap,
    required this.onTapDay,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final colWidth = cell + gap;
    String? lastMonth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final week in weekStarts)
              SizedBox(
                width: colWidth,
                child: Builder(builder: (_) {
                  final label = DateFormat.MMM().format(week);
                  final show = label != lastMonth;
                  lastMonth = label;
                  return Text(
                    show ? label : '',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: gp.textTert,
                    ),
                  );
                }),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final week in weekStarts)
              Padding(
                padding: EdgeInsets.only(right: gap),
                child: Column(
                  children: [
                    for (var d = 0; d < 7; d++)
                      Padding(
                        padding: EdgeInsets.only(bottom: gap),
                        child: _HeatCell(
                          day: week.add(Duration(days: d)),
                          count: counts[
                                  week.add(Duration(days: d)).toDateKey()] ??
                              0,
                          totalHabits: totalHabits,
                          dark: dark,
                          size: cell,
                          onTap: onTapDay,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _HeatCell extends StatelessWidget {
  final DateTime day;
  final int count;
  final int totalHabits;
  final bool dark;
  final double size;
  final void Function(DateTime day, int count) onTap;

  const _HeatCell({
    required this.day,
    required this.count,
    required this.totalHabits,
    required this.dark,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isFuture = day.startOfDay.isAfter(DateTime.now().startOfDay);
    final level = heatLevel(count, totalHabits);
    return GestureDetector(
      onTap: isFuture ? null : () => onTap(day, count),
      child: Opacity(
        opacity: isFuture ? 0.25 : 1,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: heatColor(level, dark),
            borderRadius: BorderRadius.circular(3),
            border: day.isToday
                ? Border.all(color: GameColors.gold, width: 1)
                : null,
          ),
        ),
      ),
    );
  }
}

// ─── Legend ───────────────────────────────────────────────────────────────

class _HeatLegend extends StatelessWidget {
  final bool dark;
  const _HeatLegend({required this.dark});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(s.heatmapLess,
            style: TextStyle(fontSize: 11, color: gp.textTert)),
        const SizedBox(width: 6),
        for (var level = 0; level <= 4; level++)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: heatColor(level, dark),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        const SizedBox(width: 2),
        Text(s.heatmapMore,
            style: TextStyle(fontSize: 11, color: gp.textTert)),
      ],
    );
  }
}

// ─── Stat tile ─────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
                height: 1,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: gp.textTert,
                letterSpacing: 0.6,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Upgrade card (free tier only) ─────────────────────────────────────────

class _UpgradeForFullHistoryCard extends StatelessWidget {
  final int freeWeeks;
  const _UpgradeForFullHistoryCard({required this.freeWeeks});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.pushNamed(context, '/premium');
      },
      borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: GameColors.gold.withOpacity(gp.dark ? 0.10 : 0.08),
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: GameColors.gold.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: GameColors.gold.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_clock_rounded,
                  size: 20, color: GameColors.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.heatmapUpgradeTitle,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.heatmapUpgradeBody(freeWeeks),
                    style: TextStyle(
                        fontSize: 12, color: gp.textSec, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: gp.textTert),
          ],
        ),
      ),
    );
  }
}
