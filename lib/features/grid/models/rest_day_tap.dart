import '../../../core/extensions/datetime_ext.dart';
import '../../habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitTemplate;
import '../../habits/models/habit_day_demand.dart' show movedDemandForRow;
import '../../habits/models/weekly_quota_plan.dart'
    show DayDemand, quotaWeekCredit, quotaWeekPlaces;

/// Why a covered square (see isCoveredDay) asks nothing of its habit.
enum RestDayReason {
  /// A day off a specific-days plan: a Wednesday for a Monday, Thursday and
  /// Saturday habit.
  offPlan,

  /// One of the plan's own days, stood in for by a session on another day of
  /// the same week (see moved_day_plan.dart).
  coveredBySession,

  /// A flexible quota's day once the week's target is met: whole sessions
  /// and halves adding up (Aziz, 2026-10-03, "3 + 0.5 + 0.5 = 4").
  quotaMet,

  /// A flexible quota's day that was never load-bearing, now past.
  notNeeded,
}

/// What a tap on a covered square («–») would record, worked out before
/// anything is written, for the pop-up that asks first.
///
/// Aziz, 2026-09-24, on the «سويتها يوم ثاني» sheet this replaced: "what if
/// the user wants to add a Wednesday or a Thursday? ... just make any – days
/// clickable, but with a pop up that it's rest and how it will be handled".
///
/// [covers] is the day the session would stand in for, or null when it
/// would be an extra: for a specific-days habit, the plan's own day it makes
/// up (every planned day of the week may already have a session or a mark of
/// its own); for a flexible quota, the جزئي a whole session here would push
/// out of the week, which happens only once whole sessions leave no room for
/// it (see weekly_quota_plan.dart), and only when the session adds to the
/// week. [weekNow] and [weekAfter] are a flexible quota's week as it stands
/// and once this session lands, in what it is WORTH: whole sessions and half
/// of every half, capped at the target, the number the rooms and the reports
/// read («3.5 من 4»). [weekTarget] is its target; all three null for every
/// other cadence. [pays] is whether the day is still open (see
/// DateTimeGameExt.isOpenDay), and so earns like any completion; a closed
/// day records without points.
typedef RestDayTap = ({
  RestDayReason reason,
  DateTime? covers,
  double? weekNow,
  double? weekAfter,
  int? weekTarget,
  bool pays,
});

/// [RestDayTap] for the square at [index] of [days], a whole display week,
/// Saturday first, as the Grid row holds it. [isGreenAt] and [isUnmarkedAt]
/// read the row's squares (see movedDemandForRow), [isHalfAt] its جزئي
/// squares (none when null); [now] is the real clock when null.
///
/// Which day the session would cover is found by asking the rule itself:
/// the week is resolved as it stands and again with this session added, and
/// the one planned day that turns covered is the answer. So the pop-up can
/// never promise a different day from the one the Grid then paints.
RestDayTap restDayTapFor({
  required IslamicHabitTemplate habit,
  required List<DateTime> days,
  required int index,
  required bool Function(int index) isGreenAt,
  required bool Function(int index) isUnmarkedAt,
  bool Function(int index)? isHalfAt,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final day = days[index];
  final pays = day.isOpenDayAt(clock);
  final cadence = habit.cadenceOn(day);
  if (cadence.isFlexibleQuota) {
    final target = cadence.frequencyTarget;
    final whole = {
      for (var i = 0; i < days.length; i++)
        if (isGreenAt(i)) i,
    };
    final half = {
      for (var i = 0; i < days.length; i++)
        if (!whole.contains(i) && (isHalfAt?.call(i) ?? false)) i,
    };
    // What the week is worth now and with this session: the rule the Grid
    // and the rooms grade the week by, so the pop-up can never promise a
    // different number from the one the room then shows.
    final weekNow = quotaWeekCredit(
      dayCount: days.length,
      doneDays: whole,
      halfDays: half,
      target: target,
    );
    final weekAfter = quotaWeekCredit(
      dayCount: days.length,
      doneDays: {...whole, index},
      halfDays: half,
      target: target,
    );
    // The half this session would push out of the week, if any: asked before
    // and after, so the pop-up names the very day the week then stops
    // counting. Only for a session that adds to the week. Halves add up, so
    // a whole session only ever pushes one out once wholes fill the week,
    // and a session on a week already met adds nothing and covers nothing.
    DateTime? covers;
    if (weekAfter > weekNow) {
      final placedBefore = quotaWeekPlaces(
        dayCount: days.length,
        doneDays: whole,
        halfDays: half,
        target: target,
      );
      final placedAfter = quotaWeekPlaces(
        dayCount: days.length,
        doneDays: {...whole, index},
        halfDays: half,
        target: target,
      );
      for (final i in placedBefore) {
        if (half.contains(i) && !placedAfter.contains(i)) covers = days[i];
      }
    }
    final met = weekNow >= target.clamp(1, days.length);
    return (
      reason: met ? RestDayReason.quotaMet : RestDayReason.notNeeded,
      covers: covers,
      weekNow: weekNow,
      weekAfter: weekAfter,
      weekTarget: target,
      pays: pays,
    );
  }
  final before = movedDemandForRow(
    habit: habit,
    days: days,
    isGreenAt: isGreenAt,
    isUnmarkedAt: isUnmarkedAt,
    now: clock,
  );
  final after = movedDemandForRow(
    habit: habit,
    days: days,
    isGreenAt: (i) => i == index || isGreenAt(i),
    isUnmarkedAt: (i) => i != index && isUnmarkedAt(i),
    now: clock,
  );
  DateTime? covers;
  if (after != null) {
    for (var i = 0; i < days.length; i++) {
      if (i == index) continue;
      if (after[i] == DayDemand.earned && before?[i] != DayDemand.earned) {
        covers = days[i];
        break;
      }
    }
  }
  return (
    reason: habit.isScheduledFor(day)
        ? RestDayReason.coveredBySession
        : RestDayReason.offPlan,
    covers: covers,
    weekNow: null,
    weekAfter: null,
    weekTarget: null,
    pays: pays,
  );
}
