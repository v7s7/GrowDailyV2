// The plan card's tiles and the room's habit filter on the real
// RoomDetailScreen (Aziz, 2026-09-27, option ب of the design canvas): tap a
// habit tile and every row draws that habit alone, the bar above the rows
// names it, and ✕ or a second tap puts the whole plan back. A long press
// holds what the tap used to do.
//
// Every stream is overridden and the controller records instead of writing,
// so nothing here reaches Firestore. Hive is initialised and never opened
// (see room_dates_arabic_test.dart): whatever reaches for a box waits.
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

class _RecordingController extends RoomsController {
  _RecordingController(super.ref);

  final removed = <int>[];

  @override
  Future<RemoveSharedHabitResult> removeSharedHabit(
    RoomModel room,
    int index,
  ) async {
    removed.add(index);
    return RemoveSharedHabitResult.removed;
  }

  @override
  Future<void> syncLinkedHabitsProgress(
    RoomModel room, {
    Map<String, SquareState>? todaySquares,
    DateTime? liveDay,
    RoomDayReads<DocumentSnapshot<Map<String, dynamic>>>? dayReads,
  }) async {}
}

/// The Grid, never loaded: the plan card only asks it about weekly quotas,
/// and this plan has none.
class _IdleGrid extends WeeklyGridNotifier {
  _IdleGrid(Ref ref) : super(null, ref);
}

IslamicHabitTemplate _habit(String id, String name) => IslamicHabitTemplate(
      id: id,
      name: name,
      description: '',
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
    );

RoomHabitTemplate _slot(
  String name, {
  String? addedDay,
  DateTime? removedAt,
  String? stopsOn,
}) =>
    RoomHabitTemplate(
      name: name,
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      addedDay: addedDay,
      removedAt: removedAt,
      removedBy: removedAt == null ? null : 'leader-uid',
      stopsOn: stopsOn,
    );

final _today = DateTime.now().effectiveDay;
DateTime _ago(int days) =>
    DateTime(_today.year, _today.month, _today.day - days);
String _key(int days) => _ago(days).toDateKey();

/// أذكار الصباح and سورة الملك since the start, الوتر from five days ago
/// until the leader removed it yesterday (so it sits in the gray row).
RoomModel _room() => RoomModel(
      code: 'FILTER',
      name: 'اذكار الصباح',
      createdBy: 'leader-uid',
      createdByName: 'نور',
      createdAt: _ago(10),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: _ago(10),
      endDate: _ago(-20),
      sharedHabits: [
        _slot('أذكار الصباح'),
        _slot('سورة الملك'),
        _slot('الوتر',
            addedDay: _key(5),
            removedAt: _ago(1).add(const Duration(hours: 14)),
            stopsOn: _key(0)),
      ],
    );

/// A member whose per-habit record is [days]: date offset -> one letter per
/// slot ('.' = no mark), with the counts written to agree, as the sync does.
RoomParticipant _person(String uid, String name, Map<int, String> days) {
  final marks = <String, Map<String, RoomHabitMark>>{};
  final done = <String, int>{};
  final scheduled = <String, int>{};
  days.forEach((ago, letters) {
    final m = <String, RoomHabitMark>{};
    for (var i = 0; i < letters.length; i++) {
      final mark = RoomHabitMark.fromCode(letters[i]);
      if (mark != null) m['$uid-h$i'] = mark;
    }
    marks[_key(ago)] = m;
    done[_key(ago)] = m.values.where((x) => x == RoomHabitMark.done).length;
    scheduled[_key(ago)] = m.values.where((x) => x.wasAsked).length;
  });
  return RoomParticipant(
    uid: uid,
    displayName: name,
    characterId: 'male_ghutra_blue',
    joinedAt: _ago(10),
    linkedHabitIds: ['$uid-h0', '$uid-h1', '$uid-h2'],
    linkedHabitNames: const ['أذكار الصباح', 'سورة الملك', 'صلاة الوتر'],
    dailyHabitMarks: marks,
    dailyDoneCount: done,
    dailyScheduledCount: scheduled,
    lastUpdated: _today,
  );
}

// سورة الملك: mine done 3 of the 4 decided days (75%), the leader's 2 of 3
// (67%). Today is open with it unmarked for both, so it is in neither. My
// أذكار الصباح is done today: its tile carries the tick.
final _me = _person('me-uid', 'Aziz', {
  4: 'dd.',
  3: 'dmd',
  2: 'ddd',
  1: 'ddd',
  0: 'dm.',
});
final _leader = _person('leader-uid', 'نور', {
  4: 'dd.',
  3: 'dd.',
  2: 'mmd',
  1: 'd.m',
  0: 'mm.',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    Hive.init((await Directory.systemTemp.createTemp('room_filter_')).path);
  });

  _RecordingController? controller;

  Future<void> pumpRoom(
    WidgetTester tester, {
    String signedIn = 'me-uid',
    bool compact = true,
  }) async {
    tester.view.physicalSize = const Size(402 * 3, 2200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    controller = null;
    final roster = [_me, _leader];
    final mine = signedIn == 'me-uid' ? _me : _leader;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider
            .overrideWith((ref) => Stream<User?>.value(fakeUser(signedIn))),
        roomProvider
            .overrideWith((ref, code) => Stream<RoomModel?>.value(_room())),
        roomParticipantsProvider.overrideWith(
            (ref, code) => Stream<List<RoomParticipant>>.value(roster)),
        roomRosterHistoryProvider.overrideWith(
            (ref, code) => Stream<List<RoomParticipant>>.value(roster)),
        roomsControllerProvider.overrideWith((ref) {
          final c = _RecordingController(ref);
          controller = c;
          return c;
        }),
        habitListProvider.overrideWithValue([
          for (var i = 0; i < 3; i++)
            _habit(mine.linkedHabitIds[i], mine.linkedHabitNames[i]),
        ]),
        pausedHabitsProvider.overrideWithValue(const []),
        weeklyGridProvider.overrideWith((ref) => _IdleGrid(ref)),
        // «آخر 7 أيام» is the default; «كل الأيام» draws the side labels.
        roomRowsCompactProvider.overrideWith((ref) => compact),
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
        home: const RoomDetailScreen(code: 'FILTER'),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  /// The plan card's tile for [name]: the tile's own box, the nearest
  /// Container above its name.
  Finder tile(String name) => find
      .ancestor(of: find.text(name).first, matching: find.byType(Container))
      .first;

  testWidgets('equal tiles, today\'s row, the gray row and the tick',
      (tester) async {
    await pumpRoom(tester);
    expect(find.text('انشالت من الخطة'), findsOneWidget);
    final a = tester.getSize(tile('أذكار الصباح'));
    final b = tester.getSize(tile('سورة الملك'));
    final c = tester.getSize(tile('صلاة الوتر'));
    expect(b, a, reason: 'every tile is the same size');
    expect(c, a, reason: 'the gray one too');
    // One tick: أذكار الصباح, done today. سورة الملك is not; الوتر is gone.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('tap a tile: every row shows that habit, ✕ puts it back',
      (tester) async {
    await pumpRoom(tester);
    expect(find.byTooltip('اعرض كل العادات'), findsNothing);

    await tester.tap(tile('سورة الملك'));
    await settle(tester);
    expect(find.byTooltip('اعرض كل العادات'), findsOneWidget,
        reason: 'the bar above the rows, with its ✕');
    expect(find.text('75%'), findsOneWidget, reason: 'mine: 3 of 4');
    expect(find.text('67%'), findsOneWidget, reason: 'the leader: 2 of 3');
    expect(find.text('3 من 4'), findsOneWidget);

    await tester.tap(find.byTooltip('اعرض كل العادات'));
    await settle(tester);
    expect(find.byTooltip('اعرض كل العادات'), findsNothing);
    expect(find.text('75%'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a second tap on the same tile turns the filter off',
      (tester) async {
    await pumpRoom(tester);
    await tester.tap(tile('سورة الملك'));
    await settle(tester);
    expect(find.byTooltip('اعرض كل العادات'), findsOneWidget);
    await tester.tap(tile('سورة الملك'));
    await settle(tester);
    expect(find.byTooltip('اعرض كل العادات'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a removed habit\'s tile shows its days, ending «آخر يوم»',
      (tester) async {
    await pumpRoom(tester, compact: false);
    await tester.tap(tile('صلاة الوتر'));
    await settle(tester);
    expect(find.byTooltip('اعرض كل العادات'), findsOneWidget);
    expect(find.text('آخر يوم', skipOffstage: false), findsNWidgets(2),
        reason: 'one strip per member, each ending on the last counted day');
    await unmount(tester);
  });

  testWidgets('a member\'s long press opens the change-link sheet straight',
      (tester) async {
    await pumpRoom(tester);
    await tester.longPress(tile('سورة الملك'));
    await settle(tester);
    expect(find.text('غيّر العادة المربوطة'), findsWidgets);
    expect(find.text('إزالة من الخطة'), findsNothing);
    expect(find.byTooltip('اعرض كل العادات'), findsNothing,
        reason: 'a long press is not a filter tap');
    await unmount(tester);
  });

  testWidgets('the leader\'s long press offers both, and remove confirms',
      (tester) async {
    await pumpRoom(tester, signedIn: 'leader-uid');
    await tester.longPress(tile('سورة الملك'));
    await settle(tester);
    expect(find.text('غيّر العادة المربوطة'), findsOneWidget);
    expect(find.text('إزالة من الخطة'), findsOneWidget);
    await tester.tap(find.text('إزالة من الخطة'));
    await settle(tester);
    expect(find.text('إزالة «سورة الملك» من الخطة؟'), findsOneWidget);
    await tester.tap(find.text('إزالة'));
    await settle(tester);
    expect(controller!.removed, [1]);
    await unmount(tester);
  });

  testWidgets('the gray tile has no long-press actions', (tester) async {
    await pumpRoom(tester, signedIn: 'leader-uid');
    await tester.longPress(tile('صلاة الوتر'));
    await settle(tester);
    expect(find.text('إزالة من الخطة'), findsNothing);
    expect(find.text('غيّر العادة المربوطة'), findsNothing);
    await unmount(tester);
  });
}
