import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../grid/screens/monthly_heatmap_screen.dart'
    show MonthlyHeatmapScreen, heatColor, heatLevel;
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../models/milestone_event.dart';
import '../notifiers/milestone_notifier.dart';

/// A year-at-a-glance view of the user's whole history on GrowDaily — the
/// zoomed-out counterpart to [MonthlyHeatmapScreen]'s month-by-month,
/// day-tappable detail. Deliberately doesn't duplicate that screen's job:
/// day squares here are display-only (a compact density map, not another
/// place to open a day's full breakdown — see the "Open full Heatmap" row
/// below for that), and the one thing this view adds that the heatmap
/// can't — a whole year in one glance, plus that year's milestone tally
/// sitting right under it — is exactly the gap between "browse recent
/// months in detail" and "see my whole life on this app at once."
///
/// Reuses [heatColor]/[heatLevel] from monthly_heatmap_screen.dart directly
/// (same color scale, same percent-of-scheduled-habits logic) rather than
/// redefining a second color scheme, reads the same
/// [DashboardState.dailyGreenCounts] rollup (no new data/reads), and tallies
/// [MilestoneType] counts from the same [milestoneEventsProvider] Journey
/// Page reads — this screen adds no detection or storage of its own, only a
/// different lens on data that already exists.
///
/// Same free/Premium split as the heatmap: free shows the current year
/// only; Premium unlocks every year back to account creation.
class LifeTimelineScreen extends ConsumerWidget {
  const LifeTimelineScreen({super.key});

  // Same safety ceiling as MonthlyHeatmapScreen's _maxLifetimeMonths (240 =
  // 20 years): a corrupt/hand-edited dailyGreenCounts key with a bogus
  // ancient date must never make this screen try to build hundreds of years
  // of day-square widgets in one go — this ListView isn't .builder, so
  // every _YearSection below is constructed eagerly, not lazily on scroll.
  // 20 years of real usage stays comfortably inside this.
  static const int _maxLifetimeYears = 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final dark = gp.dark;
    final isPremium = ref.watch(premiumProvider);
    final dashState = ref.watch(dashboardProvider);
    final counts = dashState.dailyGreenCounts;
    final habits = ref.watch(allHabitsEverProvider);
    final milestones = ref.watch(milestoneEventsProvider).valueOrNull ?? const [];

    final today = DateTime.now().effectiveDay;
    final earliestYear = _earliestYear(counts, dashState.accountCreatedAt, today.year);
    // max(earliestYear, today.year - _maxLifetimeYears + 1) — written as an
    // explicit comparison rather than int.clamp(), whose declared return
    // type is num (not int) even when called on an int with int bounds, so
    // it would need an extra .toInt() to safely assign here.
    final capYear = today.year - _maxLifetimeYears + 1;
    final oldestYearToShow = earliestYear > capYear ? earliestYear : capYear;
    final years = isPremium
        ? [for (var y = today.year; y >= oldestYearToShow; y--) y]
        : [today.year];

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(s.lifeTimelineTitle,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary)),
      ),
      // ListView.builder, not a plain ListView(children:[...]): with the
      // 20-year cap above, a long-time Premium account can still have up to
      // 20 _YearSections, each drawing up to ~366 day squares — eagerly
      // building every one of those (~7000+ leaf widgets) on every rebuild
      // regardless of how many years are actually scrolled into view was a
      // real first-paint/rebuild cost. Lazily building only the header,
      // whichever years are on screen, and the footer keeps this cheap
      // regardless of account age.
      body: ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: 1 + years.length + (isPremium ? 1 : 2),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                s.lifeTimelineSubtitle,
                style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.4),
              ),
            );
          }
          final yearIndex = index - 1;
          if (yearIndex < years.length) {
            final year = years[yearIndex];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _YearSection(
                year: year,
                counts: counts,
                habits: habits,
                milestonesThisYear:
                    milestones.where((e) => e.occurredAt.year == year).toList(),
                today: today,
                dark: dark,
              ),
            );
          }
          final footerIndex = yearIndex - years.length;
          if (footerIndex == 0) {
            return Container(
              margin: const EdgeInsets.only(top: 4, bottom: 16),
              child: InkWell(
                borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MonthlyHeatmapScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: gp.surface,
                    borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
                    border: Border.all(color: gp.border, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_view_month_rounded,
                          size: 18, color: gp.textSec),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.lifeTimelineOpenHeatmap,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: gp.textPrimary),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 18, color: gp.textTert),
                    ],
                  ),
                ),
              ),
            );
          }
          // Only reachable when !isPremium (itemCount only reserves this
          // second footer slot in that case).
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: GameColors.gold.withOpacity(gp.dark ? 0.10 : 0.08),
              borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
              border: Border.all(color: GameColors.gold.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_clock_rounded, size: 20, color: GameColors.gold),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.lifeTimelineUpgradeBody,
                    style: TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.4),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Earliest year worth offering as a Premium section — the account's own
  /// creation year if known, else the earliest year with any recorded green
  /// square, else just this year (a brand-new account with nothing yet).
  static int _earliestYear(
    Map<String, int> counts,
    DateTime? accountCreatedAt,
    int currentYear,
  ) {
    if (accountCreatedAt != null) return accountCreatedAt.year;
    var earliest = currentYear;
    for (final entry in counts.entries) {
      if (entry.value <= 0) continue;
      final parsed = DateTime.tryParse(entry.key);
      if (parsed != null && parsed.year < earliest) earliest = parsed.year;
    }
    return earliest;
  }
}

class _YearSection extends StatelessWidget {
  final int year;
  final Map<String, int> counts;
  final List<IslamicHabitTemplate> habits;
  final List<MilestoneEvent> milestonesThisYear;
  final DateTime today;
  final bool dark;

  const _YearSection({
    required this.year,
    required this.counts,
    required this.habits,
    required this.milestonesThisYear,
    required this.today,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isCurrentYear = year == today.year;
    final lastDay = isCurrentYear
        ? today
        : DateTime(year, 12, 31);
    var yearTotal = 0;

    final cells = <Widget>[];
    for (var d = DateTime(year, 1, 1); !d.isAfter(lastDay); d = d.add(const Duration(days: 1))) {
      final count = counts[d.toDateKey()] ?? 0;
      yearTotal += count;
      final scheduled = habits.where((h) => h.isScheduledFor(d)).length;
      cells.add(_DaySquare(
        color: heatColor(heatLevel(count, scheduled), dark),
        isToday: d.isRealToday,
      ));
    }

    // Tally per MilestoneType so a busy year still reads as a handful of
    // compact badges ("Level Up x4") instead of one chip per event.
    final tally = tallyMilestonesByType(milestonesThisYear);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$year',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: gp.textPrimary),
              ),
              const Spacer(),
              if (yearTotal > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: GameColors.emerald.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                  ),
                  child: Text(
                    s.lifeTimelineYearTotal(yearTotal),
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, color: GameColors.emerald),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 3, runSpacing: 3, children: cells),
          if (tally.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in tally.entries)
                  _MilestoneTallyChip(type: entry.key, count: entry.value),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DaySquare extends StatelessWidget {
  final Color color;
  final bool isToday;
  const _DaySquare({required this.color, required this.isToday});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        border: isToday ? Border.all(color: GameColors.gold, width: 1) : null,
      ),
    );
  }
}

class _MilestoneTallyChip extends StatelessWidget {
  final MilestoneType type;
  final int count;
  const _MilestoneTallyChip({required this.type, required this.count});

  @override
  Widget build(BuildContext context) {
    final isAr = S.of(context).isAr;
    final color = type.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(type.icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            '${type.localizedName(isAr)} ×$count',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
