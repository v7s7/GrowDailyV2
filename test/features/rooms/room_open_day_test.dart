// A room may not count a day that is still open.
//
// Aziz, 2026-09-11 on Reports: "it should show the percent without count
// today as missing, because today still not finish. If the day finish and the
// flex hour finishes, here it should count the day as missed. Every where in
// progress like this." That shipped for Reports as d1729b7; rooms were left
// for this change, and he chose "same as reports" on 2026-09-12.
//
// What it costs when rooms judge at midnight, measured on ELQVF8 «Being
// Better» across midnight that night: Hoor fell from 69.7% to 63.9% and her
// 6-day streak read 0, with her own 11 Sep still markable until 10:00. Every
// number below is that room's real shape.
//
// The rule: a day enters a score once it is CLOSED (kDayCutoffHour the next
// morning) or ANSWERED (everything it asked for is done). Until then it
// leaves both sides, exactly as a rest day does, and the streak walks
// straight through it.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';

/// The room as it stood: 1 to 30 Sep, تمرين 4x a week, صلاة الوتر daily, and
/// قراءة القرآن daily from the 9th.
RoomModel _room() => RoomModel(
  code: 'ELQVF8',
  name: 'Being Better',
  createdBy: 'aziz',
  createdByName: 'Aziz',
  createdAt: DateTime(2026, 9),
  habitMode: RoomHabitMode.shared,
  sharedHabits: [
    const RoomHabitTemplate(
      name: 'تمرين',
      category: HabitCategory.health,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 4,
    ),
    const RoomHabitTemplate(
      name: 'صلاة الوتر',
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
    ),
    RoomHabitTemplate(
      name: 'قراءة القرآن',
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      addedAt: DateTime(2026, 9, 9, 0, 48),
    ),
  ],
  duration: RoomDuration.fixed,
  startDate: DateTime(2026, 9),
  endDate: DateTime(2026, 9, 30),
);

RoomHabitRule _rule(String from, {bool weekly = false}) => RoomHabitRule(
  from: from,
  frequencyType: weekly ? HabitFrequencyType.weekly : HabitFrequencyType.daily,
  frequencyTarget: weekly ? 4 : 1,
);

RoomParticipant _member({
  required String name,
  required Map<String, int> done,
  Map<String, int> partial = const {},
  Map<String, int> scheduled = const {},
  List<String> quotaOkWeeks = const [],
  String quranFrom = '2026-09-09',
}) =>
    RoomParticipant(
      uid: name,
      displayName: name,
      characterId: 'none',
      joinedAt: DateTime(2026, 9),
      linkedHabitIds: const ['t', 'w', 'q'],
      dailyDoneCount: done,
      dailyPartialCount: partial,
      dailyScheduledCount: scheduled,
      quotaOkWeeks: quotaOkWeeks,
      habitRules: {
        't': [_rule('2026-09-01', weekly: true)],
        'w': [_rule('2026-09-01')],
        'q': [_rule(quranFrom)],
      },
      lastUpdated: DateTime(2026, 9, 12),
    );

/// Aziz on the night of the 11th: صلاة الوتر every day, تمرين on the 2nd, a
/// جزئي on the 3rd, then the 8th and the 11th, and قراءة القرآن from the 9th.
/// His 4x week of the 5th closed short, which is why the 5th, 6th and 7th
/// ask one habit instead of two.
RoomParticipant _aziz() => _member(
  name: 'Aziz',
  done: const {
    '2026-09-01': 1,
    '2026-09-02': 2,
    '2026-09-03': 1,
    '2026-09-04': 1,
    '2026-09-05': 1,
    '2026-09-06': 1,
    '2026-09-07': 1,
    '2026-09-08': 2,
    '2026-09-09': 2,
    '2026-09-10': 2,
    '2026-09-11': 3,
  },
  partial: const {'2026-09-03': 1},
  scheduled: const {'2026-09-05': 1, '2026-09-06': 1, '2026-09-07': 1},
);

/// Hoor on the same night: nothing on the 3rd and 4th, everything from the
/// 5th, and the 11th two of three with قراءة القرآن still open.
RoomParticipant _hoor() => _member(
  name: 'Hoor',
  quranFrom: '2026-09-08',
  done: const {
    '2026-09-01': 1,
    '2026-09-02': 1,
    '2026-09-05': 2,
    '2026-09-06': 2,
    '2026-09-07': 2,
    '2026-09-08': 3,
    '2026-09-09': 3,
    '2026-09-10': 2,
    '2026-09-11': 2,
  },
  scheduled: const {'2026-09-10': 2},
  quotaOkWeeks: const ['2026-09-05'],
);

/// 23:59 on the 11th, and six minutes later.
final _beforeMidnight = DateTime(2026, 9, 11, 23, 59);
final _afterMidnight = DateTime(2026, 9, 12, 0, 5);

/// Once the 11th has closed, and once the 12th has too.
final _afterCutoff = DateTime(2026, 9, 12, 10, 30);
final _nextMorning = DateTime(2026, 9, 13, 10, 30);

int _percent(double ratio) => (ratio * 100).round();

void main() {
  group('dayIsCountableAt', () {
    test('an unfinished day is not countable while it is still open', () {
      final hoor = _hoor();
      // Her 11th: two of the three habits, so not answered.
      expect(hoor.dayIsCountableAt('2026-09-11', _beforeMidnight), isFalse);
      expect(hoor.dayIsCountableAt('2026-09-11', _afterMidnight), isFalse);
      // It closes at 10:00 the next morning, and counts from then.
      expect(hoor.dayIsCountableAt('2026-09-11', _afterCutoff), isTrue);
    });

    test('a finished day counts the moment it is finished', () {
      // Aziz marked his third habit on the 11th at 23:56. Waiting until the
      // next morning to show it would hide the day he just completed.
      expect(_aziz().dayIsCountableAt('2026-09-11', _beforeMidnight), isTrue);
    });

    test('a day that has not started yet never counts', () {
      expect(_aziz().dayIsCountableAt('2026-09-12', _beforeMidnight), isFalse);
    });
  });

  group('no midnight dip', () {
    test('the percentage is the same either side of midnight', () {
      final room = _room();
      for (final member in [_aziz(), _hoor()]) {
        expect(
          _percent(member.progressRatio(room, now: _afterMidnight)),
          _percent(member.progressRatio(room, now: _beforeMidnight)),
          reason: '${member.displayName} own score',
        );
        expect(
          _percent(member.roomProgressRatio(room, now: _afterMidnight)),
          _percent(member.roomProgressRatio(room, now: _beforeMidnight)),
          reason: '${member.displayName} room score',
        );
      }
    });

    test('Hoor reads 70%, not the 64% the midnight reading gave her', () {
      // 7.0 of her 10 settled days: 0.5 + 0.5 on the 1st and 2nd, nothing on
      // the 3rd and 4th, then six whole days. The 11th is still open and the
      // 12th has not started, so neither is in the fraction.
      final hoor = _hoor();
      final room = _room();
      expect(_percent(hoor.progressRatio(room, now: _afterMidnight)), 70);
      expect(hoor.daysCompleted(room, now: _afterMidnight), closeTo(7.0, 1e-9));
      expect(hoor.daysElapsedIn(room, now: _afterMidnight), 10);
    });

    test('the new day joins the fraction only once it closes', () {
      final hoor = _hoor();
      final room = _room();
      // The 11th closes at 10:00 on the 12th: two of three, so it lands as a
      // fraction of a day rather than as nothing.
      expect(hoor.daysElapsedIn(room, now: _afterCutoff), 11);
      expect(_percent(hoor.progressRatio(room, now: _afterCutoff)), 70);
      // The 12th closes the next morning, empty.
      expect(hoor.daysElapsedIn(room, now: _nextMorning), 12);
      expect(_percent(hoor.progressRatio(room, now: _nextMorning)), 64);
    });
  });

  group('the streak walks through an open day', () {
    test('Hoor keeps her 6 across midnight', () {
      final room = _room();
      expect(_hoor().currentStreak(room, now: _beforeMidnight), 6);
      expect(_hoor().currentStreak(room, now: _afterMidnight), 6);
    });

    test('it breaks once the unfinished day closes', () {
      // 10:00 on the 12th: the 11th is final at two of three, so the run ends.
      expect(_hoor().currentStreak(_room(), now: _afterCutoff), 0);
    });

    test('a finished open day extends it', () {
      // Aziz finished the 11th, so it counts at once; the 10th was two of
      // three, which ends the run behind it.
      expect(_aziz().currentStreak(_room(), now: _beforeMidnight), 1);
    });
  });

  group('the room score gets the same treatment', () {
    test('an unfinished open day leaves both sides of the room score', () {
      final room = _room();
      final hoor = _hoor();
      expect(hoor.roomDaysElapsedIn(room, now: _afterMidnight), 10);
      expect(
        hoor.roomDaysCompleted(room, now: _afterMidnight),
        closeTo(7.0, 1e-9),
      );
      expect(_percent(hoor.roomProgressRatio(room, now: _afterMidnight)), 70);
    });
  });
}
