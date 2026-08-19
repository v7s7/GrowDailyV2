// The hour of day (0-23) before which a new calendar day hasn't "really"
// started yet for the app's purposes — see [DateTimeGameExt.effectiveDay].
// A fixed 6:00 AM cutoff (not user-configurable) was chosen as a middle
// ground: generous enough to cover someone who doesn't go to sleep until
// 3 or 4 AM and still wants last night's habits to count, without being so
// late that it eats into a normal next-morning routine. Every place in the
// app that decides "what day is this for streaks/grid squares/logs" should
// go through effectiveDay (or isToday/isYesterday below, which already do)
// instead of a raw calendar date — that's what keeps a task finished at
// 4:40 AM counted as belonging to the day that hadn't ended yet, rather
// than silently skipped because the calendar quietly rolled over at
// midnight.
const int kDayCutoffHour = 6;

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

  /// The "app day" this moment belongs to — a plain midnight-aligned
  /// DateTime, exactly like [startOfDay], except the boundary between one
  /// day and the next sits at [kDayCutoffHour] instead of midnight.
  ///
  /// Concretely: subtracting the cutoff and then taking that moment's
  /// startOfDay rolls anything before the cutoff back onto the previous
  /// calendar date automatically (00:00–05:59 becomes "yesterday" at the
  /// default 6-hour cutoff), while anything at or after the cutoff is
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

  /// The closing stretch of the CURRENT effective day: 6pm until the
  /// cutoff. What "your streak is on the line" surfaces should key off.
  ///
  /// The obvious spelling, `hour >= 18`, silently stops being true at
  /// midnight — and midnight is not when the day ends here. Someone up at
  /// 1am still has five hours to save their streak, which is the entire
  /// reason [kDayCutoffHour] exists, and the warning used to disappear on
  /// them at exactly the moment it mattered most. It ran 18:00 to 23:59
  /// and then went quiet for the six hours the cutoff had just granted.
  ///
  /// Deliberately a wrapped window (>= 18 OR < cutoff) rather than a
  /// comparison against [effectiveDay]: those small hours belong to
  /// yesterday's effective day, so they are late in it, not early.
  bool get isDayClosing => hour >= 18 || hour < kDayCutoffHour;
}
