// An ENDED room asks nothing of today, and its screen says so (the room
// body's RoomTodayCard gate and _MyPlanCard's headline).
//
// Found on the simulator 2026-09-27 in ZCNGFT «صلاة الأوابين», over since 12
// August: under its own finale it still drew «اليوم · 0 من 2 خلّصوا», the
// room's last day under the word today, and a plan card headed «لم يُنجز بعد
// اليوم» about a day the room will never count. The team card already
// dropped its today line after the end; the competitive room now does the
// same, and its plan card reads «انتهت».
//
// Every stream is overridden and the controller records instead of writing,
// so nothing here reaches Firestore (the harness of
// room_habit_filter_widget_test.dart).
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show DocumentSnapshot;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/providers/room_rows_view_provider.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/room_day_reads.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart';

import '../../helpers/fake_user.dart';

class _QuietController extends RoomsController {
  _QuietController(super.ref);

  @override
  Future<void> syncLinkedHabitsProgress(
    RoomModel room, {
    Map<String, SquareState>? todaySquares,
    DateTime? liveDay,
    RoomDayReads<DocumentSnapshot<Map<String, dynamic>>>? dayReads,
  }) async {}
}

class _IdleGrid extends WeeklyGridNotifier {
  _IdleGrid(Ref ref) : super(null, ref);
}

final _today = DateTime.now().effectiveDay;
DateTime _ago(int days) =>
    DateTime(_today.year, _today.month, _today.day - days);

RoomModel _room({required DateTime end}) => RoomModel(
      code: 'ENDED1',
      name: 'صلاة الأوابين',
      createdBy: 'leader-uid',
      createdByName: 'mohdabood',
      createdAt: _ago(40),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: _ago(40),
      endDate: end,
      sharedHabits: const [
        RoomHabitTemplate(
          name: 'صلاة الضحى',
          category: HabitCategory.faith,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
        ),
      ],
    );

RoomParticipant _person(String uid, String name) => RoomParticipant(
      uid: uid,
      displayName: name,
      characterId: 'male_ghutra_blue',
      joinedAt: _ago(40),
      linkedHabitIds: ['$uid-duha'],
      linkedHabitNames: const ['صلاة الضحى'],
      dailyDoneCount: {_ago(35).toDateKey(): 1},
      lastUpdated: _today,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    Hive.init((await Directory.systemTemp.createTemp('room_ended_')).path);
  });

  Future<void> pumpRoom(WidgetTester tester, RoomModel room) async {
    tester.view.physicalSize = const Size(402 * 3, 2200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final roster = [_person('me-uid', 'Aziz'), _person('leader-uid', 'mohd')];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider
            .overrideWith((ref) => Stream<User?>.value(fakeUser('me-uid'))),
        roomProvider
            .overrideWith((ref, code) => Stream<RoomModel?>.value(room)),
        roomParticipantsProvider.overrideWith(
            (ref, code) => Stream<List<RoomParticipant>>.value(roster)),
        roomRosterHistoryProvider.overrideWith(
            (ref, code) => Stream<List<RoomParticipant>>.value(roster)),
        roomsControllerProvider.overrideWith((ref) => _QuietController(ref)),
        habitListProvider.overrideWithValue([
          IslamicHabitTemplate(
            id: 'me-uid-duha',
            name: 'صلاة الضحى',
            description: '',
            category: HabitCategory.faith,
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
            hasTimer: false,
            xpReward: 10,
            goldReward: 5,
          ),
        ]),
        pausedHabitsProvider.overrideWithValue(const []),
        weeklyGridProvider.overrideWith((ref) => _IdleGrid(ref)),
        roomRowsCompactProvider.overrideWith((ref) => true),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: const RoomDetailScreen(code: 'ENDED1'),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a live room asks about today', (tester) async {
    await pumpRoom(tester, _room(end: _ago(-10)));
    expect(find.byType(RoomTodayCard), findsOneWidget);
    expect(find.text('لم يُنجز بعد اليوم'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('an ended room does not: no today card, and the plan card '
      'says it ended', (tester) async {
    final room = _room(end: _ago(10));
    expect(room.isEnded, isTrue);
    await pumpRoom(tester, room);
    expect(find.byType(RoomTodayCard), findsNothing);
    expect(find.text('لم يُنجز بعد اليوم'), findsNothing);
    // The header's own pill says it too; the plan card is the second.
    expect(find.text('انتهت'), findsNWidgets(2));
    await unmount(tester);
  });
}
