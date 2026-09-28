import '../../../core/extensions/datetime_ext.dart';
import '../../habits/models/weekly_quota_plan.dart'
    show DayDemand, quotaWeekCredit, weeklyQuotaDemand;
import 'room_model.dart';

// ─── A flexible quota's week, as the room grades it ───────────────────────
//
// The plan card prints one line per weekly-quota habit: «تمرين: 1 من 4 هذا
// الأسبوع», and «مطلوب اليوم» on a day the week cannot be met without. It
// used to count the Grid's whole Saturday-to-Friday week, while the room
// grades only the days it ran and the slot was in its plan, and caps the
// target at how many of those there are (weeklyQuotaScheduledDays in
// rooms_notifier.dart), or asks a short week's share once that is switched
// on (roomQuotaWeekTarget, room_quota_share.dart). Two rooms read wrong on
// 2026-09-27:
//
//  * F8HQKE «بزنس مِن» started on Sunday. Its line said 1 of 4 from
//    Saturday's session, a day before the room existed. The room counts
//    none of it and needs all four in the six days it has that week (three
//    with the share).
//  * ELQVF8 «Being Better» ends on Wednesday. Its line measured the week
//    against Thursday and Friday, days the room will never grade, so the
//    last-chance «مطلوب اليوم» stayed quiet on the days it was true.

/// The days of one Grid week, [weekDays], that the room grades shared slot
/// [slot] on for [participant]: on or after their own first day and the day
/// the slot joined the plan, not after the room's end, not a day the room
/// was paused, their plan stood down, or the leader had the slot out, and
/// only the days the slot held the habit linked in it now. The same days the
/// sync's `present` list holds for the week, and the ones
/// [RoomParticipant.quotaWeekIsLost] counts over.
///
/// The habit is asked of each day the way the sync asks it (slotGradesOn,
/// through [RoomParticipant.habitInSlotOn]): after a change of link
/// (RoomsController.relinkPlanHabit) the days before it are the old habit's,
/// and a stretch the slot spent declined is no habit's.
/// Without it a slot relinked on Wednesday counted the new habit's squares
/// from Saturday and asked 4 over seven days, while the room grades that
/// habit Wednesday to Friday and asks 3, 4 capped at its three days.
List<DateTime> roomSlotWeekDays(
  RoomModel room,
  RoomParticipant participant,
  int slot,
  List<DateTime> weekDays,
) {
  final first = participant.countedStartIn(room).startOfDay;
  final joinedKey = room.slotJoinedPlanKey(slot);
  final end = room.endDate?.startOfDay;
  final linked = participant.linkedHabitIds;
  final habit = slot >= 0 && slot < linked.length ? linked[slot] : null;
  return [
    for (final d in weekDays)
      if (!d.isBefore(first) &&
          (end == null || !d.isAfter(end)) &&
          d.toDateKey().compareTo(joinedKey) >= 0 &&
          room.slotLiveOn(slot, d.toDateKey()) &&
          (habit == null ||
              participant.habitInSlotOn(slot, d.toDateKey()) == habit) &&
          !room.isPausedOn(d.toDateKey()) &&
          !participant.isStoodDownOn(d.toDateKey()))
        d,
  ];
}

/// One weekly quota's standing in the current week, over the days the room
/// grades it ([roomSlotWeekDays]): what the week is worth so far (a جزئي is
/// half, see weekly_quota_plan.dart), the target those days can ask for,
/// and whether [today] is a [DayDemand.owed] day. Null when the room grades
/// none of the week, so the card prints nothing rather than a week that is
/// not the room's.
///
/// [target] is the habit's own weekly target. Once the short-week share is on
/// (room_quota_share.dart), a week the room only partly covers asks its share
/// of it (quotaWeekTargetFor), the same number the grader holds the week to.
///
/// [isDone] and [isHalf] read the member's own Grid squares, the same ones
/// the room grader reads.
({double done, int target, bool neededToday})? roomQuotaWeekStanding({
  required RoomModel room,
  required RoomParticipant participant,
  required int slot,
  required List<DateTime> weekDays,
  required bool Function(DateTime day) isDone,
  required bool Function(DateTime day) isHalf,
  required int target,
  required DateTime today,
}) {
  final days = roomSlotWeekDays(room, participant, slot, weekDays);
  if (days.isEmpty) return null;
  final linked = participant.linkedHabitIds;
  final weekTarget = slot >= 0 && slot < linked.length
      ? participant.quotaWeekTargetFor(linked[slot], target, room, days.first)
      : target;
  final doneIdx = {
    for (var i = 0; i < days.length; i++)
      if (isDone(days[i])) i,
  };
  final halfIdx = {
    for (var i = 0; i < days.length; i++)
      if (!doneIdx.contains(i) && isHalf(days[i])) i,
  };
  final demand = weeklyQuotaDemand(
    dayCount: days.length,
    doneDays: doneIdx,
    halfDays: halfIdx,
    target: weekTarget,
  );
  final todayIdx = days.indexWhere((d) => d.isSameDayAs(today));
  return (
    done: quotaWeekCredit(
      dayCount: days.length,
      doneDays: doneIdx,
      halfDays: halfIdx,
      target: weekTarget,
    ),
    target: weekTarget.clamp(1, days.length),
    neededToday: todayIdx >= 0 && demand[todayIdx] == DayDemand.owed,
  );
}
