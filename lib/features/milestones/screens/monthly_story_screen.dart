import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/share_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../../shared/widgets/calendar_month_scaffold.dart';
import '../../../shared/widgets/history_demo_gate.dart';
import '../../../shared/widgets/month_picker_sheet.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../premium/notifiers/premium_notifier.dart';
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

  /// Whether [prevMonthTotal] is a real comparison rather than the zero of
  /// a month that predates the account. False suppresses the delta chip
  /// entirely — see computeMonthlyStory.
  final bool hasBaseline;

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
    this.hasBaseline = true,
  });

  int get delta => totalGreenSquares - prevMonthTotal;

  /// Whether the delta is worth showing at all.
  bool get showsDelta => hasBaseline && delta != 0;

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
  DateTime? today,
  DateTime? earliestMonth,
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

  // ── The comparison month ─────────────────────────────────────────────
  //
  // Only the SAME stretch of the previous month counts. A month in
  // progress is otherwise measured against a month that finished: on the
  // 18th of August, 18 days of August were being subtracted from all 31
  // days of July, so someone having an identical month saw a large amber
  // deficit and kept seeing one until roughly the last day of every month.
  // The screenshot that prompted this read "34" against "-48", and both
  // numbers were correct — the comparison was not.
  //
  // [today] is optional so the pure tally can still be computed with no
  // notion of "now"; when it is absent, or when [month] is any month that
  // has already finished, the whole previous month is the right baseline.
  final prevMonth = DateTime(month.year, month.month - 1);
  final prevDaysInMonth = DateTime(prevMonth.year, prevMonth.month + 1, 0).day;
  final isMonthInProgress = today != null &&
      today.year == month.year &&
      today.month == month.month;
  // Clamped: comparing "through the 31st" against a 30-day month would
  // silently read as through the 30th, which is right, but the 29th of
  // February against January would not be.
  final prevUpTo = isMonthInProgress
      ? (today.day < prevDaysInMonth ? today.day : prevDaysInMonth)
      : prevDaysInMonth;
  var prevTotal = 0;
  for (var d = 1; d <= prevUpTo; d++) {
    final day = DateTime(prevMonth.year, prevMonth.month, d);
    prevTotal += dailyGreenCounts[day.toDateKey()] ?? 0;
  }

  // On the earliest month anyone can open, the "previous month" is a month
  // the account did not exist for. Its total is zero, so the delta came
  // out as +N with N identical to the total printed right beside it — a
  // number that looked like growth and was just the same figure twice.
  final hasBaseline = earliestMonth == null ||
      !normalizedMonth
          .isAtSameMomentAs(DateTime(earliestMonth.year, earliestMonth.month));

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
    hasBaseline: hasBaseline,
  );
}

/// The earliest month [MonthlyStoryScreen] will let someone navigate back to.
///
/// Deliberately the EARLIER of the account's creation month and the first
/// month holding a green square, rather than creation alone.
///
/// `createdAt` is written only by AuthNotifier._createUserDoc, which runs
/// the one time a user doc is first created; _ensureUserDoc backfills only
/// `email` and explicitly leaves everything else as-is. So every account
/// whose doc predates that field simply has no createdAt, forever.
/// Measured against production on 2026-08-18: of 25 user docs, 23 had
/// none, including accounts with months of recorded history.
///
/// Treating a missing createdAt as "this month" collapsed the floor onto
/// the ceiling: canGoBack and canGoForward were BOTH false, both arrows
/// were disabled, and months of real data were unreachable with no
/// explanation on screen. That is the bug this function exists to prevent,
/// which is why it is a testable top-level function rather than three
/// lines inside build().
///
/// Taking the minimum of the two (rather than preferring createdAt) also
/// covers the opposite direction: a guest whose local history is merged
/// into a freshly created account has squares older than createdAt, and
/// those months are just as real.
DateTime earliestStoryMonth({
  required Map<String, int> dailyGreenCounts,
  required DateTime? accountCreatedAt,
  required DateTime currentMonth,
}) {
  final ceiling = DateTime(currentMonth.year, currentMonth.month);
  DateTime? earliest;
  for (final entry in dailyGreenCounts.entries) {
    if (entry.value <= 0) continue;
    final parsed = DateTime.tryParse(entry.key);
    if (parsed == null) continue;
    final month = DateTime(parsed.year, parsed.month);
    if (earliest == null || month.isBefore(earliest)) earliest = month;
  }
  if (accountCreatedAt != null) {
    final created = DateTime(accountCreatedAt.year, accountCreatedAt.month);
    if (earliest == null || created.isBefore(earliest)) earliest = created;
  }
  // A future-dated createdAt (clock skew, a bad import) must never push the
  // floor above the ceiling and re-freeze the screen the way the old code
  // did by accident.
  if (earliest == null || earliest.isAfter(ceiling)) return ceiling;
  // Same 240-month safety ceiling MonthlyHeatmapScreen documents:
  // dailyGreenCounts is user-doc data, so one corrupt or hand-edited key
  // with a bogus ancient date must never make the picker render thousands
  // of month cells. Twenty years of real use stays well inside it.
  final floor = DateTime(ceiling.year, ceiling.month - _maxHistoryMonths + 1);
  return earliest.isBefore(floor) ? floor : earliest;
}

const int _maxHistoryMonths = 240;

/// Every month from [earliest] through [current] inclusive, newest first —
/// what the month picker lists. Both ends are normalised to the first of
/// the month, so callers may pass any day.
List<DateTime> storyMonthsBetween(DateTime earliest, DateTime current) =>
    monthsBetween(earliest, current);

/// A shareable "your month in review" card — the monthly-grain, richer
/// sibling of WeeklyRecapCard (grid/widgets/weekly_recap_card.dart), which
/// stays exactly as it is (a quiet Friday nudge embedded in Profile). This
/// is deliberately a full destination instead: browsable to any past month
/// back to [earliestStoryMonth], and built to be shared
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
    // effectiveDay, not DateTime.now(): the app's day rolls over at 6am
    // (see DateTimeGameExt.effectiveDay). Opening on the raw calendar
    // month meant that between midnight and 06:00 on the 1st this screen
    // showed a brand-new, guaranteed-empty month while the habits the user
    // had just finished sat one step back.
    final today = DateTime.now().effectiveDay;
    _viewedMonth = DateTime(today.year, today.month);
  }

  /// Opens the month grid.
  ///
  /// [counts] decides which cells are drawn as "has a story", so a run of
  /// months from before the user actually started is distinguishable at a
  /// glance from months they did use, rather than twelve identical cells.
  ///
  /// Green squares alone, deliberately, not the full hasAnything: telling
  /// the marker apart properly would mean one milestone query per month in
  /// the picker (see milestonesForMonthProvider) to change a dimming level.
  /// A month with milestones but no green square at all is close to
  /// impossible anyway, since every milestone this app logs is downstream
  /// of completing something.
  Future<void> _pickMonth({
    required List<DateTime> months,
    required bool Function(DateTime) unlocked,
    required Map<String, int> counts,
  }) async {
    final picked = await showMonthPicker(
      context,
      months: months,
      selected: _viewedMonth,
      isUnlocked: unlocked,
      hasStory: (month) {
        final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
        for (var d = 1; d <= daysInMonth; d++) {
          final key = DateTime(month.year, month.month, d).toDateKey();
          if ((counts[key] ?? 0) > 0) return true;
        }
        return false;
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _viewedMonth = picked);
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
    // Queried per month rather than filtered out of the shared newest-first
    // window, which stops reaching older months once an account passes
    // ~500 events — see milestonesForMonthProvider.
    final milestones =
        ref.watch(milestonesForMonthProvider(_viewedMonth)).valueOrNull ??
            const <MilestoneEvent>[];
    final isPremium = ref.watch(premiumProvider);
    final today = DateTime.now().effectiveDay;
    final currentMonth = DateTime(today.year, today.month);
    final earliestMonth = earliestStoryMonth(
      dailyGreenCounts: dashState.dailyGreenCounts,
      accountCreatedAt: dashState.accountCreatedAt,
      currentMonth: currentMonth,
    );
    // Free browses the current month plus the two before it, exactly as on
    // the Monthly Heatmap, Grid Journal and Night Review History — see
    // canBrowseHistoryMonth. This screen was the one history surface with
    // no gate at all, which only went unnoticed because the bounds bug
    // meant nobody could reach a second month anyway.
    bool unlocked(DateTime month) => canBrowseHistoryMonth(
          monthStart: month,
          now: today,
          isPremium: isPremium,
        );

    final data = computeMonthlyStory(
      dailyGreenCounts: dashState.dailyGreenCounts,
      month: _viewedMonth,
      allMilestones: milestones,
      today: today,
      earliestMonth: earliestMonth,
    );
    final monthLabel = westernDate(_viewedMonth, 'MMMM yyyy', locale);
    final previousMonth =
        DateTime(_viewedMonth.year, _viewedMonth.month - 1);
    // Deliberately bounded by the DATA range only, not by Premium. A
    // locked month leaves the arrow live and answers on tap with the
    // history-locked snackbar, the same as Night Review History and Grid
    // Journal. Greying it out instead would reproduce the exact failure
    // this change exists to fix: a dead control that explains nothing.
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
          // The shared header, not a private copy: Rooms' participant
          // calendar already renders this exact control, and the version
          // that used to live here was a bare unstyled IconButton row that
          // looked like a different control doing the same job.
          CalendarMonthHeader(
            month: _viewedMonth,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            onBack: () {
              HapticFeedback.selectionClick();
              if (!unlocked(previousMonth)) {
                showHistoryDemoGate(context);
                return;
              }
              setState(() => _viewedMonth = previousMonth);
            },
            onForward: () {
              HapticFeedback.selectionClick();
              setState(() => _viewedMonth =
                  DateTime(_viewedMonth.year, _viewedMonth.month + 1));
            },
            onTapMonth: () => _pickMonth(
              months: storyMonthsBetween(earliestMonth, currentMonth),
              unlocked: unlocked,
              counts: dashState.dailyGreenCounts,
            ),
          ),
          const SizedBox(height: 8),
          // Order matters. The empty state is an assertion about the USER
          // ("there's nothing recorded for this month"), and a dashboard
          // that failed to load produces exactly the zeros that would
          // trigger it — so a network failure used to be rendered as a
          // claim that the user did nothing. Both load states are checked
          // before that sentence is allowed on screen.
          if (dashState.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (dashState.loadFailed)
            _StoryLoadFailed(s: s)
          else if (!data.hasAnything)
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

/// Shown when the dashboard load itself failed, instead of the empty
/// state. Deliberately worded as a failure on our side, since the one
/// thing it must never do is tell someone they recorded nothing when the
/// truth is that we could not read what they recorded.
class _StoryLoadFailed extends StatelessWidget {
  final S s;
  const _StoryLoadFailed({required this.s});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: gp.textTert),
          const SizedBox(height: 12),
          Text(
            s.monthlyStoryLoadFailed,
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
              if (data.showsDelta) ...[
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
                    // westernDate, matching the header above it: this
                    // card rendered "١٣ يونيو" in Arabic-Indic digits
                    // directly beside "2 أيام نشطة" and "2026" in ASCII,
                    // three digit systems in one card.
                    : westernDate(data.bestDay!, 'd MMM', locale),
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
