import '../../../core/extensions/datetime_ext.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart' show startOfGridWeek;
import '../../habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitTemplate;
import '../../grid/models/square_state.dart';
import '../../habits/models/habit_day_demand.dart' show movedDemandOn;
import '../../habits/models/habit_model.dart' show HabitFrequencyType;
import '../../habits/models/weekly_quota_plan.dart'
    show DayDemand, weeklyQuotaDemand;
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

/// [missIsAttributable] for the schedule [habit] had on [day] (see
/// IslamicHabitTemplate.cadenceOn), which is what every question about one
/// day has to ask: a habit that was four times a week until Tuesday and is
/// daily since owes Tuesday by the day and the Monday before it by the week.
bool missIsAttributableOn(IslamicHabitTemplate habit, DateTime day) =>
    !habit.cadenceOn(day).isFlexibleQuota;

int expectedCompletions({
  required IslamicHabitTemplate habit,
  required List<DateTime> days,
  Set<String> restDays = const {},

  /// The habit's recorded marks, by dateKey. Read only when [now] is given,
  /// to tell an answered open day (done, or فشل) from one still in progress.
  Map<String, SquareState> marks = const {},

  /// Every mark the habit has, inside the window or not; [marks] when null.
  /// Read only for the week its schedule changed in, whose quota days are
  /// judged against the whole Saturday week's sessions (see "The week a
  /// schedule changed in" below).
  Map<String, SquareState>? allMarks,

  /// The wall clock. Null keeps the older reading, in which every elapsed
  /// day counts from the moment it begins; see "still open" below.
  DateTime? now,

  /// The report window's last day, which runs past [days] while the window
  /// is still in progress. A quota week that is still running needs its
  /// remaining days to know how many sessions can still fit. Ignored when
  /// [now] is null.
  DateTime? windowEnd,
}) {
  if (days.isEmpty) return 0;
  // ── Still open ───────────────────────────────────────────────────────
  // Aziz, 2026-09-11, on a monthly card reading «2 يوم 18%» at 05:19: the
  // 11th, still open, was already counted as a miss. A day stays markable
  // until kDayCutoffHour the next morning, so until then a blank or جزئي day
  // is in progress and owes nothing yet. It enters the moment it is answered
  // (done, or فشل) or the moment it closes, whichever comes first, and a
  // blank day that closes counts as missed exactly as it always did. See
  // DateTimeGameExt.isSettledAt.
  bool settled(DateTime day) =>
      now == null ||
      day.isSettledAt(
        now,
        answered: (marks[day.toDateKey()] ?? SquareState.none).answersDay,
      );
  // ── By the day ───────────────────────────────────────────────────────
  // Every day whose own schedule was daily or specific days. Each day asks
  // the schedule it had (isScheduledFor reads IslamicHabitTemplate.
  // pastCadences), so a Monday-and-Thursday habit made daily this week keeps
  // last week's Tuesday out of the count, where it always was.
  var count = 0;
  for (final day in days) {
    if (!missIsAttributableOn(habit, day)) continue;
    // A day marked تخطّي leaves the denominator entirely. This one line is
    // the arithmetic finally agreeing with the app's own position that a
    // rest day is not a missed day: before it, choosing to rest lowered
    // your percentage exactly as much as forgetting would have.
    if (restDays.contains(day.toDateKey())) continue;
    // A specific-days week holding a session off its plan: the planned day
    // that session stands in for leaves the count, and the session itself
    // enters it on its own day, on both sides (see moved_day_plan.dart), so
    // one week's spare session can never pad another week's real miss. Read
    // over every mark, so a week cut by the window's edge still sees the
    // sessions on its far side.
    final moved = movedDemandOn(
      habit: habit,
      day: day,
      isGreen: (_, d) =>
          ((allMarks ?? marks)[d.toDateKey()] ?? SquareState.none).isGreen,
      markOn: (_, d) => (allMarks ?? marks)[d.toDateKey()] ?? SquareState.none,
      now: now,
    );
    final owes = moved == null ? habit.isScheduledFor(day) : !moved.isRest;
    if (owes && settled(day)) count++;
  }
  // Quota habits are counted per Saturday-anchored week: a week the habit
  // was alive for only two days can never owe three completions, so the
  // target is clamped to the days actually available in that week.
  //
  // A week still running owes the sessions it has already finished, plus
  // every session that can no longer fit in the days it has left:
  //
  //   owed = min(T, max(G, T - S))
  //
  // T is that clamped target, G the settled days finished in full (green),
  // S the days not yet settled (still open, or still to come). G counts
  // greens only. A جزئي that has closed still earns its half
  // (HabitPeriodStat.creditedUnits), but it is not a finished session:
  // counted as one, it made the week owe a whole session more for half a
  // session's credit, so a 3x week with Saturday done read 75% with a closed
  // جزئي Sunday and 100% with a blank one. Its half now sits on top of what
  // is owed, where the rate stops at 100%, the reading a week that can still
  // reach its target already gets with nothing on Sunday. It is the reachability
  // RoomParticipant.quotaWeekIsLost crosses a room's week out on, so a blank
  // 4x week starts owing on the morning its fourth blank day closes: not on
  // its first morning, and not only once Friday is over. A closed week has
  // S = 0 and owes T, exactly the old clamp, and so does every week when
  // [now] is null.
  //
  // The week is only ever the part of it inside the report window. A week a
  // month edge cuts (Sat 26 Sep to Fri 2 Oct, read on the October card) is
  // judged on its in-window days alone, so it can owe a session the real
  // Saturday-to-Friday week could still fit on the days outside the window.
  // That clamp predates the open-day rule, and the reachability claim above
  // holds only for a week the window contains whole.
  final walk = <DateTime>[
    for (final day in days)
      if (!missIsAttributableOn(habit, day)) day,
  ];
  if (now != null && windowEnd != null) {
    final last = days.last;
    for (var d = DateTime(last.year, last.month, last.day + 1);
        !d.isAfter(windowEnd);
        d = DateTime(d.year, d.month, d.day + 1)) {
      if (!missIsAttributableOn(habit, d)) walk.add(d);
    }
  }
  if (walk.isEmpty) return count;

  // ── The week a schedule changed in ───────────────────────────────────
  // The whole-week count below assumes the week ran on ONE quota from
  // Saturday to Friday. A week the schedule changed in did not: four a week
  // until Tuesday and daily after it, say. Its daily days are already counted
  // above, and its quota days are judged one by one with the day-local rule
  // the Grid paints them by (weeklyQuotaDemand, each day with the target it
  // had): a day owes once skipping it put the week out of reach, and every
  // session of the week counts toward the target, the ones logged under the
  // other schedule included. Squeezing the target into the three quota days
  // instead, the way a habit born mid-week is clamped, would have made all
  // three owed, for a week nobody had fallen behind in. A habit that never
  // changed schedule has no such week and skips all of this.
  final changedWeeks = <String>{};
  if (habit.pastCadences.isNotEmpty) {
    final seen = <String>{};
    for (final day in walk) {
      final start = startOfGridWeek(day);
      if (!seen.add(start.toDateKey())) continue;
      final first = habit.cadenceOn(start);
      for (var i = 1; i < 7; i++) {
        final other = habit.cadenceOn(
          DateTime(start.year, start.month, start.day + i),
        );
        if (!other.sameAs(first)) {
          changedWeeks.add(start.toDateKey());
          break;
        }
      }
    }
  }
  var dayByDay = 0;
  final weekMarks = allMarks ?? marks;
  for (final day in walk) {
    final start = startOfGridWeek(day);
    if (!changedWeeks.contains(start.toDateKey())) continue;
    final dayKey = day.toDateKey();
    if (restDays.contains(dayKey)) continue;
    if (!habit.isScheduledFor(day) || !settled(day)) continue;
    if (markIsDone(marks[dayKey] ?? SquareState.none)) {
      dayByDay++;
      continue;
    }
    final index = DateTime.utc(day.year, day.month, day.day)
        .difference(DateTime.utc(start.year, start.month, start.day))
        .inDays;
    final demand = weeklyQuotaDemand(
      dayCount: 7,
      doneDays: {
        for (var i = 0; i < 7; i++)
          if (markIsDone(weekMarks[DateTime(
                      start.year, start.month, start.day + i)
                  .toDateKey()] ??
              SquareState.none))
            i,
      },
      target: habit.cadenceOn(day).frequencyTarget,
    )[index];
    if (demand == DayDemand.owed) dayByDay++;
  }

  final alivePerWeek = <String, int>{};
  final finishedPerWeek = <String, int>{};
  final stillOpenPerWeek = <String, int>{};
  final targetPerWeek = <String, int>{};
  for (final day in walk) {
    final dayKey = day.toDateKey();
    if (restDays.contains(dayKey)) continue;
    if (!habit.isScheduledFor(day)) continue;
    final key = startOfGridWeek(day).toDateKey();
    if (changedWeeks.contains(key)) continue;
    // One quota the whole week, so any of its days names the target: the
    // habit's own for a week before any change, the one it had then for a
    // week after one.
    targetPerWeek[key] ??= habit.cadenceOn(day).frequencyTarget;
    alivePerWeek[key] = (alivePerWeek[key] ?? 0) + 1;
    if (!settled(day)) {
      stillOpenPerWeek[key] = (stillOpenPerWeek[key] ?? 0) + 1;
    } else if (markIsDone(marks[dayKey] ?? SquareState.none)) {
      finishedPerWeek[key] = (finishedPerWeek[key] ?? 0) + 1;
    }
  }
  var total = 0;
  for (final entry in alivePerWeek.entries) {
    final alive = entry.value;
    final weekTarget = targetPerWeek[entry.key]!;
    final target = alive < weekTarget ? alive : weekTarget;
    final finished = finishedPerWeek[entry.key] ?? 0;
    final cannotFit = target - (stillOpenPerWeek[entry.key] ?? 0);
    final owed = finished > cannotFit ? finished : cannotFit;
    total += owed < target ? owed : target;
  }
  return count + dayByDay + total;
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

    /// The wall clock. When given, a day still open adds credit only once it
    /// is answered, the rule [expectedCompletions] applies to the
    /// denominator: a جزئي on a day still being lived is held out of both
    /// sides until it is finished or the day closes, so marking half of today
    /// can never pull a percentage down. Null credits every mark.
    DateTime? now,
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
      if (now == null) {
        credit += markCredit(mark);
      } else {
        final day = DateTime.tryParse(entry.key);
        if (day == null || day.isSettledAt(now, answered: mark.answersDay)) {
          credit += markCredit(mark);
        }
      }
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

  /// Whether the period owed anything yet, which is whether [rate] means
  /// anything. False for a habit created today and not yet done, and for a
  /// period whose only due days are still open and unanswered: the cards
  /// print a placeholder then, never a 0% nobody has earned.
  bool get hasRate => expected > 0;

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
/// A habit with a start date the record can count from.
///
/// A preset switched on before switch-on days were kept has no `createdAt`,
/// and [IslamicHabitTemplate.isScheduledFor] reads a habit with no start as
/// alive forever: owed, and missed, on every day of any window. So «سنة»
/// counted such a habit from 1 January, months before it was ever done,
/// while «الكل» counted it from the record's first square, and one record
/// read 28% on one tab and 52% on the other (Aziz's account, 2026-09-21;
/// الصدقة ولو بالقليل is one of these presets).
///
/// So a habit with no known start begins on the first day it recorded
/// anything, and one that has recorded nothing begins [today], claiming no
/// past at all. The squares already followed this rule (cellStatesByWeek);
/// every rate now does too, since every rate is counted through
/// [computeHabitPeriodStats], and Insights applies it to its own list.
///
/// For counting only. isScheduledFor itself is left alone, because streaks,
/// reminders and rooms read it too.
IslamicHabitTemplate habitWithKnownStart(
  IslamicHabitTemplate habit,
  Map<String, SquareState> allMarks, {
  required DateTime today,
}) {
  if (habit.createdAt != null) return habit;
  String? firstKey;
  for (final key in allMarks.keys) {
    if (firstKey == null || key.compareTo(firstKey) < 0) firstKey = key;
  }
  // withDates, not withCreatedAt: the latter drops archivedAt, and an
  // archived habit's days after it was put away would then read as alive.
  return habit.withDates(
    createdAt: (firstKey == null ? null : DateTime.tryParse(firstKey)) ??
        DateTime(today.year, today.month, today.day),
    archivedAt: habit.archivedAt,
  );
}

/// Where the whole record begins: the earlier of its first square and the
/// first day any habit was owed, so «الكل» counts every habit from its own
/// start exactly as a year does, and the two agree on a record that fits in
/// one year. Habits here must already have a known start (see
/// [habitWithKnownStart]); null for a record with neither.
DateTime? recordStartOf(
  Iterable<IslamicHabitTemplate> habits,
  DateTime? firstMark,
) {
  DateTime? start = firstMark == null
      ? null
      : DateTime(firstMark.year, firstMark.month, firstMark.day);
  for (final h in habits) {
    final born = h.createdAt;
    if (born == null) continue;
    final day = DateTime(born.year, born.month, born.day);
    if (start == null || day.isBefore(start)) start = day;
  }
  return start;
}

List<HabitPeriodStat> computeHabitPeriodStats({
  required List<IslamicHabitTemplate> habits,
  required Map<String, Map<String, SquareState>> history,
  required List<DateTime> days,

  /// The wall clock and the window's last day; see [expectedCompletions].
  /// Both null keep the older every-elapsed-day reading.
  ///
  /// Required, though nullable, so every caller has to choose. Left
  /// optional, a screen that forgot to pass its clock compiled and quietly
  /// printed the old number: Aziz's «2 يوم 18%» at 05:19 would come back
  /// with every pure test still green.
  required DateTime? now,
  required DateTime? windowEnd,
}) {
  final windowKeys = {for (final d in days) d.toDateKey()};
  final out = <HabitPeriodStat>[];
  // The day a habit that has recorded nothing is said to begin (see
  // habitWithKnownStart): the live day when there is a clock, else the
  // window's end.
  final today = now?.effectiveDay ??
      windowEnd ??
      (days.isEmpty ? DateTime.now().effectiveDay : days.last);
  for (final raw in habits) {
    final all = history[raw.id] ?? const <String, SquareState>{};
    final habit = habitWithKnownStart(raw, all, today: today);
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
    final expected = expectedCompletions(
      habit: habit,
      days: days,
      restDays: restDays,
      marks: marks,
      allMarks: all,
      now: now,
      windowEnd: windowEnd,
    );
    // Dropped only when the habit had nothing to do with this window at all.
    // Asked of the schedule, not of [expected], which is legitimately 0 for
    // a live habit whose only due days are still open: judged on that, a
    // blank habit's card vanished between midnight and 10:00 on the first
    // day of every week and month, beside another habit already green.
    if (marks.isEmpty && !days.any(habit.isScheduledFor)) continue;
    out.add(
      HabitPeriodStat(
        habit: habit,
        marks: marks,
        expected: expected,
        now: now,
      ),
    );
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

  /// What every habit in the window earned, summed: each habit's
  /// [HabitPeriodStat.creditedUnits], so a جزئي is worth half and one on a
  /// day still open waits, exactly as on the cards. [rate]'s numerator;
  /// [totalDone] stays a count of green squares, for the headline.
  final double creditedTotal;

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
    required this.creditedTotal,
    required this.bestDay,
    required this.bestDayCount,
    required this.activeDays,
    required this.longestRun,
  });

  /// 0..1: credit over what was owed, both summed across the window's
  /// habits, so a report holding one habit reads what that habit's card
  /// reads. It used to divide [totalDone]: two greens and a جزئي in five owed
  /// days read 40% above a card reading 50%. Aziz, 2026-09-11, asked whether
  /// جزئي counts as half here too: "yes".
  ///
  /// Only the total is capped, for the reason [HabitPeriodStat.rate] is. No
  /// habit is capped before the sum, as when this counted green squares.
  double get rate => expectedTotal == 0
      ? 0
      : (creditedTotal / expectedTotal).clamp(0.0, 1.0).toDouble();

  bool get hasAnything => totalDone > 0;

  /// Whether anything was owed yet, which is whether [rate] means anything.
  /// See [HabitPeriodStat.hasRate].
  bool get hasRate => expectedTotal > 0;

  /// This summary with «أفضل يوم» replaced, for a tab that judges its best
  /// day on how full each day was (see [dayExtremes]) rather than on the
  /// raw count this summary picked it by.
  PeriodSummary withBestDay(DateTime? day, int count) => PeriodSummary(
        totalDone: totalDone,
        expectedTotal: expectedTotal,
        creditedTotal: creditedTotal,
        bestDay: day,
        bestDayCount: count,
        activeDays: activeDays,
        longestRun: longestRun,
      );
}

/// A window's best and weakest days, judged on how FULL each day was: what
/// was done against what the day asked for, the same two numbers a month
/// calendar cell is drawn from.
///
/// Aziz's rule, 2026-09-22: the fullest day is the best; between equally
/// full days the one with more habits wins (a full 8 of 8 over a full 7 of
/// 7); days still equal after that all share the mark. It replaced a
/// weekday card on the month page, which named a weekday ("الاثنين") where
/// a month is read in dates.
///
/// The weakest mirrors it: the emptiest day, only among days that have
/// closed (a day still being lived is not a weak day, see
/// DateTimeGameExt.isSettledAt) and that asked for something; between
/// equally empty days the one that asked for more; still equal, all of
/// them. There is no weakest when it would be as full as the best, so a
/// month of full days names no weak day.
///
/// A day that asked for nothing is never a weak day. Work done on it anyway
/// reads full, exactly as its calendar cell draws it (dayFill), so it can be
/// a best day, counted by the habits done on it. Returned in date order.
({List<DateTime> best, List<DateTime> weakest}) dayExtremes({
  required Iterable<DateTime> days,
  required int Function(DateTime day) doneOn,
  required int Function(DateTime day) owedOn,
  required bool Function(DateTime day) settledOn,
}) {
  // Fractions compared by cross-multiplying, never as doubles: 2 of 6 and
  // 1 of 3 are equally full and must tie, exactly.
  int fuller(({int done, int owed}) a, ({int done, int owed}) b) =>
      (a.done * b.owed).compareTo(b.done * a.owed);
  final best = <DateTime>[];
  final weakest = <DateTime>[];
  ({int done, int owed})? top;
  ({int done, int owed})? bottom;
  for (final day in days) {
    final owedRaw = owedOn(day);
    final doneRaw = doneOn(day);
    if (owedRaw <= 0 && doneRaw <= 0) continue;
    // Nothing owed but something done: a full day of what was done.
    final owed = owedRaw > 0 ? owedRaw : doneRaw;
    final cell = (done: doneRaw.clamp(0, owed).toInt(), owed: owed);
    if (cell.done > 0) {
      final c = top == null ? 1 : fuller(cell, top);
      if (c > 0 || (c == 0 && cell.done > top!.done)) {
        top = cell;
        best
          ..clear()
          ..add(day);
      } else if (c == 0 && cell.done == top!.done) {
        best.add(day);
      }
    }
    if (owedRaw > 0 && settledOn(day)) {
      final c = bottom == null ? -1 : fuller(cell, bottom);
      if (c < 0 || (c == 0 && cell.owed > bottom!.owed)) {
        bottom = cell;
        weakest
          ..clear()
          ..add(day);
      } else if (c == 0 && cell.owed == bottom!.owed) {
        weakest.add(day);
      }
    }
  }
  if (top != null && bottom != null && fuller(bottom, top) >= 0) {
    weakest.clear();
  }
  return (best: best, weakest: weakest);
}

/// Summarises one window from [dayCounts] (see [dayCountsFrom]) plus the
/// per-habit denominators and credit.
PeriodSummary computePeriodSummary({
  required Map<String, int> dayCounts,
  required List<DateTime> days,
  required List<HabitPeriodStat> habitStats,

  /// The wall clock. When given, a blank day still open neither breaks the
  /// longest run nor extends it: at 05:00 a green 9th, a still-open 10th and
  /// a green 11th read as a run of 2, and as 1 once the 10th closes blank.
  /// Required, though nullable, for the reason [computeHabitPeriodStats]
  /// gives.
  required DateTime? now,
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
      if (now != null && !day.isSettledAt(now)) continue;
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
  // Both sides of the rate are read off the cards' own stats, never
  // re-derived here, so they cover the same days at the same clock: the free
  // floor and a جزئي still open are already settled in [habitStats].
  var expected = 0;
  var credited = 0.0;
  for (final stat in habitStats) {
    expected += stat.expected;
    credited += stat.creditedUnits;
  }
  return PeriodSummary(
    totalDone: total,
    expectedTotal: expected,
    creditedTotal: credited,
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
/// 3. A DAY STILL OPEN CANNOT COUNT AGAINST ITSELF. At 05:00 today holds
///    only the greens finished so far, and it was compared with the whole of
///    the same day last period, so every morning opened on a deficit. A day
///    still open (DateTimeGameExt.isSettledAt) now takes its partner at most
///    at its own count: it can raise the change, never lower it, and it is
///    compared in full from the moment it closes.
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

  /// The wall clock, for rule 3. Null compares every day in full. Required,
  /// though nullable, for the reason [computeHabitPeriodStats] gives.
  required DateTime? now,
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

  final currentCounts =
      _doneCountsByDay(history: history, habits: habits, days: currentDays);
  final previousCounts =
      _doneCountsByDay(history: history, habits: habits, days: prevDays);
  var delta = 0;
  for (var i = 0; i < currentDays.length; i++) {
    final current = currentCounts[currentDays[i].toDateKey()] ?? 0;
    delta += current;
    if (i >= prevDays.length) continue;
    var previous = previousCounts[prevDays[i].toDateKey()] ?? 0;
    if (now != null &&
        !currentDays[i].isSettledAt(now) &&
        previous > current) {
      previous = current;
    }
    delta -= previous;
  }
  return delta;
}

/// [totalDoneIn], kept per day, so [periodDelta] can pair each day with its
/// partner in the previous period. Same counting rule, same source.
Map<String, int> _doneCountsByDay({
  required Map<String, Map<String, SquareState>> history,
  required List<IslamicHabitTemplate> habits,
  required List<DateTime> days,
}) {
  final keys = {for (final d in days) d.toDateKey()};
  final out = <String, int>{};
  for (final habit in habits) {
    final marks = history[habit.id] ?? const <String, SquareState>{};
    for (final entry in marks.entries) {
      if (keys.contains(entry.key) && markIsDone(entry.value)) {
        out[entry.key] = (out[entry.key] ?? 0) + 1;
      }
    }
  }
  return out;
}

/// [days] without the ones still open at [now] (see
/// DateTimeGameExt.isSettledAt).
///
/// For averages with no denominator to hold a day out of. The weekday
/// rhythm card averages greens per occurrence of each weekday, so a Friday
/// read at 05:00 was a whole Friday sample holding five hours of work, and
/// it pulled every Friday down with it. The card's bars and its sentence
/// both read this one list, so they describe the same days.
List<DateTime> settledDaysAt({
  required List<DateTime> days,
  required DateTime now,
}) =>
    [
      for (final day in days)
        if (day.isSettledAt(now)) day,
    ];

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
