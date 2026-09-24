// The "New habit in the plan" sheet, opened the way the room opens it, with
// the room and the habit list from Aziz's screenshot of 2026-09-24: what
// each row's dropdown shows before he touches anything.
//
// Before habit_name_match.dart, «الضحى» and «الوتر» came up as "Add as new"
// although «صلاة الضحى» and «صلاة الوتر» were right there. The matching
// rules have their own tests (habit_name_match_test.dart); this one holds
// the sheet to actually using them, one habit per row.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/widgets/resolve_new_shared_habits_sheet.dart';

import 'room_sync_harness.dart';

/// Opens the sheet the way the room does, over [container].
Future<void> _openSheet(
  WidgetTester tester,
  ProviderContainer container,
  RoomModel room,
  RoomParticipant me,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showResolveNewHabitsSheet(context, room: room, mine: me),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

IslamicHabitTemplate _habit(String name) => IslamicHabitTemplate(
      id: 'h_$name',
      name: name,
      description: '',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    );

RoomHabitTemplate _slot(String name) => RoomHabitTemplate(
      name: name,
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
    );

void main() {
  setUpAll(initHarnessHive);

  final mine = [
    _habit('سنة الفجر'),
    _habit('أذكار الصباح'),
    _habit('صلاة الضحى'),
    _habit('الصدقة ولو بالقليل'),
    _habit('قراءة القرآن'),
    _habit('تنعيم اللحية'),
    _habit('اخذ كرياتين'),
    _habit('تمرين'),
    _habit('صلاة الوتر'),
    _habit('شامبو ضد القشرة'),
    _habit('سورة الملك'),
  ];

  final room = RoomModel(
    code: 'TEST42',
    name: 'Room',
    createdBy: 'leader-uid',
    createdByName: 'Leader',
    createdAt: DateTime(2026, 9),
    habitMode: RoomHabitMode.shared,
    duration: RoomDuration.fixed,
    startDate: DateTime(2026, 9),
    endDate: DateTime(2026, 12, 31),
    sharedHabits: [
      _slot('سنة الظهر البعدية'),
      _slot('سنة الفجر'),
      _slot('الضحى'),
      _slot('الوتر'),
    ],
  );

  final me = RoomParticipant(
    uid: 'me-uid',
    displayName: 'Aziz',
    characterId: 'male_ghutra_blue',
    joinedAt: DateTime(2026, 9, 2),
    lastUpdated: DateTime(2026, 9, 20),
  );

  testWidgets('each new plan habit opens on the habit it is, or on "add as new"',
      (tester) async {
    final container = ProviderContainer(
      overrides: [habitListProvider.overrideWithValue(mine)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      showResolveNewHabitsSheet(context, room: room, mine: me),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final rows = tester
        .widgetList<DropdownButton<String?>>(find.byType(DropdownButton<String?>))
        .map((d) => d.value)
        .toList();
    expect(rows, [
      null, // سنة الظهر البعدية: nothing like it, so "add as new"
      'h_سنة الفجر',
      'h_صلاة الضحى',
      'h_صلاة الوتر',
    ]);
    // What he reads on the closed dropdowns.
    expect(find.text('ربط: صلاة الضحى'), findsOneWidget);
    expect(find.text('ربط: صلاة الوتر'), findsOneWidget);
    expect(find.text('ربط: سنة الفجر'), findsOneWidget);
  });

  testWidgets('a habit another slot held is neither pre-selected nor offered',
      (tester) async {
    // «تمرين» filled the «الضحى» slot by mistake until the 10th, when it was
    // changed to «صلاة الضحى» (RoomsController.relinkPlanHabit). Then the
    // leader added «تمرين» to the plan. The room grades a habit through one
    // slot, so resolvePlanHabit refuses it for the new one: the sheet opened
    // on it anyway, and saving then linked nothing.
    final grown = RoomModel(
      code: 'TEST43',
      name: 'Room',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 9),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 9),
      endDate: DateTime(2026, 12, 31),
      sharedHabits: [_slot('الضحى'), _slot('تمرين')],
    );
    final relinked = RoomParticipant(
      uid: 'me-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 9, 2),
      linkedHabitIds: const ['h_صلاة الضحى'],
      linkedHabitNames: const ['صلاة الضحى'],
      lastUpdated: DateTime(2026, 9, 20),
      slotHabitHistory: const {
        0: [(habitId: 'h_تمرين', until: '2026-09-10')],
      },
    );
    final container = ProviderContainer(
      overrides: [habitListProvider.overrideWithValue(mine)],
    );
    addTearDown(container.dispose);
    await _openSheet(tester, container, grown, relinked);

    final row = tester.widget<DropdownButton<String?>>(
        find.byType(DropdownButton<String?>));
    expect(row.value, isNull);
    expect(row.items!.map((i) => i.value), isNot(contains('h_تمرين')));
    expect(row.items!.map((i) => i.value), isNot(contains('h_صلاة الضحى')));
  });

  testWidgets('a save the room refuses says so instead of closing as if it '
      'saved', (tester) async {
    final room = RoomModel(
      code: 'TEST44',
      name: 'Room',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 9),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 9),
      endDate: DateTime(2026, 12, 31),
      sharedHabits: [_slot('الضحى'), _slot('قراءة القرآن'), _slot('الوتر')],
    );
    final h = RoomSyncHarness(
      room: room,
      uid: 'me-uid',
      habits: [_habit('صلاة الضحى'), _habit('قراءة القرآن'), _habit('صلاة الوتر')],
    );
    addTearDown(h.dispose);
    // On the server «قراءة القرآن» is linked already, from another phone.
    await tester.runAsync(() async {
      await h.createRoom();
      await h.join(RoomParticipant(
        uid: 'me-uid',
        displayName: 'Aziz',
        characterId: 'male_ghutra_blue',
        joinedAt: DateTime(2026, 9, 2),
        linkedHabitIds: const ['h_صلاة الضحى', 'h_قراءة القرآن'],
        linkedHabitNames: const ['صلاة الضحى', 'قراءة القرآن'],
        lastUpdated: DateTime(2026, 9, 20),
      ));
    });
    // This phone still has the member from before that.
    final stale = RoomParticipant(
      uid: 'me-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 9, 2),
      linkedHabitIds: const ['h_صلاة الضحى'],
      linkedHabitNames: const ['صلاة الضحى'],
      lastUpdated: DateTime(2026, 9, 20),
    );
    await _openSheet(tester, h.container, room, stale);
    await tester.tap(find.byType(FilledButton));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    final s = S.of(tester.element(find.byType(Scaffold).first));
    expect(find.text(s.roomRelinkFailed), findsOneWidget);
    // And it stopped there, rather than link the rows after it out of line.
    final after = await tester.runAsync(h.member);
    expect(after!.linkedHabitIds, ['h_صلاة الضحى', 'h_قراءة القرآن']);
  });
}
