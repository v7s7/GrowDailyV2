// What a Room does about a habit it can no longer resolve, and why the
// answer is deliberately conservative.
//
// A paused habit stays linked to its rooms (pausing is reversible; see
// GridScreen._pauseHabit for why unlinking was tried and reverted). The
// grading code therefore meets a linked id it cannot find in the active
// habit list, and both sync paths treat that as "this device cannot grade
// this room correctly right now" rather than guessing.
//
// It is tempting to make grading resolve paused habits instead, so the
// paused days drop out of the scheduled set. These tests record why that
// is NOT what the app does: a day with nothing scheduled is a FINISHED
// day here, worth full credit, because that is what a weekly quota's rest
// day means. Dropping a paused habit out of the denominator would pay a
// member 100% a day for pausing everything, keep their streak perfect,
// and in a competitive room hand them the podium prize.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

RoomModel _room({required DateTime start}) => RoomModel(
      code: 'A8GEL7',
      name: 'الإلتزااام',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: start,
      habitMode: RoomHabitMode.own,
      duration: RoomDuration.fixed,
      startDate: start,
      endDate: start.add(const Duration(days: 90)),
    );

RoomParticipant _participant({
  List<String> linkedHabitIds = const ['h1'],
  Map<String, int> dailyDoneCount = const {},
  Map<String, int> dailyScheduledCount = const {},
  DateTime? joinedAt,
}) =>
    RoomParticipant(
      uid: 'member-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: joinedAt ?? DateTime(2026, 7, 28),
      linkedHabitIds: linkedHabitIds,
      dailyDoneCount: dailyDoneCount,
      dailyScheduledCount: dailyScheduledCount,
      lastUpdated: DateTime(2026, 7, 28),
    );

void main() {
  test('a day that asks nothing is FULL credit, not a neutral day', () {
    // The rest-day rule, pinned here because it is what a well-meaning
    // change to Room grading would trip over: a paused habit must not
    // simply vanish from the scheduled set.
    final p = _participant(
      dailyScheduledCount: const {'2026-08-19': 0},
    );
    expect(p.creditFor('2026-08-19'), 1.0,
        reason: 'nothing asked means the day is finished, by design');
    expect(p.isFullyDone('2026-08-19'), isTrue,
        reason: 'and it keeps the room streak alive');
  });

  test('a normal day still grades on what was actually done', () {
    final p = _participant(
      linkedHabitIds: const ['h1', 'h2'],
      dailyDoneCount: const {'2026-08-19': 1},
      dailyScheduledCount: const {'2026-08-19': 2},
    );
    expect(p.creditFor('2026-08-19'), 0.5);
    expect(p.isFullyDone('2026-08-19'), isFalse);
  });

  test('only a ROOM-level pause shortens the elapsed-days denominator', () {
    // The other half of why a paused habit cannot "drop out of both
    // sides": there is no per-participant, per-habit pause concept in the
    // denominator at all. A habit-paused day would go free in the
    // numerator while still counting here.
    //
    // Both rooms below already ended, so lastCountedDay is their endDate
    // and neither figure moves with the calendar.
    final start = DateTime(2020, 1, 1);
    final ended = RoomModel(
      code: 'ENDED1',
      name: 'ended',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: start,
      habitMode: RoomHabitMode.own,
      duration: RoomDuration.fixed,
      startDate: start,
      endDate: DateTime(2020, 1, 10),
    );
    // Joined on day one of that room, or countedStartIn clamps the
    // window to nothing and both figures collapse to the floor of 1.
    final p = _participant(joinedAt: start);
    final full = p.daysElapsedIn(ended);

    final withRoomPause = RoomModel(
      code: 'ENDED2',
      name: 'ended, paused',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: start,
      habitMode: RoomHabitMode.own,
      duration: RoomDuration.fixed,
      startDate: start,
      endDate: DateTime(2020, 1, 10),
      pausedSpans: const [(from: '2020-01-03', to: '2020-01-05')],
    );
    expect(p.daysElapsedIn(withRoomPause), full - 3,
        reason: 'three room-paused days stop being elapsed');
  });

  test('pausing leaves the link in place, so the id still occupies a slot',
      () {
    // countedHabitIdsIn reads the participant doc, never the habit list.
    // This is exactly why grading meets an id it cannot resolve, instead
    // of the link quietly disappearing when a habit is paused.
    final room = _room(start: DateTime(2026, 7, 28));
    final p = _participant(linkedHabitIds: const ['paused-habit']);
    expect(p.countedHabitIdsIn(room), contains('paused-habit'));
  });
}
