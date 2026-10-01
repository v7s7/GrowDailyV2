// The board draws exactly what it drew, and rebuilds whenever that could
// change it, now that its provider reads are made once in _GridTableState.build
// instead of inside the LayoutBuilder and every square.
//
// Every ref.watch of the board used to run during layout, so each rebuild
// closed and reopened all of them (84 voice selects among them), and the two
// room indexes were watched whole: any snapshot of any of the person's rooms
// or participants hands out a new Map or Set with the same content, and every
// one of those rebuilt all 84 squares. The indexes are now read as one flag
// per row, so the board rebuilds only when a row's trophy or 2x changes.
//
// The one rebuild that must stay is the day boundary. Signed in, the room
// index is re-read at midnight and when yesterday closes at 10:00, and that
// rebuild is what takes yesterday's count off a habit counted several times
// a day. The board now watches the day clock itself when signed in, exactly
// when the index did; a guest's index never read the clock, so a guest's
// board still keeps yesterday's count until something else rebuilds it.
//
// The parity tests here were run green against the board as it was before
// the change. The two "rebuilds no square" pins are the saving: 84 of 84
// squares were rebuilt before.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/notifiers/square_voice_notes.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/grid/screens/grid_screen.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/mascot/sprout_praise.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

import '../../helpers/landing_harness.dart';
import 'board_parity_fixture.dart';

/// A signed-in account, as far as the board asks: only its uid.
// ignore: subtype_of_sealed_class
class _SignedIn implements User {
  @override
  String get uid => 'board-watch-test';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The room indexes as a room or participant snapshot rebuilds them: a new
/// Map or Set on every [tick], holding [ids].
final _linkedSource =
    StateProvider<({int tick, Set<String> ids})>((ref) => (tick: 0, ids: {}));
final _boostedSource =
    StateProvider<({int tick, Set<String> ids})>((ref) => (tick: 0, ids: {}));

bool _isSquareCell(Widget w) => w.runtimeType.toString() == '_SquareCell';

List<Widget> _cells() => find
    .byWidgetPredicate(_isSquareCell, skipOffstage: false)
    .evaluate()
    .map((e) => e.widget)
    .toList();

/// How many of the board's squares are new widgets after [change].
Future<int> _replacedBy(WidgetTester tester, void Function() change) async {
  final before = _cells();
  expect(before, isNotEmpty);
  change();
  await tester.pump();
  final after = _cells();
  expect(after.length, before.length);
  var replaced = 0;
  for (var i = 0; i < before.length; i++) {
    if (!identical(before[i], after[i])) replaced++;
  }
  return replaced;
}

/// Every habit id in the order the boards draw them: Build, then Quit, then
/// Paused, each board's rows top to bottom.
List<String> _boardOrder() => [
      for (final e in find
          .byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_GridTable',
            skipOffstage: false,
          )
          .evaluate())
        for (final habit in (e.widget as dynamic).habits as List)
          (habit as dynamic).id as String,
    ];

/// The square of [habitId] on [day].
dynamic _cellOf(String habitId, DateTime day) {
  final row = _boardOrder().indexOf(habitId);
  final cells = _cells();
  for (var i = row * 7; i < row * 7 + 7; i++) {
    final cell = cells[i] as dynamic;
    if ((cell.day as DateTime).isSameDayAs(day)) return cell;
  }
  throw StateError('no square for $habitId on $day');
}

void main() {
  const en = S(Locale('en'));

  group('room flags', () {
    late LandingHarness h;
    late BoardFixture fixture;

    setUp(() async {
      fixture = BoardFixture(DateTime(2026, 3, 7), now: DateTime.now());
      h = LandingHarness();
      await h.prepare(extraOverrides: [
        habitListProvider.overrideWith((ref) => fixture.habits),
        habitsArchivedTodayProvider.overrideWith((ref) => const []),
        weeklyGridProvider
            .overrideWith((ref) => PinnedGrid(ref, fixture.state())),
        dashboardProvider
            .overrideWith((ref) => PinnedDashboard(fixture.dashboard())),
        myLinkedRoomHabitsProvider.overrideWith((ref) {
          final s = ref.watch(_linkedSource);
          return {for (final id in s.ids) id: <RoomModel>[]};
        }),
        roomBoostedHabitsProvider
            .overrideWith((ref) => {...ref.watch(_boostedSource).ids}),
      ]);
    });
    tearDown(() => h.dispose());

    /// Which rows, in board order, draw the trophy dot and the 2x badge, and
    /// how far above its tile each row keeps Doum clear.
    ({List<bool> trophy, List<bool> boost, List<double> reach}) rows(
        WidgetTester tester) {
      final keepClear = find
          .byWidgetPredicate(
            (w) => w.runtimeType.toString() == 'SproutKeepClear',
            skipOffstage: false,
          )
          .evaluate()
          .toList();
      bool holds(Element row, Finder what) => find
          .descendant(of: find.byElementPredicate((e) => e == row), matching: what)
          .evaluate()
          .isNotEmpty;
      return (
        trophy: [
          for (final r in keepClear)
            holds(r, find.byIcon(Icons.emoji_events_rounded, skipOffstage: false)),
        ],
        boost: [
          for (final r in keepClear)
            holds(r, find.text('2x', skipOffstage: false)),
        ],
        reach: [
          for (final r in keepClear) (r.widget as dynamic).reachAbove as double,
        ],
      );
    }

    testWidgets('a flag set on one habit is drawn on exactly its row',
        (tester) async {
      await h.pumpApp(tester);
      final order = _boardOrder();
      final none = rows(tester);
      expect(none.trophy, everyElement(false));
      expect(none.boost, everyElement(false));
      expect(none.reach, everyElement(0.0));

      h.container.read(_linkedSource.notifier).state =
          (tick: 1, ids: {'h_quota'});
      h.container.read(_boostedSource.notifier).state =
          (tick: 1, ids: {'h_quota'});
      await tester.pump();
      final one = rows(tester);
      final expected = [for (final id in order) id == 'h_quota'];
      expect(one.trophy, expected);
      expect(one.boost, expected);
      expect(one.reach, [for (final e in expected) e ? 9.0 : 0.0]);

      // A paused habit (the Paused board) draws its pause tile whatever the
      // rooms say, and a quit one draws the flags like any other.
      h.container.read(_linkedSource.notifier).state =
          (tick: 2, ids: {'h_quit', 'h_archived'});
      h.container.read(_boostedSource.notifier).state =
          (tick: 2, ids: {'h_quit', 'h_archived'});
      await tester.pump();
      final quit = rows(tester);
      expect(quit.trophy.where((t) => t).length, 1);
      expect(quit.boost.where((t) => t).length, 1);
      expect(quit.reach.where((r) => r == 9).length, 1);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets(
        'the same flags handed out again rebuild no square '
        '(every Build and Quit square did)',
        (tester) async {
      h.container.read(_linkedSource.notifier).state =
          (tick: 0, ids: {'h_daily'});
      await h.pumpApp(tester);
      expect(
        await _replacedBy(tester, () {
          h.container.read(_linkedSource.notifier).state =
              (tick: 1, ids: {'h_daily'});
          h.container.read(_boostedSource.notifier).state =
              (tick: 1, ids: const {});
        }),
        0,
      );
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a recording marks its own square, and one from another week '
        'rebuilds nothing', (tester) async {
      await h.pumpApp(tester);
      final days = fixture.days;
      bool marked(Widget c) => (c as dynamic).hasNote as bool;
      final before = [for (final c in _cells()) marked(c)];

      final voice = h.container.read(squareVoiceIndexProvider.notifier);
      expect(
        await _replacedBy(tester, () {
          voice.setCount(squareVoiceKey('h_daily', DateTime(2026, 1, 3)), 1);
        }),
        0,
      );

      await _replacedBy(tester, () {
        voice.setCount(squareVoiceKey('h_monthu', days[5]), 1);
      });
      final after = [for (final c in _cells()) marked(c)];
      final target = _cells().indexOf(_cellOf('h_monthu', days[5]) as Widget);
      for (var i = 0; i < after.length; i++) {
        expect(after[i], i == target ? true : before[i], reason: 'square $i');
      }
      expect(
        (_cellOf('h_monthu', days[5]).semanticLabel as String)
            .endsWith(en.gridNoteSemantics),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('a guest', () {
    late LandingHarness h;

    setUp(() async {
      final fixture = BoardFixture(DateTime(2026, 3, 7), now: DateTime.now());
      h = LandingHarness();
      await h.prepare(extraOverrides: [
        habitListProvider.overrideWith((ref) => fixture.habits),
        habitsArchivedTodayProvider.overrideWith((ref) => const []),
        weeklyGridProvider
            .overrideWith((ref) => PinnedGrid(ref, fixture.state())),
        dashboardProvider
            .overrideWith((ref) => PinnedDashboard(fixture.dashboard())),
      ]);
    });
    tearDown(() => h.dispose());

    testWidgets('room indexes read again rebuild no square', (tester) async {
      await h.pumpApp(tester);
      // The guest index is the one const map, so no watcher is ever told.
      expect(
        await _replacedBy(tester, () {
          h.container.invalidate(myLinkedRoomHabitsProvider);
          h.container.invalidate(roomBoostedHabitsProvider);
        }),
        0,
      );
      await tester.pump(const Duration(seconds: 2));
    });
  });

  // Yesterday's count on a habit counted three times a day, drawn while
  // yesterday is open and gone once it closes at 10:00.
  group('yesterday closing at 10:00', () {
    final realToday = DateTime.now();
    final yesterday =
        DateTime(realToday.year, realToday.month, realToday.day - 1);
    late DateTime clockNow;
    DateTime clock() => clockNow;
    late BoardFixture fixture;

    List<Override> boardOverrides() => [
          habitListProvider.overrideWith((ref) => fixture.habits),
          habitsArchivedTodayProvider.overrideWith((ref) => const []),
          weeklyGridProvider
              .overrideWith((ref) => PinnedGrid(ref, fixture.state())),
          dashboardProvider
              .overrideWith((ref) => PinnedDashboard(fixture.dashboard())),
          dayClockSourceProvider.overrideWithValue(clock),
        ];

    setUp(() {
      clockNow = DateTime(realToday.year, realToday.month, realToday.day, 2, 18);
      fixture = BoardFixture(startOfGridWeek(yesterday), now: realToday);
    });

    /// Yesterday's square of the counted habit: its count, and whether its
    /// spoken label still says it.
    ({String? count, bool spoken}) yesterdaysCount() {
      final cell = _cellOf('h_counted', yesterday);
      final count = cell.dayCount;
      return (
        count: count == null ? null : '${count.done}/${count.target}',
        spoken: (cell.semanticLabel as String)
            .contains(en.timesPerDayProgress(1, 3)),
      );
    }

    /// Moves the clock past 10:00 and re-reads the day clock, as its own
    /// timer does. In the real zone, so the timer it arms for the next
    /// boundary is a real one that the container's dispose cancels.
    Future<void> closeYesterday(
        WidgetTester tester, ProviderContainer container) async {
      clockNow = DateTime(realToday.year, realToday.month, realToday.day, 10, 30);
      await tester.runAsync(() async {
        container.invalidate(dayClockProvider);
        container.read(dayClockProvider);
      });
      await tester.pump();
    }

    group('signed in', () {
      late ProviderContainer container;
      late Directory tmp;

      setUp(() async {
        NotificationService.instance.celebrationsEnabled = false;
        GoogleFonts.config.allowRuntimeFetching = false;
        PraisePicker.persist = false;
        final view =
            TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
        view.physicalSize = LandingHarness.surface * view.devicePixelRatio;
        tmp = await Directory.systemTemp.createTemp('board_watch_test_');
        Hive.init(tmp.path);
        await Hive.openBox<dynamic>('box_settings');
        await Hive.openBox<dynamic>('box_daily_logs');
        await Hive.openBox<dynamic>('box_habits');
        container = ProviderContainer(overrides: [
          authStateProvider
              .overrideWith((ref) => Stream<User?>.value(_SignedIn())),
          myRoomCodesProvider
              .overrideWith((ref) => Stream.value(const <String>[])),
          // The recordings index reads the account's document when signed
          // in; the guest store answers the same for a board with none.
          squareVoiceIndexProvider.overrideWith(
            (ref) => SquareVoiceIndexNotifier(SquareVoiceStore(), null),
          ),
          ...boardOverrides(),
        ]);
        await container.read(authStateProvider.future);
        await container.read(myRoomCodesProvider.future);
        container.read(dayClockProvider);
      });
      tearDown(() {
        container.dispose();
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!
            .resetPhysicalSize();
      });

      testWidgets('the count leaves yesterday\'s square at 10:00',
          (tester) async {
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: GameTheme.light,
            home: const GridScreen(),
          ),
        ));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(yesterdaysCount(), (count: '1/3', spoken: true));
        await closeYesterday(tester, container);
        expect(yesterdaysCount(), (count: null, spoken: false));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
      });
    });

    group('a guest', () {
      late LandingHarness h;

      setUp(() async {
        h = LandingHarness();
        await h.prepare(extraOverrides: boardOverrides());
      });
      tearDown(() => h.dispose());

      testWidgets('keeps yesterday\'s count until something else rebuilds',
          (tester) async {
        await h.pumpApp(tester);
        expect(yesterdaysCount(), (count: '1/3', spoken: true));
        await closeYesterday(tester, h.container);
        expect(yesterdaysCount(), (count: '1/3', spoken: true));
        // The next rebuild takes it off, as it always has.
        (h.container.read(weeklyGridProvider.notifier) as PinnedGrid)
            .repin(fixture.state());
        await tester.pump();
        expect(yesterdaysCount(), (count: null, spoken: false));
        await tester.pump(const Duration(seconds: 2));
      });
    });
  });
}
