// A room ends when its last day closes, not at midnight.
//
// RoomModel.isEndedAt read `now.effectiveDay.isAfter(endDate)`, which rolls
// at midnight, while the final day itself stays markable until
// kDayCutoffHour the next morning (DateTimeGameExt.isOpenDayAt). For those
// ten hours the room was already "over": the podium could be claimed on a
// record that was missing every rival's night marks, the 2x boost stopped,
// and both sync paths skipped the room, so a completion made in the final
// day's grace tail never reached it.
//
// The boundary matters twice over, because the naive spelling of the fix
// (`!endDate.isOpenDayAt(now)`) is ALSO true before the end day begins, which
// called every running room ended: its finale announced on day one, its
// members not live, its shared-plan prompts silent. Both directions are
// pinned here.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

RoomModel _room({required DateTime? endDate}) => RoomModel(
  code: 'ELQVF8',
  name: 'Being Better',
  createdBy: 'aziz',
  createdByName: 'Aziz',
  createdAt: DateTime(2026, 9),
  habitMode: RoomHabitMode.shared,
  duration: endDate == null ? RoomDuration.open : RoomDuration.fixed,
  startDate: DateTime(2026, 9),
  endDate: endDate,
);

void main() {
  final lastDay = DateTime(2026, 9, 30);
  final room = _room(endDate: lastDay);

  test('live all through its final day', () {
    expect(room.isEndedAt(DateTime(2026, 9, 30, 0, 1)), isFalse);
    expect(room.isEndedAt(DateTime(2026, 9, 30, 23, 59)), isFalse);
  });

  test('still live in the final day grace tail, before the cutoff', () {
    // The whole point: a member finishing the last day at 02:00 is still
    // inside it, so the room must still count the mark and still pay 2x.
    expect(room.isEndedAt(DateTime(2026, 10, 1, 0, 5)), isFalse);
    expect(room.isEndedAt(DateTime(2026, 10, 1, 9, 59)), isFalse);
  });

  test('ended the moment that day closes', () {
    expect(room.isEndedAt(DateTime(2026, 10, 1, kDayCutoffHour)), isTrue);
    expect(room.isEndedAt(DateTime(2026, 10, 2, 8)), isTrue);
  });

  test('a room whose end is still ahead is never ended', () {
    // The regression the first spelling of this fix caused: "not open" is
    // also true for a day that has not started.
    for (final at in [
      DateTime(2026, 9, 12, 2),
      DateTime(2026, 9, 12, 11),
      DateTime(2026, 9, 29, 23, 59),
    ]) {
      expect(room.isEndedAt(at), isFalse, reason: 'at $at');
    }
  });

  test('an open-ended room never ends', () {
    final open = _room(endDate: null);
    expect(open.isEndedAt(DateTime(2027, 1, 1, 12)), isFalse);
  });

  test('grading still stops at the end date itself', () {
    // lastCountedDayAt is unchanged by any of this: the final day is the
    // last one that counts, even while the room stays live through its tail.
    expect(room.lastCountedDayAt(DateTime(2026, 10, 1, 0, 5)), lastDay);
    expect(room.lastCountedDayAt(DateTime(2026, 9, 20, 12)), DateTime(2026, 9, 20));
  });
}
