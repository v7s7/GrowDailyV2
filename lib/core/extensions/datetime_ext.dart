// How long a finished day stays open for marking after midnight: until
// 10:00 AM the next morning, fixed and not user-configurable.
//
// ── THIS IS A DEADLINE NOW, NOT A DAY BOUNDARY ────────────────────────────
//
// It used to BE the boundary: [DateTimeGameExt.effectiveDay] shifted back by
// it, so until 10 AM the whole app still called yesterday "today". That is
// gone (see effectiveDay for what it cost). The new day now starts at
// midnight everywhere, and this constant only says how long YESTERDAY
// remains markable alongside it — see [DateTimeGameExt.isOpenDay].
//
// Ten hours, because the person the window is really for is not the one who
// went to bed at 3 or 4 (6 AM already covered them) but the one who is
// simply asleep at 6 and opens the app at 9. They can still finish the 27th
// at 9:59 on the 28th, and still keep its streak point.
//
// The old value had to clear Bahrain's earliest Dhuhr (11:22 across all 521
// days in assets/prayer/bahrain_official.json), because back then a cutoff
// past noon would have silently banked every on-time Dhuhr against the
// previous day. That constraint is gone with the shift: a completion is
// always stamped on the day it happened, and yesterday is only ever marked
// deliberately. Ten is kept because it is the right amount of grace, not
// because Dhuhr forces it.
const int kDayCutoffHour = 10;

extension DateTimeGameExt on DateTime {
  /// Returns 'YYYY-MM-DD' key used as Firestore document IDs for daily logs.
  ///
  /// This is a pure formatter — it does NOT apply the day-cutoff shift
  /// itself. Call it on an already-correct day (e.g.
  /// `DateTime.now().effectiveDay.toDateKey()`, or a specific calendar date
  /// you built on purpose, like a grid week's Monday), never directly on a
  /// raw `DateTime.now()` when what you actually want is "today's key."
  String toDateKey() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  bool isSameDayAs(DateTime other) =>
      year == other.year && month == other.month && day == other.day;

  bool isSameMonthAs(DateTime other) =>
      year == other.year && month == other.month;

  /// True when this date is the CURRENT calendar day.
  ///
  /// It used to respect [kDayCutoffHour], so yesterday's square stayed
  /// `isToday` until 10 AM. It no longer does — the day rolls at midnight,
  /// which makes this and [isRealToday] the same answer at every hour.
  ///
  /// Use this for "which day is the current one": what the board opens on,
  /// which square wears the ring, which day a fresh completion defaults to.
  /// Do NOT use it to decide whether a square may EARN anything — yesterday
  /// is still payable inside its grace tail, and [isOpenDay] is the test for
  /// that. Getting those two confused is what produced the bug this whole
  /// model change exists to fix.
  bool get isToday => isSameDayAs(DateTime.now().effectiveDay);

  bool get isYesterday =>
      isSameDayAs(DateTime.now().effectiveDay.subtract(const Duration(days: 1)));

  /// True when this date is today on the device calendar.
  ///
  /// Now IDENTICAL to [isToday] at every hour, because the day rolls at
  /// midnight for both. It existed to mark the gold "today" ring in
  /// calendar views while [isToday] pointed at the still-open previous day,
  /// and that gap is exactly what let a square be labelled TODAY, be
  /// tappable, and pay nothing.
  ///
  /// Kept rather than removed, at 45 call sites that all read better for
  /// it: at a marker or a header, "is this the real calendar today" is the
  /// question being asked, and spelling it out is clearer than [isToday]
  /// there. The two must never drift apart again — if a future change gives
  /// "the current day" a different definition, this getter follows it.
  bool get isRealToday => isSameDayAs(DateTime.now());

  /// Returns the start of this day (00:00:00).
  DateTime get startOfDay => DateTime(year, month, day);

  /// Returns the start of the ISO week (Monday) containing this date.
  DateTime get startOfWeek {
    final daysFromMonday = weekday - DateTime.monday;
    return startOfDay.subtract(Duration(days: daysFromMonday));
  }

  /// The start of the SATURDAY week containing this date - the week this app
  /// actually shows people, matching the Grid screen's own columns and the
  /// Gulf working week. The single definition of "this week" for anything a
  /// user sees, so use this rather than [startOfWeek] for anything
  /// user-facing.
  ///
  /// [startOfWeek] (Monday, ISO) is kept for genuinely calendar-standard
  /// needs, but the two must never both be used to answer the same question:
  /// the Rooms weekly-quota rule once bucketed by Monday while the Grid drew
  /// Saturday weeks, so "4 times this week" silently meant a different seven
  /// days than the week the person was looking at. startOfGridWeek
  /// (weekly_grid_notifier.dart) delegates here so there is exactly one
  /// Saturday-week rule in the codebase.
  DateTime get startOfDisplayWeek {
    final daysFromSaturday = (weekday - DateTime.saturday + 7) % 7;
    return startOfDay.subtract(Duration(days: daysFromSaturday));
  }

  /// The "app day" this moment belongs to — the plain calendar day, which
  /// starts at midnight on the device's own clock.
  ///
  /// ── THIS USED TO SHIFT BACK BY [kDayCutoffHour], AND NO LONGER DOES ──
  ///
  /// It returned `subtract(cutoff).startOfDay`, so between 00:00 and 09:59
  /// "today" was still YESTERDAY everywhere: the Today board, the streak,
  /// the Grid's editable square. The cutoff's purpose was to protect
  /// someone who is up at 2am or asleep at 6, and it did — but by making
  /// the whole app disagree with the phone in their hand for ten hours a
  /// day, and the two halves of the app then disagreed with each other.
  /// The Grid drew its week and its gold "today" ring from the real
  /// calendar (see [isRealToday]) while the reward engine was still on
  /// yesterday, so at 2am the square labelled TODAY was tappable, turned
  /// green, and paid nothing: no XP, no gold, no streak, no completion
  /// record. Rooms grade off the square, so the room credited the day while
  /// the person's own account did not. Real case, room ELQVF8, 2026-09-05.
  ///
  /// The rule now: the new day starts at midnight, everywhere, with no
  /// exception. What the cutoff bought is kept, and kept explicitly — the
  /// PREVIOUS day stays open for marking until [kDayCutoffHour] (see
  /// [isOpenDay] and [isInGraceWindow]), so a night owl can still finish
  /// yesterday and still earn its streak point. The difference is that
  /// yesterday is now a day you deliberately go back to, instead of the day
  /// the app silently assumed you meant.
  ///
  /// That also removes a quiet mis-attribution the old shift caused: a
  /// habit finished at 9:40am was banked against YESTERDAY, which is why
  /// the cutoff had to be argued down from noon to clear Bahrain's earliest
  /// Dhuhr (see [kDayCutoffHour]). A 9:40am completion is today's now, and
  /// the Dhuhr argument no longer has to hold anything up.
  ///
  /// Still call this rather than raw `.startOfDay` anywhere the app decides
  /// which day "today" is: it is the one place that answer is defined, and
  /// leaving the calls in place is what makes a future change to the rule a
  /// single edit again. Don't call it on a DateTime that already represents
  /// a specific, deliberately-chosen calendar date (one column of a
  /// rendered week) — only on "now", or on a moment you are asking "what
  /// day did this happen on", like a completion timestamp.
  DateTime get effectiveDay => startOfDay;

  /// Whether this calendar day is currently open for marking.
  ///
  /// A day runs from its own 00:00 until [kDayCutoffHour] the NEXT morning,
  /// so from midnight to 10:00 there are TWO open days: the one that just
  /// started, and the one that just ended still inside its grace tail.
  /// Both may be marked, and both pay in full — the grace exists so that
  /// going to bed at 23:00 with a habit unticked does not cost the day.
  ///
  /// This is the test for "may this square earn anything", replacing
  /// [isToday] at every such decision. [isToday] still answers the narrower
  /// question of which day is the CURRENT one (what the board defaults to,
  /// which square wears the ring); a day can be open without being today.
  ///
  /// Tomorrow is never open: `now` is before its 00:00, so no square can be
  /// marked ahead of the day it belongs to.
  bool get isOpenDay => isOpenDayAt(DateTime.now());

  /// [isOpenDay] against an explicit clock.
  ///
  /// Exists so the rule can be tested at every hour of the day rather than
  /// only at whichever hour the suite happens to run — the old cutoff had a
  /// full window test precisely because a rule that reads `DateTime.now()`
  /// internally is otherwise only ever exercised at one point on the clock,
  /// and this rule has a boundary at midnight AND another at the cutoff.
  bool isOpenDayAt(DateTime now) {
    if (now.isBefore(startOfDay)) return false;
    return now.isBefore(closesAt);
  }

  /// The instant this calendar day stops being open for marking: its own
  /// start plus one day and [kDayCutoffHour] hours.
  ///
  /// That is [kDayCutoffHour] the next morning on the wall clock, except on
  /// a day a daylight-saving change runs through, where the fixed 34 hours
  /// land an hour either side of it. The one definition [isOpenDayAt] closes
  /// on, and the one the day clock's timer arms for (nextDayBoundaryAfter),
  /// so a screen left open refreshes at the instant the day really closes.
  DateTime get closesAt =>
      startOfDay.add(const Duration(days: 1, hours: kDayCutoffHour));

  /// Whether this day is open ONLY because of the grace tail — i.e. it is
  /// yesterday, and the clock has not yet reached [kDayCutoffHour].
  ///
  /// Exactly `isOpenDay && !isToday`, spelled out because the reward engine
  /// has to treat the two differently: today's marks move the in-memory
  /// board state, a grace day's marks belong to a day the board is no
  /// longer showing.
  bool get isInGraceWindow => isInGraceWindowAt(DateTime.now());

  /// [isInGraceWindow] against an explicit clock — see [isOpenDayAt].
  bool isInGraceWindowAt(DateTime now) =>
      isOpenDayAt(now) && !isSameDayAs(now.effectiveDay);

  /// Whether a habit-day on this date may be COUNTED at [now]: enter a
  /// percentage, be drawn as missed, or break a streak.
  ///
  /// Aziz, 2026-09-11, on a monthly report read at 05:19: the 11th was
  /// already counted as a miss, "because today still not finish". A day
  /// stays markable until [kDayCutoffHour] the next morning ([isOpenDayAt]),
  /// so until then a blank or half-done day is in progress, not missed. It
  /// counts once it is [answered] (finished, or an explicit فشل the person
  /// chose to record), or once it has closed, whichever comes first. A future
  /// day never counts, answered or not.
  ///
  /// Built only on [isOpenDayAt], so the cutoff is still defined in exactly
  /// one place. Streak code passes `answered: false`: an earned streak day
  /// has already moved the streak's own marker, so the days a streak asks
  /// about are only ever the unanswered ones.
  bool isSettledAt(DateTime now, {bool answered = false}) =>
      !now.isBefore(startOfDay) && (answered || !isOpenDayAt(now));

  /// The stretch in which SOME day's streak is on the line: 6pm until
  /// [kDayCutoffHour] the next morning. What "your streak is on the line"
  /// surfaces should key off.
  ///
  /// The obvious spelling, `hour >= 18`, silently stops being true at
  /// midnight, and midnight is not when the last chance passes. Someone up
  /// at 1am still has until 10 AM to save YESTERDAY (see [isOpenDay]'s
  /// grace tail), and the warning used to disappear on them at exactly the
  /// moment it mattered most.
  ///
  /// The definition is unchanged by the move to calendar days, but what it
  /// means shifted by one day either side of midnight: from 18:00 it is
  /// today's own streak that is closing, and from midnight to the cutoff it
  /// is yesterday's, still savable in its grace window. Both are real, and
  /// both deserve the same warning.
  bool get isDayClosing => hour >= 18 || hour < kDayCutoffHour;
}

/// The earliest day still open for marking at [now]: yesterday while the
/// grace tail runs, today once the cutoff has passed.
///
/// Every day strictly before this one is settled, so this is the exclusive
/// bound for any loop that judges past days: the one place that answers how
/// far back it is safe to look before accusing someone of missing a day they
/// can still finish.
///
/// It is a named helper because the bound used to be spelled inline as
/// `today`, which rolls at midnight while a day stays markable until
/// [kDayCutoffHour] the next morning (see [DateTimeGameExt.isOpenDayAt]).
/// Between midnight and the cutoff that judged a day the person could still
/// finish: an app opened in that window spent a streak freeze, or ended the
/// streak outright when the bank was empty, for a day that was not yet
/// missed. Hoor lost her only freeze that way at about 02:42 on 2026-09-08,
/// having finished the 7th inside its own grace window.
DateTime firstOpenDayAt(DateTime now) {
  final today = now.effectiveDay;
  final yesterday = today.subtract(const Duration(days: 1));
  return yesterday.isOpenDayAt(now) ? yesterday : today;
}

/// Whether a RESUME should run a full room resync, given when the last one
/// ran.
///
/// A resume is not evidence that anything changed: iOS fires it every time
/// the app returns to the foreground, which for a habit app full of reminders
/// is easily a dozen times a day. Each resync costs one participant read plus
/// up to kRoomSyncWindowDays daily reads PER ROOM the account is in, and
/// measured against the live project on 2026-09-12 almost none of those reads
/// discovered anything at all.
///
/// Two things always force a sync through, and both matter more than the
/// saving:
///
///  * no resync has run yet this session ([last] null), so there is nothing
///    to be stale relative to; and
///  * the day has rolled over since the last one. [DateTimeGameExt.
///    effectiveDay] rolls at MIDNIGHT, not at kDayCutoffHour (which is when
///    yesterday stops being markable), and midnight is when today's squares
///    reset. A board carried across it would be showing the wrong DAY rather
///    than merely old news.
///
/// Yesterday settling at kDayCutoffHour is deliberately NOT forced through
/// here. It is a re-grade nobody is sitting and watching for, and [gap]
/// already bounds how late it can be.
///
/// Pure and top-level for the same reason [firstOpenDayAt] is: a rule the
/// tests cannot reach is a rule that drifts from the behaviour it describes.
bool shouldResyncOnResume({
  required DateTime? last,
  required DateTime now,
  required Duration gap,
}) {
  if (last == null) return true;
  if (last.effectiveDay != now.effectiveDay) return true;
  return now.difference(last) >= gap;
}
