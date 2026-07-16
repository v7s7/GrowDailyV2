// The hour of day (0-23) before which a new calendar day hasn't "really"
// started yet for the app's purposes — see [DateTimeGameExt.effectiveDay].
// A fixed 3:00 AM cutoff (not user-configurable) was chosen as a middle
// ground: generous enough to cover a habit like "read before bed" finished
// well after midnight, without being so late that it eats into a normal
// next-morning routine. Every place in the app that decides "what day is
// this for streaks/grid squares/logs" should go through effectiveDay (or
// isToday/isYesterday below, which already do) instead of a raw calendar
// date — that's what keeps a task finished at 12:40 AM counted as
// belonging to the day that hadn't ended yet, rather than silently
// skipped because the calendar quietly rolled over at midnight.
const int kDayCutoffHour = 3;

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

  /// True when this date is the same as "today," where "today" itself
  /// respects [kDayCutoffHour] — see [effectiveDay]. A grid square for
  /// yesterday's calendar date is still `isToday` until the cutoff hour
  /// actually passes.
  bool get isToday => isSameDayAs(DateTime.now().effectiveDay);

  bool get isYesterday =>
      isSameDayAs(DateTime.now().effectiveDay.subtract(const Duration(days: 1)));

  /// True when this date is today on the *real* device calendar — unlike
  /// [isToday], this never shifts for [kDayCutoffHour]. Exists for exactly
  /// one purpose: deciding which date the gold "today" marker sits on in
  /// calendar-style views (Grid's week header, Monthly Heatmap, Night
  /// Review, Rooms, Matrix history) — nothing about *earning* anything
  /// (streak/XP/gold, which square is editable, which day a completion is
  /// recorded under) should ever key off this getter, only [isToday]/
  /// [effectiveDay] should.
  ///
  /// The two only disagree for the few hours between midnight and
  /// [kDayCutoffHour] — outside that window `isRealToday == isToday`
  /// exactly, so this is a no-op change the other 21 hours of the day. In
  /// that narrow window, this lets the UI stop looking like it's stuck on
  /// yesterday (the calendar clearly shows a new day) while [isToday]
  /// keeps pointing at the still-open previous day for anything that
  /// actually earns a reward — see effectiveDay's doc comment for why that
  /// day, not this one, is still the one that counts.
  bool get isRealToday => isSameDayAs(DateTime.now());

  /// Returns the start of this day (00:00:00).
  DateTime get startOfDay => DateTime(year, month, day);

  /// Returns the start of the ISO week (Monday) containing this date.
  DateTime get startOfWeek {
    final daysFromMonday = weekday - DateTime.monday;
    return startOfDay.subtract(Duration(days: daysFromMonday));
  }

  /// The "app day" this moment belongs to — a plain midnight-aligned
  /// DateTime, exactly like [startOfDay], except the boundary between one
  /// day and the next sits at [kDayCutoffHour] instead of midnight.
  ///
  /// Concretely: subtracting the cutoff and then taking that moment's
  /// startOfDay rolls anything before the cutoff back onto the previous
  /// calendar date automatically (00:00–02:59 becomes "yesterday" at the
  /// default 3-hour cutoff), while anything at or after the cutoff is
  /// unaffected. Call this instead of raw `DateTime.now()` (or `.startOfDay`
  /// on it) anywhere the app is deciding which day "today" currently is —
  /// streak keys, grid/log date keys, the current week/month, habit
  /// scheduling, "is this the current day" checks. Don't call it on a
  /// DateTime that already represents a *specific*, deliberately-chosen
  /// calendar date (e.g. one column of a rendered week) — only on "now"
  /// (or another moment you're asking "what day did this happen on,"
  /// like a completion timestamp).
  DateTime get effectiveDay =>
      subtract(const Duration(hours: kDayCutoffHour)).startOfDay;
}
