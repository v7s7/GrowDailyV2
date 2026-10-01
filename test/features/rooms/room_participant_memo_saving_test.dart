import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart'
    show roomRaceStripEnd, roomRaceStripFor;

/// What the per-instance day memo on RoomParticipant (room_model.dart,
/// _DayMemo) saves, counted with its assert-only counters: each answer is
/// worked out once per instance and turn of the event loop, the same
/// questions asked again in that turn work out nothing again, and the next
/// turn works everything out afresh (the device's time zone may have moved
/// in between). room_participant_memo_parity_test.dart pins that the
/// answers themselves did not move.
///
/// The workload is the one the memo was measured on (2026-09-30): the Room
/// Race snapshot (rooms_notifier.dart, myRoomRaceSnapshotProvider) over 5
/// members of a three-slot shared room, 60 days each. The room has ended, so
/// its last counted day is its end day whenever the suite runs.

final _start = DateTime(2026, 7, 3);
final _end = DateTime(2026, 8, 31);
final _now = DateTime(2026, 9, 28, 12);

/// A fixed generator, so the records never depend on the SDK's Random.
class _Rng {
  _Rng(int seed) : _s = seed;
  int _s;
  int next(int max) {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return (_s >> 8) % max;
  }
}

/// A member that notes every date key the board asks it about, so the
/// counters can be held against the number of distinct questions.
class _Asked extends RoomParticipant {
  _Asked({
    required super.uid,
    required super.linkedHabitIds,
    required super.dailyDoneCount,
    required super.dailyScheduledCount,
    required super.dailyPartialCount,
    required super.dailyRestedCount,
    required super.habitRules,
    required super.lastUpdated,
    super.restAllowanceFrom,
    super.lastSyncedDay,
    super.lastSyncedAt,
  }) : super(
          displayName: uid,
          characterId: 'male_ghutra_blue',
          joinedAt: DateTime(2026, 7, 2, 20),
        );

  final scheduledKeys = <String>{};
  final phantomKeys = <String>{};
  int scheduledCalls = 0;

  @override
  int scheduledCountFor(String dateKey) {
    scheduledCalls++;
    scheduledKeys.add(dateKey);
    return super.scheduledCountFor(dateKey);
  }

  @override
  double phantomWeightOn(RoomModel room, String dateKey) {
    phantomKeys.add(dateKey);
    return super.phantomWeightOn(room, dateKey);
  }
}

final _room = RoomModel(
  code: 'SAVE01',
  name: 'save',
  createdBy: 'u0',
  createdByName: 'L',
  createdAt: _start,
  habitMode: RoomHabitMode.shared,
  sharedHabits: const [
    RoomHabitTemplate(
      name: 'a',
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
    ),
    RoomHabitTemplate(
      name: 'b',
      category: HabitCategory.health,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
    ),
    RoomHabitTemplate(
      name: 'c',
      category: HabitCategory.health,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 4,
    ),
  ],
  duration: RoomDuration.fixed,
  startDate: _start,
  endDate: _end,
);

/// [_room] with its wall clock in the test's hands: [lastCountedDay] reads
/// [clock] where a real room reads DateTime.now(), so a test can turn the
/// day under one room instance.
class _ClockedRoom extends RoomModel {
  _ClockedRoom(this.clock)
      : super(
          code: _room.code,
          name: _room.name,
          createdBy: _room.createdBy,
          createdByName: _room.createdByName,
          createdAt: _room.createdAt,
          habitMode: _room.habitMode,
          sharedHabits: _room.sharedHabits,
          duration: _room.duration,
          startDate: _room.startDate,
          endDate: _room.endDate,
        );

  DateTime clock;

  @override
  DateTime get lastCountedDay => lastCountedDayAt(clock);
}

List<_Asked> _members() {
  final rng = _Rng(7);
  return [
    for (var u = 0; u < 5; u++)
      () {
        final done = <String, int>{};
        final sched = <String, int>{};
        final partial = <String, int>{};
        final rested = <String, int>{};
        for (var i = 0; i < 60; i++) {
          final k = DateTime(_start.year, _start.month, _start.day + i)
              .toDateKey();
          final r = rng.next(10);
          if (r < 6) done[k] = 1 + rng.next(3);
          if (r == 6) partial[k] = 1;
          if (r == 7) rested[k] = 3;
          if (rng.next(5) == 0) sched[k] = 2;
        }
        return _Asked(
          uid: 'u$u',
          // One member declined the second slot, so the plan has a phantom.
          linkedHabitIds: u == 4
              ? const ['h1', kDeclinedSlot, 'h3']
              : const ['h1', 'h2', 'h3'],
          dailyDoneCount: done,
          dailyScheduledCount: sched,
          dailyPartialCount: partial,
          dailyRestedCount: rested,
          restAllowanceFrom: DateTime(2026, 7, 9).toDateKey(),
          habitRules: {
            'h1': [
              RoomHabitRule(
                from: _start.toDateKey(),
                frequencyType: HabitFrequencyType.daily,
                frequencyTarget: 1,
              ),
            ],
            'h2': [
              RoomHabitRule(
                from: _start.toDateKey(),
                frequencyType: HabitFrequencyType.daily,
                frequencyTarget: 1,
              ),
            ],
            'h3': [
              RoomHabitRule(
                from: _start.toDateKey(),
                frequencyType: HabitFrequencyType.weekly,
                frequencyTarget: 4,
              ),
            ],
          },
          lastSyncedDay: DateTime(2026, 8, 20).toDateKey(),
          lastSyncedAt: DateTime(2026, 8, 20, 21),
          lastUpdated: DateTime(2026, 8, 20, 21),
        );
      }(),
  ];
}

/// The race snapshot's reads, in its order: the standings (each member's
/// room score on its own clock), then each row at the provider's clock.
void _snapshot(List<RoomParticipant> members, {bool standings = true}) {
  if (standings) _room.standings(members);
  final stripEnd = roomRaceStripEnd(_room, _now);
  final todayKey = _room.lastCountedDayAt(_now).toDateKey();
  for (final p in members) {
    p.planCoverageIn(_room, now: _now);
    p.roomDaysCompleted(_room, now: _now);
    p.roomProgressRatio(_room, now: _now);
    p.roomDaysElapsedIn(_room, now: _now);
    p.currentStreak(_room, now: _now);
    p.isStoodDownOn(todayKey);
    p.isFullyDone(todayKey);
    roomRaceStripFor(_room, p, end: stripEnd, now: _now);
  }
}

void _resetCounters() {
  RoomParticipant.debugScheduledComputed = 0;
  RoomParticipant.debugPhantomComputed = 0;
  RoomParticipant.debugCountableComputed = 0;
  RoomParticipant.debugConcededComputed = 0;
}

void main() {
  setUp(_resetCounters);

  test('scheduledCountFor is worked out once per member and day', () {
    final members = _members();
    _snapshot(members);
    final distinct =
        members.fold<int>(0, (n, p) => n + p.scheduledKeys.length);
    final calls = members.fold<int>(0, (n, p) => n + p.scheduledCalls);
    expect(RoomParticipant.debugScheduledComputed, distinct);
    expect(distinct, lessThanOrEqualTo(5 * 70));
    // Asked many times over for every answer it works out.
    expect(calls, greaterThan(10 * distinct));

    _resetCounters();
    _snapshot(members);
    expect(RoomParticipant.debugScheduledComputed, 0);
  });

  test('phantomWeightOn is worked out once per member, room and day', () {
    final members = _members();
    _snapshot(members);
    final distinct = members.fold<int>(0, (n, p) => n + p.phantomKeys.length);
    expect(RoomParticipant.debugPhantomComputed, distinct);

    _resetCounters();
    _snapshot(members);
    expect(RoomParticipant.debugPhantomComputed, 0);

    // Another instance of the same room is another room to the memo: the
    // answers are worked out again, never borrowed.
    final copy = RoomModel(
      code: _room.code,
      name: _room.name,
      createdBy: _room.createdBy,
      createdByName: _room.createdByName,
      createdAt: _room.createdAt,
      habitMode: _room.habitMode,
      sharedHabits: _room.sharedHabits,
      duration: _room.duration,
      startDate: _room.startDate,
      endDate: _room.endDate,
    );
    final key = DateTime(2026, 8, 10).toDateKey();
    final p = members.last;
    final before = p.phantomWeightOn(_room, key);
    _resetCounters();
    expect(p.phantomWeightOn(copy, key), before);
    expect(RoomParticipant.debugPhantomComputed, 1);
  });

  test('the conceded days are walked once per member, room and last day', () {
    final members = _members();
    _snapshot(members);
    expect(RoomParticipant.debugConcededComputed, members.length);

    _resetCounters();
    _snapshot(members);
    expect(RoomParticipant.debugConcededComputed, 0);

    // The public set is still built fresh on every call.
    final p = members.first;
    expect(
      identical(p.concededDaysIn(_room), p.concededDaysIn(_room)),
      isFalse,
    );
    expect(RoomParticipant.debugConcededComputed, 2);
  });

  test('the conceded days are walked again once the last counted day moves',
      () {
    final p = _members().first;
    final room = _ClockedRoom(DateTime(2026, 8, 20, 12));
    p.roomDaysElapsedIn(room, now: room.clock);
    expect(RoomParticipant.debugConcededComputed, 1);
    p.roomProgressRatio(room, now: room.clock);
    expect(RoomParticipant.debugConcededComputed, 1);

    // Midnight: the same room instance, a new last counted day.
    room.clock = DateTime(2026, 8, 21);
    p.roomDaysElapsedIn(room, now: room.clock);
    expect(RoomParticipant.debugConcededComputed, 2);
    p.daysElapsedIn(room, now: room.clock);
    expect(RoomParticipant.debugConcededComputed, 2);
  });

  test('a kept answer lasts one turn of the event loop, no longer', () async {
    final members = _members();
    _snapshot(members);
    final scheduled = RoomParticipant.debugScheduledComputed;
    final phantom = RoomParticipant.debugPhantomComputed;
    final conceded = RoomParticipant.debugConcededComputed;
    expect(scheduled, greaterThan(0));
    expect(phantom, greaterThan(0));
    expect(conceded, members.length);

    // The rest of the same turn reads every answer back.
    _resetCounters();
    _snapshot(members);
    expect(RoomParticipant.debugScheduledComputed, 0);
    expect(RoomParticipant.debugPhantomComputed, 0);
    expect(RoomParticipant.debugConcededComputed, 0);

    // The next turn works them all out again, on the same instances, so a
    // time zone the device changed in between is read exactly as the
    // uncached code reads it.
    await Future<void>.delayed(Duration.zero);
    _resetCounters();
    _snapshot(members);
    expect(RoomParticipant.debugScheduledComputed, scheduled);
    expect(RoomParticipant.debugPhantomComputed, phantom);
    expect(RoomParticipant.debugConcededComputed, conceded);
    expect(RoomParticipant.debugCountableComputed, greaterThan(0));
  });

  test('dayIsCountableAt is worked out once per member, clock and day', () {
    final members = _members();
    _snapshot(members);
    // The standings' own clock, then the rows' one.
    final days = _end.difference(_start).inDays + 1;
    expect(
      RoomParticipant.debugCountableComputed,
      lessThanOrEqualTo(2 * members.length * days),
    );
    expect(RoomParticipant.debugCountableComputed, greaterThan(0));

    // The rows again at the same clock: nothing new to work out.
    _resetCounters();
    _snapshot(members, standings: false);
    expect(RoomParticipant.debugCountableComputed, 0);

    // A different clock is a different question.
    final p = members.first;
    final key = DateTime(2026, 8, 12).toDateKey();
    p.dayIsCountableAt(key, _now);
    expect(RoomParticipant.debugCountableComputed, 0);
    p.dayIsCountableAt(key, DateTime(2026, 8, 13, 9, 59, 59));
    expect(RoomParticipant.debugCountableComputed, 1);
  });
}
