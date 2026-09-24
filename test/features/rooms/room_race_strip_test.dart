import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/home_widget_service.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_strip_day.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart'
    show roomStripColumns;

/// The Room Race Home Screen widget draws a member's days from one character
/// per day (RoomRaceRow.days), decoded in GrowDailyWidget.swift. Aziz asked
/// on 2026-09-24 for the widget to be "same as the one in rooms", so these
/// pin three promises:
///
///  - every character is the room strip's own state for that day, through
///    the one rule both read (roomStripDayOf), and each state has its own
///    character;
///  - every member's string covers the same days, oldest first, so a late
///    joiner's squares still sit under the right day;
///  - the score prints exactly as the room row prints it, including the
///    quarter-credit days where Dart and Swift would round differently.
///
/// The room runs from 2026-09-01; the member joined on the 10th; the clock
/// is Thursday 2026-09-24 at noon, so the 30-day window is 08-26 to 09-24.
final _now = DateTime(2026, 9, 24, 12);

RoomModel _room({List<({String from, String to})> paused = const []}) =>
    RoomModel(
      code: 'PBYAS5',
      name: 'اذكار الصباح',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 9, 1),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 12, 31),
      pausedSpans: paused,
    );

RoomParticipant _member({
  Map<String, int> done = const {},
  List<String> standDownDays = const [],
}) =>
    RoomParticipant(
      uid: 'member-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 9, 10),
      linkedHabitIds: const ['h1'],
      dailyDoneCount: done,
      standDownDays: standDownDays,
      habitRules: const {
        'h1': [
          RoomHabitRule(
            from: '2026-09-10',
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
          ),
        ],
      },
      lastUpdated: DateTime(2026, 9, 24),
    );

/// The character for [day] in [strip], which ends on 09-24.
String _at(String strip, DateTime day) =>
    strip[strip.length - 1 - DateTime(2026, 9, 24).difference(day).inDays];

void main() {
  group('roomRaceDayCode', () {
    RoomStripDay day({
      double credit = 0,
      bool stood = false,
      bool rest = false,
      bool declared = false,
      bool missed = false,
      bool pending = false,
    }) =>
        RoomStripDay(
          credit: credit,
          isStoodDown: stood,
          isRest: rest,
          isDeclaredRest: declared,
          isMissed: missed,
          isPending: pending,
        );

    test('each drawn state has its own character, as the Swift side decodes',
        () {
      expect(roomRaceDayCode(day(stood: true)), 'p');
      expect(roomRaceDayCode(day(pending: true)), 'o');
      expect(roomRaceDayCode(day(declared: true)), 's');
      expect(roomRaceDayCode(day(rest: true)), 'r');
      expect(roomRaceDayCode(day(missed: true)), 'x');
      expect(roomRaceDayCode(day()), '0');
      expect(roomRaceDayCode(day(credit: 0.25)), '1');
      expect(roomRaceDayCode(day(credit: 0.5)), '2');
      expect(roomRaceDayCode(day(credit: 0.75)), '3');
      expect(roomRaceDayCode(day(credit: 1)), '4');
    });

    test('the states win in the room strip order', () {
      // A stood-down day is none of the others, whatever else is set.
      expect(
        roomRaceDayCode(day(stood: true, missed: true, rest: true, credit: 1)),
        'p',
      );
      // An open day with nothing on it is not a rest or a miss yet...
      expect(roomRaceDayCode(day(pending: true, rest: true)), 'o');
      // ...but an open day that already earned something shows it.
      expect(roomRaceDayCode(day(pending: true, credit: 0.5)), '2');
      // تخطّي is a choice, drawn before the calendar's own rest.
      expect(roomRaceDayCode(day(declared: true, rest: true)), 's');
      expect(roomRaceDayCode(day(rest: true, missed: true)), 'r');
    });
  });

  group('roomRaceStripFor', () {
    test('a month, oldest first, every day the room strip state of that day',
        () {
      final room = _room(paused: const [(from: '2026-09-15', to: '2026-09-16')]);
      final p = _member(
        done: const {'2026-09-20': 1, '2026-09-21': 1, '2026-09-23': 1},
        standDownDays: const ['2026-09-22'],
      );
      final end = roomRaceStripEnd(room, _now);
      final strip = roomRaceStripFor(room, p, end: end, now: _now);

      expect(end.toDateKey(), '2026-09-24');
      expect(strip.length, roomRaceStripDays);
      expect(strip.length, 30);
      for (var i = 0; i < 30; i++) {
        final day = end.subtract(Duration(days: 29 - i));
        final expected = day.isBefore(p.countedStartIn(room))
            ? '.'
            : roomRaceDayCode(roomStripDayOf(room, p, day, now: _now));
        expect(strip[i], expected, reason: day.toDateKey());
      }
    });

    test('draws each case the way the room screen does', () {
      final room = _room(paused: const [(from: '2026-09-15', to: '2026-09-16')]);
      final p = _member(
        done: const {'2026-09-20': 1, '2026-09-21': 1, '2026-09-23': 1},
        standDownDays: const ['2026-09-22'],
      );
      final strip = roomRaceStripFor(
        room,
        p,
        end: roomRaceStripEnd(room, _now),
        now: _now,
      );
      // Before they joined, nothing: their squares start on the 10th.
      expect(_at(strip, DateTime(2026, 9, 9)), '.');
      expect(_at(strip, DateTime(2026, 8, 26)), '.');
      expect(strip.indexOf(RegExp(r'[^.]')), 15, reason: strip);
      // Done in full.
      expect(_at(strip, DateTime(2026, 9, 23)), '4');
      // Their plan stood down, and the room paused: the dash, both.
      expect(_at(strip, DateTime(2026, 9, 22)), 'p');
      expect(_at(strip, DateTime(2026, 9, 15)), 'p');
      // A daily habit's closed empty day: the cross.
      expect(_at(strip, DateTime(2026, 9, 19)), 'x');
      // Today, open, nothing on it yet: faint, never a miss.
      expect(_at(strip, DateTime(2026, 9, 24)), 'o');
    });

    test('yesterday is not crossed out while it can still be marked', () {
      // 03:00 on the 25th: the 24th stays markable until the cutoff, so it
      // is drawn like an open day, not a miss (roomStripMissIsFinal).
      final early = DateTime(2026, 9, 25, 3);
      final room = _room();
      final p = _member();
      final strip = roomRaceStripFor(
        room,
        p,
        end: roomRaceStripEnd(room, early),
        now: early,
      );
      expect(roomRaceStripEnd(room, early).toDateKey(), '2026-09-25');
      expect(_atEnd(strip, 1), isNot('x'), reason: strip);
    });

    test('a late joiner lines up with everyone else, day for day', () {
      final room = _room();
      final early = RoomParticipant(
        uid: 'early',
        displayName: 'نور',
        characterId: 'female_1',
        joinedAt: DateTime(2026, 9, 1),
        linkedHabitIds: const ['h1'],
        dailyDoneCount: const {'2026-09-23': 1},
        habitRules: const {
          'h1': [
            RoomHabitRule(
              from: '2026-09-01',
              frequencyType: HabitFrequencyType.daily,
              frequencyTarget: 1,
            ),
          ],
        },
        lastUpdated: DateTime(2026, 9, 24),
      );
      final late = _member(done: const {'2026-09-23': 1});
      final end = roomRaceStripEnd(room, _now);
      final a = roomRaceStripFor(room, early, end: end, now: _now);
      final b = roomRaceStripFor(room, late, end: end, now: _now);
      expect(a.length, b.length);
      // The same day sits at the same index in both.
      expect(_at(a, DateTime(2026, 9, 23)), '4');
      expect(_at(b, DateTime(2026, 9, 23)), '4');
      expect(_at(a, DateTime(2026, 9, 5)), isNot('.'));
      expect(_at(b, DateTime(2026, 9, 5)), '.');
    });
  });

  group('the large face calendar', () {
    test('the room splits the same 30 days into the same columns', () {
      // The widget's roomCalendarColumns (WidgetFaceRules.swift) is a port
      // of roomStripColumns, and its Mac harness asserts exactly these six
      // columns for this window. Pinning them here too means neither side
      // can change the split without the other's check failing.
      final end = DateTime(2026, 9, 24);
      final days = [
        for (var i = 29; i >= 0; i--) end.subtract(Duration(days: i)),
      ];
      final lead = (days.first.weekday + 1) % 7;
      final columns = roomStripColumns(lead, days);
      // As text: a record holding a List compares that List by identity.
      expect(
        [for (final c in columns) '${c.monthKey % 12 + 1}: ${c.dayIndex}'],
        [
          '8: [-1, -1, -1, -1, 0, 1, 2]',
          '8: [3, 4, 5, -1, -1, -1, -1]',
          '9: [-1, -1, -1, 6, 7, 8, 9]',
          '9: [10, 11, 12, 13, 14, 15, 16]',
          '9: [17, 18, 19, 20, 21, 22, 23]',
          '9: [24, 25, 26, 27, 28, 29, -1]',
        ],
      );
    });
  });

  group('roomScoreText', () {
    test('prints what the room row prints, «24.2 من 42»', () {
      for (final lang in ['ar', 'en']) {
        final s = S(Locale(lang));
        for (final v in [0.0, 1.0, 24.0, 24.2, 24.25, 0.25, 12.05, 3.45, 9.75]) {
          final expected = s.roomDayCount(v, 42);
          final built = lang == 'ar'
              ? '${roomScoreText(v)} من 42'
              : '${roomScoreText(v)}/42';
          expect(built, expected, reason: '$lang $v');
        }
      }
    });

    test('rounds a half up, where printf in Swift would round it to even', () {
      // Why the app sends this text instead of letting the widget format the
      // double itself: 24.25 is exact in binary, and Swift's
      // String(format: "%.1f") prints it as 24.2 against the room's 24.3.
      expect(roomScoreText(24.25), '24.3');
      expect(roomScoreText(0.25), '0.3');
      expect(roomScoreText(24), '24');
    });
  });

  group('roomRacePayload', () {
    test('writes every key RoomRaceRow and RawRaceData decode', () {
      final payload = HomeWidgetService.roomRacePayload(
        hasRoom: true,
        roomName: 'اذكار الصباح',
        isLive: true,
        daysRemaining: 36,
        isTeam: false,
        stripEndDay: '2026-09-24',
        rows: const [
          (
            name: 'Aziz',
            rank: 1,
            percent: 58,
            isMe: true,
            uid: 'u1',
            daysDone: 24,
            daysTotal: 42,
            score: 24.2,
            scoreText: '24.2',
            partialPlan: false,
            streak: 4,
            isLeader: false,
            pausedNow: false,
            doneToday: false,
            countsToday: true,
            days: '...4x4o',
          ),
        ],
      );
      expect(
        payload.keys.toSet(),
        {
          'hasRoom',
          'roomName',
          'isLive',
          'daysRemaining',
          'isTeam',
          'stripEndDay',
          'rows',
        },
      );
      final row = (payload['rows']! as List).single as Map<String, Object?>;
      expect(
        row.keys.toSet(),
        {
          'name',
          'rank',
          'percent',
          'isMe',
          'uid',
          'daysDone',
          'daysTotal',
          'score',
          'scoreText',
          'partialPlan',
          'streak',
          'isLeader',
          'pausedNow',
          'doneToday',
          'countsToday',
          'days',
        },
      );
      // Swift decodes daysDone as an Int and score as a Double: a fraction
      // in the Int would fail the row, and then the whole face.
      expect(row['daysDone'], isA<int>());
      expect(row['score'], isA<double>());
      expect(row['days'], '...4x4o');
    });
  });
}

/// The character [back] days before the strip's last one.
String _atEnd(String strip, int back) => strip[strip.length - 1 - back];
