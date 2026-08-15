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
///   count(owed and not done) == max(0, target − done)
///
/// The app therefore never accuses someone of more misses than they actually
/// fell short by, and never fewer. Do 2 of 3 and precisely one day is marked
/// missed — not five blank-looking days, and not zero. This is proved by
/// property test over every target and every completion pattern in
/// test/features/habits/weekly_quota_plan_test.dart, not argued for here.
///
/// Ints only — no habit, no room, no clock — so the Grid's live habit and a
/// room's frozen RoomHabitRule can both call it and cannot drift apart.
library;

/// What a single day of a weekly-quota week was asking of the person.
enum DayDemand {
  /// They recorded it on this day.
  done,

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
  earned;

  /// Nothing was owed on this day, so an empty square is not a miss.
  bool get isRest => this == spare || this == earned;

  /// True once the day can never change verdict again — i.e. it is not a
  /// still-open `spare`. `earned` qualifies because a met target cannot be
  /// un-met, and `owed`/`done` are already final.
  bool get isSettled => this != spare;
}

/// The per-day demand across one week, index-aligned with the week's days in
/// chronological order.
///
/// [dayCount] is normally 7 but is a parameter because a room's first or last
/// week can be short, and a habit created mid-week has fewer days present.
/// [doneDays] holds the indices actually completed. [target] is clamped to
/// [dayCount] so a 7x-a-week habit in a 3-day window asks for 3, not 7 — the
/// same clamp the rooms grader already applies.
List<DayDemand> weeklyQuotaDemand({
  required int dayCount,
  required Set<int> doneDays,
  required int target,
}) {
  if (dayCount <= 0) return const [];
  final effectiveTarget = target.clamp(1, dayCount);

  final out = <DayDemand>[];
  var doneBefore = 0;
  for (var i = 0; i < dayCount; i++) {
    final need = effectiveTarget - doneBefore;
    if (need <= 0) {
      // Target already banked before this day began. Anything here is extra.
      out.add(doneDays.contains(i) ? DayDemand.done : DayDemand.earned);
    } else {
      final remaining = dayCount - i; // includes today
      // slack == 0 means every remaining day is needed, this one included.
      out.add(doneDays.contains(i)
          ? DayDemand.done
          : (remaining - need <= 0 ? DayDemand.owed : DayDemand.spare));
    }
    if (doneDays.contains(i)) doneBefore++;
  }
  return out;
}
