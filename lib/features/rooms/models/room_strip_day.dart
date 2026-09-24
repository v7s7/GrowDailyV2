import '../../../core/extensions/datetime_ext.dart';
import '../../habits/models/habit_model.dart' show HabitFrequencyType;
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
  final onQuota = participant.countedHabitIds.any(
    (id) =>
        participant.ruleFor(id, day.toDateKey())?.frequencyType ==
        HabitFrequencyType.weekly,
  );
  if (!onQuota) return true;
  return roomStripWeekIsClosed(room, day, now: now) ||
      participant.quotaWeekIsLost(day.toDateKey(), room, now: now);
}

/// Whether the Saturday week containing [day] has finished counting. The
/// quota grader only settles a week once it is over, so nothing in it is
/// lost before then. Mirrors isQuotaWeekClosed in rooms_notifier.dart.
bool roomStripWeekIsClosed(RoomModel room, DateTime day, {required DateTime now}) =>
    day.startOfDisplayWeek
        .add(const Duration(days: 6))
        .isBefore(room.lastCountedDayAt(now));
