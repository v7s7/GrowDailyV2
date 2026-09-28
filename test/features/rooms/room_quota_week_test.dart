import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_quota_week.dart';

/// The plan card's quota line (room_quota_week.dart) counts the days the
/// ROOM grades a weekly quota on, not the Grid's whole Saturday-to-Friday
/// week, the way the grader itself does (weeklyQuotaScheduledDays: present
/// days only, target capped at how many there are). With the short-week
/// share switched on, see room_quota_short_week_test.dart.
///
/// Both rooms here are the real ones read wrong on 2026-09-27, on the
/// Grid week of Saturday 26 September to Friday 2 October, «تمرين» four
/// times a week, done on the Saturday.
final _week = [for (var d = 0; d < 7; d++) DateTime(2026, 9, 26 + d)];

RoomHabitTemplate _slot({
  String? addedDay,
  DateTime? removedAt,
  String? stopsOn,
}) =>
    RoomHabitTemplate(
      name: 'تمرين',
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 4,
      addedDay: addedDay,
      removedAt: removedAt,
      stopsOn: stopsOn,
    );

RoomModel _room({
  required DateTime start,
  DateTime? end,
  List<RoomHabitTemplate>? plan,
  List<({String from, String to})> paused = const [],
}) =>
    RoomModel(
      code: 'ROOM01',
      name: 'Room',
      createdBy: 'aziz',
      createdByName: 'Aziz',
      createdAt: start,
      habitMode: RoomHabitMode.shared,
      sharedHabits: plan ?? [_slot()],
      duration: end == null ? RoomDuration.open : RoomDuration.fixed,
      startDate: start,
      endDate: end,
      pausedSpans: paused,
    );

RoomParticipant _member({DateTime? joined, List<String> stoodDown = const []}) =>
    RoomParticipant(
      uid: 'aziz',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: joined ?? DateTime(2026, 8, 1),
      linkedHabitIds: const ['tamreen'],
      standDownDays: stoodDown,
      habitRules: const {
        'tamreen': [
          RoomHabitRule(
            from: '2026-08-01',
            frequencyType: HabitFrequencyType.weekly,
            frequencyTarget: 4,
          ),
        ],
      },
      lastUpdated: DateTime(2026, 9, 27),
    );

bool _on(DateTime d, Set<int> days) => days.contains(d.day);

({double done, int target, bool neededToday})? _standing(
  RoomModel room, {
  RoomParticipant? member,
  Set<int> done = const {26},
  Set<int> half = const {},
  required DateTime today,
}) =>
    roomQuotaWeekStanding(
      room: room,
      participant: member ?? _member(),
      slot: 0,
      weekDays: _week,
      isDone: (d) => d.month == 9 && _on(d, done),
      isHalf: (d) => d.month == 9 && _on(d, half),
      target: 4,
      today: today,
    );

List<int> _days(List<DateTime> days) => [for (final d in days) d.day];

void main() {
  group('a room that started mid-week (F8HQKE, Sunday 27 September)', () {
    final room = _room(
      start: DateTime(2026, 9, 27),
      end: DateTime(2026, 10, 26),
    );
    final member = _member(joined: DateTime(2026, 9, 27, 13));

    test('grades Sunday to Friday, never the Saturday before it', () {
      expect(
        _days(roomSlotWeekDays(room, member, 0, _week)),
        [27, 28, 29, 30, 1, 2],
      );
    });

    test('Saturday\'s session is not the room\'s: 0 of 4, not 1 of 4', () {
      final s = _standing(room, member: member, today: DateTime(2026, 9, 27))!;
      expect(s.done, 0);
      expect(s.target, 4);
      // Four sessions in six days: two to spare, so not today yet.
      expect(s.neededToday, isFalse);
    });

    test('and by Tuesday with nothing done, every day left is needed', () {
      final s = _standing(room, member: member, today: DateTime(2026, 9, 29))!;
      expect(s.done, 0);
      expect(s.neededToday, isTrue);
    });
  });

  group('a room that ends mid-week (ELQVF8, Wednesday 30 September)', () {
    final room = _room(
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 30),
    );

    test('grades Saturday to Wednesday, never Thursday or Friday', () {
      expect(
        _days(roomSlotWeekDays(room, _member(), 0, _week)),
        [26, 27, 28, 29, 30],
      );
    });

    test('Sunday: 1 of 4, three more in four days, one to spare', () {
      final s = _standing(room, today: DateTime(2026, 9, 27))!;
      expect(s.done, 1);
      expect(s.target, 4);
      expect(s.neededToday, isFalse);
    });

    test('Monday after a blank Sunday: needed today', () {
      // Three more in Monday, Tuesday and Wednesday. Measured against the
      // Grid's whole week there were five days left for them, and the line
      // said nothing.
      final s = _standing(room, today: DateTime(2026, 9, 28))!;
      expect(s.neededToday, isTrue);
    });

    test('a room of three days that week asks three, not four', () {
      final short = _room(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 28),
      );
      final s = _standing(short, today: DateTime(2026, 9, 27))!;
      expect(s.target, 3);
    });
  });

  test('a room running the whole week counts the whole week', () {
    final room = _room(start: DateTime(2026, 9, 1));
    expect(_days(roomSlotWeekDays(room, _member(), 0, _week)).length, 7);
    final s = _standing(
      room,
      done: const {26, 27},
      half: const {28},
      today: DateTime(2026, 9, 29),
    )!;
    // Two whole and a جزئي at half.
    expect(s.done, 2.5);
    expect(s.target, 4);
  });

  test('a slot added on Tuesday counts from Tuesday', () {
    final room = _room(
      start: DateTime(2026, 9, 1),
      plan: [_slot(addedDay: '2026-09-29')],
    );
    expect(
      _days(roomSlotWeekDays(room, _member(), 0, _week)),
      [29, 30, 1, 2],
    );
  });

  test('a slot the leader removed stops on its last day', () {
    final room = _room(
      start: DateTime(2026, 9, 1),
      plan: [
        _slot(removedAt: DateTime(2026, 9, 28, 15), stopsOn: '2026-09-29'),
      ],
    );
    expect(_days(roomSlotWeekDays(room, _member(), 0, _week)), [26, 27, 28]);
  });

  test('a member who joined on Monday counts from Monday', () {
    final room = _room(start: DateTime(2026, 9, 1));
    expect(
      _days(roomSlotWeekDays(
          room, _member(joined: DateTime(2026, 9, 28, 20)), 0, _week)),
      [28, 29, 30, 1, 2],
    );
  });

  test('paused and stood-down days are not the room\'s to count', () {
    final room = _room(
      start: DateTime(2026, 9, 1),
      paused: const [(from: '2026-09-27', to: '2026-09-28')],
    );
    expect(
      _days(roomSlotWeekDays(
          room, _member(stoodDown: const ['2026-09-30']), 0, _week)),
      [26, 29, 1, 2],
    );
  });

  test('a room that has ended prints no line for this week', () {
    final ended = _room(
      start: DateTime(2026, 7, 14),
      end: DateTime(2026, 8, 12),
    );
    expect(_standing(ended, today: DateTime(2026, 9, 27)), isNull);
  });
}
