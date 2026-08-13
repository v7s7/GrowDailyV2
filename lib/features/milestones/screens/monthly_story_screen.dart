import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/share_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../models/milestone_event.dart';
import '../notifiers/milestone_notifier.dart';

/// One month's numbers, computed purely from [DashboardState.dailyGreenCounts]
/// (zero extra reads, same reasoning as WeeklyRecapData in
/// weekly_recap_card.dart) plus the shared [MilestoneEvent] log filtered to
/// that month — this adds no detection of its own, only tallies what
/// completeHabit already logged. Pure and unit-testable with a hand-built
/// map/list, no Firestore/Riverpod involved.
class MonthlyStoryData {
  final DateTime month;
  final int totalGreenSquares;
  final int activeDays;
  final DateTime? bestDay;
  final int bestDayCount;
  final int perfectDays;
  final int perfectWeeks;
  final int levelUps;
  final int streakMilestones;
  final int achievementsUnlocked;
  final int prevMonthTotal;

  const MonthlyStoryData({
    required this.month,
    required this.totalGreenSquares,
    required this.activeDays,
    required this.bestDay,
    required this.bestDayCount,
    required this.perfectDays,
    required this.perfectWeeks,
    required this.levelUps,
    required this.streakMilestones,
    required this.achievementsUnlocked,
    required this.prevMonthTotal,
  });

  int get delta => totalGreenSquares - prevMonthTotal;

  /// Whether there's anything at all worth showing a story for — a month
  /// with zero greens and zero milestones renders an empty state instead.
  bool get hasAnything => totalGreenSquares > 0 || milestoneCount > 0;

  int get milestoneCount =>
      perfectDays + perfectWeeks + levelUps + streakMilestones + achievementsUnlocked;
}

MonthlyStoryData computeMonthlyStory({
  required Map<String, int> dailyGreenCounts,
  required DateTime month,
  required List<MilestoneEvent> allMilestones,
}) {
  final normalizedMonth = DateTime(month.year, month.month);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

  var total = 0;
  var activeDays = 0;
  DateTime? bestDay;
  var best = 0;
  for (var d = 1; d <= daysInMonth; d++) {
    final day = DateTime(month.year, month.month, d);
    final count = dailyGreenCounts[day.toDateKey()] ?? 0;
    if (count <= 0) continue;
    total += count;
    activeDays++;
    if (count > best) {
      best = count;
      bestDay = day;
    }
  }

  final prevMonth = DateTime(month.year, month.month - 1);
  final prevDaysInMonth = DateTime(prevMonth.year, prevMonth.month + 1, 0).day;
  var prevTotal = 0;
  for (var d = 1; d <= prevDaysInMonth; d++) {
    final day = DateTime(prevMonth.year, prevMonth.month, d);
    prevTotal += dailyGreenCounts[day.toDateKey()] ?? 0;
  }

  final inMonth = allMilestones.where(
    (e) => e.occurredAt.year == month.year && e.occurredAt.month == month.month,
  );
  // One pass building the whole tally, then a lookup per type — replaces
  // five separate `.where((e) => e.type == t).length` passes over the same
  // iterable (O(n) total instead of O(n * types)). Shared with Life
  // Timeline's per-year badges via tallyMilestonesByType rather than each
  // screen re-deriving "count events by type" its own way.
  final tally = tallyMilestonesByType(inMonth);

  return MonthlyStoryData(
    month: normalizedMonth,
    totalGreenSquares: total,
    activeDays: activeDays,
    bestDay: bestDay,
    bestDayCount: best,
    perfectDays: tally[MilestoneType.perfectDay] ?? 0,
    perfectWeeks: tally[MilestoneType.perfectWeek] ?? 0,
    levelUps: tally[MilestoneType.levelUp] ?? 0,
    streakMilestones: tally[MilestoneType.streakMilestone] ?? 0,
    achievementsUnlocked: tally[MilestoneType.achievementUnlocked] ?? 0,
    prevMonthTotal: prevTotal,
  );
}

/// A shareable "your month in review" card — the monthly-grain, richer
/// sibling of WeeklyRecapCard (grid/widgets/weekly_recap_card.dart), which
/// stays exactly as it is (a quiet Friday nudge embedded in Profile). This
/// is deliberately a full destination instead: browsable to any past month
/// back to [DashboardState.accountCreatedAt], and built to be shared
/// outside the app via the same ShareService Rooms already uses (see
/// _share below / RoomDetailScreen's own share action), which neither
/// WeeklyRecapCard nor the day-level MonthlyHeatmapScreen offer.
class MonthlyStoryScreen extends ConsumerStatefulWidget {
  const MonthlyStoryScreen({super.key});

  @override
  ConsumerState<MonthlyStoryScreen> createState() => _MonthlyStoryScreenState();
}

class _MonthlyStoryScreenState extends ConsumerState<MonthlyStoryScreen> {
  late DateTime _viewedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewedMonth = DateTime(now.year, now.month);
  }

  void _share(MonthlyStoryData data, String monthLabel, bool isAr) {
    HapticFeedback.selectionClick();
    final s = S.of(context);
    ShareService.shareText(
      context,
      s.monthlyStoryShareText(
        monthLabel,
        data.totalGreenSquares,
        data.perfectDays,
        data.levelUps,
        data.achievementsUnlocked,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final dashState = ref.watch(dashboardProvider);
    final milestones = ref.watch(milestoneEventsProvider).valueOrNull ?? const [];
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final earliestMonth = dashState.accountCreatedAt == null
        ? currentMonth
        : DateTime(dashState.accountCreatedAt!.year, dashState.accountCreatedAt!.month);

    final data = computeMonthlyStory(
      dailyGreenCounts: dashState.dailyGreenCounts,
      month: _viewedMonth,
      allMilestones: milestones,
    );
    final monthLabel = DateFormat('MMMM yyyy', locale).format(_viewedMonth);
    final canGoBack = _viewedMonth.isAfter(earliestMonth);
    final canGoForward = _viewedMonth.isBefore(currentMonth);

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(s.monthlyStoryTitle,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: gp.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: s.roomShareAction,
            onPressed: data.hasAnything ? () => _share(data, monthLabel, s.isAr) : null,
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: canGoBack
                    ? () {
                        HapticFeedback.selectionClick();
                        setState(() => _viewedMonth =
                            DateTime(_viewedMonth.year, _viewedMonth.month - 1));
                      }
                    : null,
              ),
              Text(monthLabel,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: gp.textPrimary)),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: canGoForward
                    ? () {
                        HapticFeedback.selectionClick();
                        setState(() => _viewedMonth =
                            DateTime(_viewedMonth.year, _viewedMonth.month + 1));
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!data.hasAnything)
            _StoryEmptyState(s: s)
          else ...[
            _StoryHeroCard(data: data, monthLabel: monthLabel, locale: locale),
            const SizedBox(height: 16),
            _StoryMilestoneGrid(data: data),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _share(data, monthLabel, s.isAr),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: Text(s.monthlyStoryShareAction),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StoryEmptyState extends StatelessWidget {
  final S s;
  const _StoryEmptyState({required this.s});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.auto_stories_rounded, size: 40, color: gp.textTert),
          const SizedBox(height: 12),
          Text(
            s.monthlyStoryEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// The headline card — total greens, delta vs. last month, active days, and
/// best day, styled with more presence (gold border/glow) than a plain
/// stats card since this is the one part of the screen someone actually
/// screenshots or shares.
class _StoryHeroCard extends StatelessWidget {
  final MonthlyStoryData data;
  final String monthLabel;
  final String locale;
  const _StoryHeroCard({required this.data, required this.monthLabel, required this.locale});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final delta = data.delta;
    final deltaColor = delta > 0
        ? GameColors.emerald
        : delta < 0
            ? GameColors.warning
            : gp.textTert;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.gold.withOpacity(0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.monthlyStoryHeadline(monthLabel),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: gp.textSec),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${data.totalGreenSquares}',
                style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: gp.textPrimary,
                    letterSpacing: -1.5,
                    height: 1),
              ),
              const SizedBox(width: 8),
              Text(s.monthlyStoryGreenSquares,
                  style: TextStyle(fontSize: 13, color: gp.textSec)),
              if (delta != 0) ...[
                const SizedBox(width: 8),
                Text(
                  delta > 0 ? '+$delta' : '$delta',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: deltaColor),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StoryMiniStat(value: '${data.activeDays}', label: s.heatmapActiveDays),
              _StoryMiniStat(
                value: data.bestDay == null
                    ? '—'
                    : DateFormat('d MMM', locale).format(data.bestDay!),
                label: s.heatmapBestDay,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StoryMiniStat extends StatelessWidget {
  final String value;
  final String label;
  const _StoryMiniStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: gp.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10.5, color: gp.textTert)),
        ],
      ),
    );
  }
}

/// The month's milestone tally as a compact 2-column grid of cards, one per
/// [MilestoneType] with at least one hit — skips types with a zero count
/// rather than showing a wall of zeros.
class _StoryMilestoneGrid extends StatelessWidget {
  final MonthlyStoryData data;
  const _StoryMilestoneGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // Every label sourced from MilestoneType.localizedName, not a lifetime
    // total phrasing like "current level number" or "X/Y unlocked lifetime" -
    // this grid means "count of level-ups or unlocks this month", a
    // different meaning that a lifetime-total label would misstate (e.g. a
    // card reading "4" next to "Level" when it meant 4 level-ups this month).
    final entries = <(IconData, Color, int, String)>[
      if (data.levelUps > 0)
        (Icons.bolt_rounded, GameColors.gold, data.levelUps,
            MilestoneType.levelUp.localizedName(s.isAr)),
      if (data.streakMilestones > 0)
        (Icons.local_fire_department_rounded, GameColors.iconStreak, data.streakMilestones,
            MilestoneType.streakMilestone.localizedName(s.isAr)),
      if (data.perfectDays > 0)
        (Icons.star_rounded, GameColors.success, data.perfectDays,
            MilestoneType.perfectDay.localizedName(s.isAr)),
      if (data.perfectWeeks > 0)
        (Icons.auto_awesome_rounded, GameColors.iconXp, data.perfectWeeks,
            MilestoneType.perfectWeek.localizedName(s.isAr)),
      if (data.achievementsUnlocked > 0)
        (Icons.emoji_events_rounded, GameColors.gold, data.achievementsUnlocked,
            MilestoneType.achievementUnlocked.localizedName(s.isAr)),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.6,
      children: [
        for (final e in entries)
          _MilestoneCountCard(icon: e.$1, color: e.$2, count: e.$3, label: e.$4),
      ],
    );
  }
}

class _MilestoneCountCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final String label;
  const _MilestoneCountCard({
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$count',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: gp.textPrimary)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5, color: gp.textTert)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
