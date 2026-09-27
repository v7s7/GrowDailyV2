// The free room limit (Aziz, 2026-09-26: "make it only 3 rooms for free
// users").
//
// A free account can be in kFreeRoomLimit rooms at a time: lobbies, rooms
// counting down, running rooms and open-ended rooms each take a place,
// rooms it leads as much as rooms it joined. A finished room stays on the
// list and frees its place at 10:00 the morning after its last day. Premium
// is uncapped, and an account already past the limit keeps its rooms.
//
// Pinned here: the counting rule itself, the Join sheet (where an invite
// link lands) refusing and allowing at the right counts, the Create sheet's
// submit asking again, the gate's own words, and the paywall opening on the
// rooms row. RoomsHubScreen's Create button is not pumped: that screen asks
// for push permission as it builds, and there is no Firebase here.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/premium/offers/offers_store.dart';
import 'package:grow_daily_v2/features/premium/offers/paywall_offer.dart';
import 'package:grow_daily_v2/features/premium/screens/premium_screen.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/room_limit.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';
import 'package:grow_daily_v2/features/rooms/widgets/create_room_sheet.dart';
import 'package:grow_daily_v2/features/rooms/widgets/join_room_sheet.dart';

import '../../helpers/fake_user.dart';

/// The moment the pure tests are read at: midday, 2026-09-26.
final _now = DateTime(2026, 9, 26, 12);

RoomModel _room(
  String code, {
  String status = 'active',
  DateTime? start,
  DateTime? end,
  RoomDuration duration = RoomDuration.fixed,
}) =>
    RoomModel(
      code: code,
      name: 'Room $code',
      createdBy: 'leader-uid',
      createdByName: 'Leader',
      createdAt: DateTime(2026, 9, 1),
      habitMode: RoomHabitMode.shared,
      duration: duration,
      startDate: start ?? DateTime(2026, 9, 1),
      endDate: end,
      status: status,
    );

// Relative to the real clock, for the widget tests: the screens ask at
// DateTime.now().
RoomModel _running(String code) => _room(
      code,
      start: DateTime.now().subtract(const Duration(days: 3)),
      end: DateTime.now().add(const Duration(days: 10)),
    );
RoomModel _lobby(String code) => _room(code, status: 'lobby');
RoomModel _openEnded(String code) => _room(
      code,
      duration: RoomDuration.open,
      start: DateTime.now().subtract(const Duration(days: 3)),
    );
RoomModel _finished(String code) => _room(
      code,
      start: DateTime.now().subtract(const Duration(days: 40)),
      end: DateTime.now().subtract(const Duration(days: 10)),
    );

/// The real controller, with its two writes swapped for counters: the limit
/// is asked by the screens before either would run, and whether they ran is
/// what these tests watch. [RoomsController.myRooms] and previewRoom are the
/// real ones, reading the overridden room streams and [db].
class _RecordingController extends RoomsController {
  _RecordingController(Ref ref, FirebaseFirestore db)
      : super(ref, firestore: db);

  int joins = 0;
  int creates = 0;

  @override
  Future<bool> joinRoom(
    RoomModel room, {
    List<String> linkedHabitIds = const [],
    List<String> linkedHabitNames = const [],
    List<String?> planResolutions = const [],
  }) async {
    joins++;
    return true;
  }

  @override
  Future<String?> createRoom({
    required String name,
    required RoomHabitMode habitMode,
    List<String> planHabitIds = const [],
    required RoomDuration duration,
    int? lengthDays,
    List<String> leaderLinkedHabitIds = const [],
    List<String> leaderLinkedHabitNames = const [],
    RoomCompeteMode competeMode = RoomCompeteMode.competitive,
  }) async {
    creates++;
    // Null keeps the sheet on its form, the way a failed create does.
    return null;
  }
}

void main() {
  const ar = S(Locale('ar'));

  group('roomsHoldingAPlace', () {
    test('a lobby, a countdown, a running room and an open room all count',
        () {
      final rooms = [
        _room('LOBBY1', status: 'lobby'),
        // Started, first counted day tomorrow.
        _room('SOON01', start: DateTime(2026, 9, 27)),
        _room('RUN001', end: DateTime(2026, 10, 10)),
        _room('OPEN01', duration: RoomDuration.open),
      ];
      expect(roomsHoldingAPlace(rooms, _now), 4);
    });

    test('a finished room stays on the list but holds no place', () {
      final rooms = [
        _room('RUN001', end: DateTime(2026, 10, 10)),
        _room('DONE01', end: DateTime(2026, 9, 20)),
      ];
      expect(roomsHoldingAPlace(rooms, _now), 1);
    });

    test('the last day holds its place until it closes at 10:00', () {
      final endedYesterday = [_room('LAST01', end: DateTime(2026, 9, 25))];
      expect(
        roomsHoldingAPlace(endedYesterday, DateTime(2026, 9, 26, 9, 59)),
        1,
        reason: 'the final day can still be marked, so the room is on',
      );
      expect(roomsHoldingAPlace(endedYesterday, DateTime(2026, 9, 26, 10)), 0);
    });
  });

  group('mayTakeAnotherRoom', () {
    test('a free account may while under $kFreeRoomLimit', () {
      expect(kFreeRoomLimit, 3);
      for (var held = 0; held < kFreeRoomLimit; held++) {
        expect(mayTakeAnotherRoom(held: held, isPremium: false), isTrue,
            reason: 'held $held');
      }
      expect(mayTakeAnotherRoom(held: kFreeRoomLimit, isPremium: false),
          isFalse);
    });

    test('past the limit (Premium ended) is the same no', () {
      expect(mayTakeAnotherRoom(held: 5, isPremium: false), isFalse);
    });

    test('Premium always may', () {
      expect(mayTakeAnotherRoom(held: kFreeRoomLimit, isPremium: true), isTrue);
      expect(mayTakeAnotherRoom(held: 40, isPremium: true), isTrue);
    });
  });

  group('the sheets', () {
    late Directory tmp;

    setUp(() async {
      NotificationService.instance.celebrationsEnabled = false;
      GoogleFonts.config.allowRuntimeFetching = false;
      tmp = await Directory.systemTemp.createTemp('room_limit_test_');
      Hive.init(tmp.path);
      await Hive.openBox<dynamic>('box_settings');
      await Hive.openBox<dynamic>('box_daily_logs');
      await Hive.openBox<dynamic>('box_habits');
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    late _RecordingController controller;

    /// A signed-in account in [mine], free or [premium], with a fake store
    /// that holds [extra] (a room somebody could join).
    Future<void> pump(
      WidgetTester tester, {
      required List<RoomModel> mine,
      required bool premium,
      required Widget home,
      RoomModel? extra,
      bool roomListFails = false,
    }) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = FakeFirebaseFirestore();
      if (extra != null) {
        await db.collection('rooms').doc(extra.code).set(extra.toFirestore());
      }
      final byCode = {for (final r in mine) r.code: r};
      final container = ProviderContainer(overrides: [
        authStateProvider
            .overrideWith((ref) => Stream<User?>.value(fakeUser('me-uid'))),
        myRoomCodesProvider.overrideWith((ref) => roomListFails
            ? Stream<List<String>>.error(StateError('rooms unreadable'))
            : Stream.value([for (final r in mine) r.code])),
        roomProvider.overrideWith(
            (ref, code) => Stream<RoomModel?>.value(byCode[code])),
        premiumAccessProvider.overrideWithValue(premium),
        habitListProvider
            .overrideWithValue(IslamicHabitCatalog.templates.take(3).toList()),
        roomsControllerProvider.overrideWith(
            (ref) => controller = _RecordingController(ref, db)),
      ]);
      addTearDown(container.dispose);
      await container.read(authStateProvider.future);
      if (!roomListFails) await container.read(myRoomCodesProvider.future);
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
          theme: GameTheme.light,
          home: Scaffold(body: home),
        ),
      ));
      // The Join sheet searches its code a frame after it opens.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    /// Opens the Join sheet on an invite for a room this account is not in,
    /// and taps Join once the room's preview is showing.
    Future<void> joinFromInvite(
      WidgetTester tester, {
      required List<RoomModel> mine,
      bool premium = false,
      bool roomListFails = false,
    }) async {
      final target = _running('INVITE');
      await pump(
        tester,
        mine: mine,
        premium: premium,
        extra: target,
        home: JoinRoomSheet(initialCode: target.code),
        roomListFails: roomListFails,
      );
      expect(find.text(target.name), findsOneWidget,
          reason: 'the invite shows which room it is before anything else');
      await tester.tap(find.text(ar.roomJoinSubmit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('three rooms held: Join opens the gate and joins nothing',
        (tester) async {
      await joinFromInvite(tester, mine: [
        _lobby('ROOM01'),
        _openEnded('ROOM02'),
        _running('ROOM03'),
      ]);
      expect(find.text(ar.roomLimitTitle), findsOneWidget);
      expect(find.text(ar.roomLimitBody(kFreeRoomLimit)), findsOneWidget);
      expect(controller.joins, 0);

      // "Maybe later" closes the gate, and the sheet is as it was: Join can
      // be tapped again (no spinner left behind). One frame to start the
      // closing animation, then its length.
      await tester.tap(find.text(ar.guestLimitMaybeLater));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(ar.roomLimitTitle), findsNothing);
      expect(find.text(ar.roomJoinSubmit), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a finished room frees its place: the join goes through',
        (tester) async {
      await joinFromInvite(tester, mine: [
        _running('ROOM01'),
        _running('ROOM02'),
        _finished('DONE01'),
      ]);
      expect(find.text(ar.roomLimitTitle), findsNothing);
      expect(controller.joins, 1);
    });

    testWidgets('two rooms held: the join goes through', (tester) async {
      await joinFromInvite(tester, mine: [
        _running('ROOM01'),
        _lobby('ROOM02'),
      ]);
      expect(find.text(ar.roomLimitTitle), findsNothing);
      expect(controller.joins, 1);
    });

    testWidgets('five rooms kept after Premium ended: still the gate',
        (tester) async {
      await joinFromInvite(tester, mine: [
        for (var i = 1; i <= 5; i++) _running('ROOM0$i'),
      ]);
      expect(find.text(ar.roomLimitTitle), findsOneWidget);
      expect(controller.joins, 0);
    });

    // Not a limit anybody reached, so no Premium pitch, and the Join button,
    // spinning while the rooms are counted, must not be left spinning.
    testWidgets('a room list that fails to load does not lock Join',
        (tester) async {
      await joinFromInvite(tester, mine: const [], roomListFails: true);
      expect(find.text(ar.roomLimitTitle), findsNothing);
      expect(controller.joins, 1);
    });

    testWidgets('Premium joins a fourth room', (tester) async {
      await joinFromInvite(
        tester,
        premium: true,
        mine: [_running('ROOM01'), _running('ROOM02'), _running('ROOM03')],
      );
      expect(find.text(ar.roomLimitTitle), findsNothing);
      expect(controller.joins, 1);
    });

    /// Fills in the Create sheet (name, then one habit) and taps Create.
    Future<void> createFourth(WidgetTester tester, {required bool premium}) async {
      await pump(
        tester,
        mine: [_running('ROOM01'), _running('ROOM02'), _lobby('ROOM03')],
        premium: premium,
        home: const CreateRoomSheet(),
      );
      await tester.enterText(find.byType(TextField).first, 'العائلة');
      await tester.pump();
      await tester.tap(find.text(ar.roomCreateNext));
      await tester.pump();
      await tester
          .tap(find.text(IslamicHabitCatalog.templates.first.localName(true)));
      await tester.pump();
      await tester.tap(find.text(ar.roomCreateSubmit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('three rooms held: Create asks again on submit, form kept',
        (tester) async {
      await createFourth(tester, premium: false);
      expect(find.text(ar.roomLimitTitle), findsOneWidget);
      expect(controller.creates, 0);

      await tester.tap(find.text(ar.guestLimitMaybeLater));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(ar.roomLimitTitle), findsNothing);
      // Still on step two with the habit picked: nothing to fill in again.
      expect(find.text(ar.roomCreateStepHabitsTitle), findsOneWidget);
      expect(find.text(ar.roomPlanSelectedCount(1)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Premium creates a fourth room', (tester) async {
      await createFourth(tester, premium: true);
      expect(find.text(ar.roomLimitTitle), findsNothing);
      expect(controller.creates, 1);
    });
  });

  group('the paywall', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('room_limit_paywall_');
      Hive.init(tmp.path);
      await Hive.openBox<dynamic>('box_settings');
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    Future<void> pumpPaywall(WidgetTester tester, PremiumReason reason) async {
      tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          premiumProvider.overrideWith((ref) => PremiumNotifier(initial: false)),
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
          home: PremiumScreen(
            reason: reason,
            source: 'room_limit',
            offeringLoader: () async => null,
            offersSource: PaywallOffersSource(
              loadConfig: () async => OffersConfig.fallback,
              readWelcomeStart: (_) async => null,
              ensureWelcomeStarted: (now, _) async => now,
            ),
          ),
        ),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    double top(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    testWidgets('the room gate opens the paywall on the rooms row',
        (tester) async {
      await pumpPaywall(tester, PremiumReason.rooms);
      expect(find.text(ar.premiumBenefitRoomsTitle), findsOneWidget);
      expect(
        top(tester, ar.premiumBenefitRoomsTitle),
        lessThan(top(tester, ar.premiumBenefitHabitsTitle)),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('anywhere else, rooms sits second, after habits',
        (tester) async {
      await pumpPaywall(tester, PremiumReason.general);
      final habits = top(tester, ar.premiumBenefitHabitsTitle);
      final rooms = top(tester, ar.premiumBenefitRoomsTitle);
      final history = top(tester, ar.premiumBenefitHistoryTitle);
      expect(habits, lessThan(rooms));
      expect(rooms, lessThan(history));
    });
  });
}
