// Every day of the room strip sits on its own weekday row, Saturday at the
// top, from a room's first day. Aziz, 2026-09-28, on F8HQKE «بزنس مِن», which
// began on Sunday 27 September: the strip drew that Sunday on the top row,
// while every other room on the screen had Saturday at the top of the same
// week and today on the Monday row. "It should think where it will be ...
// skip 1 square only." The rows no day had reached were being dropped.
//
// Nothing here depends on the day the suite runs: a young room is compared
// with a long one, whose seven rows are all in use, at the same moment.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart'
    show RoomStrip, roomStripColumns;
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
  });

  final today = DateTime.now().effectiveDay;

  /// An open room that started [days] days ago, one member in it since.
  RoomModel roomOf(int days) {
    final start = today.subtract(Duration(days: days - 1));
    return RoomModel(
      code: 'ROWS01',
      name: 'بزنس مِن',
      createdBy: 'me',
      createdByName: 'Aziz',
      createdAt: start,
      habitMode: RoomHabitMode.own,
      duration: RoomDuration.open,
      startDate: start,
    );
  }

  Future<void> pumpStrip(WidgetTester tester, int days) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final room = roomOf(days);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.light,
        home: Scaffold(
          body: ListView(
            children: [
              Center(
                child: SizedBox(
                  width: 274,
                  child: RoomStrip(
                    room: room,
                    participant: RoomParticipant(
                      uid: 'me',
                      displayName: 'Aziz',
                      characterId: 'none',
                      joinedAt: room.startDate,
                      lastUpdated: today,
                      linkedHabitIds: const ['h1'],
                      linkedHabitNames: const ['تمرين'],
                    ),
                    isYou: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Rect stripRect(WidgetTester t) => t.getRect(find.byType(RoomStrip));

  /// «اليوم»'s distance from the strip's top edge: which row today is on.
  double todayRowOffset(WidgetTester t) =>
      t.getRect(find.text('اليوم', skipOffstage: false)).top -
      stripRect(t).top;

  testWidgets('a room one day old draws the same seven rows as a long one',
      (tester) async {
    await pumpStrip(tester, 90);
    final full = stripRect(tester).height;
    await pumpStrip(tester, 1);
    expect(
      stripRect(tester).height,
      full,
      reason: 'rows no day has reached yet are drawn, empty',
    );
  });

  testWidgets('today sits on its weekday row in a room two days old',
      (tester) async {
    // The long room uses every row, so its today is on today's weekday row.
    await pumpStrip(tester, 90);
    final row = todayRowOffset(tester);
    await pumpStrip(tester, 2);
    expect(
      todayRowOffset(tester),
      row,
      reason: 'a young room puts today where every other room does',
    );
  });

  test(
      'the first column leaves empty exactly the days from Saturday to the '
      'start', () {
    // The table in RoomStrip's doc: Sat 0, Sun 1, Mon 2 ... Fri 6. Starts on
    // Saturday 5 September 2026 and the six days after it, so each first
    // week lies inside one month.
    const names = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    for (var w = 0; w < 7; w++) {
      final start = DateTime(2026, 9, 5 + w);
      final days = [
        for (var i = 0; i < 14; i++) DateTime(2026, 9, start.day + i),
      ];
      // The strip's own lead: (weekday + 1) % 7.
      final lead = (start.weekday + 1) % 7;
      expect(lead, w, reason: names[w]);
      final first = roomStripColumns(lead, days).first.dayIndex;
      expect(
        first.takeWhile((i) => i < 0).length,
        w,
        reason: '${names[w]}: $w empty slots above the first day',
      );
      expect(first[w], 0, reason: '${names[w]}: the first day on its own row');
    }
  });

  testWidgets('every start day puts the first square on its own weekday row',
      (tester) async {
    // Rooms one to seven days old began on seven different weekdays, so
    // whatever day the suite runs, each row holds one room's first square.
    // Their «البداية» labels must step down one row per weekday from
    // Saturday at the top, evenly.
    final topByRow = <int, double>{};
    for (var age = 1; age <= 7; age++) {
      await pumpStrip(tester, age);
      final start = today.subtract(Duration(days: age - 1));
      final label = find.textContaining('البداية', skipOffstage: false);
      topByRow[(start.weekday + 1) % 7] =
          tester.getRect(label).top - stripRect(tester).top;
    }
    expect(topByRow.keys.toSet(), {0, 1, 2, 3, 4, 5, 6});
    final pitch = topByRow[1]! - topByRow[0]!;
    expect(pitch, greaterThan(0), reason: 'Saturday is the top row');
    for (var r = 1; r < 7; r++) {
      expect(
        topByRow[r]! - topByRow[r - 1]!,
        closeTo(pitch, 0.5),
        reason: 'row $r sits one row below row ${r - 1}',
      );
    }
  });
}
