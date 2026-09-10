import 'dart:math' as math;

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

/// One plan slot's name, what it did, and what that was WORTH to the day.
class RoomSlotDay {
  final String name;
  final RoomSlotOutcome outcome;

  /// This habit's share of the day, 0..1.
  ///
  /// A day is worth 1 and is split between the habits it asked for, which is
  /// exactly how [RoomParticipant.creditFor] divides it: two habits make each
  /// one worth 0.5, three make each 0.33, and a جزئي is worth half of its
  /// own share. Aziz asked for that arithmetic to be on screen rather than
  /// implied (2026-09-10): "if room started with 2 habit the info should be
  /// +0.5 +0.5, so we know that this is how it being counted".
  ///
  /// Zero for a rest, a declined slot, and a missed one.
  final double share;

  const RoomSlotDay({
    required this.name,
    required this.outcome,
    required this.share,
  });
}

/// Several slots that landed the same way, for a day whose counts do not say
/// WHICH slot was which.
///
/// The honest middle ground between naming habits we cannot name and saying
/// nothing at all: the outcome and the count are certain, so the arithmetic
/// can still be shown in full.
class RoomSlotGroup {
  final RoomSlotOutcome outcome;
  final int count;

  /// What this group contributed to the day: [count] times one slot's share.
  final double share;

  const RoomSlotGroup({
    required this.outcome,
    required this.count,
    required this.share,
  });
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

  /// One row per plan slot that was part of THIS day, or empty when the room
  /// cannot say which slot did what (see [roomDayBreakdown]). Never a guess.
  final List<RoomSlotDay> slots;

  /// The fallback for a day [slots] cannot describe: the same outcomes and
  /// the same arithmetic, grouped instead of named.
  final List<RoomSlotGroup> groups;

  const RoomDayBreakdown({
    required this.scheduled,
    required this.done,
    required this.partial,
    required this.rested,
    required this.credited,
    required this.slots,
    required this.groups,
  });

  /// What one of this day's habits is worth on its own: a day is 1, split
  /// between the habits it asked for.
  double get shareEach => scheduled == 0 ? 0 : 1 / scheduled;

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
  final each = scheduled == 0 ? 0.0 : 1 / scheduled;
  final live = <String>[];
  final declined = <String>[];
  final named = _namedSlotsOn(
    room: room,
    participant: participant,
    dateKey: dateKey,
    live: live,
    declined: declined,
  );

  RoomSlotOutcome? uniform;
  if (named) {
    if (scheduled == 0) {
      uniform = RoomSlotOutcome.rest;
    } else if (live.length == scheduled) {
      // Nothing was excused, so every live slot is one of the counted ones
      // and the totals below describe all of them at once.
      if (done == live.length) {
        uniform = RoomSlotOutcome.done;
      } else if (partial == live.length) {
        uniform = RoomSlotOutcome.partial;
      } else if (done == 0 && partial == 0) {
        uniform = RoomSlotOutcome.missed;
      }
    }
  }
  // Mixed, or a day where some slots were excused and some were not: the
  // counts are known, the attribution is not, and inventing it here would be
  // the room telling somebody they skipped a habit they may well have done.
  final attributable = named && (uniform != null || live.isEmpty);

  return RoomDayBreakdown(
    scheduled: scheduled,
    done: done,
    partial: partial,
    rested: rested,
    credited: scheduled == 0 ? 0 : credited,
    slots: attributable
        ? [
            for (final name in live)
              RoomSlotDay(
                name: name,
                outcome: uniform ?? RoomSlotOutcome.rest,
                share: _shareFor(uniform ?? RoomSlotOutcome.rest, each),
              ),
            for (final name in declined)
              RoomSlotDay(
                name: name,
                outcome: RoomSlotOutcome.declined,
                share: 0,
              ),
          ]
        : const [],
    groups: attributable
        ? const []
        : [
            if (done > 0)
              RoomSlotGroup(
                outcome: RoomSlotOutcome.done,
                count: done,
                share: done * each,
              ),
            if (partial > 0)
              RoomSlotGroup(
                outcome: RoomSlotOutcome.partial,
                count: partial,
                share: partial * each * 0.5,
              ),
            if (scheduled - done - partial > 0)
              RoomSlotGroup(
                outcome: RoomSlotOutcome.missed,
                count: scheduled - done - partial,
                share: 0,
              ),
            if (rested > 0)
              RoomSlotGroup(
                outcome: RoomSlotOutcome.rest,
                count: rested,
                share: 0,
              ),
          ],
  );
}

/// The shares as they should be PRINTED, adjusted so the numbers on screen
/// add up to the total beside them.
///
/// Two thirds and a sixth print as 0.67 and 0.17, which sum to 0.84 while
/// the day says 83%. That was visible on the first build of this card, and
/// arithmetic that does not add up defeats the whole reason for showing it.
///
/// Largest remainder, the same method a receipt uses: floor everything, then
/// hand the leftover pennies to the entries with the biggest fractions. A
/// zero share is never bumped, because "this habit added nothing" is a fact
/// rather than a rounding choice.
///
/// Pure, so the property that matters can be tested directly: the rounded
/// list sums to the rounded total, always.
List<double> roundedShares(List<double> shares, {int decimals = 2}) {
  if (shares.isEmpty) return const [];
  final scale = math.pow(10, decimals).toDouble();
  final target = (shares.fold<double>(0, (a, b) => a + b) * scale).round();
  final units = [for (final v in shares) (v * scale).floor()];
  var residue = target - units.fold<int>(0, (a, b) => a + b);
  if (residue > 0) {
    final order = [for (var i = 0; i < shares.length; i++) i]..sort((a, b) {
      // Compared at a tolerance, not exactly. Equal fractions are the COMMON
      // case here (n habits of the same size all round identically), and in
      // binary they are never quite equal: two thirds and a sixth leave
      // 0.6666666666666572 and 0.666666666666664, so noise in the
      // thirteenth decimal was silently deciding which row absorbed the
      // rounding.
      final fa = ((shares[a] * scale - units[a]) * 1e9).round();
      final fb = ((shares[b] * scale - units[b]) * 1e9).round();
      final byFraction = fb.compareTo(fa);
      if (byFraction != 0) return byFraction;
      // Then the share itself, so the BIGGEST contributor absorbs it, which
      // is both deterministic and the one a reader would pick.
      return shares[b].compareTo(shares[a]);
    });
    for (final i in order) {
      if (residue == 0) break;
      if (shares[i] <= 0) continue;
      units[i] += 1;
      residue -= 1;
    }
  }
  return [for (final u in units) u / scale];
}

/// What one slot's outcome is worth, given what one slot of this day is
/// worth. A جزئي is half of its own share, the same half it is everywhere
/// else in this app.
double _shareFor(RoomSlotOutcome outcome, double each) => switch (outcome) {
      RoomSlotOutcome.done => each,
      RoomSlotOutcome.partial => each * 0.5,
      RoomSlotOutcome.missed ||
      RoomSlotOutcome.rest ||
      RoomSlotOutcome.declined =>
        0,
    };

/// Fills [live] and [declined] with the names of the plan slots that were
/// part of [dateKey], and says whether naming is possible at all.
///
/// A slot the leader added on day 9 was not something this member failed on
/// day 3, so it must not appear on day 3's card at all. Aziz, 2026-09-10:
/// "some habit are being added after, not from day 1... only the counted
/// days for it should show it".
///
/// The join test is [RoomParticipant.slotOpenBy], the SAME one
/// [RoomParticipant.countedHabitCountOn] uses to build the denominator. That
/// is deliberate: if the rows were filtered by a different rule than the
/// number they sum to, the two would eventually disagree on screen. It fails
/// open for a slot with no recorded rule, exactly as that one does.
bool _namedSlotsOn({
  required RoomModel room,
  required RoomParticipant participant,
  required String dateKey,
  required List<String> live,
  required List<String> declined,
}) {
  // An 'own'-mode room holds no names: every member picks their own habits
  // and the document carries only ids. Nothing to label a row with.
  if (room.habitMode != RoomHabitMode.shared) return false;
  for (var i = 0; i < room.sharedHabits.length; i++) {
    final template = room.sharedHabits[i];
    if (template.isRemoved) continue;
    final name = template.name.trim();
    if (name.isEmpty) return false;
    final isDeclined = participant.slotDeclinedOn(i, dateKey);
    // A declined slot has no habit id to ask about, so fall back to the
    // room's own record of when the slot entered the plan.
    final habitId = participant.habitInSlotOn(i, dateKey);
    final joined = habitId != null
        ? participant.slotOpenBy(habitId, dateKey)
        : dateKey.compareTo(room.slotJoinedPlanKey(i)) >= 0;
    if (!joined) continue;
    (isDeclined ? declined : live).add(name);
  }
  return live.isNotEmpty || declined.isNotEmpty;
}
