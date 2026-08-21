import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../grid/screens/monthly_heatmap_screen.dart'
    show MonthlyHeatmapScreen, derivedDayCounts, heatColor, heatLevel;
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../../../shared/widgets/history_demo_gate.dart';
import '../../../shared/widgets/milestone_tally_chip.dart';
import '../notifiers/habit_history_notifier.dart';
import '../models/milestone_event.dart';
import '../notifiers/milestone_notifier.dart';
import '../reports/report_period.dart' show historyFloorFor;

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
    // Every habit that still exists, archived included: archiving keeps its
    // history (the reports fold it under المؤرشفة rather than dropping it),
    // deleting does not. Same rule the Heatmap now follows.
    final habits = ref.watch(allHabitsEverProvider);
    // THE MIRROR, not the rollup.
    //
    // This screen used to read DashboardState.dailyGreenCounts directly, and
    // that rollup still carries days belonging to habits the user has since
    // DELETED. The Monthly Heatmap stopped trusting it for exactly that
    // reason (see [derivedDayCounts]' doc comment: orphaned ids were painting
    // glowing perfect days), and the reports hub reads the same mirror. Left
    // alone, this screen printed 127 squares for a year the Heatmap and the
    // yearly report both read as 83, on the same account, on the same day.
    //
    // Falls back to the rollup only while the mirror is still loading, so the
    // grid does not flash empty. Same trade the Heatmap makes.
    final countedIds = {for (final h in habits) h.id};
    final counts = ref.watch(habitYearHistoryProvider).maybeWhen(
          data: (mirror) => derivedDayCounts(mirror, countedIds),
          orElse: () => dashState.dailyGreenCounts,
        );
    final milestones = ref.watch(milestoneEventsProvider).valueOrNull ?? const [];

    final today = DateTime.now().effectiveDay;

    // Lifetime figures for the header card. Scalars, not browsable history:
    // the free tier already sees its lifetime totals on the Profile hero, so
    // withholding them here would gate a number the app gives away two taps
    // to the left. What IS gated is the day-by-day colour below, which is
    // the thing you could actually read a past out of.
    var lifetimeSquares = 0;
    var lifetimeActiveDays = 0;
    var lifetimeBestDay = 0;
    for (final value in counts.values) {
      if (value <= 0) continue;
      lifetimeSquares += value;
      lifetimeActiveDays++;
      if (value > lifetimeBestDay) lifetimeBestDay = value;
    }

    final earliestYear = _earliestYear(counts, dashState.accountCreatedAt, today.year);
    // max(earliestYear, today.year - _maxLifetimeYears + 1) — written as an
    // explicit comparison rather than int.clamp(), whose declared return
    // type is num (not int) even when called on an int with int bounds, so
    // it would need an extra .toInt() to safely assign here.
    final capYear = today.year - _maxLifetimeYears + 1;
    final oldestYearToShow = earliestYear > capYear ? earliestYear : capYear;
    // Every year, for everyone.
    //
    // The roadmap decided this screen is free ("no premiumProvider check
    // anywhere in this screen"), and the lifetime numbers it exists to show
    // - total completions, longest streak, the year you started - are not
    // history you browse, they are one sentence about your account. Hiding
    // whole years behind the paywall contradicted that, while the year it
    // DID show was drawn unmuted back to 1 January, which was looser than
    // the Monthly Heatmap for the very same days.
    //
    // So the gate moved off the year list and onto the days themselves: the
    // shape of every year is visible, and the day-level heat behind the free
    // window is muted, exactly as the reports hub's year strips already do.
    final years = [for (var y = today.year; y >= oldestYearToShow; y--) y];

    // Null for premium and for any year the floor does not reach into. See
    // [historyFloorFor], the same definition the reports hub and the
    // per-habit detail sheet read, so no two screens can disagree about
    // which days are walled.
    DateTime? floorFor(int year) => historyFloorFor(
          windowStart: DateTime(year),
          today: today,
          isPremium: isPremium,
        );

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
        // +1 for the lifetime header that now sits under the subtitle.
        itemCount: 2 + years.length + (isPremium ? 1 : 2),
        itemBuilder: (context, index) {
          if (index == 1) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _LifetimeHeader(
                since: dashState.accountCreatedAt ?? _earliestRecordedDay(counts),
                squares: lifetimeSquares,
                activeDays: lifetimeActiveDays,
                bestDay: lifetimeBestDay,
                locale: Localizations.localeOf(context).languageCode,
              ),
            );
          }
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                s.lifeTimelineSubtitle,
                style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.4),
              ),
            );
          }
          final yearIndex = index - 2;
          if (yearIndex < years.length) {
            final year = years[yearIndex];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _YearSection(
                year: year,
                lockedBefore: floorFor(year),
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
          return InkWell(
            // Tappable now, and it answers with the shared demo sheet rather
            // than nothing at all. Every other locked-history surface in the
            // app previews before it asks.
            onTap: () => showHistoryDemoGate(context),
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
                  Icon(Icons.lock_clock_rounded,
                      size: 20, color: GameColors.gold),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.lifeTimelineUpgradeBody(kFreeHistoryMonths),
                      style: TextStyle(
                          fontSize: 12.5, color: gp.textSec, height: 1.4),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: GameColors.gold.withOpacity(0.7)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// The first day anything was recorded, for accounts with no stored
  /// creation date (guests, and anyone signed up before that field existed).
  /// Without this the header simply dropped its "since" line, which is the
  /// one sentence the screen is built around.
  static DateTime? _earliestRecordedDay(Map<String, int> counts) {
    DateTime? earliest;
    for (final entry in counts.entries) {
      if (entry.value <= 0) continue;
      final day = DateTime.tryParse(entry.key);
      if (day == null) continue;
      if (earliest == null || day.isBefore(earliest)) earliest = day;
    }
    return earliest;
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

/// The one thing this screen owns that no other screen says: when the record
/// starts, and what the whole of it adds up to.
///
/// Deliberately NOT a copy of the Profile hero's stat row. That row answers
/// "where am I now" (streak, level, gold, XP); this one answers "how much is
/// there, in total, since the beginning", which is the frame the years below
/// hang off. The three figures are the Monthly Heatmap's own three, widened
/// from its visible window to the whole record, so the labels are shared and
/// the difference between the two screens is the SCOPE rather than the
/// vocabulary.
class _LifetimeHeader extends StatelessWidget {
  final DateTime? since;
  final int squares;
  final int activeDays;
  final int bestDay;
  final String locale;

  const _LifetimeHeader({
    required this.since,
    required this.squares,
    required this.activeDays,
    required this.bestDay,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.gold.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (since != null) ...[
            Row(
              children: [
                Icon(Icons.flag_rounded, size: 15, color: GameColors.gold),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    s.lifeTimelineSince(
                        westernDate(since!, 'MMMM yyyy', locale)),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              _LifetimeStat(
                  value: squares, label: s.heatmapTotalGreen, gold: true),
              _LifetimeStat(value: activeDays, label: s.heatmapActiveDays),
              _LifetimeStat(value: bestDay, label: s.heatmapBestDay),
            ],
          ),
        ],
      ),
    );
  }
}

class _LifetimeStat extends StatelessWidget {
  final int value;
  final String label;
  final bool gold;
  const _LifetimeStat({
    required this.value,
    required this.label,
    this.gold = false,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              // Western digits everywhere, same as every other number in the
              // app, so an Arabic build never mixes numeral systems.
              toWesternDigits('$value'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: gold ? GameColors.gold : gp.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: gp.textSec),
          ),
        ],
      ),
    );
  }
}

class _YearSection extends StatelessWidget {
  final int year;

  /// Days before this are behind the paywall: drawn muted, excluded from the
  /// year's own total, and tappable to raise the demo sheet. Null when
  /// nothing in this year is walled.
  final DateTime? lockedBefore;
  final Map<String, int> counts;
  final List<IslamicHabitTemplate> habits;
  final List<MilestoneEvent> milestonesThisYear;
  final DateTime today;
  final bool dark;

  const _YearSection({
    required this.year,
    required this.lockedBefore,
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
      final locked = lockedBefore != null && d.isBefore(lockedBefore!);
      final count = counts[d.toDateKey()] ?? 0;
      // The total counts what the grid SHOWS. A lifetime figure printed
      // beside a mostly-muted year is the walled number arriving by another
      // door, which is the same rule the reports hub's habit rows and header
      // both follow.
      if (!locked) yearTotal += count;
      final scheduled = habits.where((h) => h.isScheduledFor(d)).length;
      final square = _DaySquare(
        color: locked
            ? (dark
                ? Colors.white.withOpacity(0.03)
                : Colors.black.withOpacity(0.03))
            : heatColor(heatLevel(count, scheduled), dark),
        isToday: !locked && d.isRealToday,
      );
      cells.add(locked
          ? GestureDetector(
              // Only the muted squares sell. A gate that fired anywhere on
              // the grid would interrupt someone reading days they already
              // have.
              onTap: () => showHistoryDemoGate(context),
              child: square,
            )
          : square);
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
                  MilestoneTallyChip(
                    icon: entry.key.icon,
                    color: entry.key.color,
                    count: entry.value,
                    label: entry.key.localizedName(S.of(context).isAr),
                  ),
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

