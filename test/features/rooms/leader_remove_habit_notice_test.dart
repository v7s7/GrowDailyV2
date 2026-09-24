// Who is told that the leader changed the plan, and what they are told.
//
// Aziz, 2026-09-22: "make it a pop up when they open, no need for
// notification and extra cost". So this is recomputed from the room
// documents every time they change, the same shape as unseenFinishedRooms,
// and every "should this announce?" case is a plain function call here.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/room_plan_notices.dart';

final _now = DateTime(2026, 7, 20, 21);
String _k(int d) => '2026-07-${d.toString().padLeft(2, '0')}';

RoomHabitTemplate _slot(
  String name, {
  String? addedDay,
  DateTime? removedAt,
  String? stopsOn,
  String removedBy = 'leader',
  DateTime? restoredAt,
  String restoredBy = 'leader',
}) =>
    RoomHabitTemplate(
      name: name,
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      addedAt: addedDay == null ? null : DateTime.parse(addedDay),
      addedDay: addedDay,
      removedAt: removedAt,
      removedBy: removedAt == null ? null : removedBy,
      stopsOn: stopsOn,
      restoredAt: restoredAt,
      restoredBy: restoredAt == null ? null : restoredBy,
    );

RoomModel _room(
  List<RoomHabitTemplate> slots, {
  DateTime? end,
}) =>
    RoomModel(
      code: 'NOTICE',
      name: 'الغرفة',
      createdBy: 'leader',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 7, 1),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 7, 1),
      endDate: end ?? DateTime(2026, 7, 30),
      sharedHabits: slots,
    );

RoomParticipant _member(
  String uid, {
  List<String> linked = const ['q', 'e'],
  DateTime? joinedAt,
  DateTime? leftAt,
}) =>
    RoomParticipant(
      uid: uid,
      displayName: uid,
      characterId: 'male_ghutra_blue',
      joinedAt: joinedAt ?? DateTime(2026, 7, 1),
      linkedHabitIds: linked,
      lastUpdated: _now,
      leftAt: leftAt,
    );

List<RoomPlanNotice> _notices(
  RoomModel room, {
  required String uid,
  List<RoomParticipant>? roster,
  DateTime? now,
}) =>
    roomPlanNoticesFor(
      uid: uid,
      myCodes: const ['NOTICE'],
      roomFor: (code) => room,
      participantsFor: (code) =>
          roster ?? [_member('me'), _member('leader'), _member('other')],
      now: now ?? _now,
    );

void main() {
  final removedToday = _room([
    _slot('قراءة القرآن'),
    _slot('تمرين', removedAt: DateTime(2026, 7, 20, 20), stopsOn: _k(21)),
  ]);

  test('the members are told, the leader who did it is not', () {
    final mine = _notices(removedToday, uid: 'me');
    expect(mine, hasLength(1));
    expect(mine.single.habitName, 'تمرين');
    expect(mine.single.kind, RoomPlanNoticeKind.removed);
    expect(mine.single.hadLinked, isTrue);
    expect(mine.single.countsToday, isTrue, reason: 'the removal day');
    expect(_notices(removedToday, uid: 'leader'), isEmpty);
  });

  test('from the next day the popup drops the "counts today" line', () {
    final later = _notices(removedToday, uid: 'me',
        now: DateTime(2026, 7, 21, 9));
    expect(later.single.countsToday, isFalse);
  });

  test('somebody who joined after it was removed hears nothing', () {
    final late = _member('me', joinedAt: DateTime(2026, 7, 20, 20, 5));
    expect(_notices(removedToday, uid: 'me', roster: [late]), isEmpty);
  });

  test('a member who left hears nothing', () {
    final gone = _member('me', leftAt: DateTime(2026, 7, 19));
    expect(_notices(removedToday, uid: 'me', roster: [gone]), isEmpty);
  });

  test('a legacy removal, an ended room and an old change say nothing', () {
    final legacy = _room([
      _slot('قراءة القرآن'),
      _slot('تمرين', removedAt: DateTime(2026, 7, 20, 20)),
    ]);
    expect(_notices(legacy, uid: 'me'), isEmpty);

    final ended = _room(
      [
        _slot('قراءة القرآن'),
        _slot('تمرين', removedAt: DateTime(2026, 7, 10), stopsOn: _k(11)),
      ],
      end: DateTime(2026, 7, 15),
    );
    expect(_notices(ended, uid: 'me'), isEmpty);

    final old = _room([
      _slot('قراءة القرآن'),
      _slot('تمرين', removedAt: DateTime(2026, 7, 1), stopsOn: _k(2)),
    ]);
    expect(_notices(old, uid: 'me'), isEmpty, reason: 'older than the window');
  });

  test('a habit added and removed the same day is news only to whoever had '
      'linked it', () {
    final mistake = _room([
      _slot('قراءة القرآن'),
      _slot('تمرين',
          addedDay: _k(20),
          removedAt: DateTime(2026, 7, 20, 20),
          stopsOn: _k(20)),
    ]);
    expect(_notices(mistake, uid: 'me'), hasLength(1),
        reason: 'they had linked it');
    final unlinked = _member('me', linked: const ['q']);
    expect(_notices(mistake, uid: 'me', roster: [unlinked]), isEmpty);
  });

  test('bringing it back is its own notice, with its own key', () {
    final back = _room([
      _slot('قراءة القرآن'),
      _slot('تمرين', restoredAt: DateTime(2026, 7, 20, 20)),
    ]);
    final mine = _notices(back, uid: 'me');
    expect(mine.single.kind, RoomPlanNoticeKind.restored);
    expect(_notices(back, uid: 'leader'), isEmpty);
    expect(mine.single.key, contains('restored'));
    expect(_notices(removedToday, uid: 'me').single.key, contains('removed'));
  });
}
