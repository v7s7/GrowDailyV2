import '../../../core/extensions/datetime_ext.dart';
import '../../habits/models/weekly_quota_plan.dart'
    show DayDemand, weeklyQuotaDemand;
import 'room_model.dart';
import 'room_strip_day.dart';

// ─── One habit of the plan, on every member's strip ───────────────────────
//
// Aziz, 2026-09-27: "add a filter like user can click on a habit to see the
// room grid showing the grid of that choosen habit". He picked the plan
// card's own tiles as the filter: tap «سورة الملك» and every row's strip
// draws سورة الملك alone.
//
// The counts a room grades on (dailyDoneCount and its siblings) cannot say
// which habit did what, so this reads RoomParticipant.dailyHabitMarks, the
// per-habit record the sync writes beside them for the day card. It is a
// DISPLAY field behind the wall in room_model.dart: nothing here may reach
// the room score, the ranking, or a payout. The strip and the row's own
// "this habit" number are all it feeds.
//
// Read only through habitMarksFor, which drops a day whose marks disagree
// with that day's counts (the anti-backdating clamp held it, or an older
// build regraded it without them). Such a day is drawn as unknown rather
// than guessed.

/// The calendar days shared slot [slot] was in [participant]'s room, for its
/// own strip: from the later of their own first day and the day the slot
/// joined the plan, to the room's last counted day, or to the slot's last
/// counted day when the leader removed it (RoomHabitTemplate.stopsOn).
///
/// Null when the slot never counted for them: a legacy removal (counted on
/// no day), a slot removed before they joined, or one removed the day it
/// was added.
({DateTime first, DateTime last})? roomSlotStripWindow(
  RoomModel room,
  RoomParticipant participant,
  int slot, {
  required DateTime now,
}) {
  if (slot < 0) return null;
  var first = participant.countedStartIn(room).startOfDay;
  final joined = DateTime.tryParse(room.slotJoinedPlanKey(slot));
  if (joined != null && joined.isAfter(first)) first = joined.startOfDay;
  var last = room.lastCountedDayAt(now).startOfDay;
  if (room.habitMode == RoomHabitMode.shared &&
      slot < room.sharedHabits.length) {
    final t = room.sharedHabits[slot];
    if (t.isRemoved) {
      if (participant.slotRemovedBeforeJoin(room, slot)) return null;
      final stopDay = DateTime.tryParse(t.stopsOn ?? '');
      if (stopDay == null) return null;
      final lastLive = DateTime(stopDay.year, stopDay.month, stopDay.day - 1);
      if (lastLive.isBefore(last)) last = lastLive;
    }
  }
  if (last.isBefore(first)) return null;
  return (first: first, last: last);
}

/// [day] of [participant]'s record for shared slot [slot] alone, judged at
/// [now], in the same [RoomStripDay] shape the whole-plan strip paints, so
/// the two views share one drawing of every state:
///
///  * done, credit 1; جزئي, credit 0.5 (the room's own weights);
///  * تخطّي on the day, or the slot skipped by this member that day (the
///    room held it against them, and nothing of theirs was in it): the
///    declared-rest look, neutral, "chosen, nothing earned";
///  * rest (off its named weekdays, or a quota's spare day): the rest look;
///  * missed: crossed out once it can no longer be saved, the same moment
///    the whole-plan strip crosses a day; before that, a plain square;
///  * today (or yesterday's grace tail) with nothing on it: pending;
///  * a pause, a stand-down, or a stretch the leader had the slot out of the
///    plan: the stand-down dash, nothing was owed;
///  * no mark to read (a day the marks do not describe): pending while the
///    day is open, plain after, never a claim either way.
RoomStripDay roomStripSlotDayOf(
  RoomModel room,
  RoomParticipant participant,
  int slot,
  DateTime day, {
  required DateTime now,
}) {
  final key = day.toDateKey();
  if (room.isPausedOn(key) ||
      participant.isStoodDownOn(key) ||
      !room.slotLiveOn(slot, key)) {
    return const RoomStripDay(
      credit: 0,
      isStoodDown: true,
      isRest: false,
      isDeclaredRest: false,
      isMissed: false,
      isPending: false,
    );
  }
  final habitId = participant.habitInSlotOn(slot, key);
  if (habitId == null) {
    return const RoomStripDay(
      credit: 0,
      isStoodDown: false,
      isRest: false,
      isDeclaredRest: true,
      isMissed: false,
      isPending: false,
    );
  }
  final open = day.isOpenDayAt(now);
  RoomStripDay plain({double credit = 0, bool pending = false}) => RoomStripDay(
        credit: credit,
        isStoodDown: false,
        isRest: false,
        isDeclaredRest: false,
        isMissed: false,
        isPending: pending,
      );
  switch (participant.habitMarksFor(key)?[habitId]) {
    case RoomHabitMark.done:
      return plain(credit: 1);
    case RoomHabitMark.partial:
      return plain(credit: 0.5);
    case RoomHabitMark.skipped:
      return const RoomStripDay(
        credit: 0,
        isStoodDown: false,
        isRest: false,
        isDeclaredRest: true,
        isMissed: false,
        isPending: false,
      );
    case RoomHabitMark.rest:
      // Credit 1, as creditFor pays a rest day: the week bar reads it as
      // settled, and RoomStripDay.look draws the rest tone before credit.
      return const RoomStripDay(
        credit: 1,
        isStoodDown: false,
        isRest: true,
        isDeclaredRest: false,
        isMissed: false,
        isPending: false,
      );
    case RoomHabitMark.missed:
      if (open) return plain(pending: true);
      if (!_slotMissIsFinal(room, participant, slot, habitId, day, now)) {
        return plain();
      }
      return const RoomStripDay(
        credit: 0,
        isStoodDown: false,
        isRest: false,
        isDeclaredRest: false,
        isMissed: true,
        isPending: false,
      );
    case null:
      return plain(pending: open);
  }
}

/// Whether a missed mark on a closed [day] is final for [habitId], the
/// single-habit form of roomStripMissIsFinal: a daily habit's closed day is
/// gone; a weekly quota's blank day waits for its week to close and then
/// crosses only if it was owed (weeklyQuotaDemand), because the week's own
/// close turns its spare blank days into rest days, and the marks only say
/// so after this member's phone has graded the closed week.
bool _slotMissIsFinal(
  RoomModel room,
  RoomParticipant participant,
  int slot,
  String habitId,
  DateTime day,
  DateTime now,
) {
  if (day.isAfter(room.lastCountedDayAt(now))) return false;
  final key = day.toDateKey();
  final rule = participant.ruleFor(habitId, key);
  if (rule == null || !rule.isFlexibleQuota || rule.frequencyTarget < 1) {
    return true;
  }
  if (!roomStripWeekIsClosed(room, day, now: now)) return false;
  final weekStart = day.startOfDisplayWeek;
  final present = <String>[];
  final done = <int>{};
  for (var i = 0; i < 7; i++) {
    final d = DateTime(weekStart.year, weekStart.month, weekStart.day + i);
    final k = d.toDateKey();
    if (participant.habitInSlotOn(slot, k) != habitId) continue;
    if (room.isPausedOn(k) || participant.isStoodDownOn(k)) continue;
    if (!room.slotLiveOn(slot, k)) continue;
    final mark = participant.habitMarksFor(k)?[habitId];
    if (mark == null) continue;
    // A جزئي holds one of the week's places, like a whole session, for the
    // question asked here: which BLANK days the week still needed.
    if (mark == RoomHabitMark.done || mark == RoomHabitMark.partial) {
      done.add(present.length);
    }
    present.add(k);
  }
  final at = present.indexOf(key);
  if (at < 0) return true;
  final demand = weeklyQuotaDemand(
    dayCount: present.length,
    doneDays: done,
    target: rule.frequencyTarget,
  );
  return demand[at] == DayDemand.owed;
}

/// What shared slot [slot] adds up to for [participant] at [now]: the days
/// it was done (a جزئي at half) over the days it was asked and decided. A
/// day still open with nothing on it, a rest day, a pause and a day the
/// marks cannot describe leave both sides, the way the room's own
/// denominator treats them; a skipped day and a final miss stay in.
///
/// Display only, for the filtered row's number and bar. The ranking never
/// reads it (see dailyHabitMarks's wall).
({double done, int asked}) roomSlotScore(
  RoomModel room,
  RoomParticipant participant,
  int slot, {
  required DateTime now,
}) {
  final window = roomSlotStripWindow(room, participant, slot, now: now);
  if (window == null) return (done: 0, asked: 0);
  var done = 0.0;
  var asked = 0;
  for (var d = window.first;
      !d.isAfter(window.last);
      d = DateTime(d.year, d.month, d.day + 1)) {
    final s = roomStripSlotDayOf(room, participant, slot, d, now: now);
    if (s.isStoodDown || s.isRest || s.isPending) continue;
    if (s.credit > 0) {
      asked++;
      done += s.credit;
    } else if (s.isDeclaredRest || s.isMissed) {
      asked++;
    }
  }
  return (done: done, asked: asked);
}
