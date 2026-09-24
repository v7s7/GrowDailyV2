import '../../core/extensions/datetime_ext.dart';
import '../grid/models/square_state.dart';
import '../habits/catalog/islamic_habit_catalog.dart';
import '../habits/models/habit_day_demand.dart';

/// How a habit asks for its days, which decides what its record can honestly
/// say about it.
///
/// Aziz, 2026-09-18, on the weekday sheet of «الصدقة ولو بالقليل», a Monday
/// and Thursday habit: the sheet drew all seven weekdays, five of them dashes
/// and the two real ones as lone dots, "these kind of habits must have diff
/// shows". The three shapes ask different questions of the same window:
///
///  - [daily] owes every day, so which weekday slips is a real question, and
///    the seven-day wave answers it.
///  - [specificDays] owes only its own weekdays. The other days are not weak
///    days, they are days it never asked for, so its record is its own days
///    and nothing else, each one week by week.
///  - [weeklyQuota] owes a COUNT per week, on no day in particular. Which of
///    its blank days count as owed is decided by arithmetic
///    ([weeklyQuotaDemand]): a day is owed only once skipping it puts the
///    target out of reach, and in a week that falls short those are always
///    the LAST days of the week. Its per-weekday miss rate therefore measures
///    where the week ends, not when the person slips, so it makes no weekday
///    claim at all, and its record is its weeks.
enum InsightCadence {
  daily,
  specificDays,
  weeklyQuota;

  static InsightCadence of(IslamicHabitTemplate habit) {
    if (isFlexibleQuota(habit)) return weeklyQuota;
    final days = habit.scheduledWeekdays.toSet();
    // A list naming all seven days is a daily habit spelled the long way.
    return days.isNotEmpty && days.length < 7 ? specificDays : daily;
  }
}

/// The seven weekdays (DateTime.monday..sunday values) in the order the Grid
/// draws a week, Saturday first today.
///
/// Derived from [DateTimeGameExt.startOfDisplayWeek] rather than written out,
/// for the reason monthGridCells gives: the day this app grows a
/// first-day-of-week setting, the week's order must move in one place.
final List<int> displayWeekOrder = () {
  final start = DateTime(2026, 7, 13).startOfDisplayWeek;
  return List<int>.unmodifiable([
    for (var i = 0; i < 7; i++)
      DateTime(start.year, start.month, start.day + i).weekday,
  ]);
}();

/// What one of a habit's own days in the window came to, as a cell of its
/// record draws it.
enum InsightDayState {
  /// Completed: a green square, or any recorded count.
  done,

  /// Completed, and marked as a bonus on the Grid.
  bonus,

  /// A جزئي on a day that has closed. This engine reads a day as done or not
  /// and has always counted it as not done, which is what a half-filled cell
  /// beside the row's count says: half a day is not a whole one.
  partial,

  /// An explicit فشل.
  failed,

  /// A تخطّي: a rest that was chosen, and leaves the count.
  rest,

  /// Owed, closed, and nothing recorded.
  missed,

  /// Owed, but still open and unanswered (today, or yesterday before
  /// kDayCutoffHour), so not counted yet.
  open,

  /// Not owed at all: a quota's spare or already banked day.
  covered,
}

/// One of a habit's own days inside the window, as [computeInsights] read it.
class InsightDay {
  final DateTime day;

  /// The square as it was recorded, [SquareState.none] when nothing was.
  final SquareState mark;

  /// Completed by this engine's reading: a green square, or any recorded
  /// count (a counted habit part way there included, see [computeInsights]).
  final bool done;

  /// Whether the habit owed this day (see habitOwesDay).
  final bool owed;

  /// Whether the day entered the habit's rate. False for a تخطّي, for a day
  /// still open and unanswered, and for a day that was never owed.
  final bool counted;

  const InsightDay({
    required this.day,
    required this.mark,
    required this.done,
    required this.owed,
    required this.counted,
  });

  InsightDayState get state {
    if (mark == SquareState.skipped) return InsightDayState.rest;
    if (done) {
      return mark == SquareState.bonus
          ? InsightDayState.bonus
          : InsightDayState.done;
    }
    if (!owed) return InsightDayState.covered;
    if (!counted) return InsightDayState.open;
    return switch (mark) {
      SquareState.failed => InsightDayState.failed,
      SquareState.partial => InsightDayState.partial,
      _ => InsightDayState.missed,
    };
  }
}

/// One Saturday week of a weekly quota habit, inside the window.
class QuotaWeek {
  /// The week's first day, as the Grid draws it.
  final DateTime start;

  /// Sessions recorded: the days of the week with a completion, up to today.
  final int done;

  /// Sessions the week asks for.
  final int target;

  /// Whether the habit was alive on all seven days. A week it began, paused
  /// or ended in part-way never asked for the whole [target], so it is drawn
  /// but never scored.
  final bool whole;

  /// Whether the week's answer is final: the target reached, the week
  /// closed, or the target already out of reach (fewer days left than
  /// sessions missing, the rule a room's strip uses to cross a quota week out
  /// before it ends).
  final bool settled;

  const QuotaWeek({
    required this.start,
    required this.done,
    required this.target,
    required this.whole,
    required this.settled,
  });

  bool get met => done >= target;

  /// Whether this week enters the "reached its target in N of M weeks" line.
  bool get scored => whole && settled;
}

/// One habit's aggregated record over the analysis window — scheduled vs
/// completed, overall and per weekday (DateTime.monday..sunday keys).
class HabitPattern {
  final String habitId;

  /// How the habit asks for its days; see [InsightCadence].
  final InsightCadence cadence;

  /// The weekdays this habit runs on, in [displayWeekOrder]: its own days for
  /// [InsightCadence.specificDays], all seven otherwise.
  final List<int> weekdays;

  int scheduled = 0;
  int completed = 0;
  final Map<int, int> scheduledByWeekday = {};
  final Map<int, int> completedByWeekday = {};

  /// Every day in the window this habit was alive on and allowed on, keyed
  /// by dateKey: the cells of its record. Counted or not, so a rest and a
  /// day still open have a cell too. The counted ones ARE [scheduled] and the
  /// done ones among them [completed], so a row of cells and the count
  /// printed beside it cannot disagree.
  final Map<String, InsightDay> record = {};

  /// For [InsightCadence.weeklyQuota]: the window's Saturday weeks, oldest
  /// first. Empty for every other cadence.
  final List<QuotaWeek> quotaWeeks = [];

  HabitPattern(
    this.habitId, {
    this.cadence = InsightCadence.daily,
    List<int>? weekdays,
  }) : weekdays = weekdays ?? displayWeekOrder;

  double get rate => scheduled == 0 ? 0 : completed / scheduled;

  /// The weekday this habit misses most — only meaningful (non-null) when
  /// that weekday has at least [minSamples] scheduled occurrences AND its
  /// miss rate is at least 0.5: below either bar, calling it a "pattern"
  /// would just be noise dressed up as insight.
  ///
  /// Three more bars, all about "most" having to mean something:
  ///  - never for a weekly quota, whose blank days are placed on the end of
  ///    a short week by arithmetic (see [InsightCadence.weeklyQuota]);
  ///  - never with fewer than two weekdays to compare, so a Friday-only habit
  ///    is not said to slip "most on Fridays";
  ///  - for a specific-days habit, never on a tie. Two days level with each
  ///    other is the absence of a weaker day, and naming one would be false.
  ///    A daily habit keeps the first of a tie, as it always has: with seven
  ///    days a shared worst still marks a weak stretch of its week.
  int? worstWeekday({int minSamples = 3}) {
    if (cadence == InsightCadence.weeklyQuota) return null;
    int? worst;
    var worstMissRate = 0.5 - 1e-9;
    var comparable = 0;
    var tied = false;
    for (final e in scheduledByWeekday.entries) {
      if (e.value < minSamples) continue;
      comparable++;
      final missRate = 1 - ((completedByWeekday[e.key] ?? 0) / e.value);
      if (worst != null && (missRate - worstMissRate).abs() < 1e-9) {
        tied = true;
      } else if (missRate > worstMissRate) {
        worstMissRate = missRate;
        worst = e.key;
        tied = false;
      }
    }
    if (comparable < 2) return null;
    if (tied && cadence == InsightCadence.specificDays) return null;
    return worst;
  }

  /// For a weekly quota: how many of its scored weeks reached the target, of
  /// how many, when at most half did. Null otherwise, and for every other
  /// cadence.
  ///
  /// The quota's own version of [worstWeekday]'s bar: at least [minWeeks]
  /// weeks behind it and a shortfall in at least half of them, or it is noise
  /// rather than a pattern.
  ({int met, int weeks})? quotaShortfall({int minWeeks = 3}) {
    if (cadence != InsightCadence.weeklyQuota) return null;
    final scored = quotaWeeks.where((w) => w.scored).toList();
    if (scored.length < minWeeks) return null;
    final met = scored.where((w) => w.met).length;
    return met * 2 <= scored.length ? (met: met, weeks: scored.length) : null;
  }

  /// For a weekly quota: sessions recorded per scored week, on average, or
  /// null before any week is scored. Extra sessions count as they happened,
  /// so a week of five on a target of four lifts it, the way it lifts the
  /// week itself.
  double? get quotaAveragePerWeek {
    final scored = quotaWeeks.where((w) => w.scored).toList();
    if (scored.isEmpty) return null;
    return scored.fold<int>(0, (sum, w) => sum + w.done) / scored.length;
  }

  /// For a weekly quota: the sessions each week asks for. Null otherwise.
  ///
  /// The newest week's, which is the habit's target now: an older week can
  /// carry the target it had before the schedule changed.
  int? get quotaTarget => quotaWeeks.isEmpty ? null : quotaWeeks.last.target;
}

/// Habits ordered for the per-habit rate list: best first, but never on a
/// rate computed from almost nothing.
///
/// A plain `sort by rate` put a habit scheduled once and completed once at
/// the very top on 100% — above one completed 18 times out of 28 — which
/// reads as "your strongest habit" when the honest answer is "one day isn't
/// a rate". Anything under [minSamples] scheduled days sinks below every
/// habit that has a real sample behind it, keeping its row (it's still the
/// user's own data; hiding it would be a worse lie than ranking it low)
/// but stopping it from crowning the list.
///
/// Ties break on volume, so two habits at the same rate order by how much
/// work is actually behind that rate.
///
/// Pure and order-stable — no Riverpod, no Firestore. See
/// test/features/insights/insight_ranking_test.dart.
List<HabitPattern> rankHabitPatterns(
  Iterable<HabitPattern> patterns, {
  int minSamples = 5,
}) {
  final ranked = patterns.toList()
    ..sort((a, b) {
      final aThin = a.scheduled < minSamples;
      final bThin = b.scheduled < minSamples;
      if (aThin != bThin) return aThin ? 1 : -1;
      final byRate = b.rate.compareTo(a.rate);
      return byRate != 0 ? byRate : b.scheduled.compareTo(a.scheduled);
    });
  return ranked;
}

/// Everything the Insights screen renders, distilled from the raw per-day
/// docs. Pure output of [computeInsights].
class InsightsResult {
  /// habitId → its pattern. Only habits with any scheduled day in-window.
  final Map<String, HabitPattern> patterns;

  /// Weekday (DateTime.monday..sunday) with the highest overall completion
  /// rate, or null when there isn't enough data to say.
  final int? strongestWeekday;

  /// Account-wide (every habit combined) scheduled/completed counts per
  /// weekday — the same aggregates [strongestWeekday] is picked from, kept
  /// here too so the "Your strongest day" headline can open a detail view
  /// showing the full week, not just announce the one winning day. Same
  /// DateTime.monday..sunday keys as [HabitPattern.scheduledByWeekday].
  ///
  /// Weekly quotas are left out of both, for the reason
  /// [InsightCadence.weeklyQuota] gives.
  final Map<int, int> overallScheduledByWeekday;
  final Map<int, int> overallCompletedByWeekday;

  /// Highest/lowest completion-rate habits (need >= 7 scheduled samples
  /// each, so a habit added two days ago can't claim either title).
  final String? mostConsistentHabitId;
  final String? needsPushHabitId;

  /// Total scheduled samples across everything — the "is there anything to
  /// analyze at all" signal the empty state keys off.
  final int totalSamples;

  /// The first and the last day the window held (the last is the clock's
  /// day), or null for an empty window. A habit's record is laid out from
  /// these, so it shows exactly the days that were read.
  final DateTime? windowStart;
  final DateTime? windowEnd;

  const InsightsResult({
    required this.patterns,
    required this.strongestWeekday,
    required this.overallScheduledByWeekday,
    required this.overallCompletedByWeekday,
    required this.mostConsistentHabitId,
    required this.needsPushHabitId,
    required this.totalSamples,
    this.windowStart,
    this.windowEnd,
  });
}

/// Aggregates [days] (each day paired with its daily doc — the same
/// squareStates/habitCompletions maps every other history surface reads)
/// against the current habit list. Pure and synchronous: all Firestore/Hive
/// work happens before this is called, so it's trivially unit-testable —
/// see test/features/insights/insight_engine_test.dart.
///
/// "Completed" = a green square (complete/bonus) OR any habitCompletions
/// count > 0 (multi-tap habits never mirror squares — same rule the
/// heatmap's day sheet uses). Skipped squares count as neither completed
/// nor missed: a deliberate skip is a decision, and it shouldn't poison a
/// habit's miss-rate the way a real slip does — so it's excluded from the
/// scheduled total entirely.
///
/// [now] holds back a day still open (see DateTimeGameExt.isSettledAt). The
/// window always includes today, so a blank today counted as a miss from
/// 00:00: it lowered its habit's rate and its weekday's rate, and could name
/// a habit as needing a push before the day had begun. A day counts at once
/// when it is answered by THIS engine's own reading: "completed" as above,
/// or a فشل square. Anything else waits for its day to close.
///
/// That is not the reports' reading for a counted habit part way there (1 of
/// 4). This engine has always called that day completed, and the reports
/// credit it as a جزئي (half, and only once it closes). Holding it out here
/// until 10:00 and then counting it whole would only move the same number
/// to the cutoff, so it counts as completed at once, exactly as before the
/// clock existed. The two screens still value that day differently; that
/// difference predates the open-day rule.
///
/// [now] is required, though nullable, so a screen cannot forget its clock
/// and compile. Null counts every day, as before.
InsightsResult computeInsights({
  required List<IslamicHabitTemplate> habits,
  required List<(DateTime, Map<String, dynamic>)> days,
  required DateTime? now,
}) {
  // One pattern per habit id, shaped by its cadence. allHabitsEverProvider
  // lists a paused-and-resumed habit once per stint, and every stint feeds
  // the same pattern.
  final patterns = <String, HabitPattern>{};
  for (final h in habits) {
    patterns.putIfAbsent(h.id, () {
      final cadence = InsightCadence.of(h);
      return HabitPattern(
        h.id,
        cadence: cadence,
        weekdays: cadence == InsightCadence.specificDays
            ? [
                for (final w in displayWeekOrder)
                  if (h.scheduledWeekdays.contains(w)) w,
              ]
            : null,
      );
    });
  }
  final byId = {for (final h in habits) h.id: h};

  // Which sessions a flexible weekly quota banked, so [habitOwesDay] can tell
  // its rest days from the days it really owed. Without this a 4x-a-week habit
  // was measured against all seven days of every week and could never read
  // above 57%, which named it as the one "needing a push" for doing exactly
  // what it promised.
  //
  // Read from [days] alone, so a week only partly inside the window is missing
  // the sessions that fell outside it and can show an owed day that was really
  // spare. It errs at the window's first week and nowhere else; every whole
  // week in it is exact.
  final greenIdsByDay = <String, Set<String>>{};
  // The marks themselves, for the one question a green cannot answer: whether
  // a planned day a moved session could stand in for was left empty or marked
  // by the person (see moved_day_plan.dart). Same window, same edge.
  final marksByDay = <String, Map<String, SquareState>>{};
  DateTime? windowStart;
  DateTime? windowEnd;
  for (final (day, doc) in days) {
    final states = (doc['squareStates'] as Map?) ?? const {};
    final completions = (doc['habitCompletions'] as Map?) ?? const {};
    greenIdsByDay[day.toDateKey()] = {
      for (final h in habits)
        if (SquareState.fromJson(states[h.id]?.toString()).isGreen ||
            (completions[h.id] is num && (completions[h.id] as num) > 0))
          h.id,
    };
    marksByDay[day.toDateKey()] = {
      for (final h in habits)
        if (states[h.id] != null)
          h.id: SquareState.fromJson(states[h.id]?.toString()),
    };
    final date = DateTime(day.year, day.month, day.day);
    if (windowStart == null || date.isBefore(windowStart)) windowStart = date;
    if (windowEnd == null || date.isAfter(windowEnd)) windowEnd = date;
  }
  bool isGreen(String habitId, DateTime day) =>
      greenIdsByDay[day.toDateKey()]?.contains(habitId) ?? false;
  SquareState markOn(String habitId, DateTime day) =>
      marksByDay[day.toDateKey()]?[habitId] ?? SquareState.none;

  for (final (day, doc) in days) {
    final rawStates = (doc['squareStates'] as Map?) ?? const {};
    final rawCompletions = (doc['habitCompletions'] as Map?) ?? const {};
    for (final h in habits) {
      // Not alive, or not one of its weekdays: not a day of this habit at
      // all, so no cell in its record either. The one exception is a day off
      // a specific-days plan that holds a session: it counts for the week and
      // stands in for one of the habit's own days (see moved_day_plan.dart),
      // so it belongs in the record like any other session.
      if (!h.isScheduledFor(day) &&
          !(h.isAliveOn(day) && isGreen(h.id, day))) {
        continue;
      }
      final p = patterns[h.id]!;
      final sq = SquareState.fromJson(rawStates[h.id]?.toString());
      final done = sq.isGreen ||
          (rawCompletions[h.id] is num &&
              (rawCompletions[h.id] as num) > 0);
      final owed = habitOwesDay(
        habit: h,
        day: day,
        isGreen: isGreen,
        markOn: markOn,
      );
      final counted = owed &&
          sq != SquareState.skipped &&
          (now == null ||
              day.isSettledAt(now, answered: done || sq == SquareState.failed));
      p.record[day.toDateKey()] = InsightDay(
        day: DateTime(day.year, day.month, day.day),
        mark: sq,
        done: done,
        owed: owed,
        counted: counted,
      );
      if (!counted) continue;
      p.scheduled++;
      if (done) p.completed++;
      // The weekday spread is about the days the habit runs on NOW, the ones
      // its sheet has rows for. A day owed under an older schedule still
      // counts in the habit's own rate above, but a Wednesday from before it
      // moved to Monday and Thursday must not be named as its weak day.
      if (!p.weekdays.contains(day.weekday)) continue;
      p.scheduledByWeekday[day.weekday] =
          (p.scheduledByWeekday[day.weekday] ?? 0) + 1;
      if (done) {
        p.completedByWeekday[day.weekday] =
            (p.completedByWeekday[day.weekday] ?? 0) + 1;
      }
    }
  }

  if (windowStart != null && windowEnd != null) {
    _fillQuotaWeeks(
      patterns: patterns,
      habits: habits,
      windowStart: windowStart,
      windowEnd: windowEnd,
      isGreen: isGreen,
      now: now,
    );
  }

  patterns.removeWhere((_, p) => p.scheduled == 0);

  // Overall strongest weekday, across all habits together.
  final weekdayScheduled = <int, int>{};
  final weekdayCompleted = <int, int>{};
  var totalSamples = 0;
  for (final p in patterns.values) {
    totalSamples += p.scheduled;
    // A quota's blank days sit on the end of a short week by arithmetic (see
    // InsightCadence.weeklyQuota), and its early days only ever enter when
    // done, so its weekday spread says where weeks end, not which day is
    // strong. It still counts toward the data floor above.
    if (p.cadence == InsightCadence.weeklyQuota) continue;
    for (final e in p.scheduledByWeekday.entries) {
      weekdayScheduled[e.key] = (weekdayScheduled[e.key] ?? 0) + e.value;
    }
    for (final e in p.completedByWeekday.entries) {
      weekdayCompleted[e.key] = (weekdayCompleted[e.key] ?? 0) + e.value;
    }
  }
  int? strongest;
  // Seeded at 0, not -1. At -1 a rate of 0.0 still beat the seed, so on an
  // account where nothing has been completed the FIRST weekday with enough
  // samples was crowned "your strongest day" at 0%. Seeding at zero means a
  // day has to actually have completions to win, and `strongest` stays null
  // when none does — which the caller already renders as "no insight yet".
  var strongestRate = 0.0;
  for (final e in weekdayScheduled.entries) {
    if (e.value < 4) continue; // too few samples to crown a day
    final rate = (weekdayCompleted[e.key] ?? 0) / e.value;
    if (rate > strongestRate) {
      strongestRate = rate;
      strongest = e.key;
    }
  }

  String? best;
  String? worst;
  // Same fix as strongestRate above: a habit completed zero times must never
  // be announced as the most consistent one. worstRate keeps its high seed —
  // a 0% habit genuinely IS the worst, and that half was always correct.
  var bestRate = 0.0;
  var worstRate = 2.0;
  for (final p in patterns.values) {
    if (p.scheduled < 7 || !byId.containsKey(p.habitId)) continue;
    if (p.rate > bestRate) {
      bestRate = p.rate;
      best = p.habitId;
    }
    if (p.rate < worstRate) {
      worstRate = p.rate;
      worst = p.habitId;
    }
  }
  // A single qualifying habit shouldn't be both the star and the problem.
  if (best != null && best == worst) worst = null;

  return InsightsResult(
    patterns: patterns,
    strongestWeekday: strongest,
    overallScheduledByWeekday: weekdayScheduled,
    overallCompletedByWeekday: weekdayCompleted,
    mostConsistentHabitId: best,
    needsPushHabitId: worst,
    totalSamples: totalSamples,
    windowStart: windowStart,
    windowEnd: windowEnd,
  );
}

/// Every weekly quota's Saturday weeks that START inside the window, oldest
/// first: seven that have ended and the one in progress, since a 56-day
/// window always holds exactly eight Saturdays.
///
/// The days before the window's first Saturday are left out on purpose. They
/// belong to a week whose other days were never read, so its count would be
/// short by whatever happened outside the window.
void _fillQuotaWeeks({
  required Map<String, HabitPattern> patterns,
  required List<IslamicHabitTemplate> habits,
  required DateTime windowStart,
  required DateTime windowEnd,
  required GreenOnDay isGreen,
  required DateTime? now,
}) {
  final stints = <String, List<IslamicHabitTemplate>>{};
  for (final h in habits) {
    (stints[h.id] ??= []).add(h);
  }
  var firstSaturday = windowStart.startOfDisplayWeek;
  if (firstSaturday.isBefore(windowStart)) {
    firstSaturday = DateTime(
      firstSaturday.year,
      firstSaturday.month,
      firstSaturday.day + 7,
    );
  }
  // A day that can still change: after the window (the rest of this week),
  // or still open for marking. Without a clock, only the days after the
  // window, the way computeInsights counts every day it was given.
  bool stillOpen(DateTime day) =>
      now == null ? day.isAfter(windowEnd) : !day.isSettledAt(now);

  for (final p in patterns.values) {
    if (p.cadence != InsightCadence.weeklyQuota) continue;
    final own = stints[p.habitId]!;
    bool alive(DateTime day) => own.any((h) => h.isScheduledFor(day));
    for (var start = firstSaturday;
        !start.isAfter(windowEnd);
        start = DateTime(start.year, start.month, start.day + 7)) {
      final week = [
        for (var i = 0; i < 7; i++)
          DateTime(start.year, start.month, start.day + i),
      ];
      // Each week asks for the target it had then (every stint carries the
      // same schedule history, so any of them answers). A week that was not
      // one quota from Saturday to Friday, because the schedule changed in
      // it or before it, never asked for a whole week's target and is drawn
      // but never scored, the same as a week the habit only lived part of.
      final cadences = [for (final d in week) own.first.cadenceOn(d)];
      final oneQuota = cadences.first.isFlexibleQuota &&
          cadences.every((c) => c.sameAs(cadences.first));
      final quotaDays = cadences.where((c) => c.isFlexibleQuota);
      // weeklyQuotaDemand clamps the same way, so a week never asks for more
      // days than it has.
      final target = (quotaDays.isEmpty
              ? own.first.frequencyTarget
              : quotaDays.last.frequencyTarget)
          .clamp(1, 7);
      final done = week
          .where((d) => !d.isAfter(windowEnd) && isGreen(p.habitId, d))
          .length;
      final spendable = week
          .where((d) => alive(d) && !isGreen(p.habitId, d) && stillOpen(d))
          .length;
      p.quotaWeeks.add(
        QuotaWeek(
          start: start,
          done: done,
          target: target,
          whole: oneQuota && week.every(alive),
          settled: done >= target ||
              !stillOpen(week.last) ||
              done + spendable < target,
        ),
      );
    }
  }
}
