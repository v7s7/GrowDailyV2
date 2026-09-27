// The plan card's rows (roomPlanTilesFor), on room اذكار الصباح as it was on
// 26-27 September 2026: the leader removed four of its seven habits at 14:50
// on the 26th, and brought two of them back at 06:42 on the 27th.
//
// Aziz's report, 06:15 on the 27th: the card said «1 من 3 اليوم» (right)
// above seven chips, four tagged «آخر يوم». Their last day was the 26th,
// still open until 10:00, so they were drawn in today's row with a tag that
// read as "today is the last day".
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_plan_tiles.dart';

RoomHabitTemplate _slot(
  String name, {
  String? addedDay,
  DateTime? removedAt,
  String? stopsOn,
  DateTime? restoredAt,
}) =>
    RoomHabitTemplate(
      name: name,
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      addedDay: addedDay,
      addedAt: addedDay == null ? null : DateTime.parse('${addedDay}T22:14:00'),
      removedAt: removedAt,
      removedBy: removedAt == null ? null : 'leader-uid',
      stopsOn: stopsOn,
      restoredAt: restoredAt,
      restoredBy: restoredAt == null ? null : 'leader-uid',
    );

final _removed = DateTime(2026, 9, 26, 14, 50);

/// PBYAS5's plan. [restored] brings back سنة الفجر and الضحى, as the leader
/// did at 06:42 on the 27th.
RoomModel _room({bool restored = false, String status = 'active'}) {
  RoomHabitTemplate removedOrBack(String name) => restored
      ? _slot(name, addedDay: '2026-09-24', restoredAt: DateTime(2026, 9, 27, 6, 42))
      : _slot(name, addedDay: '2026-09-24', removedAt: _removed, stopsOn: '2026-09-27');
  return RoomModel(
    code: 'PBYAS5',
    name: 'اذكار الصباح',
    createdBy: 'leader-uid',
    createdByName: 'نور',
    createdAt: DateTime(2026, 8, 14),
    habitMode: RoomHabitMode.shared,
    duration: RoomDuration.fixed,
    startDate: DateTime(2026, 8, 14),
    endDate: DateTime(2026, 10, 29),
    status: status,
    sharedHabits: [
      _slot('أذكار الصباح'),
      _slot('سورة الملك'),
      _slot('صدقة', addedDay: '2026-09-21'),
      _slot('سنة الظهر البعدية',
          addedDay: '2026-09-24', removedAt: _removed, stopsOn: '2026-09-27'),
      removedOrBack('سنة الفجر'),
      removedOrBack('الضحى'),
      _slot('الوتر',
          addedDay: '2026-09-24', removedAt: _removed, stopsOn: '2026-09-27'),
    ],
  );
}

RoomParticipant _me({
  List<String>? ids,
  DateTime? joinedAt,
}) =>
    RoomParticipant(
      uid: 'me-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: joinedAt ?? DateTime(2026, 8, 14),
      linkedHabitIds: ids ?? const ['h0', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'],
      linkedHabitNames: const [
        'أذكار الصباح',
        'سورة الملك',
        'الصدقة ولو بالقليل',
        'سنة الظهر البعدية',
        'سنة الفجر',
        'صلاة الضحى',
        'صلاة الوتر',
      ],
      lastUpdated: DateTime(2026, 9, 27),
    );

List<int> _slots(List<RoomPlanTile> tiles, RoomPlanTileRow row) =>
    [for (final t in tiles) if (t.row == row) t.slot];

void main() {
  group('the morning after the removal', () {
    test('06:15: today holds the three that count, the four removed are gray',
        () {
      final tiles = roomPlanTilesFor(_room(), _me(), DateTime(2026, 9, 27, 6, 15));
      expect(_slots(tiles, RoomPlanTileRow.today), [0, 1, 2],
          reason: 'the same three the headline «1 من 3» counts');
      expect(_slots(tiles, RoomPlanTileRow.lastDay), isEmpty,
          reason: 'their last day was yesterday, not today');
      expect(_slots(tiles, RoomPlanTileRow.removed), [3, 4, 5, 6]);
    });

    test('still gray at 09:59, while yesterday itself is still open', () {
      final tiles = roomPlanTilesFor(_room(), _me(), DateTime(2026, 9, 27, 9, 59));
      expect(_slots(tiles, RoomPlanTileRow.today), [0, 1, 2]);
      expect(_slots(tiles, RoomPlanTileRow.removed), [3, 4, 5, 6]);
    });

    test('after the 06:42 restore: five today, two gray', () {
      final tiles = roomPlanTilesFor(
          _room(restored: true), _me(), DateTime(2026, 9, 27, 7, 40));
      expect(_slots(tiles, RoomPlanTileRow.today), [0, 1, 2, 4, 5]);
      expect(_slots(tiles, RoomPlanTileRow.removed), [3, 6]);
    });
  });

  test('the removal day: the four still count, in their own row', () {
    final tiles = roomPlanTilesFor(_room(), _me(), DateTime(2026, 9, 26, 18, 50));
    expect(_slots(tiles, RoomPlanTileRow.today), [0, 1, 2]);
    expect(_slots(tiles, RoomPlanTileRow.lastDay), [3, 4, 5, 6]);
    expect(_slots(tiles, RoomPlanTileRow.removed), isEmpty);
  });

  test('a removed habit stays gray for seven days after its last day', () {
    // Last counted day 26 Sep: gray from the 27th through 3 Oct.
    final seventh =
        roomPlanTilesFor(_room(), _me(), DateTime(2026, 10, 3, 23, 59));
    expect(_slots(seventh, RoomPlanTileRow.removed), [3, 4, 5, 6]);
    final eighth = roomPlanTilesFor(_room(), _me(), DateTime(2026, 10, 4, 0, 1));
    expect(_slots(eighth, RoomPlanTileRow.removed), isEmpty);
    expect(_slots(eighth, RoomPlanTileRow.today), [0, 1, 2]);
  });

  test('rows keep plan order, whatever order the slots were removed in', () {
    final tiles = roomPlanTilesFor(_room(), _me(), DateTime(2026, 9, 27, 8));
    expect(tiles.map((t) => t.slot).toList(), [0, 1, 2, 3, 4, 5, 6]);
  });

  group('no tile at all', () {
    RoomModel withSlot3(RoomHabitTemplate t) {
      final r = _room(restored: true);
      return RoomModel(
        code: r.code,
        name: r.name,
        createdBy: r.createdBy,
        createdByName: r.createdByName,
        createdAt: r.createdAt,
        habitMode: r.habitMode,
        duration: r.duration,
        startDate: r.startDate,
        endDate: r.endDate,
        sharedHabits: [...r.sharedHabits]..[3] = t,
      );
    }

    test('a legacy removal (no stopsOn), which counted on no day', () {
      final room = withSlot3(_slot('سنة الظهر البعدية',
          addedDay: '2026-09-24', removedAt: _removed));
      final tiles = roomPlanTilesFor(room, _me(), DateTime(2026, 9, 26, 18));
      expect(tiles.map((t) => t.slot), isNot(contains(3)));
    });

    test('a habit added and removed the same day, which never counted', () {
      final room = withSlot3(_slot('سنة الظهر البعدية',
          addedDay: '2026-09-26', removedAt: _removed, stopsOn: '2026-09-26'));
      final tiles = roomPlanTilesFor(room, _me(), DateTime(2026, 9, 26, 18));
      expect(tiles.map((t) => t.slot), isNot(contains(3)));
    });

    test('a habit removed before this member joined', () {
      final tiles = roomPlanTilesFor(
        _room(),
        _me(joinedAt: DateTime(2026, 9, 26, 20)),
        DateTime(2026, 9, 27, 8),
      );
      expect(_slots(tiles, RoomPlanTileRow.removed), isEmpty);
      expect(_slots(tiles, RoomPlanTileRow.today), [0, 1, 2]);
    });

    test('a skipped habit the leader then removed', () {
      final tiles = roomPlanTilesFor(
        _room(),
        _me(ids: const ['h0', 'h1', 'h2', kDeclinedSlot, 'h4', 'h5', 'h6']),
        DateTime(2026, 9, 26, 18),
      );
      expect(tiles.map((t) => t.slot), isNot(contains(3)));
      expect(_slots(tiles, RoomPlanTileRow.lastDay), [4, 5, 6]);
    });

    test('a slot with no name yet (the new-habit banner speaks for it)', () {
      final me = RoomParticipant(
        uid: 'me-uid',
        displayName: 'Aziz',
        characterId: 'male_ghutra_blue',
        joinedAt: DateTime(2026, 8, 14),
        linkedHabitIds: const ['h0', 'h1'],
        linkedHabitNames: const ['أذكار الصباح', ' '],
        lastUpdated: DateTime(2026, 9, 27),
      );
      final tiles =
          roomPlanTilesFor(_room(restored: true), me, DateTime(2026, 9, 27, 8));
      expect(tiles.map((t) => t.slot).toList(), [0]);
    });
  });

  test('a skipped habit still in the plan sits in today\'s row, marked', () {
    final tiles = roomPlanTilesFor(
      _room(restored: true),
      _me(ids: const ['h0', kDeclinedSlot, 'h2', 'h3', 'h4', 'h5', 'h6']),
      DateTime(2026, 9, 27, 8),
    );
    expect(
      tiles.firstWhere((t) => t.slot == 1),
      const RoomPlanTile(slot: 1, row: RoomPlanTileRow.today, skipped: true),
    );
  });

  test('an own-habits room has no removals: every tile is today\'s', () {
    final room = RoomModel(
      code: 'OWN001',
      name: 'عاداتي',
      createdBy: 'leader-uid',
      createdByName: 'نور',
      createdAt: DateTime(2026, 9, 1),
      habitMode: RoomHabitMode.own,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 10, 1),
    );
    final tiles = roomPlanTilesFor(room, _me(), DateTime(2026, 9, 27, 8));
    expect(_slots(tiles, RoomPlanTileRow.today), [0, 1, 2, 3, 4, 5, 6]);
  });

  group('roomHabitFilterAvailable', () {
    test('a running shared room', () {
      expect(roomHabitFilterAvailable(_room(), now: DateTime(2026, 9, 27)),
          isTrue);
    });

    test('never in the lobby, where no day has counted', () {
      expect(
        roomHabitFilterAvailable(_room(status: 'lobby'),
            now: DateTime(2026, 9, 27)),
        isFalse,
      );
    });

    test('never in an own-habits room, where slot i differs per member', () {
      final own = RoomModel(
        code: 'OWN001',
        name: 'عاداتي',
        createdBy: 'leader-uid',
        createdByName: 'نور',
        createdAt: DateTime(2026, 9, 1),
        habitMode: RoomHabitMode.own,
        duration: RoomDuration.fixed,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 10, 1),
      );
      expect(roomHabitFilterAvailable(own, now: DateTime(2026, 9, 27)), isFalse);
    });

    test('not before the first day', () {
      expect(roomHabitFilterAvailable(_room(), now: DateTime(2026, 8, 13)),
          isFalse);
    });
  });
}
