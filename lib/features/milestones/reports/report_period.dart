import '../../../core/extensions/datetime_ext.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart' show startOfGridWeek;
import '../../habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitTemplate;
import '../../grid/models/square_state.dart';
import '../../habits/models/habit_model.dart' show HabitFrequencyType;
import '../../premium/notifiers/premium_notifier.dart'
    show canBrowseHistoryMonth, kFreeHistoryMonths;
import 'habit_day_marks.dart';

/// Which grain the reports hub is showing: the three segments of the
/// أسبوعي / شهري / سنوي control at the top of [ProgressHubScreen].
///
/// One enum rather than three screens because every tab answers the same
/// question at a different zoom, and they share a period stepper, a premium
/// floor and a summary row. The tabs differ only in the window they hand to
/// the pure functions below.
enum ReportScope { week, month, year }

/// The inclusive day window [scope] covers around [anchor].
///
/// The week arm is Saturday-anchored via [startOfGridWeek], the same origin
/// every other week surface in this app uses (Grid, the room strips, the
/// year strip's rows). A Monday-anchored report beside a Saturday-anchored
/// Grid would put the same completion in two different columns.
({DateTime start, DateTime end}) reportWindow(
  ReportScope scope,
  DateTime anchor,
) {
  switch (scope) {
    case ReportScope.week:
      final start = startOfGridWeek(anchor);
      return (
        start: start,
        end: DateTime(start.year, start.month, start.day + 6),
      );
    case ReportScope.month:
      return (
        start: DateTime(anchor.year, anchor.month),
        end: DateTime(anchor.year, anchor.month + 1, 0),
      );
    case ReportScope.year:
      return (
        start: DateTime(anchor.year),
        end: DateTime(anchor.year, 12, 31),
      );
  }
}

/// Whether a free account may open the period [scope] covers around
/// [anchor].
///
/// The three grains are gated differently on purpose.
///
/// WEEK: always open. The Grid has never gated past weeks (see _pickWeek in
/// grid_screen_summary.dart, which records that decision explicitly), and it
/// shows the same completions this report does, one tap away, for free.
/// Gating the weekly report would wall off nothing: it would only teach
/// someone that the lock is arbitrary, which is worse for the upgrade than
/// no lock at all.
///
/// MONTH: gated by [canBrowseHistoryMonth], the same free window the Monthly
/// Heatmap, Grid Journal, Night Review history and Matrix history all use.
/// The month view is the aggregate nobody can assemble by hand, so it is the
/// thing actually being sold.
///
/// YEAR: never blocked at the navigation level, because the year tab draws
/// its locked days muted inside a strip that is otherwise perfectly
/// readable. Blocking the step would hide years the strip could partly show;
/// the muting is the gate, and a tap on a muted region raises the demo sheet.
bool reportPeriodUnlocked({
  required ReportScope scope,
  required DateTime anchor,
  required DateTime now,
  required bool isPremium,
}) {
  if (isPremium) return true;
  switch (scope) {
    case ReportScope.week:
    case ReportScope.year:
      return true;
    case ReportScope.month:
      final start = reportWindow(scope, anchor).start;
      return canBrowseHistoryMonth(
        monthStart: DateTime(start.year, start.month),
        now: now,
        isPremium: isPremium,
      );
  }
}

/// The first day of the oldest month a free account may open, given
/// [today].
///
/// The single definition of the free-history floor for every reports
/// surface. It exists as a shared function rather than a private helper
/// because two screens now draw the same floor: the reports hub's period
/// stepper and per-habit year strips, and the per-habit detail sheet the
/// hub opens. Those two show the SAME habit's SAME days, so a floor that
/// drifted between them would let one screen lock a day the other still
/// paints in full colour, which is exactly the "same data, two prices"
/// bug this floor exists to prevent.
///
/// Pure, so [kFreeHistoryMonths] can be moved without hunting call sites,
/// and so the boundary is unit-testable without Riverpod or RevenueCat -
/// see test/features/milestones/habit_detail_gate_test.dart.
DateTime freeHistoryFloor(DateTime today) =>
    DateTime(today.year, today.month - (kFreeHistoryMonths - 1));

/// The floor a surface showing days from [windowStart] onward should draw
/// muted, or null when it should draw no lock styling at all.
///
/// Null in two different cases, and both matter:
///  * Premium, which is never floored.
///  * A window that does not reach back past the floor. Handing a painter a
///    floor that nothing on screen predates drew lock icons over a fully
///    visible period - the bug the reports hub's own `floorBites` check was
///    added for. A year strip is the sharp case: from January through the
///    month the floor lands in, the whole visible year sits INSIDE the free
///    window, so a strip that muted "everything before the floor" would mute
///    nothing and must say so by returning null rather than a floor.
///
/// Shared by the reports hub's period stepper and by the per-habit detail
/// sheet's year strip so the two cannot disagree about which days are
/// walled. See [freeHistoryFloor] for the floor itself.
DateTime? historyFloorFor({
  required DateTime windowStart,
  required DateTime today,
  required bool isPremium,
}) {
  if (isPremium) return null;
  final floor = freeHistoryFloor(today);
  return windowStart.isBefore(floor) ? floor : null;
}

/// [days], with everything the free tier may not see removed.
///
/// The rule this exists to enforce is already written down one layer below,
/// on the per-habit year row: "the label counts what the strip SHOWS", so a
/// full-history count never sits beside a mostly-muted strip. The aggregate
/// cards at the TOP of a report have to obey the same rule, or one screen
/// tells two stories: muted strips reading zero, under a header printing the
/// real total for a year the strips are hiding.
///
/// Returns [days] itself when [floor] is null, so a premium report and an
/// unwalled period both skip the copy entirely.
List<DateTime> visibleDaysFrom({
  required List<DateTime> days,
  required DateTime? floor,
}) {
  if (floor == null) return days;
  return [
    for (final day in days)
      if (!day.isBefore(floor)) day,
  ];
}

/// Every calendar day from [start] through [end] inclusive, never running
/// past [today].
///
/// Constructed day by day rather than `.add(Duration(days: 1))` for the
/// same DST reason [yearStripDay] documents: a 23-hour day makes duration
/// arithmetic land a day early, and this list is what every denominator on
/// the reports hub is counted against.
List<DateTime> elapsedDaysIn({
  required DateTime start,
  required DateTime end,
  required DateTime today,
}) {
  final last = end.isAfter(today) ? today : end;
  final out = <DateTime>[];
  for (var d = DateTime(start.year, start.month, start.day);
      !d.isAfter(DateTime(last.year, last.month, last.day));
      d = DateTime(d.year, d.month, d.day + 1)) {
    out.add(d);
  }
  return out;
}

/// How many completions [habit] was expected to make across [days].
///
/// This is the denominator behind every percentage on the reports hub, and
/// it deliberately is NOT "number of days in the period".
///
/// Three different shapes of habit live in this app and a single denominator
/// misreports two of them:
///  - A daily habit is expected once per elapsed day it was alive for.
///  - A habit with explicit [scheduledWeekdays] (say Monday and Thursday
///    fasting) is expected only on those weekdays. Counting all seven would
///    print 29% for a month that was actually perfect.
///  - A weekly-quota habit with no fixed weekdays (three times a week,
///    any three) is expected [frequencyTarget] times per week, whichever
///    days those land on. Counting seven days a week would print 43% for
///    someone who hit their target every single week.
///
/// [IslamicHabitTemplate.isScheduledFor] already answers "was this habit
/// alive and due on this day", including its createdAt and archivedAt
/// bounds, so the first two arms defer to it rather than re-deriving
/// aliveness here.
/// Whether a miss can be pinned on a PARTICULAR day for this habit.
///
/// False for a quota habit with no fixed weekdays ("three times a week, any
/// three"). Nobody owed Tuesday in particular, so no individual blank square
/// is a failure, and the grid must not draw one as though it were: a habit
/// with a target of four, hit four times, was rendering four filled cells
/// beside three "missed" outlines AND a PERFECT badge on the same row, which
/// is the report contradicting itself in a single glance.
///
/// True for daily habits and for habits with explicit [scheduledWeekdays],
/// where a specific day really was owed and really was not done.
///
/// Deliberately the same predicate [expectedCompletions] branches on, so the
/// denominator and the squares can never disagree about which habits have
/// day-level obligations.
bool missIsAttributable(IslamicHabitTemplate habit) =>
    !(habit.frequencyType == HabitFrequencyType.weekly &&
        habit.scheduledWeekdays.isEmpty &&
        habit.frequencyTarget > 0);

int expectedCompletions({
  required IslamicHabitTemplate habit,
  required List<DateTime> days,
  Set<String> restDays = const {},
}) {
  if (days.isEmpty) return 0;
  final quotaOnly = !missIsAttributable(habit);
  if (!quotaOnly) {
    var count = 0;
    for (final day in days) {
      // A day marked تخطّي leaves the denominator entirely. This one line is
      // the arithmetic finally agreeing with the app's own position that a
      // rest day is not a missed day: before it, choosing to rest lowered
      // your percentage exactly as much as forgetting would have.
      if (restDays.contains(day.toDateKey())) continue;
      if (habit.isScheduledFor(day)) count++;
    }
    return count;
  }
  // Quota habits are counted per Saturday-anchored week: a week the habit
  // was alive for only two days can never owe three completions, so the
  // target is clamped to the days actually available in that week.
  final aliveDaysPerWeek = <String, int>{};
  for (final day in days) {
    if (restDays.contains(day.toDateKey())) continue;
    if (!habit.isScheduledFor(day)) continue;
    final key = startOfGridWeek(day).toDateKey();
    aliveDaysPerWeek[key] = (aliveDaysPerWeek[key] ?? 0) + 1;
  }
  var total = 0;
  for (final alive in aliveDaysPerWeek.values) {
    total += alive < habit.frequencyTarget ? alive : habit.frequencyTarget;
  }
  return total;
}

/// One habit's record across one report window.
///
/// Holds the six-state [SquareState] mark for every day the window recorded
/// anything, not just a set of green days, which is what lets a report say
/// "you rested" instead of silently scoring it the same as "you forgot".
class HabitPeriodStat {
  final IslamicHabitTemplate habit;

  /// Recorded marks inside the window, keyed by dateKey. Days with nothing
  /// recorded are absent rather than [SquareState.none].
  final Map<String, SquareState> marks;

  /// What [expectedCompletions] says the window owed, already net of any
  /// day marked تخطّي.
  final int expected;

  /// Days that count as achieved: complete or bonus. Kept as a set because
  /// every grid asks "is this day done" once per cell.
  final Set<String> doneDays;

  /// Days deliberately rested. Shown to the user, never counted against them.
  final int restCount;

  /// Days explicitly marked فشل. Distinct from a day nobody touched: one is
  /// an admission, the other is silence.
  final int failedCount;

  /// Whole-day credit earned, with جزئي worth 0.5 (see [markCredit]).
  /// Fractional, unlike [doneCount], which is why the two exist separately:
  /// "5 يوم" must stay an honest count of days, while the percentage can
  /// reflect a half-finished one.
  final double creditedUnits;

  const HabitPeriodStat._({
    required this.habit,
    required this.marks,
    required this.expected,
    required this.doneDays,
    required this.restCount,
    required this.failedCount,
    required this.creditedUnits,
  });

  factory HabitPeriodStat({
    required IslamicHabitTemplate habit,
    required Map<String, SquareState> marks,
    required int expected,
  }) {
    final done = <String>{};
    var rest = 0;
    var failed = 0;
    var credit = 0.0;
    for (final entry in marks.entries) {
      final mark = entry.value;
      if (markIsDone(mark)) done.add(entry.key);
      if (markIsRest(mark)) rest++;
      if (mark == SquareState.failed) failed++;
      credit += markCredit(mark);
    }
    return HabitPeriodStat._(
      habit: habit,
      marks: marks,
      expected: expected,
      doneDays: done,
      restCount: rest,
      failedCount: failed,
      creditedUnits: credit,
    );
  }

  int get doneCount => doneDays.length;

  SquareState markOn(DateTime day) =>
      marks[day.toDateKey()] ?? SquareState.none;

  /// 0..1 against [expected], not against calendar days. Capped so a quota
  /// habit done four times against a target of three reads as a full bar
  /// rather than an impossible 133%.
  double get rate => expected == 0
      ? 0
      : (creditedUnits / expected).clamp(0.0, 1.0).toDouble();

  /// The PERFECT ribbon's condition. Requires a real denominator: a habit
  /// that owed nothing this period has not earned a perfect mark, it simply
  /// was not due.
  bool get isPerfect => expected > 0 && creditedUnits >= expected;
}

/// Per-habit stats for one window, ordered exactly as [habits] came in.
///
/// [history] is habitYearHistoryProvider's habitId to dateKey-set map, so
/// this costs no reads of its own. Habits that owed nothing AND recorded
/// nothing in the window are dropped: an archived habit that predates the
/// month is noise, while a live habit with an empty row is a commitment
/// worth seeing.
List<HabitPeriodStat> computeHabitPeriodStats({
  required List<IslamicHabitTemplate> habits,
  required Map<String, Map<String, SquareState>> history,
  required List<DateTime> days,
}) {
  final windowKeys = {for (final d in days) d.toDateKey()};
  final out = <HabitPeriodStat>[];
  for (final habit in habits) {
    final all = history[habit.id] ?? const <String, SquareState>{};
    final marks = <String, SquareState>{
      for (final entry in all.entries)
        if (windowKeys.contains(entry.key)) entry.key: entry.value,
    };
    // Rest days come out of the denominator before it is computed, so the
    // habit is never asked to account for a day it was excused from.
    final restDays = {
      for (final entry in marks.entries)
        if (markIsRest(entry.value)) entry.key,
    };
    final expected =
        expectedCompletions(habit: habit, days: days, restDays: restDays);
    if (expected == 0 && marks.isEmpty) continue;
    out.add(HabitPeriodStat(habit: habit, marks: marks, expected: expected));
  }
  return out;
}

/// Splits one window's stats into the habits someone is still keeping and
/// the ones they have archived.
///
/// Archived rows are dropped entirely unless they actually recorded
/// something inside the window. Archiving means "not part of my present",
/// so an archived habit with an empty row is pure noise, while one with real
/// completions is history the report should not quietly delete.
///
/// Shared by all three tabs so they cannot disagree about what counts as
/// archived. Before this, only the yearly tab separated them: the monthly
/// grid rendered an archived habit's card identically to a live one, so a
/// habit someone had deliberately put away sat in the middle of their month
/// looking like a current commitment.
({List<HabitPeriodStat> active, List<HabitPeriodStat> archived}) splitArchived(
  List<HabitPeriodStat> stats,
) =>
    (
      active: [
        for (final stat in stats)
          if (stat.habit.archivedAt == null) stat,
      ],
      archived: [
        for (final stat in stats)
          if (stat.habit.archivedAt != null && stat.doneCount > 0) stat,
      ],
    );

/// Per-day completion counts derived from the SAME per-habit truth the
/// grids are drawn from.
///
/// The screen used to mix two sources: the grids came from the habit_history
/// mirror while every total came from [DashboardState.dailyGreenCounts]. The
/// two do not agree, and they are not meant to: dayIsDone counts a habit
/// done when its completion count is positive OR its grid square landed on
/// complete/bonus, so the mirror is a strict superset of the green-square
/// tally. On 17 August that showed up as a day sheet headed "تم إنجاز 4"
/// above a list of six ticked habits.
///
/// Deriving every number from [stats] costs nothing (the data is already in
/// hand) and makes the arithmetic checkable by eye: the total is what you
/// get by counting the filled cells.
Map<String, int> dayCountsFrom(List<HabitPeriodStat> stats) {
  final out = <String, int>{};
  for (final stat in stats) {
    for (final key in stat.doneDays) {
      out[key] = (out[key] ?? 0) + 1;
    }
  }
  return out;
}

/// The four numbers under every tab's grid.
class PeriodSummary {
  /// Green squares recorded in the window.
  final int totalDone;

  /// What every habit in the window owed, summed.
  final int expectedTotal;

  final DateTime? bestDay;
  final int bestDayCount;

  /// Days in the window with at least one completion.
  final int activeDays;

  /// The longest unbroken run of days with at least one completion, counted
  /// INSIDE the window only.
  ///
  /// Deliberately not the account's real streak (which is an 80%-of-habits
  /// rule that survives rest days, see the streak notifier): this is a
  /// property of the period on screen, and a lifetime streak printed under a
  /// month's grid would answer a question the grid did not ask.
  final int longestRun;

  const PeriodSummary({
    required this.totalDone,
    required this.expectedTotal,
    required this.bestDay,
    required this.bestDayCount,
    required this.activeDays,
    required this.longestRun,
  });

  /// 0..1. Capped for the same reason [HabitPeriodStat.rate] is.
  double get rate => expectedTotal == 0
      ? 0
      : (totalDone / expectedTotal).clamp(0.0, 1.0).toDouble();

  bool get hasAnything => totalDone > 0;
}

/// Summarises one window from [dayCounts] (see [dayCountsFrom]) plus the
/// per-habit denominators.
PeriodSummary computePeriodSummary({
  required Map<String, int> dayCounts,
  required List<DateTime> days,
  required List<HabitPeriodStat> habitStats,
}) {
  var total = 0;
  var activeDays = 0;
  var longestRun = 0;
  var run = 0;
  DateTime? bestDay;
  var best = 0;
  for (final day in days) {
    final count = dayCounts[day.toDateKey()] ?? 0;
    if (count <= 0) {
      run = 0;
      continue;
    }
    total += count;
    activeDays++;
    run++;
    if (run > longestRun) longestRun = run;
    if (count > best) {
      best = count;
      bestDay = day;
    }
  }
  var expected = 0;
  for (final stat in habitStats) {
    expected += stat.expected;
  }
  return PeriodSummary(
    totalDone: total,
    expectedTotal: expected,
    bestDay: bestDay,
    bestDayCount: best,
    activeDays: activeDays,
    longestRun: longestRun,
  );
}

/// Completions inside [days], counted from the per-habit history.
///
/// The same counting rule as [dayCountsFrom], expressed over an arbitrary
/// stretch of days rather than the window on screen, so a period and its
/// predecessor are measured identically.
int totalDoneIn({
  required Map<String, Map<String, SquareState>> history,
  required List<IslamicHabitTemplate> habits,
  required List<DateTime> days,
}) {
  final keys = {for (final d in days) d.toDateKey()};
  var total = 0;
  for (final habit in habits) {
    final marks = history[habit.id] ?? const <String, SquareState>{};
    for (final entry in marks.entries) {
      if (keys.contains(entry.key) && markIsDone(entry.value)) total++;
    }
  }
  return total;
}

/// Change against the comparable stretch of the previous period.
///
/// Two rules make this honest, both learned from the bug the old monthly
/// delta shipped with:
///
/// 1. ONLY THE SAME STRETCH COUNTS. A period in progress is otherwise
///    measured against one that finished: on the 18th of August, 18 days
///    were being compared with all 31 days of July, so someone having an
///    identical month saw a large deficit every month until roughly its
///    last day.
/// 2. IT IS COUNTED FROM THE SAME SOURCE AS THE HEADLINE. The first cut
///    took the total from the per-habit history and the delta from
///    DashboardState.dailyGreenCounts, which produced a July card reading
///    "40 مربعًا أخضر" beside "+80": both numbers correct, neither
///    comparable to the other.
///
/// Returns null when there is no baseline worth comparing to, which is any
/// period whose predecessor ended before [earliestData]. A brand new
/// account otherwise gets a delta identical to its own total, which looks
/// like growth and is just the same figure twice.
int? periodDelta({
  required ReportScope scope,
  required DateTime anchor,
  required Map<String, Map<String, SquareState>> history,
  required List<IslamicHabitTemplate> habits,
  required DateTime today,
  required DateTime? earliestData,

  /// The free-history floor, when one is in force. A comparison against a
  /// period the viewer is not allowed to see is not a comparison, it is the
  /// walled number arriving by subtraction, so any overlap between the
  /// previous window and the walled past suppresses the delta entirely.
  /// Null for premium and for any period no floor reaches.
  DateTime? floor,
}) {
  final current = reportWindow(scope, anchor);
  final currentDays =
      elapsedDaysIn(start: current.start, end: current.end, today: today);
  if (currentDays.isEmpty) return null;

  final previousAnchor = switch (scope) {
    ReportScope.week => DateTime(
        current.start.year, current.start.month, current.start.day - 7),
    ReportScope.month => DateTime(anchor.year, anchor.month - 1),
    ReportScope.year => DateTime(anchor.year - 1),
  };
  final previous = reportWindow(scope, previousAnchor);
  if (earliestData != null && previous.end.isBefore(earliestData)) return null;
  // Deliberately previous.START, not previous.end: a window that merely
  // reaches into the walled past is already unusable as a comparison, and
  // showing a delta computed from days the strips below are muting would
  // hand back the exact number the floor exists to withhold.
  if (floor != null && previous.start.isBefore(floor)) return null;

  // The same number of days, taken from the start of the previous window,
  // and never more days than that window actually holds (comparing "through
  // the 31st" against a 30 day month, or a leap day against February).
  final prevWhole =
      elapsedDaysIn(start: previous.start, end: previous.end, today: today);
  final take = currentDays.length < prevWhole.length
      ? currentDays.length
      : prevWhole.length;
  final prevDays = prevWhole.take(take).toList();

  return totalDoneIn(history: history, habits: habits, days: currentDays) -
      totalDoneIn(history: history, habits: habits, days: prevDays);
}

/// Which weekday someone actually shows up on, and which one they lose.
///
/// The one number on this screen nobody can work out for themselves: a
/// heatmap shows every day equally, so a person who quietly collapses every
/// Thursday can stare at a year of their own history and never see it.
///
/// Averages, not rates. A rate needs a denominator per weekday, and habits
/// scheduled on specific weekdays would make that denominator differ per
/// column, so the "worst" weekday would just be whichever one had the most
/// habits due. An average of green squares per occurrence of that weekday
/// asks the plainer question: how much do you actually get done on Tuesdays.
class WeekdayInsight {
  /// DateTime.monday..DateTime.sunday.
  final int bestWeekday;
  final int worstWeekday;
  final double bestAverage;
  final double worstAverage;

  /// The fewest times any single weekday occurred in the window. One week
  /// gives every weekday exactly one sample, which is a single day wearing
  /// the word "pattern", so [isMeaningful] refuses to call it one.
  final int occurrences;

  const WeekdayInsight({
    required this.bestWeekday,
    required this.worstWeekday,
    required this.bestAverage,
    required this.worstAverage,
    required this.occurrences,
  });

  /// Whether the window is long enough for the word "pattern" to apply at
  /// all. Separate from [isMeaningful] because the two failures need
  /// different sentences: "not enough history yet" and "enough history,
  /// and your days are genuinely even" are opposite situations, and one
  /// message for both told a full year it needed two weeks.
  bool get hasEnoughSamples => occurrences >= 2;

  /// Whether this is worth putting a claim on screen for. Needs enough
  /// samples AND a real gap between the ends: a month where every weekday
  /// averages the same has no best and no worst, and printing one anyway
  /// invents a pattern out of a tie.
  bool get isMeaningful =>
      hasEnoughSamples &&
      bestWeekday != worstWeekday &&
      bestAverage - worstAverage >= 0.5;
}

/// Averages [dayCounts] by weekday across [days].
///
/// Returns null when the window holds no completions at all, so callers
/// render nothing rather than "your best day is Saturday" over an empty
/// month. Ties resolve to the earliest weekday in Saturday-anchored order,
/// so the result is deterministic.
WeekdayInsight? computeWeekdayInsight({
  required Map<String, int> dayCounts,
  required List<DateTime> days,
}) {
  if (days.isEmpty) return null;
  final totals = <int, int>{};
  final counts = <int, int>{};
  var anyGreen = false;
  for (final day in days) {
    final count = dayCounts[day.toDateKey()] ?? 0;
    if (count > 0) anyGreen = true;
    totals[day.weekday] = (totals[day.weekday] ?? 0) + count;
    counts[day.weekday] = (counts[day.weekday] ?? 0) + 1;
  }
  if (!anyGreen || counts.length < 7) return null;

  // Saturday first, matching the Grid and the year strip's rows, so a tie
  // breaks toward the weekday a reader of this app meets first.
  const order = [
    DateTime.saturday,
    DateTime.sunday,
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  ];
  var bestWeekday = order.first;
  var worstWeekday = order.first;
  var bestAvg = -1.0;
  var worstAvg = double.infinity;
  var occurrences = counts.values.first;
  for (final weekday in order) {
    final n = counts[weekday] ?? 0;
    if (n == 0) return null;
    if (n < occurrences) occurrences = n;
    final avg = (totals[weekday] ?? 0) / n;
    if (avg > bestAvg) {
      bestAvg = avg;
      bestWeekday = weekday;
    }
    if (avg < worstAvg) {
      worstAvg = avg;
      worstWeekday = weekday;
    }
  }
  return WeekdayInsight(
    bestWeekday: bestWeekday,
    worstWeekday: worstWeekday,
    bestAverage: bestAvg,
    worstAverage: worstAvg,
    occurrences: occurrences,
  );
}
