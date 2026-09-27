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
/// "Overwritten" is the other half of the ruling: whole sessions take the
/// places first, and a half keeps a place only while there is one left
/// over. Two halves and four whole sessions on a 4x week is 4 of 4, not 3;
/// two of each is 3 of 4. The halves that keep a place are the earliest ones,
/// so a later whole session pushes out the LATEST half, and the older a day
/// is, the less anything after it can change it. See [quotaWeekPlaces].
///
/// What stays day-local is every EMPTY day's verdict: it still depends only
/// on the sessions before it, whole or half, and on how many days follow.
/// Only a half day's own verdict reads the rest of its week, and only in the
/// direction of doing better: a whole session later in the week can move it
/// from [DayDemand.half] to [DayDemand.earned], which takes a half-credit day
/// out of the count for a whole-credit one.
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
  /// Also a half session left without a place: the week's places are all
  /// held by whole sessions or by earlier halves (see [quotaWeekPlaces]), so
  /// this day asks nothing, and a half here can only have pulled it down.
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

/// Which of one quota week's sessions hold its [target] places, as indices
/// into the week's [dayCount] days.
///
/// Whole sessions ([doneDays]) first, the earliest of them when there are
/// more than the target; then half sessions ([halfDays], a day in both being
/// whole), earliest first, into whatever places are left. So a whole session
/// always outranks a half ("unless it's overwritten with a full day", Aziz,
/// 2026-09-26), and among halves the older one keeps its place.
///
/// Every session when the week holds fewer sessions than its target: then
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
  for (var i = 0; i < dayCount && out.length < effectiveTarget; i++) {
    if (!doneDays.contains(i) && halfDays.contains(i)) out.add(i);
  }
  return out;
}

/// What one quota week's places are worth, in days: one for each whole session
/// holding a place, a half for each half session holding one (see
/// [quotaWeekPlaces]). Between 0 and the clamped target.
///
/// The number a week's quota is graded on wherever a WEEK is summed rather
/// than walked day by day: 2 whole and 2 halves of 4 is 3, 2 halves and 4
/// whole is 4, 3 whole and 2 halves is 3.5 (one half has no place left).
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
