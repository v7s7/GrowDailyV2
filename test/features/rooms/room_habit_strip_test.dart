// One habit of a shared plan on a member's strip: the room's habit filter
// (Aziz, 2026-09-27: "user can click on a habit to see the room grid showing
// the grid of that choosen habit"). Pure rules first, drawn from room
// اذكار الصباح's real week (Aziz's marks, 21-27 September), then the strip.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_habit_strip.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_strip_day.dart';
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart'
    show RoomStrip;

RoomHabitTemplate _slot(
  String name, {
  String? addedDay,
  DateTime? removedAt,
  String? stopsOn,
  List<({String from, String to})> offSpans = const [],
  HabitFrequencyType type = HabitFrequencyType.daily,
  int target = 1,
}) =>
    RoomHabitTemplate(
      name: name,
      category: HabitCategory.faith,
      frequencyType: type,
      frequencyTarget: target,
      addedDay: addedDay,
      removedAt: removedAt,
      removedBy: removedAt == null ? null : 'leader-uid',
      stopsOn: stopsOn,
      offSpans: offSpans,
    );

RoomModel _room({
  DateTime? start,
  List<RoomHabitTemplate>? slots,
  List<({String from, String to})> pausedSpans = const [],
}) =>
    RoomModel(
      code: 'PBYAS5',
      name: 'اذكار الصباح',
      createdBy: 'leader-uid',
      createdByName: 'نور',
      createdAt: start ?? DateTime(2026, 8, 14),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: start ?? DateTime(2026, 8, 14),
      endDate: DateTime(2026, 10, 29),
      pausedSpans: pausedSpans,
      sharedHabits: slots ??
          [
            _slot('أذكار الصباح'),
            _slot('سورة الملك'),
            _slot('صدقة', addedDay: '2026-09-21'),
            _slot('سنة الظهر البعدية',
                addedDay: '2026-09-24',
                removedAt: DateTime(2026, 9, 26, 14, 50),
                stopsOn: '2026-09-27'),
            _slot('سنة الفجر', addedDay: '2026-09-24'),
            _slot('الضحى', addedDay: '2026-09-24'),
            _slot('الوتر',
                addedDay: '2026-09-24',
                removedAt: DateTime(2026, 9, 26, 14, 50),
                stopsOn: '2026-09-27'),
          ],
    );

/// One letter per slot per day, the way the sync stores them ('.' = no
/// mark): Aziz's real record for the week.
const _week = {
  '2026-09-21': 'ddd....',
  '2026-09-22': 'ddd....',
  '2026-09-23': 'ddd....',
  '2026-09-24': 'ddddddd',
  '2026-09-25': 'mdddddd',
  '2026-09-26': 'mddmddd',
  '2026-09-27': 'mmd.dd.',
};

RoomParticipant _aziz({
  Map<String, String> days = _week,
  List<String> ids = const ['h0', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'],
  DateTime? joinedAt,
  List<String> standDownDays = const [],
  Map<String, List<RoomHabitRule>> rules = const {},
  Map<String, int> doneOverride = const {},
}) {
  final marks = <String, Map<String, RoomHabitMark>>{};
  final done = <String, int>{};
  final partial = <String, int>{};
  final scheduled = <String, int>{};
  days.forEach((day, letters) {
    final m = <String, RoomHabitMark>{};
    for (var i = 0; i < letters.length; i++) {
      final mark = RoomHabitMark.fromCode(letters[i]);
      if (mark != null) m['h$i'] = mark;
    }
    marks[day] = m;
    done[day] = m.values.where((x) => x == RoomHabitMark.done).length;
    partial[day] = m.values.where((x) => x == RoomHabitMark.partial).length;
    scheduled[day] = m.values.where((x) => x.wasAsked).length;
  });
  done.addAll(doneOverride);
  return RoomParticipant(
    uid: 'me-uid',
    displayName: 'Aziz',
    characterId: 'none',
    joinedAt: joinedAt ?? DateTime(2026, 8, 14),
    linkedHabitIds: ids,
    linkedHabitNames: const [
      'أذكار الصباح',
      'سورة الملك',
      'الصدقة ولو بالقليل',
      'سنة الظهر البعدية',
      'سنة الفجر',
      'صلاة الضحى',
      'صلاة الوتر',
    ],
    dailyHabitMarks: marks,
    dailyDoneCount: done,
    dailyPartialCount: partial,
    dailyScheduledCount: scheduled,
    standDownDays: standDownDays,
    habitRules: rules,
    lastUpdated: DateTime(2026, 9, 27),
  );
}

/// 07:40 on Sunday 27 September: yesterday is still open until 10:00.
final _now = DateTime(2026, 9, 27, 7, 40);

RoomStripDay _day(RoomModel room, RoomParticipant p, int slot, String key,
        {DateTime? now}) =>
    roomStripSlotDayOf(room, p, slot, DateTime.parse(key), now: now ?? _now);

void main() {
  group('roomSlotStripWindow', () {
    test('a habit the room started with runs from the member\'s first day',
        () {
      final w = roomSlotStripWindow(_room(), _aziz(), 1, now: _now)!;
      expect(w.first, DateTime(2026, 8, 14));
      expect(w.last, DateTime(2026, 9, 27));
    });

    test('a habit added later starts the day it joined the plan', () {
      final w = roomSlotStripWindow(_room(), _aziz(), 2, now: _now)!;
      expect(w.first, DateTime(2026, 9, 21));
    });

    test('a late joiner starts on their own first day', () {
      final w = roomSlotStripWindow(
          _room(), _aziz(joinedAt: DateTime(2026, 9, 1, 12)), 1,
          now: _now)!;
      expect(w.first, DateTime(2026, 9, 1));
    });

    test('a removed habit stops on its last counted day', () {
      final w = roomSlotStripWindow(_room(), _aziz(), 6, now: _now)!;
      expect(w.first, DateTime(2026, 9, 24));
      expect(w.last, DateTime(2026, 9, 26));
    });

    test('nothing for a habit removed before the member joined', () {
      expect(
        roomSlotStripWindow(
            _room(), _aziz(joinedAt: DateTime(2026, 9, 26, 20)), 6,
            now: _now),
        isNull,
      );
    });

    test('nothing for a legacy removal, which counted on no day', () {
      final room = _room(slots: [
        _slot('أذكار الصباح'),
        _slot('تمرين', removedAt: DateTime(2026, 9, 9)),
      ]);
      expect(roomSlotStripWindow(room, _aziz(), 1, now: _now), isNull);
    });
  });

  group('roomStripSlotDayOf', () {
    test('a done habit is a full day', () {
      final d = _day(_room(), _aziz(), 6, '2026-09-25');
      expect(d.look, RoomStripDayLook.credit);
      expect(d.credit, 1.0);
    });

    test('a closed day it missed is crossed out', () {
      final d = _day(_room(), _aziz(), 0, '2026-09-25');
      expect(d.look, RoomStripDayLook.missed);
    });

    test('yesterday before 10:00 is still open: pending, not a miss', () {
      final d = _day(_room(), _aziz(), 0, '2026-09-26');
      expect(d.look, RoomStripDayLook.pending);
      final after10 = _day(_room(), _aziz(), 0, '2026-09-26',
          now: DateTime(2026, 9, 27, 10, 1));
      expect(after10.look, RoomStripDayLook.missed);
    });

    test('جزئي is half, تخطّي is a neutral skip, a rest is a rest', () {
      final p = _aziz(days: const {'2026-09-23': 'psr....'});
      expect(_day(_room(), p, 0, '2026-09-23').credit, 0.5);
      expect(_day(_room(), p, 1, '2026-09-23').look,
          RoomStripDayLook.declaredRest);
      expect(_day(_room(), p, 2, '2026-09-23').look, RoomStripDayLook.rest);
    });

    test('a day whose marks disagree with its counts is never a claim', () {
      // The anti-backdating clamp held the day at 0 done while the marks say
      // one was: habitMarksFor refuses them, so the square draws nothing.
      final p = _aziz(
        days: const {'2026-09-23': 'ddd....'},
        doneOverride: const {'2026-09-23': 0},
      );
      final d = _day(_room(), p, 0, '2026-09-23');
      expect(d.look, RoomStripDayLook.credit);
      expect(d.credit, 0);
      expect(d.isMissed, isFalse);
    });

    test('a day this member skipped the slot is their neutral skip', () {
      final p = _aziz(ids: const ['h0', kDeclinedSlot, 'h2', 'h3', 'h4', 'h5', 'h6']);
      expect(_day(_room(), p, 1, '2026-09-23').look,
          RoomStripDayLook.declaredRest);
    });

    test('a paused room, a stand-down and a stretch out of the plan owe nothing',
        () {
      final room = _room(pausedSpans: const [(from: '2026-09-22', to: '2026-09-22')]);
      expect(_day(room, _aziz(), 1, '2026-09-22').look,
          RoomStripDayLook.standDown);
      final stoodDown = _aziz(standDownDays: const ['2026-09-23']);
      expect(_day(_room(), stoodDown, 1, '2026-09-23').look,
          RoomStripDayLook.standDown);
      final off = _room(slots: [
        _slot('أذكار الصباح'),
        _slot('سورة الملك',
            offSpans: const [(from: '2026-09-21', to: '2026-09-22')]),
      ]);
      expect(_day(off, _aziz(), 1, '2026-09-21').look,
          RoomStripDayLook.standDown);
    });

    group('a weekly quota', () {
      // سورة الملك as 3x a week for this group, week of 19-25 September.
      final rules = {
        'h1': const [
          RoomHabitRule(
            from: '2026-08-14',
            frequencyType: HabitFrequencyType.weekly,
            frequencyTarget: 3,
          ),
        ],
      };
      RoomParticipant withWeek(Map<String, String> days) =>
          _aziz(days: days, rules: rules);

      test('a blank day in a week still open is plain, never crossed', () {
        final p = withWeek(const {
          '2026-09-26': 'dm.....',
        });
        final d = _day(_room(), p, 1, '2026-09-26',
            now: DateTime(2026, 9, 28, 12));
        expect(d.look, RoomStripDayLook.credit);
        expect(d.isMissed, isFalse);
      });

      test('once the week closes, only the days it owed are crossed', () {
        // Done Sat, Sun; blank Mon-Fri: the third session was owed on the
        // last day it could still be made, Friday.
        final p = withWeek(const {
          '2026-09-19': 'dd.....',
          '2026-09-20': 'dd.....',
          '2026-09-21': 'dm.....',
          '2026-09-22': 'dm.....',
          '2026-09-23': 'dm.....',
          '2026-09-24': 'dm.....',
          '2026-09-25': 'dm.....',
        });
        final after = DateTime(2026, 9, 27, 12);
        expect(_day(_room(), p, 1, '2026-09-21', now: after).isMissed, isFalse,
            reason: 'Monday was spare: the week could still be made after it');
        expect(_day(_room(), p, 1, '2026-09-25', now: after).isMissed, isTrue,
            reason: 'Friday was the last chance');
      });
    });
  });

  group('roomSlotScore', () {
    test('done over asked, open days with nothing on them left out', () {
      // أذكار الصباح, 21-27 Sep at 07:40 on the 27th: done 21-24 (4), missed
      // 25 (closed), open with nothing 26 and 27.
      final score = roomSlotScore(
        _room(start: DateTime(2026, 9, 21)),
        _aziz(),
        0,
        now: _now,
      );
      expect(score.done, 4);
      expect(score.asked, 5);
    });

    test('a removed habit counts only its own days', () {
      final score = roomSlotScore(
        _room(start: DateTime(2026, 9, 21)),
        _aziz(),
        6,
        now: _now,
      );
      expect(score.done, 3);
      expect(score.asked, 3);
    });

    test('nothing at all for a habit that was never theirs', () {
      final score = roomSlotScore(
        _room(),
        _aziz(joinedAt: DateTime(2026, 9, 26, 20)),
        6,
        now: _now,
      );
      expect(score.asked, 0);
    });
  });

  group('RoomStrip, one habit', () {
    setUpAll(() async {
      await initializeDateFormatting('ar');
      await initializeDateFormatting('en');
    });

    // Built on the real clock, because the strip reads DateTime.now().
    final today = DateTime.now().effectiveDay;
    String key(int daysAgo) =>
        DateTime(today.year, today.month, today.day - daysAgo).toDateKey();
    final start = DateTime(today.year, today.month, today.day - 20);
    final room = _room(start: start, slots: [
      _slot('أذكار الصباح'),
      _slot('الوتر',
          addedDay: key(3),
          removedAt: DateTime(today.year, today.month, today.day - 1, 14),
          stopsOn: key(0)),
    ]);
    final member = _aziz(
      joinedAt: start,
      days: {
        for (var i = 20; i >= 0; i--)
          key(i): i <= 3 && i >= 1 ? 'dd' : 'd.',
      },
    );

    Future<void> pump(WidgetTester tester, {int? slot}) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 245,
              child: RoomStrip(
                room: room,
                participant: member,
                isYou: true,
                slot: slot,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    String mmdd(int daysAgo) {
      final d = DateTime(today.year, today.month, today.day - daysAgo);
      return '${d.month.toString().padLeft(2, '0')}/'
          '${d.day.toString().padLeft(2, '0')}';
    }

    testWidgets('a removed habit starts on its own day and ends «آخر يوم»',
        (tester) async {
      await pump(tester, slot: 1);
      expect(find.text('البداية ${mmdd(3)}', skipOffstage: false),
          findsOneWidget);
      expect(find.text('آخر يوم', skipOffstage: false), findsOneWidget);
      expect(find.text('اليوم', skipOffstage: false), findsNothing,
          reason: 'today is past its last day, so the strip never reaches it');
    });

    testWidgets('the whole plan draws as it always did', (tester) async {
      await pump(tester);
      expect(find.text('آخر يوم', skipOffstage: false), findsNothing);
      expect(find.text('اليوم', skipOffstage: false), findsOneWidget);
    });

    testWidgets('a habit never in this member\'s plan draws nothing',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: GameTheme.dark,
        home: Scaffold(
          body: RoomStrip(
            room: room,
            participant: _aziz(
              joinedAt: today,
              days: {key(0): 'd.'},
            ),
            isYou: true,
            slot: 1,
          ),
        ),
      ));
      expect(find.byType(RoomStrip), findsOneWidget);
      expect(find.text('آخر يوم', skipOffstage: false), findsNothing);
      expect(find.text('اليوم', skipOffstage: false), findsNothing);
    });
  });
}
