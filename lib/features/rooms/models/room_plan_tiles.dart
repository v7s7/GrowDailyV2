import '../../../core/extensions/datetime_ext.dart';
import 'room_model.dart';

// ─── The habit tiles on a member's plan card ───────────────────────────────
//
// Aziz, 2026-09-27, on room اذكار الصباح the morning after the leader removed
// four habits: the card said «1 من 3 اليوم» (right: three habits counted that
// day) above SEVEN chips, four of them tagged «آخر يوم». Their last day was
// the day before, still open until 10:00, so the chips were drawn, but in the
// same row as today's habits and with a tag that reads as "today is the last
// day". His words: "the list is still long not removed ... deleted should be
// in gray ... so its separate".
//
// So every tile belongs to exactly one row, decided by the day it is asked
// about rather than by the grace tail: the habits that count today, the ones
// whose last day IS today (still counting, leaving tomorrow), and the ones
// already gone, gray, for a week. The first row's size is always the number
// the header counts.

/// How long a habit the leader removed keeps a gray tile on the plan card
/// after its last counted day. Long enough that nobody misses the change,
/// short enough that a long room's card does not collect every edit ever
/// made. The habit's history stays one tap away in the room's habit filter
/// for as long as its days are inside the room's window.
const int kRemovedPlanTileDays = 7;

enum RoomPlanTileRow {
  /// In the plan today: counts, or was skipped by this member.
  today,

  /// Removed by the leader today: still counts today, and from tomorrow for
  /// nobody (RoomHabitTemplate.stopsOn).
  lastDay,

  /// Removed, its last day already over; shown gray for
  /// [kRemovedPlanTileDays] days.
  removed,
}

/// One habit tile on the plan card: which shared-plan slot it is (the index
/// into RoomParticipant.linkedHabitIds / RoomModel.sharedHabits) and which
/// row it sits in.
class RoomPlanTile {
  final int slot;
  final RoomPlanTileRow row;

  /// This member chose to skip the slot (kDeclinedSlot). Only ever in
  /// [RoomPlanTileRow.today]: a skipped slot the leader then removed has
  /// nothing of this member's in it, so it gets no tile at all.
  final bool skipped;

  const RoomPlanTile({
    required this.slot,
    required this.row,
    this.skipped = false,
  });

  @override
  bool operator ==(Object other) =>
      other is RoomPlanTile &&
      other.slot == slot &&
      other.row == row &&
      other.skipped == skipped;

  @override
  int get hashCode => Object.hash(slot, row, skipped);

  @override
  String toString() => 'RoomPlanTile($slot, ${row.name}'
      '${skipped ? ', skipped' : ''})';
}

/// The tiles [mine]'s plan card draws at [now], in slot order within each
/// row. Pure, so every case the card can be in is a hand-built test.
///
/// No tile at all for:
///  * a slot with no name (not answered yet: the new-habit banner speaks for
///    it);
///  * a LEGACY removal (no stopsOn): a data repair that counted on no day;
///  * a slot removed before this member joined, or one that never counted
///    (added and removed the same day, or before the room started);
///  * a skipped slot the leader removed;
///  * a removed slot more than [kRemovedPlanTileDays] days past its last day.
List<RoomPlanTile> roomPlanTilesFor(
  RoomModel room,
  RoomParticipant mine,
  DateTime now,
) {
  final today = now.effectiveDay;
  final todayKey = today.toDateKey();
  final shared = room.habitMode == RoomHabitMode.shared;
  final out = <RoomPlanTile>[];
  for (var i = 0; i < mine.linkedHabitNames.length; i++) {
    if (mine.linkedHabitNames[i].trim().isEmpty) continue;
    final skipped =
        i < mine.linkedHabitIds.length && mine.linkedHabitIds[i] == kDeclinedSlot;
    if (!shared || i >= room.sharedHabits.length) {
      out.add(RoomPlanTile(slot: i, row: RoomPlanTileRow.today, skipped: skipped));
      continue;
    }
    final t = room.sharedHabits[i];
    if (!t.isRemoved) {
      out.add(RoomPlanTile(slot: i, row: RoomPlanTileRow.today, skipped: skipped));
      continue;
    }
    final stops = t.stopsOn;
    if (stops == null) continue;
    if (skipped) continue;
    if (mine.slotRemovedBeforeJoin(room, i)) continue;
    if (stops.compareTo(room.slotJoinedPlanKey(i)) <= 0) continue;
    if (t.liveOn(todayKey)) {
      out.add(RoomPlanTile(slot: i, row: RoomPlanTileRow.lastDay));
      continue;
    }
    final stopDay = DateTime.tryParse(stops);
    if (stopDay == null) continue;
    // stopsOn is the first day it no longer counts, so the day before it was
    // the last one; a tile shown the morning after is one day past it.
    // Counted on UTC dates: two local midnights either side of a clock
    // change are 23 or 25 hours apart, and inDays would floor the 23.
    final daysPast = DateTime.utc(today.year, today.month, today.day)
            .difference(DateTime.utc(stopDay.year, stopDay.month, stopDay.day))
            .inDays +
        1;
    if (daysPast <= kRemovedPlanTileDays) {
      out.add(RoomPlanTile(slot: i, row: RoomPlanTileRow.removed));
    }
  }
  const order = {
    RoomPlanTileRow.today: 0,
    RoomPlanTileRow.lastDay: 1,
    RoomPlanTileRow.removed: 2,
  };
  // A stable sort: slot order stays within each row.
  final indexed = [for (var k = 0; k < out.length; k++) (k, out[k])];
  indexed.sort((a, b) {
    final byRow = order[a.$2.row]!.compareTo(order[b.$2.row]!);
    return byRow != 0 ? byRow : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Whether the plan card's tiles work as the room's habit filter (tap one and
/// every member's strip shows that habit alone): a shared plan, because only
/// there is slot [i] the same habit on every row, in a room that has started,
/// because a lobby has no days to show.
bool roomHabitFilterAvailable(RoomModel room, {DateTime? now}) =>
    room.habitMode == RoomHabitMode.shared &&
    !room.isLobby &&
    room.hasStartedAt(now ?? DateTime.now());
