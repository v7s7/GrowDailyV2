import 'room_model.dart';

/// What one plan slot did on one day, as far as the room can actually tell.
enum RoomSlotOutcome {
  /// The habit was completed that day.
  done,

  /// Marked جزئي: half the work, and half the credit ([RoomParticipant.
  /// creditFor] scores it 0.5).
  partial,

  /// Asked for, and nothing was recorded.
  missed,

  /// The day asked nothing of this slot: an off-day of a named-weekday
  /// habit, or a day a weekly quota had already bought.
  rest,

  /// This member skipped the slot when they joined, or dropped it later
  /// (see [kDeclinedSlot]). It counts neither for nor against them.
  declined,
}

/// One plan slot's name and what it did.
class RoomSlotDay {
  final String name;
  final RoomSlotOutcome outcome;

  const RoomSlotDay({required this.name, required this.outcome});
}

/// One day of one member's room record, in the shape a person reads it:
/// a score out of what was asked, the marks behind it, and, when the room
/// can honestly say so, which habit did what.
///
/// Every number here is read through the SAME accessors the leaderboard is
/// ranked on — [RoomParticipant.scheduledCountFor], [RoomParticipant.
/// creditFor]'s own arithmetic — for the reason this feature has already
/// paid for twice: a second way of computing one fact eventually disagrees
/// with the first, and then one day has two answers on two screens.
class RoomDayBreakdown {
  /// How many habits the day asked for. The denominator.
  final int scheduled;

  /// How many were completed.
  final int done;

  /// How many were marked جزئي.
  final int partial;

  /// How many were rested. DISPLAY ONLY, and deliberately absent from
  /// [credited] and [scheduled]: see [RoomParticipant.dailyRestedCount]'s
  /// wall. A rest stops a day being drawn as a failure; it does not pay.
  final int rested;

  /// [done] plus half of [partial], exactly as [RoomParticipant.creditFor]
  /// weighs them.
  final double credited;

  /// One row per live plan slot, or empty when the room cannot say which
  /// slot did what (see [roomDayBreakdown]). Never a guess.
  final List<RoomSlotDay> slots;

  const RoomDayBreakdown({
    required this.scheduled,
    required this.done,
    required this.partial,
    required this.rested,
    required this.credited,
    required this.slots,
  });

  /// How many of the day's habits went unanswered.
  int get missed {
    final open = scheduled - done - partial;
    return open < 0 ? 0 : open;
  }

  /// A day that asked nothing at all.
  bool get asksNothing => scheduled == 0;

  /// The share of the day that was earned, 0..1. The same number
  /// [RoomParticipant.creditFor] returns, and a day that asked nothing is a
  /// whole day, exactly as it is there.
  double get ratio {
    if (scheduled == 0) return 1;
    final r = credited / scheduled;
    return r < 0 ? 0 : (r > 1 ? 1 : r);
  }
}

/// Reads one day out of a member's participant document.
///
/// The per-slot rows are the delicate part. The room stores COUNTS per day
/// (done, partial, rested, scheduled), never which habit each one was, so
/// on a day where two habits were asked for and one was done there is no
/// honest way to say which. Rather than guess, [RoomDayBreakdown.slots] is
/// filled only when the counts leave no room for doubt:
///
///  * the day asked nothing, so every live slot rested; or
///  * nothing was excused (every live slot was asked for) AND all of them
///    landed the same way: all done, all جزئي, or none of either.
///
/// A one-habit plan is always in that set, which is most rooms. A mixed day
/// in a bigger plan returns no rows, and the caller shows the marks as
/// counts instead. Declined slots are certain either way and are always
/// named: skipping a slot is this member's own recorded choice.
///
/// Slots the leader has withdrawn from the plan are left out entirely, the
/// same way [RoomParticipant.countedHabitIdsIn] leaves them out of grading.
RoomDayBreakdown roomDayBreakdown({
  required RoomModel room,
  required RoomParticipant participant,
  required String dateKey,
}) {
  final scheduled = participant.scheduledCountFor(dateKey);
  final done = participant.dailyDoneCount[dateKey] ?? 0;
  final partial = participant.partialCountFor(dateKey);
  final rested = participant.dailyRestedCount[dateKey] ?? 0;
  final credited = (done + partial * 0.5).clamp(0.0, scheduled.toDouble());
  return RoomDayBreakdown(
    scheduled: scheduled,
    done: done,
    partial: partial,
    rested: rested,
    credited: scheduled == 0 ? 0 : credited,
    slots: _slotsOn(
      room: room,
      participant: participant,
      dateKey: dateKey,
      scheduled: scheduled,
      done: done,
      partial: partial,
    ),
  );
}

List<RoomSlotDay> _slotsOn({
  required RoomModel room,
  required RoomParticipant participant,
  required String dateKey,
  required int scheduled,
  required int done,
  required int partial,
}) {
  // An 'own'-mode room holds no names: every member picks their own habits
  // and the document carries only ids. Nothing to label a row with.
  if (room.habitMode != RoomHabitMode.shared) return const [];
  final live = <String>[];
  final declined = <String>[];
  for (var i = 0; i < room.sharedHabits.length; i++) {
    final template = room.sharedHabits[i];
    if (template.isRemoved) continue;
    final name = template.name.trim();
    if (name.isEmpty) return const [];
    if (participant.slotDeclinedOn(i, dateKey)) {
      declined.add(name);
    } else {
      live.add(name);
    }
  }
  if (live.isEmpty && declined.isEmpty) return const [];

  RoomSlotOutcome? uniform;
  if (scheduled == 0) {
    uniform = RoomSlotOutcome.rest;
  } else if (live.length == scheduled) {
    // Nothing was excused, so every live slot is one of the counted ones and
    // the totals below describe all of them at once.
    if (done == live.length) {
      uniform = RoomSlotOutcome.done;
    } else if (partial == live.length) {
      uniform = RoomSlotOutcome.partial;
    } else if (done == 0 && partial == 0) {
      uniform = RoomSlotOutcome.missed;
    }
  }
  // Mixed, or a day where some slots were excused and some were not: the
  // counts are known, the attribution is not, and inventing it here would be
  // the room telling somebody they skipped a habit they may well have done.
  if (uniform == null && live.isNotEmpty) return const [];

  return [
    for (final name in live)
      RoomSlotDay(name: name, outcome: uniform ?? RoomSlotOutcome.rest),
    for (final name in declined)
      RoomSlotDay(name: name, outcome: RoomSlotOutcome.declined),
  ];
}
