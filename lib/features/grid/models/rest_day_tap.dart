import '../../../core/extensions/datetime_ext.dart';
import '../../habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitTemplate;
import '../../habits/models/habit_day_demand.dart' show movedDemandForRow;
import '../../habits/models/weekly_quota_plan.dart'
    show DayDemand, quotaWeekPlaces;

/// Why a covered square (see isCoveredDay) asks nothing of its habit.
enum RestDayReason {
  /// A day off a specific-days plan: a Wednesday for a Monday, Thursday and
  /// Saturday habit.
  offPlan,

  /// One of the plan's own days, stood in for by a session on another day of
  /// the same week (see moved_day_plan.dart).
  coveredBySession,

  /// A flexible quota's day once whole sessions have met the week's target.
  /// Halves filling the week's places short of that are not a met target: a
  /// whole session here would still take one's place.
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
/// its own); for a flexible quota, the جزئي whose place in the week it would
/// take (Aziz, 2026-09-26: "unless it's overwritten with a full day", see
/// weekly_quota_plan.dart). [weekAfter] and [weekTarget] are a flexible
/// quota's sessions this week once this one lands, a جزئي counting as one,
/// and its target; null for every other cadence. Once whole sessions alone
/// meet the target they are the only ones counted, since a half then has no
/// place. [pays] is whether the day is still open (see
/// DateTimeGameExt.isOpenDay), and so earns like any completion; a closed
/// day records without points.
typedef RestDayTap = ({
  RestDayReason reason,
  DateTime? covers,
  int? weekAfter,
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
    // The half this session would push out of the week's places, if any:
    // the rule the Grid and the rooms place the week by, asked before and
    // after, so the pop-up names the very day the week then stops counting.
    DateTime? covers;
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
    final met = whole.length >= target;
    return (
      reason: met ? RestDayReason.quotaMet : RestDayReason.notNeeded,
      covers: covers,
      // Sessions, a جزئي included (the days trained), until whole ones meet
      // the target and no half has a place left.
      weekAfter: (met ? whole.length : whole.length + half.length) + 1,
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
    weekAfter: null,
    weekTarget: null,
    pays: pays,
  );
}
