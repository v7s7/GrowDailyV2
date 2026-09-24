// The leader removing a habit from a running room's shared plan, as the
// model reads it. Aziz's rule, 2026-09-22: it still counts on the day it is
// removed, for everyone, and from the next day it counts for nobody; every
// day before stays exactly as it was played.
//
// Before this, removal took the slot out of EVERY day. Traced on the real
// grader (leader_remove_habit_sync_test.dart has the same board): the leader
// who removed the habit they had missed most went from 63% (third) to 100%
// (first), and the member who had done it every day from 82% to 63%.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

String _k(int d) => '2026-07-${d.toString().padLeft(2, '0')}';

RoomHabitTemplate _slot(
  String name, {
  DateTime? addedAt,
  String? addedDay,
  DateTime? removedAt,
  String? stopsOn,
  List<({String from, String to})> offSpans = const [],
}) =>
    RoomHabitTemplate(
      name: name,
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      addedAt: addedAt,
      addedDay: addedDay,
      removedAt: removedAt,
      removedBy: removedAt == null ? null : 'leader',
      stopsOn: stopsOn,
      offSpans: offSpans,
    );

RoomModel _room(List<RoomHabitTemplate> slots, {String status = 'active'}) =>
    RoomModel(
      code: 'RMV001',
      name: 'remove',
      createdBy: 'leader',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 7, 1),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 30),
      status: status,
      sharedHabits: slots,
    );

RoomHabitRule _rule(String from) => RoomHabitRule(
      from: from,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
    );

RoomParticipant _member({
  required List<String> linked,
  Map<String, int> done = const {},
  Map<String, int> scheduled = const {},
  DateTime? joinedAt,
  Map<int, String> declinedFrom = const {},
}) =>
    RoomParticipant(
      uid: 'm',
      displayName: 'm',
      characterId: 'male_ghutra_blue',
      joinedAt: joinedAt ?? DateTime(2026, 7, 1),
      linkedHabitIds: linked,
      dailyDoneCount: done,
      dailyScheduledCount: scheduled,
      habitRules: {
        for (final id in linked)
          if (id != kDeclinedSlot) id: [_rule('2026-07-01')],
      },
      slotDeclinedFrom: declinedFrom,
      lastUpdated: DateTime(2026, 7, 30),
    );

void main() {
  group('removalStopsOn: the removal day still counts', () {
    final quran = _slot('قراءة القرآن');
    final exercise = _slot('تمرين');

    test('a running room: from the next day', () {
      final room = _room([quran, exercise]);
      expect(
        removalStopsOn(room: room, index: 1, now: DateTime(2026, 7, 19, 22)),
        '2026-07-20',
      );
    });

    test('before 10:00, the calendar day, not the grace day', () {
      // Yesterday is still open, but the removal happens today.
      final room = _room([quran, exercise]);
      expect(
        removalStopsOn(room: room, index: 1, now: DateTime(2026, 7, 20, 8)),
        '2026-07-21',
      );
    });

    test('a habit added today is removed as a mistake: never counted', () {
      final room = _room([
        quran,
        _slot('تمرين', addedAt: DateTime(2026, 7, 19, 21), addedDay: _k(19)),
      ]);
      expect(
        removalStopsOn(room: room, index: 1, now: DateTime(2026, 7, 19, 21, 5)),
        _k(19),
      );
    });

    test('a slot the room was created with, removed on day one, counts that '
        'day', () {
      final room = _room([quran, exercise]);
      expect(
        removalStopsOn(room: room, index: 1, now: DateTime(2026, 7, 1, 12)),
        _k(2),
      );
    });

    test('a lobby: nothing ever counted', () {
      final room = _room([quran, exercise], status: 'lobby');
      expect(
        removalStopsOn(room: room, index: 1, now: DateTime(2026, 6, 28, 12)),
        '2026-06-28',
      );
    });
  });

  group('liveOn', () {
    test('a removed slot counts through the removal day and not after', () {
      final t = _slot('تمرين', removedAt: DateTime(2026, 7, 19, 22), stopsOn: _k(20));
      expect(t.liveOn(_k(1)), isTrue);
      expect(t.liveOn(_k(19)), isTrue);
      expect(t.liveOn(_k(20)), isFalse);
      expect(t.liveOn(_k(30)), isFalse);
    });

    test('a legacy removal (no stopsOn) counts on no day, as before', () {
      final t = _slot('تمرين', removedAt: DateTime(2026, 7, 10));
      expect(t.isLegacyRemoval, isTrue);
      expect(t.liveOn(_k(1)), isFalse);
      expect(t.liveOn(_k(20)), isFalse);
    });

    test('a stretch spent out and brought back stays out', () {
      final t = _slot('تمرين', offSpans: [(from: _k(20), to: _k(21))]);
      expect(t.liveOn(_k(19)), isTrue);
      expect(t.liveOn(_k(20)), isFalse);
      expect(t.liveOn(_k(21)), isFalse);
      expect(t.liveOn(_k(22)), isTrue);
    });
  });

  group('the stored shape', () {
    test('every new field round-trips, and copyWith keeps addedDay', () {
      final t = _slot(
        'تمرين',
        addedAt: DateTime(2026, 7, 5, 21),
        addedDay: _k(5),
        removedAt: DateTime(2026, 7, 19, 22),
        stopsOn: _k(20),
        offSpans: [(from: _k(8), to: _k(9))],
      );
      final back = RoomHabitTemplate.fromMap(t.toFirestore());
      expect(back.addedDay, _k(5));
      expect(back.removedBy, 'leader');
      expect(back.stopsOn, _k(20));
      expect(back.offSpans, [(from: _k(8), to: _k(9))]);
      expect(back.removedAt, DateTime(2026, 7, 19, 22));

      // The old removal rebuilt the element field by field and dropped
      // addedDay, sending every phone back to keying addedAt in its own
      // timezone.
      final cleared = back.copyWith(clearRemoval: true);
      expect(cleared.addedDay, _k(5));
      expect(cleared.isRemoved, isFalse);
      expect(cleared.stopsOn, isNull);
      expect(cleared.offSpans, [(from: _k(8), to: _k(9))]);
    });

    test('a Timestamp removedAt with no stopsOn reads as legacy', () {
      final t = RoomHabitTemplate.fromMap({
        'name': 'تمرين',
        'category': 'faith',
        'frequencyType': 'weekly',
        'frequencyTarget': 4,
        'removedAt': Timestamp.fromDate(DateTime(2026, 9, 9)),
      });
      expect(t.isLegacyRemoval, isTrue);
    });
  });

  group('which habits count', () {
    final room = _room([
      _slot('قراءة القرآن'),
      _slot('تمرين', removedAt: DateTime(2026, 7, 19, 22), stopsOn: _k(20)),
    ]);
    final m = _member(linked: const ['q', 'e']);

    test('the sync grades both, day by day', () {
      expect(m.gradedHabitIdsIn(room), ['q', 'e']);
      expect(m.countedHabitIdsOn(room, _k(19)), ['q', 'e']);
      expect(m.countedHabitIdsOn(room, _k(20)), ['q']);
    });

    test('still linked through the removal day and its grace tail', () {
      expect(m.countedHabitIdsIn(room, now: DateTime(2026, 7, 19, 23)),
          ['q', 'e']);
      // 08:00 the next morning: the 19th is still open until 10:00.
      expect(m.countedHabitIdsIn(room, now: DateTime(2026, 7, 20, 8)),
          ['q', 'e']);
      expect(m.countedHabitIdsIn(room, now: DateTime(2026, 7, 20, 10, 1)),
          ['q']);
    });

    test('a habit added and removed the same morning is never linked, not '
        'even through yesterday\'s grace tail', () {
      final mistake = _room([
        _slot('قراءة القرآن'),
        _slot('تمرين', addedDay: _k(15), addedAt: DateTime(2026, 7, 15, 7),
            removedAt: DateTime(2026, 7, 15, 7, 5), stopsOn: _k(15)),
      ]);
      expect(m.countedHabitIdsIn(mistake, now: DateTime(2026, 7, 15, 8)),
          ['q']);
      expect(m.gradedHabitIdsIn(mistake), ['q', 'e'],
          reason: 'graded on no day: its window is empty');
      // From the day it was added on, it asks nothing of anybody. (Before
      // it, the slot had not joined the plan, which the sync floors by the
      // rule it seeds from the addition day.)
      for (var d = 15; d <= 30; d++) {
        expect(m.countedHabitIdsOn(mistake, _k(d)), ['q'], reason: 'day $d');
        expect(mistake.slotLiveOn(1, _k(d)), isFalse, reason: 'day $d');
      }
    });

    test('in the lobby a removed habit is simply not linked', () {
      final lobby = _room([
        _slot('قراءة القرآن'),
        _slot('تمرين', removedAt: DateTime(2026, 6, 28, 8), stopsOn: '2026-06-28'),
      ], status: 'lobby');
      expect(m.countedHabitIdsIn(lobby, now: DateTime(2026, 6, 28, 9)), ['q']);
    });

    test('a legacy removal is graded on no day at all', () {
      final legacy = _room([
        _slot('قراءة القرآن'),
        _slot('تمرين', removedAt: DateTime(2026, 7, 10)),
      ]);
      expect(m.gradedHabitIdsIn(legacy), ['q']);
      expect(m.countedHabitIdsIn(legacy, now: DateTime(2026, 7, 2)), ['q']);
    });

    test('plan coverage keeps it today and drops it tomorrow', () {
      expect(m.planCoverageIn(room, now: DateTime(2026, 7, 19, 23)),
          (linked: 2, total: 2));
      expect(m.planCoverageIn(room, now: DateTime(2026, 7, 20, 12)),
          (linked: 1, total: 1));
    });

    test('nobody is asked to link a removed slot', () {
      final grown = _room([
        _slot('قراءة القرآن'),
        _slot('تمرين', addedDay: _k(10), addedAt: DateTime(2026, 7, 10),
            removedAt: DateTime(2026, 7, 12, 9), stopsOn: _k(13)),
        _slot('المشي', addedDay: _k(14), addedAt: DateTime(2026, 7, 14)),
      ]);
      final behind = _member(linked: const ['q']);
      expect(behind.pendingPlanSlotsIn(grown), [2]);
    });
  });

  group('the room score around a removal', () {
    // Unlinked: joined before the slot was added, never answered it.
    final room = _room([
      _slot('قراءة القرآن'),
      _slot('تمرين', addedDay: _k(5), addedAt: DateTime(2026, 7, 5),
          removedAt: DateTime(2026, 7, 10, 20), stopsOn: _k(11)),
    ]);

    test('an unanswered slot was asked of them from its addition through '
        'its removal day, and never after', () {
      final m = _member(linked: const ['q']);
      expect(m.phantomSlotsOn(room, _k(4)), 0);
      expect(m.phantomSlotsOn(room, _k(5)), 1);
      expect(m.phantomSlotsOn(room, _k(10)), 1);
      expect(m.phantomSlotsOn(room, _k(11)), 0);
      expect(m.phantomSlotsOn(room, _k(20)), 0);
    });

    test('someone who joined after it was removed is never charged for it, '
        'not even on the removal day', () {
      final late = _member(
        linked: const ['q', kDeclinedSlot],
        joinedAt: DateTime(2026, 7, 10, 21),
      );
      expect(late.slotRemovedBeforeJoin(room, 1), isTrue);
      expect(late.phantomSlotsOn(room, _k(10)), 0);
      expect(late.planCoverageIn(room, now: DateTime(2026, 7, 10, 22)),
          (linked: 1, total: 1));
    });

    test('a linked member carries it on its live days only', () {
      final m = _member(linked: const ['q', 'e']);
      expect(m.ownPlanWeightOn(room, _k(10)), 2);
      expect(m.ownPlanWeightOn(room, _k(11)), 1);
    });

    test('with nothing edited, liveness changes nothing', () {
      final plain = _room([_slot('قراءة القرآن'), _slot('تمرين')]);
      final m = _member(linked: const ['q', 'e']);
      expect(m.gradedHabitIdsIn(plain), m.countedHabitIds);
      expect(m.countedHabitIdsIn(plain, now: DateTime(2026, 7, 15)),
          m.countedHabitIds);
      for (var d = 1; d <= 30; d++) {
        expect(plain.slotLiveOn(0, _k(d)), isTrue);
        expect(plain.slotLiveOn(1, _k(d)), isTrue);
      }
    });
  });
}
