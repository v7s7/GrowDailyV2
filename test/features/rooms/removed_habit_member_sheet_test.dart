// A member's sheet after the leader removed habits from the plan.
//
// Room PBYAS5, 2026-09-28: two of seven habits removed on the 26th. The line
// under a member's name still listed all seven, and the day card for a day
// their phone had not synced yet said «0 من 7 عادات» and «ما أُنجز 7». Aziz:
// "it says 7 habit, although we already removed two habit from the room".
//
// Pumped in Arabic at phone size through the same showParticipantSheet the
// leaderboard calls, with the member as the board hands it over (graded,
// RoomParticipant.withUnsyncedPlanInferred). The room is PBYAS5's plan moved
// to August and ended, so the calendar opens on a fixed month whatever day
// the suite runs.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart'
    show showParticipantSheet;
import 'package:grow_daily_v2/shared/widgets/calendar_month_scaffold.dart';
import 'package:hive/hive.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _names = [
  'أذكار الصباح',
  'سورة الملك',
  'صدقة',
  'سنة الظهر البعدية',
  'سنة الفجر',
  'الضحى',
  'الوتر',
];
const _ids = ['a', 'm', 's', 'z', 'f', 'd', 'w'];

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('removed_habit_member_sheet');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  final room = RoomModel(
    code: 'PBYAS5',
    name: 'اذكار الصباح',
    createdBy: 'noor',
    createdByName: 'نور',
    createdAt: DateTime(2026, 8),
    habitMode: RoomHabitMode.shared,
    sharedHabits: [
      for (var i = 0; i < _names.length; i++)
        RoomHabitTemplate(
          name: _names[i],
          category: HabitCategory.faith,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
          removedAt: i == 3 || i == 6 ? DateTime(2026, 8, 26, 14, 50) : null,
          removedBy: i == 3 || i == 6 ? 'noor' : null,
          stopsOn: i == 3 || i == 6 ? '2026-08-27' : null,
        ),
    ],
    duration: RoomDuration.fixed,
    startDate: DateTime(2026, 8),
    endDate: DateTime(2026, 8, 30),
  );

  // Synced on the 27th, the first day without the two (key 5), then not
  // again: the 28th to the 30th have no count at all.
  final noor = RoomParticipant(
    uid: 'noor',
    displayName: 'نور',
    characterId: 'none',
    joinedAt: DateTime(2026, 8),
    linkedHabitIds: _ids,
    linkedHabitNames: _names,
    dailyDoneCount: const {'2026-08-26': 3, '2026-08-27': 3},
    dailyScheduledCount: const {'2026-08-27': 5},
    habitRules: {
      for (final id in _ids)
        id: [
          const RoomHabitRule(
            from: '2026-08-01',
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
          ),
        ],
    },
    lastSyncedDay: '2026-08-27',
    lastSyncedAt: DateTime(2026, 8, 27, 12, 23),
    lastUpdated: DateTime(2026, 8, 27, 12, 23),
  );

  Future<void> openSheet(WidgetTester tester, RoomParticipant member) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showParticipantSheet(
                    context,
                    room: room,
                    participant: member,
                    isYou: false,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
  }

  Future<void> tapDay(WidgetTester tester, String day) async {
    final cell = find.descendant(
      of: find.byType(CalendarMonthGrid),
      matching: find.text(day),
    );
    await tester.ensureVisible(cell);
    await tester.tap(cell);
    await _settle(tester);
  }

  testWidgets('the line under the name lists the five habits the plan has',
      (tester) async {
    await openSheet(tester, noor.withUnsyncedPlanInferred(room));
    expect(
      find.text('أذكار الصباح، سورة الملك، صدقة، سنة الفجر، الضحى'),
      findsOneWidget,
    );
    expect(find.textContaining('الوتر'), findsNothing);
    expect(find.textContaining('سنة الظهر البعدية'), findsNothing);
  });

  testWidgets('a day the phone has not synced: five named rows, «0 من 5»',
      (tester) async {
    await openSheet(tester, noor.withUnsyncedPlanInferred(room));
    await tapDay(tester, '28');
    // Every one of the five was asked and none is recorded, so the card can
    // name them (roomDayBreakdown), and the sum line under them reads 0 of 5.
    // Before, it could not: seven asked against five in the plan, so it fell
    // back to «0 من 7 عادات» and a bare «ما أُنجز 7».
    expect(find.text('0 من 5'), findsOneWidget);
    expect(find.textContaining('من 7'), findsNothing);
    for (final name in [
      'أذكار الصباح',
      'سورة الملك',
      'صدقة',
      'سنة الفجر',
      'الضحى',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('الوتر'), findsNothing);
    expect(find.text('سنة الظهر البعدية'), findsNothing);
  });

  testWidgets('the synced day and the removal day are unchanged',
      (tester) async {
    await openSheet(tester, noor.withUnsyncedPlanInferred(room));
    await tapDay(tester, '27');
    expect(find.text('من 5 عادات'), findsOneWidget);
    await tapDay(tester, '26');
    // The removal day itself still counted all seven.
    expect(find.text('من 7 عادات'), findsOneWidget);
  });
}
