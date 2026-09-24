/// Deciding, for a specific-days habit ("Monday, Thursday and Saturday"), what
/// a session done on one of the OTHER days of the week stands in for.
///
/// ── Why this exists ────────────────────────────────────────────────────────
///
/// Aziz, 2026-09-24: his «شامبو ضد القشرة» runs Monday, Thursday and Saturday.
/// He showered on Wednesday. The app refused the square, because a
/// specific-days habit could only ever be marked on its own days, and his week
/// was then going to charge a miss on Thursday for a shower he had taken the
/// day before. What he asked for: "make it count as 1x, so it doesn't charge
/// me as skipped".
///
/// The days a person picks are their PLAN. The week is the PROMISE. A session
/// on another day of the same week keeps the promise, so it takes the place of
/// one planned day that has no session of its own.
///
/// ── The rule ───────────────────────────────────────────────────────────────
///
/// Within one Saturday-to-Friday week:
///
///  - every session counts, on whatever day it happened;
///  - each session on a day that is NOT one of the habit's days covers one of
///    its days that has nothing recorded at all: first the days already
///    closed (a real miss, made up), earliest first, then the days still to
///    come (done early), earliest first;
///  - a day the person marked themselves is never covered. فشل is their own
///    verdict that it counts against them, تخطّي is already a rest they chose,
///    and a جزئي already carries its half: a moved session spent on any of
///    them would overturn a record, or be wasted on a day that owes nothing;
///  - a covered day owes nothing, exactly like a quota's rest day;
///  - sessions beyond the planned days are extra: they count on their own
///    day and cover nothing more.
///
/// Covers never cross into another week. A week with no off-day session is
/// not touched at all: every planned day is owed, as it always was.
///
/// ── The guarantee, kept ────────────────────────────────────────────────────
///
/// The same one the quota plan makes (weekly_quota_plan.dart): at the end of a
/// week, the planned days still owed and empty are exactly the shortfall,
///
///   count(owed and empty) == max(0, planned days − sessions),
///
/// never more and never fewer. Proved by property test in
/// test/features/habits/moved_day_plan_test.dart over every schedule and every
/// pattern of sessions. A planned day the person marked themselves keeps the
/// mark they gave it, so the guarantee is about the days left unmarked.
///
/// ── The one thing it gives up, on purpose ─────────────────────────────────
///
/// A quota day's verdict never changes once the day is over. Here a closed
/// miss CAN change, in one direction only and only by the person's own hand:
/// a session added later in the same week turns Monday's miss into "made up".
/// Nothing can turn a good day bad, and nothing but a real session moves a
/// verdict at all. The alternative, covering only the days after the session,
/// keeps every verdict frozen but breaks the guarantee above: miss Monday, make
/// it up on Tuesday, keep Thursday and Saturday, and the week would show a miss
/// for a week in which every promised shower was taken.
///
/// Booleans only, no habit and no clock, so the arithmetic can be pinned on
/// its own and every surface that asks gets the same answer.
library;

import 'weekly_quota_plan.dart';

/// The verdict for each day of one week, index for index with the inputs, or
/// null where the habit was not alive on that day.
///
/// [alive] is whether the habit existed on the day (born, not archived).
/// [planned] is whether the day is one of the habit's own days. [green] is
/// whether a session was recorded. [unmarked] is whether nothing at all was
/// recorded, which is the only kind of planned day a session may cover; null
/// reads every day that is not green as unmarked, for a caller that only
/// knows sessions. [closed] is whether the day can no longer be marked in
/// person (see DateTimeGameExt.isOpenDay): a closed empty day is a real miss
/// and is made up first, before any day still to come.
///
/// Every list must be the same length, normally 7.
List<DayDemand?> movedDayDemand({
  required List<bool> alive,
  required List<bool> planned,
  required List<bool> green,
  required List<bool> closed,
  List<bool>? unmarked,
}) {
  final n = alive.length;
  assert(planned.length == n && green.length == n && closed.length == n);
  assert(unmarked == null || unmarked.length == n);

  var offDaySessions = 0;
  final emptyClosed = <int>[];
  final emptyOpen = <int>[];
  for (var i = 0; i < n; i++) {
    if (!alive[i]) continue;
    if (planned[i]) {
      if (green[i]) continue;
      if (!(unmarked?[i] ?? true)) continue;
      (closed[i] ? emptyClosed : emptyOpen).add(i);
    } else if (green[i]) {
      offDaySessions++;
    }
  }

  // Real misses first, then the days still to come, each earliest first.
  final covered = [...emptyClosed, ...emptyOpen].take(offDaySessions).toSet();

  return [
    for (var i = 0; i < n; i++)
      if (!alive[i])
        null
      else if (green[i])
        DayDemand.done
      else if (!planned[i])
        DayDemand.spare
      else if (covered.contains(i))
        DayDemand.earned
      else
        DayDemand.owed,
  ];
}
