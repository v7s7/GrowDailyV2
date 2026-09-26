import '../../../core/extensions/datetime_ext.dart';
import '../../habits/models/habit_model.dart' show HabitFrequencyType;
import '../../habits/models/weekly_quota_plan.dart'
    show DayDemand, weeklyQuotaDemand;
import 'room_model.dart';

/// How one day of a member's record is drawn, wherever it is drawn.
///
/// Two readers, one rule. The room's own strip (RoomStrip._cellFor in
/// room_detail_screen_leaderboard_extend.dart) paints these flags, and the
/// Room Race Home Screen widget carries them as one character per day (see
/// roomRaceDayCode in rooms_notifier.dart). The widget cannot compute any of
/// this itself, it runs in its own process with no participant and no room,
/// so until 2026-09-24 it drew a plain credit ramp: a missed day, a rest
/// day, a paused day and today still open all came out as the same empty
/// square, beside a room screen that tells the four apart. Aziz asked for the
/// widget to be "same as the one in rooms", and the only way to promise that
/// is for both to read this.
///
/// Every flag keeps the meaning it has on the strip, and the order they are
/// painted in lives in [look], not in each reader.
class RoomStripDay {
  /// 0.0 to 1.0, [RoomParticipant.creditFor]; 0 on a day the ROOM was paused.
  final double credit;

  /// The room was paused on this day, or the member's whole plan was stood
  /// down. Nothing was owed and nothing was earned; drawn as a dash.
  final bool isStoodDown;

  /// The schedule asked nothing of the member ([RoomParticipant.isRestDay]):
  /// a quota's rest or an off-day of a named-weekday habit.
  final bool isRest;

  /// Every scheduled habit was marked تخطّي and nothing was done
  /// ([RoomParticipant.isDeclaredRest]).
  final bool isDeclaredRest;

  /// Nothing earned, and the day can no longer be rescued. See
  /// [roomStripMissIsFinal].
  final bool isMissed;

  /// Drawn, but not in the member's own numbers yet
  /// ([RoomParticipant.dayIsCountableAt]): today, still open, nothing
  /// recorded on it.
  final bool isPending;

  const RoomStripDay({
    required this.credit,
    required this.isStoodDown,
    required this.isRest,
    required this.isDeclaredRest,
    required this.isMissed,
    required this.isPending,
  });

  /// Which of the strip's treatments wins, in the order roomStripCellFill
  /// has always checked them. A stood-down day first, because it is none of
  /// the other states; an open day with nothing on it before a rest or a
  /// miss, because it is neither yet; a declared rest before a structural
  /// one, because تخطّي is a choice and a rest is the calendar's doing.
  RoomStripDayLook get look {
    if (isStoodDown) return RoomStripDayLook.standDown;
    if (isPending && credit <= 0) return RoomStripDayLook.pending;
    if (isDeclaredRest) return RoomStripDayLook.declaredRest;
    if (isRest) return RoomStripDayLook.rest;
    if (isMissed) return RoomStripDayLook.missed;
    return RoomStripDayLook.credit;
  }
}

/// The five drawn states of a strip day, plus the credit ramp for
/// everything else. See [RoomStripDay.look].
enum RoomStripDayLook { standDown, pending, declaredRest, rest, missed, credit }

/// [day] of [participant]'s record in [room], judged at [now].
///
/// Exactly what the room strip computed inline before this was lifted out:
/// see the comments in RoomStrip._cellFor for why each state exists.
RoomStripDay roomStripDayOf(
  RoomModel room,
  RoomParticipant participant,
  DateTime day, {
  required DateTime now,
}) {
  final key = day.toDateKey();
  // Dead time between an ending and an extension (RoomModel.pausedSpans):
  // the room was not running, so it is neither a miss nor a rest day, and it
  // is out of the score too.
  final isRoomPaused = room.isPausedOn(key);
  final isStoodDown = isRoomPaused || participant.isStoodDownOn(key);
  final isRest = participant.isRestDay(key);
  final credit = isRoomPaused ? 0.0 : participant.creditFor(key);
  // Settled the instant it is marked, so it bypasses the miss gate: there is
  // nothing left to rescue on a day somebody said they are resting.
  final isDeclaredRest = participant.isDeclaredRest(key);
  final isMissed = !isStoodDown &&
      !isRest &&
      !isDeclaredRest &&
      credit <= 0 &&
      roomStripMissIsFinal(room, participant, day, now: now);
  final isPending =
      !isStoodDown && !participant.dayIsCountableAt(key, now);
  return RoomStripDay(
    credit: credit,
    isStoodDown: isStoodDown,
    isRest: isRest,
    isDeclaredRest: isDeclaredRest,
    isMissed: isMissed,
    isPending: isPending,
  );
}

/// Whether a day with no credit is genuinely lost, and can be crossed out.
///
/// Today is never marked: it is still doable, and a square un-ticked in the
/// Grid five seconds ago shouldn't turn red while the person is still
/// working on it. Nor is yesterday while it can still be marked: under the
/// overlapping-day window a day stays open until kDayCutoffHour the next
/// morning, so at 03:00 yesterday is still winnable and the Grid will pay a
/// session marked then. isRealToday closed it at midnight instead, ten hours
/// early (Aziz, 2026-09-10: "I may train now, so the system should add fail
/// only if it passes the flex time").
///
/// Past days split on the habit's own rule, because "you can still save
/// this" only means something for a weekly quota. A DAILY habit's yesterday
/// is simply gone: uncheck it in the Grid and it is a miss the moment the
/// day ends, which is what makes the room agree with the Grid square the
/// user just changed. A QUOTA habit's is only provisionally owed while its
/// week is open, and finishing the week converts its blank days back into
/// rest days, so the quota case waits.
///
/// Waits for the week to be DECIDED, though, which is not the same as
/// waiting for it to end. A 4x-a-week habit buys three blank days; on the
/// fourth, three sessions is the most the week can still reach and it will
/// grade as a miss whatever happens next. Without that second condition the
/// strip sat on the answer for the rest of the week: on A8GEL7 the week of
/// 09/05 was settled on Wednesday and still showed seven neutral squares on
/// Thursday. See [RoomParticipant.quotaWeekIsLost], which fails toward
/// silence in every case where it cannot be sure.
///
/// Lifted out of RoomStrip._missIsFinal on 2026-09-24, unchanged, so the
/// Room Race widget could carry the same crosses.
///
/// A decided week crosses out only the days it broke on (Aziz, 2026-09-26,
/// room A8GEL7: "it has a fail in all days for perla, no rest days"). Until
/// then every blank day of a lost or closed week was crossed, the three a 4x
/// quota buys included, while the week's own close
/// (weeklyQuotaScheduledDays) turns exactly those three into rest days and
/// marks the rest missed. Which blank days are which is
/// [weeklyQuotaDemand]'s answer: the early ones are spare while enough days
/// follow them to make the target, and the late ones are owed, the same days
/// the Grid paints red. A closed day's answer depends only on the days
/// before it and on how many days the week holds, so the close cannot
/// change it.
///
/// A spare day is left plain, not drawn as rest, until the record rests it:
/// the member's own phone at the close, or the board's reading of a week
/// their phone has not regraded yet (closedQuotaWeekInference, which starts
/// some hours after the close). Its credit arrives with that, and the strip
/// does not show credit the numbers beside it do not have yet. Plain covers
/// the hours in between, and a closed week the inference cannot prove,
/// which used to cross the whole week out. See [roomStripQuotaDemandOn] for
/// where it cannot tell.
bool roomStripMissIsFinal(
  RoomModel room,
  RoomParticipant participant,
  DateTime day, {
  required DateTime now,
}) {
  // !isOpenDayAt is roomDayIsClosedAt (rooms_notifier.dart), the same test
  // the room's own sync uses before it clamps a day. Spelled out here so the
  // model does not import the notifier.
  if (day.isOpenDayAt(now) || day.isAfter(room.lastCountedDayAt(now))) {
    return false;
  }
  // The habits in the plan THAT day: a slot whose habit was changed since
  // (RoomsController.relinkPlanHabit) keeps the cadence it had then.
  final onQuota = participant.habitsInSlotsOn(day.toDateKey()).any(
    (id) =>
        participant.ruleFor(id, day.toDateKey())?.frequencyType ==
        HabitFrequencyType.weekly,
  );
  if (!onQuota) return true;
  if (!roomStripWeekIsClosed(room, day, now: now) &&
      !participant.quotaWeekIsLost(day.toDateKey(), room, now: now)) {
    return false;
  }
  return roomStripQuotaDemandOn(room, participant, day) != DayDemand.spare;
}

/// What [day] owes its quota week, the way the week's close will grade it:
/// [weeklyQuotaDemand] over the week's present days and the days recorded
/// done. Null wherever the record cannot say, which leaves the caller where
/// it was before this existed.
///
/// Present means what the grader counts (rooms_notifier.dart,
/// syncLinkedHabitsProgress): a day inside the room, the room running, the
/// plan not stood down, and the slot holding this habit under a recorded
/// rule. Null for:
///  * a day whose plan holds more than one habit, since [dailyDoneCount]
///    counts habits, not sessions of one of them;
///  * a week with a day this member was away, or with more than one habit in
///    the slot, or two rules for it: the grader takes the week's first day's
///    rule and the habit each day held, and this cannot replay either;
///  * a rule that is not a weekly quota with a real target;
///  * a week whose record already rests a day: the member's own phone has
///    graded it closed, and its answer stands. It can differ from this one,
///    because the phone counts a square painted after its day closed as a
///    session (the anti-backdating clamp keeps that day's credit at 0, not
///    its place in the week), which the record cannot show. Perla's
///    12 September was one: her phone rested the 13th to the 15th and kept
///    the 12th due, where the record alone reads the 12th to the 14th.
DayDemand? roomStripQuotaDemandOn(
  RoomModel room,
  RoomParticipant participant,
  DateTime day,
) {
  final key = day.toDateKey();
  final habits = participant.habitsInSlotsOn(key);
  if (habits.length != 1) return null;
  final habit = habits.single;
  final rule = participant.ruleFor(habit, key);
  if (rule == null ||
      rule.frequencyType != HabitFrequencyType.weekly ||
      rule.frequencyTarget < 1) {
    return null;
  }
  DateTime dateOf(DateTime t) => DateTime(t.year, t.month, t.day);
  final first = dateOf(room.startDate);
  final end = room.endDate == null ? null : dateOf(room.endDate!);
  final weekStart = day.startOfDisplayWeek;
  final present = <String>[];
  for (var i = 0; i < 7; i++) {
    final d = DateTime(weekStart.year, weekStart.month, weekStart.day + i);
    final k = d.toDateKey();
    if (d.isBefore(first) || (end != null && d.isAfter(end))) continue;
    if (participant.isAwayOn(k)) return null;
    if (room.isPausedOn(k) || participant.isStoodDownOn(k)) continue;
    final held = participant.habitsInSlotsOn(k);
    if (held.isEmpty) continue;
    if (held.length != 1 || held.single != habit) return null;
    final dayRule = participant.ruleFor(habit, k);
    if (dayRule == null) continue;
    if (!identical(dayRule, rule)) return null;
    present.add(k);
  }
  final at = present.indexOf(key);
  if (at < 0) return null;
  if (present.any((k) => participant.recordedScheduledCountFor(k) == 0)) {
    return null;
  }
  final demand = weeklyQuotaDemand(
    dayCount: present.length,
    doneDays: {
      for (var i = 0; i < present.length; i++)
        if ((participant.dailyDoneCount[present[i]] ?? 0) > 0) i,
    },
    target: rule.frequencyTarget,
  );
  return demand[at];
}

/// Whether the Saturday week containing [day] has finished counting. The
/// quota grader only settles a week once it is over, so nothing in it is
/// lost before then. Mirrors isQuotaWeekClosed in rooms_notifier.dart,
/// which the model cannot import.
///
/// Including its grace. The grader's week closes only once its last day
/// has, at kDayCutoffHour the next morning, because Friday stays markable
/// until 10:00 on Saturday (a later fix, made there after ELQVF8). This
/// copy was never brought along, so from midnight to 10:00 every Saturday
/// the strip took a week the grader still held open as closed, and crossed
/// out every blank day in it, the quota's rest days too: the A8GEL7 strip
/// Aziz saw at 01:00 on 26 September. And like the grader, a room that has
/// ended has closed every week it had.
bool roomStripWeekIsClosed(
  RoomModel room,
  DateTime day, {
  required DateTime now,
}) {
  if (room.isEndedAt(now)) return true;
  final weekEnd = day.startOfDisplayWeek.add(const Duration(days: 6));
  if (!weekEnd.isBefore(room.lastCountedDayAt(now))) return false;
  return !weekEnd.isOpenDayAt(now);
}
