// A 4x week that can no longer be met, on the room strip.
//
// Aziz, 2026-09-26, about A8GEL7: "it has a fail in all days for perla, no
// rest days". Perla's week of 19 September had nothing done in it. Three
// things crossed out every blank day of it, the three a 4x quota rests
// included:
//  * while the week was open but already lost, the strip crossed every
//    blank day, where the week's own close rests the first three;
//  * from midnight to 10:00 on Saturday the strip took the week as closed
//    (its copy of isQuotaWeekClosed never gained the grader's grace for the
//    week's last day), and a closed week crossed every blank day;
//  * once it closed, the board's reading of a week her phone had not
//    regraded (closedQuotaWeekInference) stood aside, because she synced at
//    20:08 on the Friday, which it read at midnight on the easternmost clock
//    as a sync after the close.
// Now the days the week can only rest are never crossed, the week closes
// when its Friday does, and the board rests them once the week has closed.
//
// The strip reads the device's own clock, so its instants are local wall
// times. The inference must not depend on the zone, so its instants are UTC
// (a Bahrain wall clock via _bh), as in room_closed_quota_week_inference_test.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_strip_day.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

const _w = 'tamreen';

/// [hour]:[minute] on a Bahrain wall clock (UTC+3 all year) as a UTC instant.
DateTime _bh(int year, int month, int day, [int hour = 0, int minute = 0]) =>
    DateTime.utc(year, month, day, hour, minute)
        .subtract(const Duration(hours: 3));

RoomModel _room(DateTime start, DateTime end) => RoomModel(
      code: 'A8GEL7',
      name: 'test',
      createdBy: 'leader',
      createdByName: 'Leader',
      createdAt: start,
      habitMode: RoomHabitMode.shared,
      sharedHabits: const [
        RoomHabitTemplate(
          name: 'تمرين',
          category: HabitCategory.health,
          frequencyType: HabitFrequencyType.weekly,
          frequencyTarget: 4,
        ),
      ],
      duration: RoomDuration.fixed,
      startDate: start,
      endDate: end,
    );

/// A8GEL7 on the device's own calendar, for the strip.
final _local = _room(DateTime(2026, 7, 28), DateTime(2026, 10, 25));

/// A8GEL7 as Firestore holds it, for the inference.
final _utc = _room(_bh(2026, 7, 28), _bh(2026, 10, 25));

/// Perla's document as her phone left it on Friday 25 September: nothing
/// done since August, the rest days of her earlier September weeks
/// recorded, and the week of the 19th graded open.
RoomParticipant _perla({
  Map<String, int> scheduled = const {},
  String lastSyncedDay = '2026-09-25',
  DateTime? lastSyncedAt,
}) =>
    RoomParticipant(
      uid: 'Z0FndO3iFYgrzWzkwJ4QlOPBLPr2',
      displayName: 'Perla',
      characterId: 'female_abaya_navy',
      joinedAt: _bh(2026, 7, 28, 13, 9),
      linkedHabitIds: const [_w],
      habitRules: const {
        _w: [
          RoomHabitRule(
            from: '2026-07-28',
            frequencyType: HabitFrequencyType.weekly,
            frequencyTarget: 4,
          ),
        ],
      },
      dailyDoneCount: const {
        '2026-08-17': 1,
        '2026-08-18': 1,
        '2026-08-19': 1,
      },
      dailyScheduledCount: {
        '2026-09-05': 0,
        '2026-09-06': 0,
        '2026-09-07': 0,
        '2026-09-13': 0,
        '2026-09-14': 0,
        '2026-09-15': 0,
        ...scheduled,
      },
      quotaOkWeeks: const ['2026-08-01', '2026-08-15'],
      lastSyncedDay: lastSyncedDay,
      lastSyncedAt: lastSyncedAt ?? _bh(2026, 9, 25, 20, 8),
      lastUpdated: _bh(2026, 9, 25, 20, 8),
    );

/// The week of 19 September, Saturday to Friday.
final _week = [for (var d = 19; d <= 25; d++) DateTime(2026, 9, d)];

/// How the strip draws each day of that week at [now]: the look's race
/// code (roomRaceDayCode), which the Room Race widget carries too.
/// 'x' crossed, 'r' rest, 'o' still open, a digit a credit level.
String _drawn(RoomParticipant p, DateTime now) => [
      for (final day in _week)
        roomRaceDayCode(roomStripDayOf(_local, p, day, now: now)),
    ].join();

void main() {
  group('the strip, week of 19 September', () {
    test('Thursday, the week lost: its rest days stay plain, and only the '
        'days it broke on are crossed', () {
      // 19 to 21 are the week's rest (spare), 22 and 23 are owed, 24 is
      // today, 25 is still to come (both drawn open).
      expect(_drawn(_perla(), DateTime(2026, 9, 24, 12)), '000xxoo');
    });

    test('Saturday 01:42, Friday still markable: not closed yet', () {
      final now = DateTime(2026, 9, 26, 1, 42);
      expect(roomStripWeekIsClosed(_local, DateTime(2026, 9, 19), now: now),
          isFalse);
      expect(_drawn(_perla(), now), '000xxxo');
    });

    test('closed at 10:00, the day Friday closes, and not a minute before',
        () {
      expect(
        roomStripWeekIsClosed(
          _local,
          DateTime(2026, 9, 19),
          now: DateTime(2026, 9, 26, 9, 59),
        ),
        isFalse,
      );
      expect(
        roomStripWeekIsClosed(
          _local,
          DateTime(2026, 9, 19),
          now: DateTime(2026, 9, 26, 10),
        ),
        isTrue,
      );
    });

    test('closed and not regraded yet: still never a cross on a rest day',
        () {
      expect(_drawn(_perla(), DateTime(2026, 9, 26, 12)), '000xxxx');
    });

    test('once the record rests them, they are drawn as rest', () {
      final regraded = _perla(scheduled: const {
        '2026-09-19': 0,
        '2026-09-20': 0,
        '2026-09-21': 0,
      });
      expect(_drawn(regraded, DateTime(2026, 9, 26, 12)), 'rrrxxxx');
    });

    test('a week her phone already graded keeps the phone\'s answer', () {
      // The week of 12 September: her phone rested the 13th to the 15th and
      // kept the 12th due, because it counted the square she painted on the
      // 12th after that day had closed (held at 0 credit by the
      // anti-backdating clamp, but still a session for the quota). The
      // record alone would rest the 12th to the 14th; the phone's grading
      // stands.
      final drawn = [
        for (var d = 12; d <= 18; d++)
          roomRaceDayCode(roomStripDayOf(
            _local,
            _perla(),
            DateTime(2026, 9, d),
            now: DateTime(2026, 9, 26, 12),
          )),
      ].join();
      expect(drawn, 'xrrrxxx');
    });

    test('a room that has ended has closed every week', () {
      final ended = _room(DateTime(2026, 7, 28), DateTime(2026, 9, 22));
      expect(
        roomStripWeekIsClosed(
          ended,
          DateTime(2026, 9, 19),
          now: DateTime(2026, 9, 24, 12),
        ),
        isTrue,
      );
    });

    test('a daily habit is untouched: a blank closed day is a miss', () {
      final daily = _perla().copyWith(habitRules: const {
        _w: [
          RoomHabitRule(
            from: '2026-07-28',
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
          ),
        ],
      });
      expect(_drawn(daily, DateTime(2026, 9, 24, 12)), 'xxxxxoo');
    });
  });

  group('the board reading a week her phone has not regraded', () {
    const rests = {'2026-09-19': 0, '2026-09-20': 0, '2026-09-21': 0};

    Map<String, int> weekOf19(Map<String, int> inferred) => {
          for (final e in inferred.entries)
            if (e.key.compareTo('2026-09-19') >= 0 &&
                e.key.compareTo('2026-09-25') <= 0)
              e.key: e.value,
        };

    test('a sync at 20:08 on the Friday in Bahrain no longer hides the week',
        () {
      // 17:08 UTC: 07:08 on Saturday at UTC+14, where Friday stays
      // markable until 10:00. No clock had closed the week.
      final got = _perla().closedQuotaWeekInference(
        _utc,
        now: _bh(2026, 9, 26, 16),
      );
      expect(weekOf19(got), rests);
    });

    test('a sync once some clock had closed it stays as recorded', () {
      // 23:00 in Bahrain is 20:00 UTC, 10:00 on Saturday at UTC+14.
      for (final at in [_bh(2026, 9, 25, 23), _bh(2026, 9, 25, 23, 30)]) {
        final got = _perla(lastSyncedAt: at).closedQuotaWeekInference(
          _utc,
          now: _bh(2026, 9, 26, 16),
        );
        expect(weekOf19(got), isEmpty, reason: 'synced at $at');
      }
      final justBefore = _perla(lastSyncedAt: _bh(2026, 9, 25, 22, 59))
          .closedQuotaWeekInference(_utc, now: _bh(2026, 9, 26, 16));
      expect(weekOf19(justBefore), rests);
    });

    test('and the strip draws what the board reads', () {
      final inferred =
          _perla().withClosedQuotaWeeksInferred(_utc, now: _bh(2026, 9, 26, 16));
      // A Bahrain device at 16:00 on Saturday.
      expect(_drawn(inferred, DateTime(2026, 9, 26, 16)), 'rrrxxxx');
    });
  });
}
