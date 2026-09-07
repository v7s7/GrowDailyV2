import 'models/square_state.dart';

/// Whether the palette must treat a square as a PAID completion, so that
/// changing it reverses the canonical reward (uncompleteHabit) instead of
/// falling through to the Grid's flat-rate colour maths.
///
/// Pure, so the rule can be pinned in a test; the cell editor hands it the
/// five facts it has and does what it says.
///
/// The rule: on an open day (today, or yesterday inside its grace window), a
/// green, blue, or mid-count yellow square that the flat path did not paint
/// is a canonical completion. Every canonical completion on an open day
/// arrives through completeHabit (the square tap, the palette, the Today
/// list, the steps ladder), and none of those leave a flat receipt; the
/// flat path records what it paid on every square it colours (see
/// WeeklyGridState.flatPaid). So "no receipt" is what tells the two apart.
///
/// Two ways the old check got this wrong, both seen live on 2026-09-07:
///  - it listed `complete` and `partial` but not `bonus`, so a blue square,
///    which is exactly what the steps ladder paints at 120% of the goal,
///    fell through to the flat path. Picking «لم يكتمل» on it took a flat
///    15 XP and left the completion, the gold, the streak and the room
///    credit all standing: "I un-did it and it still counts";
///  - it asked `isToday` where every other reward decision asks
///    `isOpenDay`, so for the ten grace hours of every morning a correction
///    to yesterday's green square did the same.
///
/// [doneToday] is today's completion count for the habit and is consulted
/// only for today, because that map is today's; a grace day has no
/// synchronous count, and there the colour plus the missing receipt is the
/// evidence. If a grace-day square turns out not to be a completion after
/// all, uncompleteHabit reads the stored day, finds nothing to reverse, and
/// declines, so routing it there costs nothing.
bool paletteLockedFor({
  required bool isOpenDay,
  required bool isToday,
  required SquareState current,
  required int doneToday,
  required int target,
  required int flatPaid,
}) {
  if (!isOpenDay) return false;
  final paidColour = current == SquareState.complete ||
      current == SquareState.bonus ||
      (target > 1 && current == SquareState.partial);
  if (!paidColour) return false;
  if (flatPaid != 0) return false;
  if (isToday) return doneToday > 0;
  return true;
}

/// The states the long-press palette offers for a habit.
///
/// A build habit gets all six. A quit habit gets four: a day is kept,
/// slipped, rested, or not recorded. «جزئي» has no meaning for abstinence,
/// and «إنجاز إضافي» ("more than asked", +15 XP) offered on a quit habit
/// paid more for a clean day than the clean day itself (2026-09-08).
List<SquareState> paletteStatesFor({required bool quit}) => quit
    ? const [
        SquareState.complete,
        SquareState.failed,
        SquareState.skipped,
        SquareState.none,
      ]
    : const [
        SquareState.complete,
        SquareState.partial,
        SquareState.bonus,
        SquareState.failed,
        SquareState.skipped,
        SquareState.none,
      ];
