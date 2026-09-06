// The "today" card at the top of a competitive room: one row of faces, a
// +N slot past five that opens the full list, and a header that folds the
// card and remembers it. Pumped alone with a fake roster (the room screen
// needs Firestore), in Arabic at phone width.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart'
    show RoomTodayCard;

void main() {
  late Directory tmp;

  // Once per file, not per test: the card's blocked-members notifier loads
  // from Hive asynchronously, and a box deleted and reopened between tests
  // left that load pointing at a closed box, which hung the next test's
  // first real pump.
  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('room_today_card_test');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  final start = DateTime.now().startOfDay.subtract(const Duration(days: 3));
  final room = RoomModel(
    code: 'FACES1',
    name: 'الشلّة',
    createdBy: 'm1',
    createdByName: 'm1',
    createdAt: start,
    habitMode: RoomHabitMode.own,
    duration: RoomDuration.open,
    startDate: start,
    competeMode: RoomCompeteMode.competitive,
  );
  final todayKey = room.lastCountedDay.toDateKey();

  RoomParticipant member(String uid, {bool doneToday = false}) =>
      RoomParticipant(
        uid: uid,
        displayName: uid,
        // No catalog character: the initial renders instead of an image.
        characterId: 'none',
        joinedAt: start,
        lastUpdated: room.lastCountedDay,
        linkedHabitIds: const ['h1'],
        linkedHabitNames: const ['تمرين'],
        dailyDoneCount: {if (doneToday) todayKey: 1},
        dailyScheduledCount: {todayKey: 1},
      );

  Widget app(List<RoomParticipant> members) => ProviderScope(
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
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                RoomTodayCard(
                    room: room, participants: members, mine: members.first),
              ],
            ),
          ),
        ),
      );

  Future<void> pumpCard(WidgetTester tester, List<RoomParticipant> m) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(m));
    await tester.pump();
  }

  testWidgets('a small room shows every face and counts the finished',
      (tester) async {
    await pumpCard(tester, [
      member('m1', doneToday: true),
      member('m2'),
      member('m3'),
    ]);
    // Faces are told apart by the name under each one; mine says أنت.
    expect(find.text('أنت'), findsOneWidget);
    expect(find.text('m2'), findsOneWidget);
    expect(find.text('m3'), findsOneWidget);
    expect(find.text('1 من 3 خلّصوا'), findsOneWidget);
    expect(find.textContaining('+'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('past five, the row keeps four faces and a +N that opens all',
      (tester) async {
    await pumpCard(tester, [for (var i = 1; i <= 7; i++) member('m$i')]);
    expect(find.text('m4'), findsOneWidget, reason: 'the fourth face');
    expect(find.text('m5'), findsNothing, reason: 'the fifth slot is +3');
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('m7'), findsNothing, reason: 'folded into +3');
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('+3'));
    // A fixed pump, not pumpAndSettle: the sheet's slide is finite, and a
    // settle that never ends is the harder failure to read.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('m7'), findsOneWidget, reason: 'listed in the sheet');
    expect(find.text('0 من 7 خلّصوا'), findsNWidgets(2),
        reason: 'card header and sheet header');
  });

  // Persistence itself is room_cards_collapse_test's job: awaiting Hive
  // inside testWidgets hangs the file (see widget-tests-and-Hive notes).
  testWidgets('the header folds the faces away and back', (tester) async {
    await pumpCard(tester, [member('m1'), member('m2')]);
    expect(find.text('m2'), findsOneWidget);

    // Each fold writes its preference to Hive. Run the taps with real
    // async so that write finishes inside the test; left queued under the
    // fake clock it would deadlock the file's teardown.
    await tester.runAsync(() async {
      await tester.tap(find.text('اليوم'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pump();
    expect(find.text('m2'), findsNothing);
    expect(find.text('0 من 2 خلّصوا'), findsOneWidget,
        reason: 'the count stays on the folded header');

    await tester.runAsync(() async {
      await tester.tap(find.text('اليوم'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pump();
    expect(find.text('m2'), findsOneWidget);
  });
}
