/// One day, scored: how much of what that day actually asked for got done.
///
/// ── Why this exists ────────────────────────────────────────────────────
/// The 14-day chart on ProgressHubScreen used to plot `_completionCount`,
/// the sum of a daily document's `habitCompletions` map. That is a TAP
/// count, not a score, and it made the chart the one history surface in the
/// app that could print a different total than every other one for the same
/// day: a habit finished by painting a green square on the Grid (no
/// completion recorded) contributed 0, while a habit with a target of four,
/// tapped four times, contributed 4. Cross-checked on a real account over
/// 29 Aug - 4 Sep the chart summed to 13 for a week the reports hub read as
/// 12. Same account, same seven days, two answers.
///
/// Everything here counts HABIT-DAYS off the `habit_history` mirror through
/// [markCredit], which is the same rule the reports hub, the monthly heatmap
/// and the year strip already use, so the four surfaces cannot drift.
///
/// ── What "owed" means, and what it cannot mean ─────────────────────────
/// The denominator is a PRESENT-TENSE RECONSTRUCTION, not a record. The app
/// keeps no schedule history on the personal side: `frequencyType`,
/// `frequencyTarget` and `scheduledWeekdays` are flat current-value fields
/// with no effective-from date, so changing a habit from "Mon and Thu" to
/// "Mon, Wed, Fri" today retroactively moves every past Wednesday into the
/// denominator and every past Thursday out of it. [IslamicHabitTemplate
/// .isScheduledFor] is date-aware about EXISTENCE only (createdAt bounds
/// the start, archivedAt the end), which is what keeps a habit out of the
/// denominator on days before it was created. Rooms already solved the full
/// problem with a dated rule list (RoomHabitRule.from, ruleFor), and nothing
/// equivalent exists here; it could only ever be built forward from the day
/// it ships.
///
/// A HARD-DELETED habit is gone from allHabitsEverProvider entirely, so its
/// past days leave both sides of the ratio. That is deliberate and long
/// documented (monthly_heatmap_screen.dart records an account with 24
/// orphaned ids), not an accident here.
library;

import '../../../core/extensions/datetime_ext.dart';
import '../../grid/models/square_state.dart';
import '../../habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitTemplate;
import 'habit_day_marks.dart';
import 'report_period.dart' show missIsAttributable;

/// What one day asked for and what it got.
///
/// [done] and [credit] are deliberately two numbers rather than one: [done]
/// is the integer the chart prints and the day sheet repeats, and it is
/// byte-identical to what `dayCountsFrom` produces, while [credit] carries
/// جزئي at 0.5 and is what the bar height and the fortnight rate are built
/// from. Printing [credit] instead would put "6.5" on a chart no other
/// surface in the app can produce, and printing [done] while scaling by
/// [done] would silently drop every half day.
class DayScore {
  final DateTime day;

  /// Habits finished that day: مكتمل or إنجاز إضافي only.
  final int done;

  /// Weighted achievement: complete/bonus 1, جزئي 0.5, everything else 0.
  ///
  /// Never [SquareState.xpValue], which is economy money and pays فشل -3;
  /// a weighted numerator built from it could go below zero.
  final double credit;

  /// How many habits this day is answerable for. See the library comment
  /// for the one thing this number cannot know.
  final int owed;

  /// Habits explicitly marked فشل. Counted against the day (they stay in
  /// [owed]) and surfaced separately so the chart can mark them.
  final int failed;

  /// Habits explicitly marked تخطّي. These leave [owed] entirely, which is
  /// the whole point of the state: the app's position is that a rest day is
  /// not a missed day.
  final int rested;

  /// Whether the day was still open when it was scored (see
  /// DateTimeGameExt.isOpenDayAt). An open day's [owed] and [credit] are its
  /// progress so far: the right picture for the chart and the day sheet, and
  /// the wrong input for anything that judges the day.
  final bool isOpen;

  final int? _settledOwed;
  final double? _settledCredit;

  const DayScore({
    required this.day,
    required this.done,
    required this.credit,
    required this.owed,
    required this.failed,
    required this.rested,
    int? settledOwed,
    double? settledCredit,
    this.isOpen = false,
  })  : _settledOwed = settledOwed,
        _settledCredit = settledCredit;

  /// The part of [owed] that can already be judged: every habit on a closed
  /// day, and on a day still open only the habits already answered (done, or
  /// فشل). A blank or جزئي habit on an open day is still in progress and
  /// waits for the day to close. Falls back to [owed] for a score built
  /// without a clock.
  int get settledOwed => _settledOwed ?? owed;

  /// The credit that goes with [settledOwed]. An open جزئي adds nothing until
  /// it is finished or its day closes, so marking half of today can never
  /// pull a rate down. Falls back to [credit].
  double get settledCredit => _settledCredit ?? credit;

  /// Whether the day is still open with something on it not yet answered: a
  /// blank or جزئي habit that can still be finished before kDayCutoffHour.
  /// Such a day is in progress, so nothing may judge it yet: [windowRate]
  /// leaves that part of it out, progressTrendLine leaves the whole day out,
  /// and while nothing on it is done yet the chart draws it as a quiet dot
  /// with no line running down to it (DayScoreLinePainter.lineRuns). A day
  /// whose every habit is answered is not pending even while it is open.
  bool get isPending => isOpen && settledOwed < owed;

  /// Null when the day asked for nothing, which is NOT the same as 0%.
  /// A caller that renders `rate ?? 0` reintroduces exactly the lie this
  /// return type exists to prevent: a Wednesday for a Mon/Thu-only habit
  /// set, or a day before the first habit existed, scored as a total
  /// failure.
  double? get rate =>
      owed <= 0 ? null : (credit / owed).clamp(0.0, 1.0).toDouble();

  /// Everything the day owed, discharged. Requires a real obligation, so an
  /// empty day never reads as perfect.
  bool get isPerfect => owed > 0 && credit >= owed;

  /// A day that asked for nothing AND recorded nothing. Drawn as absence,
  /// never as a zero. Distinct from a rest day, which asked for nothing
  /// because someone chose to stand down and therefore earns a mark.
  bool get isSilent => owed == 0 && rested == 0;
}

/// Scores one day against the habits that were alive on it.
///
/// [habits] is `allHabitsEverProvider` UNDEDUPED. That provider emits one
/// synthetic template per catalog stint, each carrying its own
/// createdAt/archivedAt window, so a habit that was paused and resumed is
/// several templates sharing one id. Deduping by id first (which the reports
/// hub does, at period_report_section.dart:297-301) keeps whichever stint
/// comes out first and drops the rest, and every day belonging to a dropped
/// stint then falls outside `isScheduledFor` and quietly leaves the
/// denominator. Collecting ids into a Set instead lets EVERY stint claim its
/// own days, and the Set collapses the duplicates for free.
///
/// [history] is the `habit_history` mirror with today already overlaid via
/// [withLiveToday]. Passing the raw mirror here is a bug, not a shortcut:
/// the mirror is a cache written by three fire-and-forget writers and is
/// never authoritative for today.
DayScore dayScoreFor({
  required Iterable<IslamicHabitTemplate> habits,
  required Map<String, Map<String, SquareState>> history,
  required DateTime day,

  /// The wall clock. When given, the score also carries [DayScore.isOpen]
  /// and the settled numbers the window rate is built from. Null scores
  /// every day as closed.
  DateTime? now,
}) {
  final key = day.toDateKey();
  final everyId = <String>{};
  final dueIds = <String>{};
  for (final habit in habits) {
    everyId.add(habit.id);
    // missIsAttributable is what keeps a quota habit ("three times a week,
    // any three") out of a PER-DAY denominator: nobody owed Tuesday in
    // particular, so a blank Tuesday is not a miss. Sharing the predicate
    // with expectedCompletions is what stops this file and the reports hub
    // disagreeing about which habits have day-level obligations.
    if (missIsAttributable(habit) && habit.isScheduledFor(day)) {
      dueIds.add(habit.id);
    }
  }

  var done = 0;
  var failed = 0;
  var rested = 0;
  var owed = 0;
  var credit = 0.0;
  var settledOwed = 0;
  var settledCredit = 0.0;

  for (final id in everyId) {
    final mark = history[id]?[key] ?? SquareState.none;
    if (markIsRest(mark)) {
      rested++;
      continue;
    }
    final earned = markCredit(mark);
    // Credit is checked BEFORE the due check on purpose. A quota habit that
    // was actually done adds 1 to both sides, so it can only ever pull the
    // day up; leaving it out of the denominator would let a 3-of-2 day
    // exist. An explicit فشل also enters, because someone who marked a
    // failure is telling the app that day was owed. A blank quota day
    // enters neither side, which is the case missIsAttributable exists for.
    final counts = earned > 0 || mark == SquareState.failed || dueIds.contains(id);
    if (!counts) continue;
    owed++;
    credit += earned;
    if (markIsDone(mark)) done++;
    if (mark == SquareState.failed) failed++;
    // The still-open rule every report percentage follows: an answered habit
    // (done, or فشل) settles at once, anything else waits for its day to
    // close. See DateTimeGameExt.isSettledAt.
    if (now == null || day.isSettledAt(now, answered: mark.answersDay)) {
      settledOwed++;
      settledCredit += earned;
    }
  }

  return DayScore(
    day: day,
    done: done,
    credit: credit,
    owed: owed,
    failed: failed,
    rested: rested,
    settledOwed: settledOwed,
    settledCredit: settledCredit,
    isOpen: now != null && day.isOpenDayAt(now),
  );
}

/// [dayScoreFor] across a window, in the order [days] came in.
///
/// [now] is required, though nullable, so a screen cannot forget its clock
/// and compile: without it every open day scores as closed, and the rate
/// under the chart counts an untouched today as a miss again.
List<DayScore> computeDayScores({
  required Iterable<IslamicHabitTemplate> habits,
  required Map<String, Map<String, SquareState>> history,
  required List<DateTime> days,
  required DateTime? now,
}) =>
    [
      for (final day in days)
        dayScoreFor(habits: habits, history: history, day: day, now: now),
    ];

/// The habits that owed [day] and recorded nothing at all.
///
/// This is what makes "4 من 10" itemisable one tap below the chart: without
/// it the denominator is a number the reader has to take on faith. Built
/// from the SAME dueIds rule the score is, so the list length and the
/// fraction can never disagree.
List<IslamicHabitTemplate> silentHabitsOn({
  required Iterable<IslamicHabitTemplate> habits,
  required Map<String, Map<String, SquareState>> history,
  required DateTime day,
}) {
  final key = day.toDateKey();
  final out = <IslamicHabitTemplate>[];
  final seen = <String>{};
  for (final habit in habits) {
    if (!missIsAttributable(habit) || !habit.isScheduledFor(day)) continue;
    if (!seen.add(habit.id)) continue;
    final mark = history[habit.id]?[key] ?? SquareState.none;
    if (mark != SquareState.none) continue;
    out.add(habit);
  }
  return out;
}

/// The one number under the chart that measures the whole window: total
/// credit over total obligation.
///
/// Null when nothing in the window owed anything, for the same reason
/// [DayScore.rate] is nullable. Deliberately NOT the mean of the daily
/// rates: a day that owed one habit would then weigh exactly as much as a
/// day that owed twelve.
///
/// Built from the SETTLED numbers, so a day still open counts only what has
/// been answered on it: at 05:00 an untouched today, and a yesterday still
/// inside its grace, no longer drag the window down, and they enter the
/// moment they are done or close (Aziz, 2026-09-11).
double? windowRate(List<DayScore> scores) {
  var credit = 0.0;
  var owed = 0;
  for (final score in scores) {
    credit += score.settledCredit;
    owed += score.settledOwed;
  }
  return owed <= 0 ? null : (credit / owed).clamp(0.0, 1.0).toDouble();
}
