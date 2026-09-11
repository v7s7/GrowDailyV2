// Closed quota weeks a member's own phone has not regraded yet, inferred for
// the board from the participant document alone
// (RoomParticipant.closedQuotaWeekInference).
//
// Every member fixture is a trimmed copy of a real document read on
// 2026-09-11: A8GEL7 Perla, BKWVN9 abdulhkeem, YW68B9 y.almehza101 and m7md.
// Each last synced while a 4x-a-week week was still open, stopped opening the
// app, and kept that week and every week after it fully due, because only
// their own phone writes the rest days a closed week earns.
//
// Their rooms run to their real end dates (A8GEL7 25 October, BKWVN9
// 16 November, YW68B9 2 October), because an ended room is left as
// recorded. The scores below therefore read through whatever day the suite
// runs, and each is compared with the member's own phone on the same room
// and the same day, which holds on any day. Measured on those live rooms,
// the board moves Perla 37.8 to 45.2, y.almehza101 4.5 to 6.3, m7md 26.3 to
// 31.3, abdulhkeem 4.2 unchanged, each equal to a full regrade of their
// record. No other member's score or streak moves, and Aziz's rank in
// YW68B9 becomes a shared first, level with m7md.
//
// Every instant is an explicit UTC one (see _bh), so no expectation depends
// on the zone the suite runs in, and the inference must not either. Run this
// file under TZ=Asia/Bahrain, TZ=UTC, TZ=America/Los_Angeles and
// TZ=Pacific/Kiritimati.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

const _w = 'weekly-habit';
const _d1 = 'daily-one';
const _d2 = 'daily-two';

/// [hour]:[minute] on a Bahrain wall clock (UTC+3 all year), as the UTC
/// instant Firestore holds for it. Midnight is the instant a Bahrain leader's
/// startDate and endDate carry.
DateTime _bh(int year, int month, int day, [int hour = 0, int minute = 0]) =>
    DateTime.utc(year, month, day, hour, minute)
        .subtract(const Duration(hours: 3));

/// A Friday, noon in Bahrain: every week under test has closed on every
/// clock.
final _now = _bh(2026, 9, 11, 12);

RoomHabitTemplate _slot(
  HabitFrequencyType type, {
  int target = 1,
  DateTime? removedAt,
}) =>
    RoomHabitTemplate(
      name: 'slot',
      category: HabitCategory.faith,
      frequencyType: type,
      frequencyTarget: target,
      removedAt: removedAt,
    );

/// A shared room, running to the last day of 2026 unless [end] says
/// otherwise, so it is live at every instant these tests ask about: an ended
/// room is left as recorded (see "a room that has ended").
RoomModel _room({
  required DateTime start,
  DateTime? end,
  List<RoomHabitTemplate>? slots,
  List<({String from, String to})> paused = const [],
}) =>
    RoomModel(
      code: 'TEST',
      name: 'test',
      createdBy: 'leader',
      createdByName: 'Leader',
      createdAt: start,
      habitMode: RoomHabitMode.shared,
      sharedHabits: slots ?? [_slot(HabitFrequencyType.weekly, target: 4)],
      duration: RoomDuration.fixed,
      startDate: start,
      endDate: end ?? _bh(2026, 12, 31),
      pausedSpans: paused,
    );

RoomHabitRule _weekly(String from, [int target = 4]) => RoomHabitRule(
      from: from,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: target,
    );

RoomHabitRule _daily(String from, {List<int> weekdays = const []}) =>
    RoomHabitRule(
      from: from,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      scheduledWeekdays: weekdays,
    );

/// A8GEL7 as it stands, to 25 October.
final _perlaRoom = _room(start: _bh(2026, 7, 28), end: _bh(2026, 10, 25));

/// A8GEL7 Perla. Last synced 2026-08-26, a Wednesday, with the week of
/// 22 August open and nothing done in it; nothing synced since.
RoomParticipant _perla({
  Map<String, int> done = const {
    '2026-08-10': 1,
    '2026-08-11': 1,
    '2026-08-13': 1,
    '2026-08-15': 1,
    '2026-08-17': 1,
    '2026-08-18': 1,
    '2026-08-19': 1,
  },
  Map<String, int> partial = const {},
  Map<String, int> rested = const {},
  List<String> okWeeks = const ['2026-08-01', '2026-08-15'],
  List<String> standDown = const [],
  List<String> linked = const [_w],
  Map<String, List<RoomHabitRule>>? rules,
  String? lastSyncedDay = '2026-08-26',
  DateTime? lastSyncedAt,
  DateTime? leftAt,
  List<({String from, String to})> away = const [],
  Map<int, String> prior = const {},
}) =>
    RoomParticipant(
      uid: 'Z0FndO3iFYgrzWzkwJ4QlOPBLPr2',
      displayName: 'Perla',
      characterId: 'female_abaya_navy',
      joinedAt: _bh(2026, 7, 28, 13, 9),
      linkedHabitIds: linked,
      habitRules: rules ?? {_w: [_weekly('2026-07-28')]},
      dailyDoneCount: done,
      dailyScheduledCount: const {
        '2026-08-08': 0,
        '2026-08-09': 0,
        '2026-08-12': 0,
        '2026-08-16': 0,
        '2026-08-20': 0,
        '2026-08-21': 0,
      },
      dailyPartialCount: partial,
      dailyRestedCount: rested,
      quotaOkWeeks: okWeeks,
      standDownDays: standDown,
      lastSyncedDay: lastSyncedDay,
      lastSyncedAt: lastSyncedAt,
      leftAt: leftAt,
      awaySpans: away,
      slotPriorHabitIds: prior,
      lastUpdated: _bh(2026, 8, 26, 13, 46),
    );

const _perlaRest = {
  '2026-08-22': 0,
  '2026-08-23': 0,
  '2026-08-24': 0,
  '2026-08-29': 0,
  '2026-08-30': 0,
  '2026-08-31': 0,
};

/// YW68B9 m7md. Last synced 2026-09-04, a Friday, with the week of 29 August
/// open; the week of 22 August banked.
RoomParticipant _m7md({String? lastSyncedDay, DateTime? lastSyncedAt}) =>
    RoomParticipant(
      uid: 'MVsfLW0Lh9h9fqZfBy5VVaP9hJb2',
      displayName: 'm7md',
      characterId: '',
      joinedAt: _bh(2026, 8, 21, 20, 34),
      linkedHabitIds: const [_w],
      habitRules: {_w: [_weekly('2026-08-21')]},
      dailyDoneCount: const {
        '2026-08-21': 1,
        '2026-08-22': 1,
        '2026-08-28': 1,
        '2026-08-31': 1,
        '2026-09-01': 1,
      },
      dailyScheduledCount: const {
        '2026-08-23': 0,
        '2026-08-26': 0,
        '2026-08-27': 0,
      },
      quotaOkWeeks: const ['2026-08-22'],
      lastSyncedDay: lastSyncedDay ?? '2026-09-04',
      lastSyncedAt: lastSyncedAt,
      lastUpdated: _bh(2026, 9, 5, 0, 55),
    );

/// What the member's own phone writes when it next syncs: [keys] on top of
/// the stored map, and a watermark past every week under test so its own
/// inference has nothing left to say.
RoomParticipant _phoneWrote(RoomParticipant p, Map<String, int> keys) =>
    p.copyWith(
      dailyScheduledCount: {...p.dailyScheduledCount, ...keys},
      lastSyncedDay: '2026-09-05',
      lastSyncedAt: _bh(2026, 9, 6, 11),
    );

Iterable<String> _days(String from, String to) sync* {
  for (var d = DateTime.parse(from);
      !d.isAfter(DateTime.parse(to));
      d = DateTime(d.year, d.month, d.day + 1)) {
    yield d.toDateKey();
  }
}

void main() {
  group('the four dormant members, as their own phones would regrade them',
      () {
    test('A8GEL7 Perla: both closed short weeks rest their first three days',
        () {
      final p = _perla();
      expect(p.closedQuotaWeekInference(_perlaRoom, now: _now), _perlaRest);

      final graded = p.withClosedQuotaWeeksInferred(_perlaRoom, now: _now);
      final phone = _phoneWrote(p, _perlaRest);
      expect(graded.progressRatio(_perlaRoom), phone.progressRatio(_perlaRoom));
      expect(
        graded.roomProgressRatio(_perlaRoom),
        phone.roomProgressRatio(_perlaRoom),
      );
      expect(graded.currentStreak(_perlaRoom), phone.currentStreak(_perlaRoom));
      expect(
        graded.progressRatio(_perlaRoom),
        greaterThan(p.progressRatio(_perlaRoom)),
      );
      // The owed days stay owed.
      for (final k in ['2026-08-25', '2026-08-26', '2026-08-27', '2026-08-28']) {
        expect(graded.scheduledCountFor(k), 1, reason: k);
        expect(graded.isRestDay(k), isFalse, reason: k);
      }
    });

    test('BKWVN9 abdulhkeem: a mixed plan rests only the weekly habit', () {
      final room = _room(
        start: _bh(2026, 8, 19),
        end: _bh(2026, 11, 16),
        slots: [
          _slot(HabitFrequencyType.weekly, target: 4),
          _slot(HabitFrequencyType.daily),
          _slot(HabitFrequencyType.daily),
        ],
      );
      final p = RoomParticipant(
        uid: 'JBdFIoe8YJNSovK4RzZAK8ICRy62',
        displayName: 'abdulhkeem KBS',
        characterId: '',
        joinedAt: _bh(2026, 8, 19, 15, 9),
        linkedHabitIds: const [_w, _d1, _d2],
        habitRules: {
          _w: [_weekly('2026-08-19')],
          _d1: [_daily('2026-08-19')],
          _d2: [_daily('2026-08-19')],
        },
        dailyDoneCount: const {'2026-08-19': 3},
        dailyScheduledCount: const {
          '2026-08-22': 2,
          '2026-08-23': 2,
          '2026-08-24': 2,
        },
        lastSyncedDay: '2026-09-03',
        lastUpdated: _bh(2026, 9, 3, 19, 46),
      );
      expect(p.closedQuotaWeekInference(room, now: _now), const {
        '2026-08-29': 2,
        '2026-08-30': 2,
        '2026-08-31': 2,
      });
      final graded = p.withClosedQuotaWeeksInferred(room, now: _now);
      // Nothing was done on them, so the day is still worth nothing; only
      // the day card's "of 3" becomes "of 2".
      expect(graded.creditFor('2026-08-29'), 0);
      expect(graded.progressRatio(room), p.progressRatio(room));
    });

    test('YW68B9 m7md: the stale week rests, his held squares stay held', () {
      // His room as it stands, running to 2 October.
      final room = _room(start: _bh(2026, 8, 21), end: _bh(2026, 10, 2));
      final p = _m7md();
      const rest = {'2026-08-29': 0, '2026-08-30': 0, '2026-09-02': 0};
      expect(p.closedQuotaWeekInference(room, now: _now), rest);
      final graded = p.withClosedQuotaWeeksInferred(room, now: _now);
      expect(
        graded.roomProgressRatio(room),
        _phoneWrote(p, rest).roomProgressRatio(room),
      );
      // 24 and 25 August: squares painted after the days closed, held at
      // zero by the clamp, inside a week his phone already banked.
      for (final k in ['2026-08-24', '2026-08-25']) {
        expect(graded.scheduledCountFor(k), 1, reason: k);
        expect(graded.creditFor(k), 0, reason: k);
      }
    });

    test(
        'YW68B9 y.almehza101: the same score as her phone, one miss drawn a '
        'different day', () {
      final room = _room(start: _bh(2026, 8, 21), end: _bh(2026, 10, 2));
      final p = RoomParticipant(
        uid: 'BRE78XAgdTQC5JiZSeqytX86Wn53',
        displayName: 'y.almehza101',
        characterId: '',
        joinedAt: _bh(2026, 8, 21, 20, 28),
        linkedHabitIds: const [_w],
        habitRules: {_w: [_weekly('2026-08-21')]},
        dailyDoneCount: const {'2026-08-23': 1},
        lastSyncedDay: '2026-08-23',
        lastUpdated: _bh(2026, 8, 23, 10, 15),
      );
      final inferred = p.closedQuotaWeekInference(room, now: _now);
      expect(inferred, const {
        '2026-08-22': 0,
        '2026-08-24': 0,
        '2026-08-25': 0,
        '2026-08-29': 0,
        '2026-08-30': 0,
        '2026-08-31': 0,
      });
      // Her phone also sees the square on 22 August that the clamp holds at
      // zero, and that square counts toward the target when it picks which
      // empty days were owed. The document cannot show it.
      final phone = _phoneWrote(p, const {
        '2026-08-24': 0,
        '2026-08-25': 0,
        '2026-08-26': 0,
        '2026-08-29': 0,
        '2026-08-30': 0,
        '2026-08-31': 0,
      });
      final graded = p.withClosedQuotaWeeksInferred(room, now: _now);
      expect(graded.progressRatio(room), phone.progressRatio(room));
      expect(graded.roomProgressRatio(room), phone.roomProgressRatio(room));
      int due(RoomParticipant x) => _days('2026-08-22', '2026-08-28')
          .where((k) => x.scheduledCountFor(k) > 0)
          .length;
      expect(due(graded), 4);
      expect(due(phone), 4);
      expect(graded.isRestDay('2026-08-22'), isTrue);
      expect(phone.isRestDay('2026-08-22'), isFalse);
      expect(graded.isRestDay('2026-08-26'), isFalse);
      expect(phone.isRestDay('2026-08-26'), isTrue);
    });
  });

  group('the anti-backdating clamp never sees it', () {
    test('a document as the sync parses it carries no inference', () {
      final p = _perla();
      expect(p.inferredScheduledCount, isEmpty);
      for (final k in _days('2026-07-28', '2026-09-05')) {
        expect(p.scheduledCountFor(k), p.recordedScheduledCountFor(k), reason: k);
      }
    });

    test('recordedScheduledCountFor ignores inferred counts on every day', () {
      final p = _perla();
      final graded = p.withClosedQuotaWeeksInferred(_perlaRoom, now: _now);
      for (final k in _days('2026-07-28', '2026-09-05')) {
        expect(
          graded.recordedScheduledCountFor(k),
          p.scheduledCountFor(k),
          reason: 'the clamp compares against this on $k',
        );
      }
    });

    test('nothing a write could pick up differs', () {
      final p = _perla();
      final graded = p.withClosedQuotaWeeksInferred(_perlaRoom, now: _now);
      expect(graded.toFirestore(), p.toFirestore());
      expect(graded.dailyScheduledCount, p.dailyScheduledCount);
    });
  });

  group('fails toward the recorded value', () {
    Map<String, int> infer(RoomParticipant p, {RoomModel? room, DateTime? now}) =>
        p.closedQuotaWeekInference(room ?? _perlaRoom, now: now ?? _now);

    test('a partial mark anywhere in the week leaves the week alone', () {
      final got = infer(_perla(partial: const {'2026-08-25': 1}));
      expect(got.keys.where((k) => k.compareTo('2026-08-29') < 0), isEmpty);
      expect(got['2026-08-29'], 0, reason: 'the next week is still provable');
    });

    test('a rest mark anywhere in the week leaves the week alone', () {
      final got = infer(_perla(rested: const {'2026-08-23': 1}));
      expect(got.keys.where((k) => k.compareTo('2026-08-29') < 0), isEmpty);
    });

    test('a stood-down day with a done on it leaves the week alone', () {
      final got = infer(_perla(
        standDown: const ['2026-08-27'],
        done: const {'2026-08-27': 1},
      ),
      );
      expect(got.keys.where((k) => k.compareTo('2026-08-29') < 0), isEmpty);
    });

    test('a banked week is never touched', () {
      // A daily habit beside the weekly one, so the recorded fallback cannot
      // read the banked week's unobserved days as rest (it speaks only for
      // all-weekly plans): every day records both habits due, exactly what
      // an open week records, and nothing in the week is done. Only the
      // banked gate keeps the week as recorded.
      final room = _room(
        start: _bh(2026, 7, 28),
        end: _bh(2026, 10, 25),
        slots: [
          _slot(HabitFrequencyType.weekly, target: 4),
          _slot(HabitFrequencyType.daily),
        ],
      );
      RoomParticipant member(List<String> okWeeks) => _perla(
            linked: const [_w, _d1],
            rules: {
              _w: [_weekly('2026-07-28')],
              _d1: [_daily('2026-07-28')],
            },
            okWeeks: okWeeks,
          );
      final banked = member(const ['2026-08-15', '2026-08-22'])
          .closedQuotaWeekInference(room, now: _now);
      expect(banked.keys.where((k) => k.compareTo('2026-08-29') < 0), isEmpty);
      expect(
        banked['2026-08-29'],
        1,
        reason: 'the next week is still provable',
      );
      // The same record without the week banked rests it, so the gate is
      // what kept it.
      final unbanked = member(const ['2026-08-15'])
          .closedQuotaWeekInference(room, now: _now);
      expect(unbanked, containsPair('2026-08-22', 1));
    });

    test('a week the last sync saw closed is already graded', () {
      final got = infer(_perla(lastSyncedDay: '2026-08-29'));
      expect(got.keys.where((k) => k.compareTo('2026-08-29') < 0), isEmpty);
      expect(got['2026-08-29'], 0);
    });

    test('a week that is still open now is not graded early', () {
      final got = infer(
        _perla(),
        room: _room(start: _bh(2026, 7, 28), end: _bh(2026, 12, 31)),
        now: _bh(2026, 8, 27, 12),
      );
      expect(got, isEmpty);
    });

    test('a week the phone would no longer reach is left as stored', () {
      final got = infer(
        _perla(),
        room: _room(start: _bh(2026, 7, 28), end: _bh(2026, 12, 31)),
        now: _bh(2026, 10, 20, 12),
      );
      expect(got.keys.where((k) => k.compareTo('2026-09-05') < 0), isEmpty);
      expect(got['2026-09-05'], 0);
      expect(RoomParticipant.kSyncWindowDaysMirror, kRoomSyncWindowDays);
    });

    test('a day with anything but nothing or everything done is not provable',
        () {
      final room = _room(
        start: _bh(2026, 7, 28),
        slots: [
          _slot(HabitFrequencyType.weekly, target: 4),
          _slot(HabitFrequencyType.daily),
        ],
      );
      final p = _perla(
        linked: const [_w, _d1],
        rules: {
          _w: [_weekly('2026-07-28')],
          _d1: [_daily('2026-07-28')],
        },
        done: const {'2026-08-24': 1},
        okWeeks: const [],
      );
      final got = p.closedQuotaWeekInference(room, now: _now);
      expect(got.keys.where((k) => k.compareTo('2026-08-29') < 0), isEmpty);
    });

    test('a regular habit off its weekday makes the recorded count unproven',
        () {
      final room = _room(
        start: _bh(2026, 7, 28),
        slots: [
          _slot(HabitFrequencyType.weekly, target: 4),
          _slot(HabitFrequencyType.daily),
        ],
      );
      final p = _perla(
        linked: const [_w, _d1],
        rules: {
          _w: [_weekly('2026-07-28')],
          _d1: [_daily('2026-07-28', weekdays: const [DateTime.monday])],
        },
        okWeeks: const [],
      );
      expect(p.closedQuotaWeekInference(room, now: _now), isEmpty);
    });

    test('a rule period starting inside the week leaves the week alone', () {
      final got = infer(_perla(
        rules: {
          _w: [_weekly('2026-07-28'), _weekly('2026-08-25', 3)],
        },
      ),
      );
      expect(got.keys.where((k) => k.compareTo('2026-08-29') < 0), isEmpty);
    });

    test('a room pause or an away stretch leaves the week alone', () {
      final paused = infer(
        _perla(),
        room: _room(
          start: _bh(2026, 7, 28),
          paused: const [(from: '2026-08-26', to: '2026-08-26')],
        ),
      );
      expect(paused.keys.where((k) => k.compareTo('2026-08-29') < 0), isEmpty);
      final away = infer(
        _perla(away: const [(from: '2026-08-30', to: '2026-08-30')]),
      );
      expect(away.keys.where((k) => k.compareTo('2026-08-29') >= 0), isEmpty);
    });

    test('departed, never synced, missing rule, prior habit, withdrawn slot',
        () {
      expect(infer(_perla(leftAt: _bh(2026, 9, 2))), isEmpty);
      expect(infer(_perla(lastSyncedDay: null)), isEmpty);
      expect(infer(_perla(rules: const {})), isEmpty);
      expect(infer(_perla(prior: const {1: 'old-habit'})), isEmpty);
      expect(
        infer(
          _perla(),
          room: _room(
            start: _bh(2026, 7, 28),
            slots: [
              _slot(
                HabitFrequencyType.weekly,
                target: 4,
                removedAt: _bh(2026, 9, 2),
              ),
            ],
          ),
        ),
        isEmpty,
      );
    });

    test('a declined slot is no habit, even one the leader then withdrew', () {
      // Perla's real plan: her second slot declined, with no date and no
      // prior habit, and withdrawn from the room on 2026-09-09. Neither her
      // phone nor the recorded fallback counts it on any day, so her weeks
      // are graded on the slot she kept, exactly as without it.
      final room = _room(
        start: _bh(2026, 7, 28),
        end: _bh(2026, 10, 25),
        slots: [
          _slot(HabitFrequencyType.weekly, target: 4),
          _slot(
            HabitFrequencyType.weekly,
            target: 4,
            removedAt: DateTime.utc(2026, 9, 9, 22, 24),
          ),
        ],
      );
      final p = _perla(linked: const [_w, kDeclinedSlot]);
      expect(p.closedQuotaWeekInference(room, now: _now), _perlaRest);
      final graded = p.withClosedQuotaWeeksInferred(room, now: _now);
      final phone = _phoneWrote(p, _perlaRest);
      expect(graded.progressRatio(room), phone.progressRatio(room));
      expect(graded.roomProgressRatio(room), phone.roomProgressRatio(room));
    });

    test('never lowers a day with anything done on it', () {
      final p = _perla(done: const {'2026-08-23': 1, '2026-08-30': 1});
      final got = infer(p);
      for (final k in got.keys) {
        expect(p.dailyDoneCount[k] ?? 0, 0, reason: k);
      }
    });
  });

  group('a room that has ended is left as recorded', () {
    // Saturday 22 to Wednesday 26 August in Bahrain.
    final room = _room(start: _bh(2026, 8, 22), end: _bh(2026, 8, 26));
    RoomParticipant member({String? syncedDay, DateTime? syncedAt}) =>
        RoomParticipant(
          uid: 'u',
          displayName: 'u',
          characterId: '',
          joinedAt: _bh(2026, 8, 22),
          linkedHabitIds: const [_w],
          habitRules: {_w: [_weekly('2026-08-22', 3)]},
          dailyDoneCount: const {'2026-08-22': 1},
          lastSyncedDay: syncedDay ?? '2026-08-26',
          lastSyncedAt: syncedAt,
          lastUpdated: _bh(2026, 8, 26, 20),
        );

    test('whenever and however it last synced', () {
      // The first of these used to be graded through the earliest reading
      // of the room's end, resting the 23rd.
      final members = [
        member(syncedDay: '2026-08-25', syncedAt: _bh(2026, 8, 25, 9)),
        member(syncedAt: _bh(2026, 8, 26, 20)),
        member(syncedAt: _bh(2026, 8, 27, 9)),
        member(),
      ];
      final clocks = [
        // 15:30 on its last day in Bahrain, where it is still running.
        DateTime.utc(2026, 8, 26, 12, 30),
        _now,
      ];
      for (final p in members) {
        for (final now in clocks) {
          expect(
            p.closedQuotaWeekInference(room, now: now),
            isEmpty,
            reason: '${p.lastSyncedAt} at $now',
          );
        }
      }
    });

    test('from the first moment its end can have passed on any clock', () {
      // Saturday 22 August to Tuesday 1 September in Bahrain. The week of
      // 22 August closed short, and its last sync, on Friday the 28th, saw
      // it open.
      final room = _room(start: _bh(2026, 8, 22), end: _bh(2026, 9, 1));
      final p = RoomParticipant(
        uid: 'u',
        displayName: 'u',
        characterId: '',
        joinedAt: _bh(2026, 8, 22),
        linkedHabitIds: const [_w],
        habitRules: {_w: [_weekly('2026-08-22')]},
        dailyDoneCount: const {'2026-08-22': 1},
        lastSyncedDay: '2026-08-28',
        lastSyncedAt: _bh(2026, 8, 28, 12),
        lastUpdated: _bh(2026, 8, 28, 12),
      );
      final keys = _days('2026-08-22', '2026-08-28').toList();
      final due = weeklyQuotaScheduledDays(
        presentDays: const [0, 1, 2, 3, 4, 5, 6],
        doneDays: const {0},
        target: 4,
        isWeekClosed: true,
      ).toSet();
      final rested = {
        for (var i = 0; i < keys.length; i++)
          if (!due.contains(i)) keys[i]: 0,
      };
      expect(rested, hasLength(3));
      // 09:59 UTC on Monday 31 August is still Monday at UTC+14: the week
      // has closed on every clock, and the room has ended on none.
      expect(
        p.closedQuotaWeekInference(room, now: DateTime.utc(2026, 8, 31, 9, 59)),
        rested,
      );
      // A minute later it is Tuesday 1 September at UTC+14, while the end
      // instant (the midnight that starts that Tuesday in Bahrain) still
      // falls on Monday at UTC-12: over on the earliest readings, so left
      // as recorded. It is 13:00 on Monday in Bahrain, with a day and a half
      // to run there. Read at the latest instead (today at UTC-12 against
      // the end at UTC+14), or on the viewer's own calendar in any of the
      // four zones this file runs in, the week is still inferred here and
      // this fails.
      expect(
        p.closedQuotaWeekInference(room, now: DateTime.utc(2026, 8, 31, 10)),
        isEmpty,
      );
    });

    test('its places are drawn from the record, whatever list a screen holds',
        () {
      // Saturday 22 August to Tuesday 1 September as a phone parses it, so
      // the places below are the same in every zone this file runs in. Two
      // members with the same record: p's week of 22 August closed short
      // after p's last sync, and q synced after the room ended.
      final room = RoomModel(
        code: 'END',
        name: 'end',
        createdBy: 'p',
        createdByName: 'P',
        createdAt: DateTime(2026, 8, 22),
        habitMode: RoomHabitMode.shared,
        sharedHabits: [_slot(HabitFrequencyType.weekly, target: 4)],
        duration: RoomDuration.fixed,
        startDate: DateTime(2026, 8, 22),
        endDate: DateTime.parse('2026-09-01'),
      );
      RoomParticipant member(String uid, String syncedDay) => RoomParticipant(
            uid: uid,
            displayName: uid,
            characterId: '',
            joinedAt: DateTime(2026, 8, 22),
            linkedHabitIds: const [_w],
            habitRules: {_w: [_weekly('2026-08-22')]},
            dailyDoneCount: const {'2026-08-22': 1},
            lastSyncedDay: syncedDay,
            lastUpdated: _bh(2026, 8, 28, 12),
          );
      final record = [member('p', '2026-08-28'), member('q', '2026-09-02')];
      // 03:00 on Sunday 30 August in Bahrain: the week has closed on every
      // clock and the room has ended on none. A screen opened then still
      // holds this list after the end, until a stream emits.
      final before = DateTime.utc(2026, 8, 30);
      final graded = [
        for (final m in record)
          m.withClosedQuotaWeeksInferred(room, now: before),
      ];
      expect(graded.first.inferredScheduledCount, hasLength(3));
      expect(graded.last.inferredScheduledCount, isEmpty);
      Map<String, int> places(List<RoomParticipant> ps) => {
            for (final s in room.standings(ps)) s.participant.uid: s.rank,
          };
      expect(places(graded), {'p': 1, 'q': 2});
      expect(places(record), {'p': 1, 'q': 1});
      // While it runs, the list is scored as handed.
      expect(
        identical(room.scoringRoster(graded, now: before), graded),
        isTrue,
      );
      // Once it has ended, the record: the finale's places, and the podium
      // prize claimPodiumBonus pays from them, are the record's. Scored as
      // handed, q would be paid second place instead of a shared first, and
      // this fails.
      final settled =
          room.scoringRoster(graded, now: DateTime.utc(2026, 9, 5));
      expect(settled.every((p) => p.inferredScheduledCount.isEmpty), isTrue);
      expect(places(settled), places(record));
    });
  });

  group("agrees with the phone's own grader", () {
    test('every target and every done pattern of a seven-day week', () {
      final room = _room(start: _bh(2026, 8, 22));
      final keys = _days('2026-08-22', '2026-08-28').toList();
      // Sunday noon in Bahrain, still Saturday at UTC-12: the week has closed
      // on every clock and the next one has not.
      final now = _bh(2026, 8, 30, 12);
      for (var target = 1; target <= 7; target++) {
        for (var mask = 0; mask < 128; mask++) {
          final doneIdx = {
            for (var i = 0; i < 7; i++)
              if (mask & (1 << i) != 0) i,
          };
          final p = RoomParticipant(
            uid: 'u',
            displayName: 'u',
            characterId: '',
            joinedAt: _bh(2026, 8, 22),
            linkedHabitIds: const [_w],
            habitRules: {_w: [_weekly('2026-08-22', target)]},
            dailyDoneCount: {for (final i in doneIdx) keys[i]: 1},
            lastSyncedDay: '2026-08-28',
            // Friday noon in Bahrain: Friday on every clock, week still open.
            lastSyncedAt: _bh(2026, 8, 28, 12),
            lastUpdated: _bh(2026, 8, 28, 12),
          );
          final got = p.closedQuotaWeekInference(room, now: now);
          if (doneIdx.length >= target) {
            // Met: the sync that saw it would have banked the week, so a
            // document that did not is not one this can vouch for.
            expect(got, isEmpty, reason: 'target $target mask $mask');
            continue;
          }
          final scheduled = weeklyQuotaScheduledDays(
            presentDays: const [0, 1, 2, 3, 4, 5, 6],
            doneDays: doneIdx,
            target: target,
            isWeekClosed: true,
          ).toSet();
          expect(
            got,
            {
              for (var i = 0; i < 7; i++)
                if (!scheduled.contains(i)) keys[i]: 0,
            },
            reason: 'target $target mask $mask',
          );
        }
      }
    });
  });

  group("which clock: a viewer cannot know the member's zone", () {
    // Every answer below has to hold for a phone on any clock from UTC-12 to
    // UTC+14, because nothing in the document says which one it keeps.
    //
    // Mutation guard. If _dayAtUtcOffset read the viewer's own calendar
    // instead (the instant's toLocal() date), two tests fail under every
    // zone this file is run in: 'the week of 5 Sep waits at 11:59 UTC on
    // Saturday, still Friday at UTC-12', because that instant is already Saturday
    // 12 September in Los Angeles (04:59), UTC, Bahrain (14:59) and
    // Kiritimati (Sunday 01:59), and 'from the first moment its end can have
    // passed on any clock', in the group on ended rooms. Others fail by
    // zone: the window test and the join-day test everywhere but Kiritimati,
    // the 01:30 Bahrain sync test and the first-day test under UTC and Los
    // Angeles, the 21:30 test under Bahrain and Kiritimati, and the 20:22
    // test and the rule-period test under Kiritimati. Measured on 2026-09-11
    // in a scratch copy.
    final room = _room(start: _bh(2026, 8, 21), end: _bh(2026, 10, 2));
    const weekOf29Aug = {'2026-08-29': 0, '2026-08-30': 0, '2026-09-02': 0};
    Map<String, int> weekOf5Sep(Map<String, int> inferred) => {
          for (final e in inferred.entries)
            if (e.key.compareTo('2026-09-05') >= 0 &&
                e.key.compareTo('2026-09-11') <= 0)
              e.key: e.value,
        };
    Map<String, int> weekOf22Aug(Map<String, int> inferred) => {
          for (final e in inferred.entries)
            if (e.key.compareTo('2026-08-22') >= 0 &&
                e.key.compareTo('2026-08-28') <= 0)
              e.key: e.value,
        };

    test('the week of 5 Sep waits at 20:22 UTC on Friday, already Saturday at UTC+4', () {
      expect(
        _m7md().closedQuotaWeekInference(
          room,
          now: DateTime.utc(2026, 9, 11, 20, 22),
        ),
        weekOf29Aug,
      );
    });

    test('the week of 5 Sep waits at 21:30 UTC on Friday, 00:30 Saturday in Bahrain', () {
      expect(
        _m7md().closedQuotaWeekInference(
          room,
          now: DateTime.utc(2026, 9, 11, 21, 30),
        ),
        weekOf29Aug,
      );
    });

    test('the week of 5 Sep waits at 11:59 UTC on Saturday, still Friday at UTC-12', () {
      expect(
        _m7md().closedQuotaWeekInference(
          room,
          now: DateTime.utc(2026, 9, 12, 11, 59),
        ),
        weekOf29Aug,
      );
    });

    test('inferred at 12:00 UTC on Saturday, closed on every clock', () {
      expect(
        _m7md().closedQuotaWeekInference(
          room,
          now: DateTime.utc(2026, 9, 12, 12),
        ),
        {
          ...weekOf29Aug,
          '2026-09-05': 0,
          '2026-09-06': 0,
          '2026-09-07': 0,
        },
      );
    });

    test('a Bahrain sync at 01:30 on Saturday keeps that week as recorded',
        () {
      // 2026-09-11T22:30Z is Saturday on a Bahrain phone, which graded the
      // week closed. The Bahrain day key says so on its own; the key held
      // back to Friday reads as a phone that saw the week open, so there
      // only the instant can keep the week as recorded.
      // Each before 10:00 UTC on 1 October, from when the room's end can
      // have passed on some clock and it is left as recorded whatever the
      // sync.
      final later = [
        DateTime.utc(2026, 9, 12, 12),
        DateTime.utc(2026, 9, 20),
        DateTime.utc(2026, 9, 30, 12),
        DateTime.utc(2026, 10, 1, 9, 59),
      ];
      for (final day in ['2026-09-12', '2026-09-11']) {
        final p = _m7md(
          lastSyncedDay: day,
          lastSyncedAt: DateTime.utc(2026, 9, 11, 22, 30),
        );
        for (final now in later) {
          expect(
            weekOf5Sep(p.closedQuotaWeekInference(room, now: now)),
            isEmpty,
            reason: 'lastSyncedDay $day at $now',
          );
        }
      }
      // Stamped at 12:59 on Friday in Bahrain instead, Friday on every
      // clock: that sync saw the week open, and the week is corrected at
      // every one of those clocks.
      final friday = _m7md(
        lastSyncedDay: '2026-09-11',
        lastSyncedAt: DateTime.utc(2026, 9, 11, 9, 59),
      );
      for (final now in later) {
        expect(
          weekOf5Sep(friday.closedQuotaWeekInference(room, now: now)),
          const {'2026-09-05': 0, '2026-09-06': 0, '2026-09-07': 0},
          reason: 'at $now',
        );
      }
    });

    test('the window ages out on the easternmost calendar', () {
      final a8gel7 = _room(start: _bh(2026, 7, 28), end: _bh(2026, 10, 25));
      // 18:00 UTC on Sunday 11 October is already Monday at UTC+14, whose
      // window starts on Saturday 29 August. At UTC-12, and in Bahrain
      // (21:00), it is still Sunday and the window reaches 22 August. A phone
      // at UTC+14 no longer regrades that week, so it stays as stored.
      final got = _perla().closedQuotaWeekInference(
        a8gel7,
        now: DateTime.utc(2026, 10, 11, 18),
      );
      expect(got.keys.where((k) => k.compareTo('2026-08-29') < 0), isEmpty);
      expect(got['2026-08-29'], 0);
      // Nine hours earlier it was Sunday on every clock, and the week of
      // 22 August was inside every phone's window.
      final earlier = _perla().closedQuotaWeekInference(
        a8gel7,
        now: DateTime.utc(2026, 10, 11, 9),
      );
      expect(earlier['2026-08-22'], 0);
    });

    test("a member's join day is read at UTC+14", () {
      // Joined on Monday 24 August at 14:00 in Bahrain, 11:00 UTC, which is
      // already Tuesday at UTC+14. A Bahrain phone counts that week from
      // Monday and rests Monday and Tuesday; this counts it from Tuesday,
      // rests only Tuesday, and leaves Monday as recorded. Read on a
      // Bahrain, UTC or Los Angeles viewer's own calendar, Monday joins the
      // week, is rested too, and this fails.
      final p = RoomParticipant(
        uid: 'u',
        displayName: 'u',
        characterId: '',
        joinedAt: _bh(2026, 8, 24, 14),
        linkedHabitIds: const [_w],
        habitRules: {_w: [_weekly('2026-08-24', 3)]},
        lastSyncedDay: '2026-08-26',
        lastSyncedAt: _bh(2026, 8, 26, 12),
        lastUpdated: _bh(2026, 8, 26, 12),
      );
      final got = p.closedQuotaWeekInference(
        _room(start: _bh(2026, 8, 22)),
        now: _now,
      );
      expect(weekOf22Aug(got), const {'2026-08-25': 0});
      final phoneDue = weeklyQuotaScheduledDays(
        presentDays: const [0, 1, 2, 3, 4],
        doneDays: const <int>{},
        target: 3,
        isWeekClosed: true,
      ).toSet();
      expect(phoneDue, {2, 3, 4}, reason: 'a Bahrain phone rests 24 and 25');
    });

    test("a week's rule is checked from the join day read at UTC-12", () {
      // Joined on Monday 24 August at 14:00 in Bahrain, 11:00 UTC: still
      // Sunday at UTC-12, already Tuesday at UTC+14. The plan was daily from
      // the 24th and 3x a week from the 25th. A phone grades a whole week by
      // the rule on its own first counted day in it, so a Bahrain phone
      // grades this week as daily from the 24th and keeps every day due.
      // Checked only from the UTC+14 join day, the 25th, the week reads as
      // 3x a week and the 25th is rested; this fails. The next week is
      // 3x a week on every phone, and is rested as usual.
      final p = RoomParticipant(
        uid: 'u',
        displayName: 'u',
        characterId: '',
        joinedAt: _bh(2026, 8, 24, 14),
        linkedHabitIds: const [_w],
        habitRules: {
          _w: [_daily('2026-08-24'), _weekly('2026-08-25', 3)],
        },
        lastSyncedDay: '2026-08-26',
        lastSyncedAt: _bh(2026, 8, 26, 12),
        lastUpdated: _bh(2026, 8, 26, 12),
      );
      expect(
        roomRuleAt(p.habitRules[_w]!, '2026-08-24').frequencyType,
        HabitFrequencyType.daily,
        reason: "a Bahrain phone's first counted day in the week",
      );
      final got = p.closedQuotaWeekInference(
        _room(start: _bh(2026, 8, 22)),
        now: _now,
      );
      expect(weekOf22Aug(got), isEmpty);
      expect(got, const {
        '2026-08-29': 0,
        '2026-08-30': 0,
        '2026-08-31': 0,
        '2026-09-01': 0,
      });
    });

    test("the room's first day is read at UTC+14", () {
      // Started at midnight on Monday 24 August in Bahrain, 21:00 UTC on
      // Sunday, which is still Sunday on a UTC clock and Monday at UTC+14.
      // Read at UTC+14, as on the Bahrain phones, the week has five days and
      // rests two. Read on a UTC or Los Angeles viewer's own calendar,
      // Sunday joins the week, is rested too, and this fails.
      final p = RoomParticipant(
        uid: 'u',
        displayName: 'u',
        characterId: '',
        // In the lobby, days before the start.
        joinedAt: _bh(2026, 8, 20, 12),
        linkedHabitIds: const [_w],
        habitRules: {_w: [_weekly('2026-08-20', 3)]},
        lastSyncedDay: '2026-08-26',
        lastSyncedAt: _bh(2026, 8, 26, 12),
        lastUpdated: _bh(2026, 8, 26, 12),
      );
      final got = p.closedQuotaWeekInference(
        _room(start: _bh(2026, 8, 24)),
        now: _now,
      );
      expect(weekOf22Aug(got), const {'2026-08-24': 0, '2026-08-25': 0});
    });
  });

  group('a team milestone pays on the record, never on the inference', () {
    // A team room, 4x a week, 16 August to 2 October. Local midnights, as a
    // phone parses them, so the team's day keys are calendar dates in every
    // zone this file runs in; each also reads as that date at UTC+14.
    final room = RoomModel(
      code: 'TEAM',
      name: 'team',
      createdBy: 'a',
      createdByName: 'A',
      createdAt: DateTime(2026, 8, 16),
      habitMode: RoomHabitMode.shared,
      sharedHabits: [_slot(HabitFrequencyType.weekly, target: 4)],
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 8, 16),
      endDate: DateTime(2026, 10, 2),
      competeMode: RoomCompeteMode.team,
    );
    RoomParticipant member(
      String uid, {
      required Map<String, int> done,
      required Map<String, int> scheduled,
      required List<String> okWeeks,
      required String syncedDay,
      required DateTime syncedAt,
    }) =>
        RoomParticipant(
          uid: uid,
          displayName: uid,
          characterId: '',
          joinedAt: DateTime(2026, 8, 16),
          linkedHabitIds: const [_w],
          habitRules: {_w: [_weekly('2026-08-16')]},
          dailyDoneCount: done,
          dailyScheduledCount: scheduled,
          quotaOkWeeks: okWeeks,
          lastSyncedDay: syncedDay,
          lastSyncedAt: syncedAt,
          lastUpdated: syncedAt,
        );
    // A did every day from the 16th to the 28th and last synced on
    // 10 September: both weeks banked, the week of 29 August graded.
    final a = member(
      'a',
      done: {for (final k in _days('2026-08-16', '2026-08-28')) k: 1},
      scheduled: const {'2026-08-29': 0, '2026-08-30': 0, '2026-08-31': 0},
      okWeeks: const ['2026-08-15', '2026-08-22'],
      syncedDay: '2026-09-10',
      syncedAt: _bh(2026, 9, 10, 12),
    );
    // B banked the week of 15 August, painted the 22nd after it closed (the
    // clamp held it at zero, so the document shows nothing), did the 23rd,
    // and has not synced since 15:01 that day: y.almehza101's record, on a
    // team.
    RoomParticipant b({Map<String, int>? done}) => member(
          'b',
          done: done ??
              const {
                '2026-08-16': 1,
                '2026-08-17': 1,
                '2026-08-18': 1,
                '2026-08-19': 1,
                '2026-08-23': 1,
              },
          scheduled: const {'2026-08-20': 0, '2026-08-21': 0},
          okWeeks: const ['2026-08-15'],
          syncedDay: '2026-08-23',
          syncedAt: _bh(2026, 8, 23, 15, 1),
        );
    List<RoomParticipant> board(List<RoomParticipant> ps) => [
          for (final p in ps) p.withClosedQuotaWeeksInferred(room, now: _now),
        ];

    test('an inferred rest day never unlocks a claim', () {
      expect(b().closedQuotaWeekInference(room, now: _now), const {
        '2026-08-22': 0,
        '2026-08-24': 0,
        '2026-08-25': 0,
        '2026-08-29': 0,
        '2026-08-30': 0,
        '2026-08-31': 0,
      });
      final graded = board([a, b()]);
      // On the board B rests the 22nd, 24th and 25th, and the team's run
      // from the 16th reaches ten days.
      expect(room.teamBestStreakWith(graded.first, graded), 10);
      // The record owes the 22nd, and so does B's own phone, which counts
      // the held square toward the target and rests the 24th to the 26th.
      expect(room.teamBestStreakWith(a, [a, b()]), 6);
      final phone = _phoneWrote(b(), const {
        '2026-08-24': 0,
        '2026-08-25': 0,
        '2026-08-26': 0,
        '2026-08-29': 0,
        '2026-08-30': 0,
        '2026-08-31': 0,
      });
      expect(room.teamBestStreakWith(a, [a, phone]), 6);
      // So the seven-day milestone (60 XP, 30 gold) is not there to claim,
      // whichever roster the team card holds. Were claimableTeamMilestone to
      // grade the roster as handed, the board's would unlock it and this
      // fails.
      expect(room.claimableTeamMilestone(graded.first, graded), isNull);
      expect(room.claimableTeamMilestone(a, [a, b()]), isNull);
    });

    test('a run the record holds is claimable on either roster', () {
      final record = [
        a,
        b(
          done: {
            for (final k in _days('2026-08-16', '2026-08-19')) k: 1,
            '2026-08-22': 1,
            '2026-08-23': 1,
          },
        ),
      ];
      expect(room.teamBestStreakWith(a, record), 8);
      expect(room.claimableTeamMilestone(a, record), 7);
      final graded = board(record);
      expect(room.claimableTeamMilestone(graded.first, graded), 7);
      expect(
        room.claimableTeamMilestone(
          a.copyWith(teamStreakClaims: const [7]),
          record,
        ),
        isNull,
        reason: 'seven is claimed, and fourteen is not reached',
      );
    });

    test("the team card's Claim button follows the record on the board roster",
        () {
      // What _TeamDayCard draws and pays: teamMilestoneRowFor over the lists
      // the room screen hands it, the board's graded ones while it runs.
      final graded = board([a, b()]);
      expect(room.teamBestStreakWith(graded.first, graded), 10);
      final row = room.teamMilestoneRowFor(graded.first, graded, graded);
      // No button: the record's run is six. Graded as handed, the board's
      // ten would draw one for seven days, and this fails.
      expect(row.claimable, isNull);
      expect(row.next, 7);
      expect(row.current, room.teamStreakWith(a, [a, b()]));
      final held = board([
        a,
        b(
          done: {
            for (final k in _days('2026-08-16', '2026-08-19')) k: 1,
            '2026-08-22': 1,
            '2026-08-23': 1,
          },
        ),
      ]);
      final claim = room.teamMilestoneRowFor(held.first, held, held);
      expect(claim.claimable, 7);
      expect(claim.next, isNull);
    });
  });

  group('the board reads it, the roster streams do not', () {
    test('the graded providers infer; the roster streams stay raw', () async {
      // Open-ended, and nothing ever done: the week of 22 August is closed
      // and inferred whatever day the suite runs, with no end for the room
      // to pass and no window for the week to age out of (a phone backfills
      // a member with no recorded day from their join).
      final room = RoomModel(
        code: 'TEST',
        name: 'test',
        createdBy: 'leader',
        createdByName: 'Leader',
        createdAt: _bh(2026, 8, 22),
        habitMode: RoomHabitMode.shared,
        sharedHabits: [_slot(HabitFrequencyType.weekly, target: 4)],
        duration: RoomDuration.open,
        startDate: _bh(2026, 8, 22),
      );
      final member = RoomParticipant(
        uid: 'u',
        displayName: 'u',
        characterId: '',
        joinedAt: _bh(2026, 8, 22),
        linkedHabitIds: const [_w],
        habitRules: {_w: [_weekly('2026-08-22')]},
        lastSyncedDay: '2026-08-24',
        lastSyncedAt: _bh(2026, 8, 24, 12),
        lastUpdated: _bh(2026, 8, 24, 12),
      );
      final container = ProviderContainer(
        overrides: [
          roomProvider('TEST').overrideWith((ref) => Stream.value(room)),
          roomParticipantsProvider('TEST')
              .overrideWith((ref) => Stream.value([member])),
          roomRosterHistoryProvider('TEST')
              .overrideWith((ref) => Stream.value([member])),
        ],
      );
      addTearDown(container.dispose);
      await container.read(roomProvider('TEST').future);
      await container.read(roomParticipantsProvider('TEST').future);
      await container.read(roomRosterHistoryProvider('TEST').future);

      void expectGraded(
        RoomParticipant raw,
        RoomParticipant Function() readGraded,
      ) {
        final before = DateTime.now();
        final graded = readGraded();
        final after = DateTime.now();
        expect(raw.inferredScheduledCount, isEmpty);
        final inferred = graded.inferredScheduledCount;
        expect(inferred, containsPair('2026-08-22', 0));
        expect(inferred, containsPair('2026-08-23', 0));
        expect(inferred, containsPair('2026-08-24', 0));
        expect(inferred.containsKey('2026-08-25'), isFalse);
        // On the device's own clock, taken as the board reads it.
        expect(
          inferred,
          anyOf(
            equals(member.closedQuotaWeekInference(room, now: before)),
            equals(member.closedQuotaWeekInference(room, now: after)),
          ),
        );
      }

      expectGraded(
        container.read(roomParticipantsProvider('TEST')).value!.single,
        () => container
            .read(gradedRoomParticipantsProvider('TEST'))
            .value!
            .single,
      );
      expectGraded(
        container.read(roomRosterHistoryProvider('TEST')).value!.single,
        () => container
            .read(gradedRoomRosterHistoryProvider('TEST'))
            .value!
            .single,
      );
    });
  });
}
