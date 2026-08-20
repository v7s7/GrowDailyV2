// The month's numbers, lifted out of the retired MonthlyStoryScreen when
// "قصة الشهر" stopped being a destination of its own and became the شهري
// tab of the reports hub (see period_report_section.dart).
//
// Only the pure math moved. The widgets did not survive the merge: the hero
// card and the milestone-count grid were replaced by ReportHeaderCard and
// its chip row, which print the month's total once instead of twice.
import '../../../core/extensions/datetime_ext.dart';
import '../../../shared/widgets/month_picker_sheet.dart' show monthsBetween;
import '../models/milestone_event.dart';
import '../notifiers/milestone_notifier.dart' show tallyMilestonesByType;

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
