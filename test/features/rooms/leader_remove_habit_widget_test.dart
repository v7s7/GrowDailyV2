// The leader's «إزالة عادة» flow on the real RoomDetailScreen, and the
// member's popup on open (Aziz, 2026-09-22: "make it a pop up when they
// open, no need for notification and extra cost").
//
// The screen is pumped with every stream overridden and a controller that
// records instead of writing, so nothing here reaches Firestore. The leader
// has no linked habits, which keeps the screen's own resync from running
// (see _RoomDetailScreenState._syncIfNeeded); the menu does not depend on it.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/room_day_reads.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/room_plan_notices.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart';
import 'package:grow_daily_v2/features/rooms/widgets/room_finale_announcer.dart';
import 'package:cloud_firestore/cloud_firestore.dart'
    show DocumentSnapshot;

import '../../helpers/fake_user.dart';

class _RecordingController extends RoomsController {
  _RecordingController(super.ref);

  final removed = <int>[];
  final restored = <(int, bool)>[];
  RemoveSharedHabitResult answer = RemoveSharedHabitResult.removed;

  @override
  Future<RemoveSharedHabitResult> removeSharedHabit(
    RoomModel room,
    int index,
  ) async {
    removed.add(index);
    return answer;
  }

  @override
  Future<bool> restoreSharedHabit(
    RoomModel room,
    int index, {
    bool undo = false,
  }) async {
    restored.add((index, undo));
    return true;
  }

  @override
  Future<void> syncLinkedHabitsProgress(
    RoomModel room, {
    Map<String, SquareState>? todaySquares,
    DateTime? liveDay,
    RoomDayReads<DocumentSnapshot<Map<String, dynamic>>>? dayReads,
  }) async {}
}

RoomHabitTemplate _slot(String name) => RoomHabitTemplate(
      name: name,
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
    );

RoomModel _room({
  required List<RoomHabitTemplate> slots,
  DateTime? end,
}) {
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day - 10);
  return RoomModel(
    code: 'REMOVE',
    name: 'غرفة الخطة',
    createdBy: 'leader-uid',
    createdByName: 'Leader',
    createdAt: start,
    habitMode: RoomHabitMode.shared,
    duration: RoomDuration.fixed,
    startDate: start,
    endDate: end ?? DateTime(today.year, today.month, today.day + 20),
    sharedHabits: slots,
  );
}

RoomParticipant _person(String uid) => RoomParticipant(
      uid: uid,
      displayName: uid,
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 1, 1),
      linkedHabitIds: const [],
      lastUpdated: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    Hive.init((await Directory.systemTemp.createTemp('room_remove_')).path);
    // Opened here, outside the fake-async zone: see
    // widget-tests-hive-fake-async in the project notes.
    await LocalStoreService.settingsBox();
  });

  tearDown(() async {
    await Hive.close();
  });

  // Null until something on the screen asks for the controller, and reset
  // for every pump: a test whose flow never reaches it must not read the
  // previous test's recorder.
  _RecordingController? controller;
  List<int> removedCalls() => controller?.removed ?? const [];

  Future<void> pumpRoom(
    WidgetTester tester,
    RoomModel room, {
    String signedIn = 'leader-uid',
  }) async {
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    controller = null;
    final roster = [_person('leader-uid'), _person('member-uid')];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider
            .overrideWith((ref) => Stream<User?>.value(fakeUser(signedIn))),
        roomProvider.overrideWith((ref, code) => Stream<RoomModel?>.value(room)),
        roomParticipantsProvider.overrideWith(
            (ref, code) => Stream<List<RoomParticipant>>.value(roster)),
        roomRosterHistoryProvider.overrideWith(
            (ref, code) => Stream<List<RoomParticipant>>.value(roster)),
        roomsControllerProvider.overrideWith((ref) {
          final c = _RecordingController(ref);
          controller = c;
          return c;
        }),
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
        home: const RoomDetailScreen(code: 'REMOVE'),
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

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the leader removes تمرين: list, confirm, undo', (tester) async {
    await pumpRoom(
      tester,
      _room(slots: [_slot('قراءة القرآن'), _slot('تمرين')]),
    );
    await openMenu(tester);
    expect(find.text('إضافة عادة'), findsOneWidget);
    await tester.tap(find.text('إزالة عادة'));
    await settle(tester);

    // The list: both habits still in the plan, with their cadence.
    expect(find.text('إزالة عادة من الخطة'), findsOneWidget);
    expect(find.text('قراءة القرآن'), findsWidgets);
    await tester.tap(find.text('تمرين').last);
    await settle(tester);

    // The confirm says exactly what happens.
    expect(find.text('إزالة «تمرين» من الخطة؟'), findsOneWidget);
    expect(
      find.text(
        'تبقى محسوبة اليوم، ومن باجر ما تنحسب لأحد في الغرفة. الأيام اللي قبل '
        'تبقى مثل ما هي، والعادة تبقى في عادات كل واحد بس ما تنربط بالغرفة.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('إزالة'));
    await settle(tester);
    expect(removedCalls(), [1]);

    // The undo bar.
    expect(find.text('انشالت «تمرين» من الخطة'), findsOneWidget);
    await tester.tap(find.text('تراجع'));
    await settle(tester);
    expect(controller!.restored, [(1, true)]);
    await unmount(tester);
  });

  testWidgets('a plan down to one habit says so before anything opens',
      (tester) async {
    await pumpRoom(tester, _room(slots: [_slot('قراءة القرآن')]));
    await openMenu(tester);
    await tester.tap(find.text('إزالة عادة'));
    await settle(tester);
    expect(find.text('آخر عادة في الخطة'), findsOneWidget);
    expect(find.text('إزالة عادة من الخطة'), findsNothing);
    expect(removedCalls(), isEmpty);
    await unmount(tester);
  });

  testWidgets('cancel removes nothing', (tester) async {
    await pumpRoom(
      tester,
      _room(slots: [_slot('قراءة القرآن'), _slot('تمرين')]),
    );
    await openMenu(tester);
    await tester.tap(find.text('إزالة عادة'));
    await settle(tester);
    await tester.tap(find.text('تمرين').last);
    await settle(tester);
    await tester.tap(find.text('إلغاء'));
    await settle(tester);
    expect(removedCalls(), isEmpty);
    await unmount(tester);
  });

  testWidgets('a member does not see it', (tester) async {
    await pumpRoom(
      tester,
      _room(slots: [_slot('قراءة القرآن'), _slot('تمرين')]),
      signedIn: 'member-uid',
    );
    await openMenu(tester);
    expect(find.text('إزالة عادة'), findsNothing);
    expect(find.text('إضافة عادة'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a finished room offers no plan edits', (tester) async {
    final today = DateTime.now();
    await pumpRoom(
      tester,
      _room(
        slots: [_slot('قراءة القرآن'), _slot('تمرين')],
        end: DateTime(today.year, today.month, today.day - 3),
      ),
    );
    await openMenu(tester);
    expect(find.text('إزالة عادة'), findsNothing);
    expect(find.text('إضافة عادة'), findsNothing);
    await unmount(tester);
  });

  group('the member popup', () {
    RoomPlanNotice notice({bool countsToday = true, bool hadLinked = true}) {
      final now = DateTime.now();
      final room = _room(slots: [
        _slot('قراءة القرآن'),
        RoomHabitTemplate(
          name: 'تمرين',
          category: HabitCategory.faith,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
          removedAt: now.subtract(const Duration(hours: 1)),
          removedBy: 'leader-uid',
          stopsOn: 'x',
        ),
      ]);
      return RoomPlanNotice(
        room: room,
        slot: 1,
        kind: RoomPlanNoticeKind.removed,
        hadLinked: hadLinked,
        countsToday: countsToday,
      );
    }

    late ProviderContainer container;

    Future<void> pumpAnnouncer(
      WidgetTester tester,
      List<RoomPlanNotice> notices, {
      Set<String> seen = const {},
    }) async {
      container = ProviderContainer(overrides: [
        unseenFinishedRoomsProvider.overrideWithValue(const []),
        roomPlanNoticesProvider.overrideWithValue(notices),
        roomPlanNoticesSeenProvider.overrideWith((ref) => seen),
        // The seen record is asserted in memory; the disk write is the one
        // thing a widget test must not start (see the writer provider).
        roomPlanNoticeWriterProvider.overrideWithValue((key) async {}),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
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
          home: const RoomFinaleAnnouncer(child: Scaffold()),
        ),
      ));
      await settle(tester);
    }

    testWidgets('on the removal day: counts today, habit stays yours, once',
        (tester) async {
      final n = notice();
      await pumpAnnouncer(tester, [n]);
      expect(find.text('تغيير في خطة الغرفة'), findsOneWidget);
      expect(
        find.text(
          'شال القائد «تمرين» من خطة «غرفة الخطة». بتنحسب اليوم آخر يوم، '
          'بس باجر لا.\n\nأيامك اللي قبل محفوظة، والعادة تبقى في عاداتك بس '
          'غير مرتبطة بالغرفة.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('تمام'));
      await settle(tester);
      expect(find.text('تغيير في خطة الغرفة'), findsNothing);
      // Recorded, so the next open says nothing.
      expect(container.read(roomPlanNoticesSeenProvider), contains(n.key));

      await tester.pumpWidget(const SizedBox());
      await pumpAnnouncer(tester, [n], seen: {n.key});
      expect(find.text('تغيير في خطة الغرفة'), findsNothing);
    });

    testWidgets('a later day, and a member who never linked it',
        (tester) async {
      await pumpAnnouncer(
          tester, [notice(countsToday: false, hadLinked: false)]);
      expect(
        find.text(
          'شال القائد «تمرين» من خطة «غرفة الخطة»، وما صارت تنحسب في الغرفة.'
          '\n\nأيامك اللي قبل محفوظة.',
        ),
        findsOneWidget,
      );
    });
  });
}
