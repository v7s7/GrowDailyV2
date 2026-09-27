// A room invite lands on Rooms with the Join sheet open over it.
//
// The reported bug (2026-09-27): main.dart pushed RoomsHubScreen and AWAITED
// the push before showing the Join sheet, and push's Future only completes
// when the pushed route is popped. So an invite opened plain Rooms, and the
// sheet it was for (filled in, see showJoinRoomSheet) came up only once the
// person had backed out of Rooms, over whatever was underneath. Seen on the
// simulator before the fix: growdaily://join/ZZTEST opened «الغرف» with no
// sheet, and the back chevron then raised the sheet over the Grid.
//
// RoomsHubScreen now takes the invite's code (initialJoinCode) and opens the
// sheet over itself, once, after it has landed. Pinned here on the real hub,
// pushed the way main.dart pushes it: the sheet is open over the hub (the
// hub's route beneath it, not popped), filled in and searched; a join still
// opens the room, with Rooms under it; a guest gets the sign-in explanation
// and no sheet; a hub closed before it lands opens nothing; and a hub opened
// without a code opens nothing by itself while its Join button still does.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/push_notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart';
import 'package:grow_daily_v2/features/rooms/screens/rooms_hub_screen.dart';
import 'package:grow_daily_v2/features/rooms/widgets/join_room_sheet.dart';
import 'package:hive/hive.dart';

import '../../helpers/fake_user.dart';

/// The room the invite is for: running, somebody else's. No plan habits, so
/// a join never meets the habit limit.
final _invited = RoomModel(
  code: 'INVITE',
  name: 'غرفة الدعوة',
  createdBy: 'leader-uid',
  createdByName: 'Leader',
  createdAt: DateTime(2026, 9, 20),
  habitMode: RoomHabitMode.shared,
  duration: RoomDuration.fixed,
  startDate: DateTime.now().subtract(const Duration(days: 3)),
  endDate: DateTime.now().add(const Duration(days: 10)),
);

final _leader = RoomParticipant(
  uid: 'leader-uid',
  displayName: 'Leader',
  characterId: 'male_ghutra_blue',
  joinedAt: DateTime(2026, 9, 20),
  lastUpdated: DateTime(2026, 9, 20),
);

/// The real controller, so the sheet's search reads the fake store, with the
/// join swapped for a record of which room was joined: that is all these
/// tests need, and the real one writes to Firestore.
class _JoinRecorder extends RoomsController {
  _JoinRecorder(super.ref, FirebaseFirestore db, this.joined)
      : super(firestore: db);

  final List<String> joined;

  @override
  Future<bool> joinRoom(
    RoomModel room, {
    List<String> linkedHabitIds = const [],
    List<String> linkedHabitNames = const [],
    List<String?> planResolutions = const [],
  }) async {
    joined.add(room.code);
    return true;
  }
}

void main() {
  const ar = S(Locale('ar'));

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Initialised, never opened: the room screen a join opens reaches for
    // boxes, and a load that stalls on the open is harmless where a write
    // from the fake-async zone is not (see room_dates_arabic_test).
    Hive.init((await Directory.systemTemp.createTemp('room_invite_')).path);
    // The hub asks for push permission as it builds, and there is no
    // Firebase here.
    PushNotificationService.instance.requestOverride = () async {};
  });

  tearDown(() {
    PushNotificationService.instance.requestOverride = null;
  });

  late GlobalKey<NavigatorState> navigator;
  late List<String> joined;

  /// A home screen with nothing on it, signed in (or a guest), in no rooms
  /// yet, with [_invited] in the fake store.
  Future<void> pumpApp(WidgetTester tester, {bool guest = false}) async {
    await tester.binding.setSurfaceSize(const Size(402, 874));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    navigator = GlobalKey<NavigatorState>();
    joined = [];
    final db = FakeFirebaseFirestore();
    await db.collection('rooms').doc(_invited.code).set(_invited.toFirestore());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          guestModeProvider.overrideWith((ref) => guest),
          authStateProvider.overrideWith(
            (ref) => Stream<User?>.value(guest ? null : fakeUser('me-uid')),
          ),
          myRoomCodesProvider
              .overrideWith((ref) => Stream.value(const <String>[])),
          myStarredRoomCodesProvider
              .overrideWith((ref) => Stream.value(const <String>[])),
          roomProvider.overrideWith(
            (ref, code) => Stream<RoomModel?>.value(
              code == _invited.code ? _invited : null,
            ),
          ),
          roomParticipantsProvider.overrideWith(
            (ref, code) => Stream<List<RoomParticipant>>.value([_leader]),
          ),
          roomRosterHistoryProvider.overrideWith(
            (ref, code) => Stream<List<RoomParticipant>>.value([_leader]),
          ),
          premiumAccessProvider.overrideWithValue(false),
          habitListProvider.overrideWithValue(
            IslamicHabitCatalog.templates.take(3).toList(),
          ),
          roomsControllerProvider
              .overrideWith((ref) => _JoinRecorder(ref, db, joined)),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.light,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
  }

  /// Pushes [screen] without waiting on the push, as main.dart and the
  /// Profile row do.
  void push(Widget screen) {
    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  /// What main.dart's pendingJoinCodeProvider listener does with an invite.
  void openInvite() => push(RoomsHubScreen(initialJoinCode: _invited.code));

  /// Fixed frames rather than pumpAndSettle, as the other room screen tests
  /// do: a second covers the page sliding in, the sheet rising, the search
  /// and the empty list's fade.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Unmounts everything, so the providers' timers (the day clock's) and
  /// the Join field's cursor are gone before the binding checks for them.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  TextField codeField(WidgetTester tester) => tester.widget<TextField>(
        find.descendant(
          of: find.byType(JoinRoomSheet),
          matching: find.byType(TextField),
        ),
      );

  testWidgets('signed in: Rooms, with the Join sheet open over it, filled in',
      (tester) async {
    await pumpApp(tester);
    openInvite();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Rooms is still sliding in, and the sheet waits for it to land.
    expect(find.byType(RoomsHubScreen), findsOneWidget);
    expect(find.byType(JoinRoomSheet), findsNothing);

    await settle(tester);
    final sheet = find.byType(JoinRoomSheet);
    expect(sheet, findsOneWidget);
    // Over Rooms: the sheet is the top route and the hub is still on the
    // stack beneath it, not popped, which is what the sheet used to wait on.
    final sheetRoute = ModalRoute.of(tester.element(sheet))!;
    final hubRoute =
        ModalRoute.of(tester.element(find.byType(RoomsHubScreen)))!;
    expect(sheetRoute.isCurrent, isTrue);
    expect(hubRoute.isActive, isTrue);
    expect(hubRoute.isCurrent, isFalse);
    expect(find.text(ar.roomsTitle), findsOneWidget);
    // Filled in and already searched: the code, and the room it is for.
    expect(codeField(tester).controller!.text, _invited.code);
    expect(find.text(_invited.name), findsOneWidget);
    expect(find.text(ar.roomJoinSubmit), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('a join opens the room, with Rooms under it', (tester) async {
    await pumpApp(tester);
    openInvite();
    await settle(tester);
    await tester.tap(find.text(ar.roomJoinSubmit));
    await settle(tester);

    expect(joined, [_invited.code]);
    expect(find.byType(JoinRoomSheet), findsNothing);
    expect(
      tester.widget<RoomDetailScreen>(find.byType(RoomDetailScreen)).code,
      _invited.code,
    );

    // Back out of the room: Rooms is where that lands, and the invite's
    // sheet does not come back.
    navigator.currentState!.pop();
    await settle(tester);
    expect(find.byType(RoomDetailScreen), findsNothing);
    expect(find.byType(RoomsHubScreen), findsOneWidget);
    expect(find.byType(JoinRoomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('a guest: the sign-in explanation, and no sheet',
      (tester) async {
    await pumpApp(tester, guest: true);
    openInvite();
    await settle(tester);
    expect(find.byType(RoomsHubScreen), findsOneWidget);
    expect(find.text(ar.roomGuestGateTitle), findsOneWidget);
    expect(find.byType(JoinRoomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('Rooms closed before it lands opens nothing', (tester) async {
    await pumpApp(tester);
    openInvite();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    navigator.currentState!.pop();
    await settle(tester);
    expect(find.byType(RoomsHubScreen), findsNothing);
    expect(find.byType(JoinRoomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('Rooms opened without a code opens no sheet; Join still does',
      (tester) async {
    await pumpApp(tester);
    push(const RoomsHubScreen());
    await settle(tester);
    expect(find.byType(RoomsHubScreen), findsOneWidget);
    expect(find.byType(JoinRoomSheet), findsNothing);

    await tester.tap(find.text(ar.roomJoinAction));
    await settle(tester);
    expect(find.byType(JoinRoomSheet), findsOneWidget);
    expect(codeField(tester).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
