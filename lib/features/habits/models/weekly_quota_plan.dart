/// Deciding, for a flexible weekly-quota habit ("N times a week, any days"),
/// what each individual day of the week was actually asking of you.
///
/// ── Why this exists ────────────────────────────────────────────────────────
///
/// The rooms grader already answers a version of this question, but it asks it
/// at the wrong time. `weeklyQuotaScheduledDays` asks a WEEK-level question —
/// "was the target reached?" — and projects that answer backwards onto every
/// day. So a Tuesday is graded using a fact from Friday, and a day silently
/// changes verdict long after it ended: do nothing all week and Tuesday reads
/// as a miss; hit your fourth session on Friday and that same Tuesday becomes
/// a rest day. Nothing about Tuesday changed. That retroactive flip is what
/// makes the whole feature feel broken, and no amount of colouring fixes it,
/// because the underlying verdict genuinely is unstable.
///
/// This asks a DAY-LOCAL question instead:
///
///   need      = target − completions strictly before this day
///   remaining = days left in the week, including this day
///   slack     = remaining − need
///
/// slack > 0  → doing nothing today still leaves the target reachable, so
///              today was never load-bearing. Not owed.
/// slack == 0 → every remaining day is needed. Skip today and the target
///              becomes arithmetically impossible. Owed.
///
/// Both inputs are frozen the moment a day ends — what happened before it
/// cannot change, and neither can how many days followed it. So a resolved
/// day's verdict is permanent. That is the whole point.
///
/// ── The correctness guarantee ──────────────────────────────────────────────
///
/// A missed day is exactly an [DayDemand.owed] day with nothing recorded on
/// it, and the count of those at week's end is exactly the shortfall:
///
///   count(owed and not done) == max(0, target − sessions)
///
/// The app therefore never accuses someone of more misses than they actually
/// fell short by, and never fewer. Do 2 of 3 and precisely one day is marked
/// missed — not five blank-looking days, and not zero. This is proved by
/// property test over every target and every completion pattern in
/// test/features/habits/weekly_quota_plan_test.dart, not argued for here.
///
/// ── Half sessions (جزئي) ───────────────────────────────────────────────────
///
/// Aziz, 2026-09-26, on the week of 19 September, when he trained half on
/// Saturday and Sunday and then nothing: "0.5 is a day count, unless it's
/// overwritten with a full day". A half session is a SESSION: it takes one of
/// the week's places exactly as a whole one does, and is worth half a day in
/// it. So that week is 0.5 + 0.5 of 4, three rest days and two misses.
///
/// The rule this replaced read a half as an empty day. Then which days of a
/// week were rest depended on where a half fell, not on what was done: early
/// in the week the half sat on a spare day, was excused as rest, and its half
/// vanished (his 19th and 20th, worth nothing in both rooms), while the same
/// half late in the week sat on an owed day and counted (his 17th, worth 0.5).
///
/// Halves ADD UP (Aziz, 2026-10-03, on the week of 26 September: three whole
/// sessions and two halves on a 4x week, "make halves add up, 3 + 0.5 + 0.5
/// = 4, but still the context should match the rest days"). The week's
/// places go to whole sessions first, then each half takes a place of its
/// own while there are places left, and once there are more halves than
/// places, two halves share one: each asks half a day and gives half a day.
/// So that week is 4 of 4, both half days count, and neither is a rest.
///
/// It read 3.5 before. "Unless it's overwritten with a full day" was taken to
/// mean a whole session on ANOTHER day pushes the latest half out of the
/// week, so the 30th, a day he trained, was graded as a rest in every room
/// whose week also held the 26th, and counted in the one room that started
/// on the 27th. Overwritten now means what it says: the same day marked
/// whole, which is simply a whole session (a day in both sets is whole). A
/// half drops out of the week only when the week is already full without
/// it: four whole sessions on a 4x week leave no half anything to give.
///
/// The arithmetic every reader leans on, proved over every week in
/// test/features/habits/weekly_quota_plan_test.dart: across a week, what the
/// places ask (a whole or a lone half one day each, a shared half half a
/// day) plus its owed empty days is exactly the target, and what they give
/// ([quotaWeekCredit]) is whole sessions plus half for every half, capped at
/// the target. So a week's share of any percentage is its worth over its
/// target, with nothing lost to where in the week a half fell.
///
/// What stays day-local is every EMPTY day's verdict: it still depends only
/// on the sessions before it, whole or half, and on how many days follow,
/// which is why two halves alone still leave three rest days and two misses
/// (the 19th). Only a half day's own standing reads the rest of its week, and
/// only in the direction of doing better: a later session can turn a lone
/// half into a shared one (asked half a day instead of a whole one), and a
/// week filled by whole sessions alone retires its halves to
/// [DayDemand.earned].
///
/// Ints only — no habit, no room, no clock — so the Grid's live habit and a
/// room's frozen RoomHabitRule can both call it and cannot drift apart.
library;

/// What a single day of a weekly-quota week was asking of the person.
enum DayDemand {
  /// They recorded a whole session on this day.
  done,

  /// They recorded a half session (جزئي) on this day, and it holds one of the
  /// week's places at half a day's credit. Owed like [done] (both sides of a
  /// rate, the half on the credit side), but never a finished session: every
  /// question asking "was it done" still asks for [done].
  half,

  /// Load-bearing: with the completions banked before it and the days left
  /// after it, skipping this day puts the target out of reach. An empty
  /// `owed` day is the only kind of day that counts as a genuine miss.
  owed,

  /// Not needed *yet*. The target is still open, but enough days remain that
  /// this one was never required on its own.
  spare,

  /// Not needed at all — the target was already met before this day. Still
  /// tappable and still rewarded: doing a 5th session on a 4x week is not an
  /// error, it is someone doing more than they promised.
  ///
  /// Also a half session the week had no room for: its places are all full
  /// without it (see [quotaWeekPlaces]), so this day asks nothing, and a half
  /// here can only have pulled it down. Never a half the week still needed:
  /// halves add up, two to a place.
  earned;

  /// Nothing was owed on this day, so an empty square is not a miss.
  bool get isRest => this == spare || this == earned;

  /// True once the day can never change verdict again — i.e. it is not a
  /// still-open `spare`. `earned` qualifies because a met target cannot be
  /// un-met, and `owed`/`done` are already final. A [half] can still give its
  /// place to a later whole session, but only by the person doing more, so no
  /// day waits on it.
  bool get isSettled => this != spare;
}

/// The per-day demand across one week, index-aligned with the week's days in
/// chronological order.
///
/// [dayCount] is normally 7 but is a parameter because a room's first or last
/// week can be short, and a habit created mid-week has fewer days present.
/// [doneDays] holds the indices completed in full, [halfDays] the ones marked
/// جزئي (a day in both is whole). [target] is clamped to [dayCount] so a
/// 7x-a-week habit in a 3-day window asks for 3, not 7 — the same clamp the
/// rooms grader already applies.
///
/// A half is a session for the day-local arithmetic (it banks one of the
/// places the days after it are measured against) and reads [DayDemand.half]
/// while it holds a place, [DayDemand.earned] once whole sessions have taken
/// them all. See the library doc.
List<DayDemand> weeklyQuotaDemand({
  required int dayCount,
  required Set<int> doneDays,
  required int target,
  Set<int> halfDays = const {},
}) {
  if (dayCount <= 0) return const [];
  final effectiveTarget = target.clamp(1, dayCount);
  final places = halfDays.isEmpty
      ? const <int>{}
      : quotaWeekPlaces(
          dayCount: dayCount,
          doneDays: doneDays,
          halfDays: halfDays,
          target: target,
        );

  final out = <DayDemand>[];
  var doneBefore = 0;
  for (var i = 0; i < dayCount; i++) {
    final whole = doneDays.contains(i);
    final half = !whole && halfDays.contains(i);
    if (whole) {
      out.add(DayDemand.done);
    } else if (half) {
      // A session either way; whether it still holds a place is the week's
      // question, not the day's.
      out.add(places.contains(i) ? DayDemand.half : DayDemand.earned);
    } else {
      final need = effectiveTarget - doneBefore;
      if (need <= 0) {
        // Target already banked before this day began. Nothing is owed.
        out.add(DayDemand.earned);
      } else {
        final remaining = dayCount - i; // includes today
        // slack == 0 means every remaining day is needed, this one included.
        out.add(remaining - need <= 0 ? DayDemand.owed : DayDemand.spare);
      }
    }
    if (whole || half) doneBefore++;
  }
  return out;
}

/// Which of one quota week's sessions count toward its [target], as indices
/// into the week's [dayCount] days.
///
/// Whole sessions ([doneDays]) first, the earliest of them when there are
/// more than the target. Then half sessions ([halfDays], a day in both being
/// whole), earliest first: one to a place while places are left, and two to
/// a place once the halves outnumber them ([quotaWeekSharedHalves] names the
/// ones sharing). So three whole sessions and two halves on a 4x week all
/// count, 4 of 4, and a half is left out only when the week is full without
/// it. Halves add up (Aziz, 2026-10-03; see the library doc).
///
/// Every session when the week holds no more sessions than its target: then
/// nothing competes for a place, and the days still missing are the owed
/// ones [weeklyQuotaDemand] names.
///
/// The earliest wholes, as the rooms grader has always taken them: a week
/// that met its target credits "the first `target` sessions", and every later
/// one is a rest day for the room (see weeklyQuotaScheduledDays).
Set<int> quotaWeekPlaces({
  required int dayCount,
  required Set<int> doneDays,
  required int target,
  Set<int> halfDays = const {},
}) {
  if (dayCount <= 0) return const {};
  final effectiveTarget = target.clamp(1, dayCount);
  final out = <int>{};
  for (var i = 0; i < dayCount && out.length < effectiveTarget; i++) {
    if (doneDays.contains(i)) out.add(i);
  }
  // Places a whole session left over: each holds one half, or two.
  final open = effectiveTarget - out.length;
  out.addAll(_halvesInOrder(dayCount, doneDays, halfDays).take(2 * open));
  return out;
}

/// The halves among [quotaWeekPlaces] that share a place with another half,
/// so each asks HALF a day of the week where a lone half asks a whole one.
///
/// Empty while every placed half has a place of its own. Once the halves
/// outnumber the places left over, the LATEST of them pair up, as many as it
/// takes to fit: so a later half can only move an earlier one from asking a
/// whole day to asking half of one (the same half, worth more of its day),
/// never out of the week.
///
/// The grader reads this to ask 0.5 of a shared half's day instead of 1, and
/// that is what keeps the week exact: places plus owed days ask the target,
/// whole sessions plus the halves give the worth, nothing in between.
Set<int> quotaWeekSharedHalves({
  required int dayCount,
  required Set<int> doneDays,
  required int target,
  Set<int> halfDays = const {},
}) {
  if (dayCount <= 0) return const {};
  final effectiveTarget = target.clamp(1, dayCount);
  var wholes = 0;
  for (var i = 0; i < dayCount; i++) {
    if (doneDays.contains(i)) wholes++;
  }
  final open = effectiveTarget - wholes;
  if (open <= 0) return const {};
  final placed =
      _halvesInOrder(dayCount, doneDays, halfDays).take(2 * open).toList();
  final shared = 2 * (placed.length - open);
  if (shared <= 0) return const {};
  return placed.sublist(placed.length - shared).toSet();
}

/// The week's halves, earliest first, a day also marked whole left out.
Iterable<int> _halvesInOrder(
  int dayCount,
  Set<int> doneDays,
  Set<int> halfDays,
) sync* {
  for (var i = 0; i < dayCount; i++) {
    if (!doneDays.contains(i) && halfDays.contains(i)) yield i;
  }
}

/// What one quota week's sessions are worth, in days: one for each whole
/// session that counts, a half for each half (see [quotaWeekPlaces]). Whole
/// sessions plus half of every half, capped at the clamped target.
///
/// The number a week's quota is graded on wherever a WEEK is summed rather
/// than walked day by day: 2 whole and 2 halves of 4 is 3, 2 halves and 4
/// whole is 4, 3 whole and 2 halves is 4 (the halves add up), 2 halves
/// alone is 1.
double quotaWeekCredit({
  required int dayCount,
  required Set<int> doneDays,
  required int target,
  Set<int> halfDays = const {},
}) {
  var credit = 0.0;
  for (final i in quotaWeekPlaces(
    dayCount: dayCount,
    doneDays: doneDays,
    halfDays: halfDays,
    target: target,
  )) {
    credit += doneDays.contains(i) ? 1.0 : 0.5;
  }
  return credit;
}

/// A count of sessions as it is shown: «4» for a whole number, «3.5» once a
/// half is in it. Latin digits, as the app writes every number.
String sessionsText(double sessions) => sessions == sessions.roundToDouble()
    ? sessions.toInt().toString()
    : sessions.toStringAsFixed(1);
