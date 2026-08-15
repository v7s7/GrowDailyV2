// The app-open "leader added a habit to your room" prompt's data source.
//
// pendingSharedPlanPromptsProvider must flag exactly the rooms _MyPlanCard's
// in-room _NewHabitBanner flags (mine.linkedHabitIds.length <
// room.sharedHabits.length) — the two surfaces show the same resolve sheet,
// so disagreeing about WHEN would mean a popup with no banner behind it, or
// a banner the app-open prompt never mentioned. Pure provider tests with
// every upstream stream overridden; no Firestore.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

import '../../helpers/fake_user.dart';

RoomModel _sharedRoom({
  required String code,
  required int planSize,
  DateTime? end,
}) =>
    RoomModel(
      code: code,
      name: 'Room $code',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 8, 1),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 8, 1),
      endDate: end ?? DateTime(2026, 12, 31),
      sharedHabits: [
        for (var i = 0; i < planSize; i++)
          RoomHabitTemplate(
            name: 'Habit $i',
            category: HabitCategory.faith,
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
          ),
      ],
    );

RoomParticipant _me(List<String> linked) => RoomParticipant(
      uid: 'me-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 8, 2),
      linkedHabitIds: linked,
      lastUpdated: DateTime(2026, 8, 10),
    );

ProviderContainer _container({
  required List<String> codes,
  required Map<String, RoomModel?> rooms,
  required Map<String, List<RoomParticipant>> participants,
}) =>
    ProviderContainer(overrides: [
      authStateProvider
          .overrideWith((ref) => Stream<User?>.value(fakeUser('me-uid'))),
      myRoomCodesProvider.overrideWith((ref) => Stream.value(codes)),
      roomProvider
          .overrideWith((ref, code) => Stream<RoomModel?>.value(rooms[code])),
      roomParticipantsProvider.overrideWith((ref, code) =>
          Stream<List<RoomParticipant>>.value(participants[code] ?? const [])),
    ]);

Future<void> _settle(ProviderContainer c, List<String> codes) async {
  // StreamProviders need one microtask turn to surface their first value.
  await c.read(authStateProvider.future);
  await c.read(myRoomCodesProvider.future);
  for (final code in codes) {
    await c.read(roomProvider(code).future);
    await c.read(roomParticipantsProvider(code).future);
  }
}

void main() {
  test('a grown shared plan is flagged; a resolved one is not', () async {
    final c = _container(
      codes: const ['GROWN1', 'FINE01'],
      rooms: {
        'GROWN1': _sharedRoom(code: 'GROWN1', planSize: 2),
        'FINE01': _sharedRoom(code: 'FINE01', planSize: 2),
      },
      participants: {
        // Joined when the plan had 1 habit; the leader added a second.
        'GROWN1': [
          _me(const ['h1'])
        ],
        'FINE01': [
          _me(const ['h1', 'h2'])
        ],
      },
    );
    addTearDown(c.dispose);
    await _settle(c, const ['GROWN1', 'FINE01']);

    final pending = c.read(pendingSharedPlanPromptsProvider);
    expect(pending.map((p) => p.room.code), ['GROWN1']);
    expect(pending.single.mine.uid, 'me-uid');
  });

  test('own-mode and ended rooms never prompt', () async {
    final ownMode = RoomModel(
      code: 'OWN001',
      name: 'Own',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 8, 1),
      habitMode: RoomHabitMode.own,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 12, 31),
    );
    final c = _container(
      codes: const ['OWN001', 'ENDED1'],
      rooms: {
        'OWN001': ownMode,
        // Grown plan, but the room finished long ago — nothing to act on.
        'ENDED1':
            _sharedRoom(code: 'ENDED1', planSize: 3, end: DateTime(2026, 8, 5)),
      },
      participants: {
        'OWN001': [_me(const [])],
        'ENDED1': [
          _me(const ['h1'])
        ],
      },
    );
    addTearDown(c.dispose);
    await _settle(c, const ['OWN001', 'ENDED1']);

    expect(c.read(pendingSharedPlanPromptsProvider), isEmpty);
  });

  test('a room this account is not a participant of is skipped', () async {
    final c = _container(
      codes: const ['GROWN1'],
      rooms: {'GROWN1': _sharedRoom(code: 'GROWN1', planSize: 2)},
      participants: const {'GROWN1': []},
    );
    addTearDown(c.dispose);
    await _settle(c, const ['GROWN1']);

    expect(c.read(pendingSharedPlanPromptsProvider), isEmpty);
  });
}
