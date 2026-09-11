// The Monthly Heatmap, for a day still open.
//
// Aziz, 2026-09-11: a day that has not finished, and whose extra hours have
// not run out, is not a missed day. The heatmap painted a blank today, and a
// blank yesterday before 10:00, with the same empty plate a day that closed
// on nothing gets, and the day sheet behind the cell labelled every blank
// habit «لم يكتمل». The cell now draws quiet until the day closes, and the
// sheet says «مطلوب», the word the report's and the Progress tab's own day
// sheets already use for a habit still due.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/grid/screens/monthly_heatmap_screen.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

class _Premium extends PremiumNotifier {
  _Premium() {
    state = false;
  }
}

/// Loaded, with nothing live for today: the fixture marks nothing on the
/// clock's own day.
class _LoadedDash extends DashboardNotifier {
  _LoadedDash() : super(null) {
    state = const DashboardState(
      level: 1,
      currentLevelXp: 0,
      cumulativeXp: 0,
      gold: 0,
      streak: 0,
      completions: {},
    );
  }
}

/// The Grid with a week already on it. The real notifier loads the wall
/// clock's week from the store; this one keeps [fixed] whatever that load
/// writes, so a test can say what the live board shows for today.
class _LiveGrid extends WeeklyGridNotifier {
  _LiveGrid(Ref ref, this.fixed) : super(null, ref) {
    super.state = fixed;
  }

  final WeeklyGridState fixed;

  @override
  set state(WeeklyGridState value) => super.state = fixed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dayFill', () {
    test('an open day with nothing done draws like a day that owed nothing',
        () {
      expect(dayFill(0, 3, settled: false), dayFill(0, 0));
      expect(dayFill(0, 3, settled: false), isNot(dayFill(0, 3)),
          reason: 'not the empty plate of a day that closed on nothing');
    });

    test('what is done on an open day still shows as it is', () {
      expect(dayFill(1, 3, settled: false), dayFill(1, 3));
      expect(dayFill(3, 3, settled: false), dayFill(3, 3));
    });
  });

  group('heatmapFailedOpenDays', () {
    // A فشل settles its day at once everywhere else, so the cell of an open
    // day holding one is judged at once too.
    final fri0519 = DateTime(2026, 9, 11, 5, 19);
    final fri1000 = DateTime(2026, 9, 11, kDayCutoffHour);
    String key(int day) => DateTime(2026, 9, day).toDateKey();
    final mirror = <String, Map<String, SquareState>>{
      'a': {key(9): SquareState.failed, key(10): SquareState.failed},
      'b': {key(11): SquareState.failed},
    };

    test('only a فشل, only on a day still open, only for a known habit', () {
      expect(
        heatmapFailedOpenDays(
          mirror: mirror,
          habitIds: const ['a', 'b'],
          now: fri0519,
        ),
        {key(10), key(11)},
        reason: 'the 9th has closed, and a closed day is settled anyway',
      );
      expect(
        heatmapFailedOpenDays(
          mirror: mirror,
          habitIds: const ['a', 'b'],
          now: fri1000,
        ),
        {key(11)},
      );
      expect(
        heatmapFailedOpenDays(
          mirror: mirror,
          habitIds: const ['a'],
          now: fri0519,
        ),
        {key(10)},
      );
      expect(
        heatmapFailedOpenDays(
          mirror: {
            'a': {key(11): SquareState.partial},
          },
          habitIds: const ['a'],
          now: fri0519,
        ),
        isEmpty,
        reason: 'a جزئي on an open day still waits',
      );
    });

    test("today's live square wins over the mirror", () {
      expect(
        heatmapFailedOpenDays(
          mirror: mirror,
          habitIds: const ['a', 'b'],
          now: fri0519,
          liveToday: (_) => SquareState.none,
        ),
        {key(10)},
        reason: 'the Grid shows the فشل on the 11th already cleared',
      );
      expect(
        heatmapFailedOpenDays(
          mirror: const {},
          habitIds: const ['a'],
          now: fri0519,
          liveToday: (_) => SquareState.failed,
        ),
        {key(11)},
        reason: 'marked moments ago, before the mirror has it',
      );
    });
  });

  group('the screen on Friday 11 September', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('heatmap_open_day_');
      Hive.init(tmp.path);
      // Opened here: the day sheet reads a guest's day through this box, and
      // opening it inside a testWidgets body never completes on fake time.
      await LocalStoreService.dailyBox();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    const s = S(Locale('ar'));
    final fri0519 = DateTime(2026, 9, 11, 5, 19);
    final fri1000 = DateTime(2026, 9, 11, kDayCutoffHour);

    final fajr = IslamicHabitTemplate(
      id: 'fajr',
      name: 'fajr',
      description: '',
      category: HabitCategory.faith,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      scheduledWeekdays: const [],
      hasTimer: false,
      xpReward: 10,
      goldReward: 1,
      createdAt: DateTime(2026, 8),
    );
    // Done on the 9th. Nothing on the 8th, the 10th or the 11th.
    final history = <String, Map<String, SquareState>>{
      'fajr': {DateTime(2026, 9, 9).toDateKey(): SquareState.complete},
    };

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    Future<void> pump(
      WidgetTester tester,
      DateTime clock, {
      Map<String, Map<String, SquareState>>? marks,
      WeeklyGridState? grid,
    }) async {
      tester.view.physicalSize = const Size(400 * 3, 2000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dayClockSourceProvider.overrideWithValue(() => clock),
          if (grid != null)
            weeklyGridProvider.overrideWith((ref) => _LiveGrid(ref, grid)),
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          premiumProvider.overrideWith((ref) => _Premium()),
          dashboardProvider.overrideWith((ref) => _LoadedDash()),
          allHabitsEverProvider.overrideWithValue([fajr]),
          habitYearHistoryProvider
              .overrideWith((ref) async => marks ?? history),
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
          home: const MonthlyHeatmapScreen(),
        ),
      ));
      await settle(tester);
    }

    /// September's cell for [day]: the number's text, which is last in the
    /// tree because September is the last month on screen.
    Finder cellNumber(int day) => find.text('$day').last;

    /// The plate colour behind September's [day].
    Color? plateOf(WidgetTester tester, int day) {
      final cell = find
          .ancestor(of: cellNumber(day), matching: find.byType(Container))
          .first;
      return (tester.widget<Container>(cell).decoration as BoxDecoration?)
          ?.color;
    }

    testWidgets('at 05:19 a blank today and a blank yesterday have no plate',
        (tester) async {
      await pump(tester, fri0519);
      expect(plateOf(tester, 11), Colors.transparent);
      expect(plateOf(tester, 10), Colors.transparent,
          reason: 'the 10th can still be marked until 10:00');
      expect(plateOf(tester, 8), isNot(Colors.transparent),
          reason: 'the 8th closed on nothing');
    });

    testWidgets('at 10:00 the 10th has closed on nothing, and gets the plate',
        (tester) async {
      await pump(tester, fri1000);
      expect(plateOf(tester, 10), isNot(Colors.transparent));
      expect(plateOf(tester, 11), Colors.transparent);
    });

    testWidgets('at 05:19 an open day holding a فشل is judged at once',
        (tester) async {
      await pump(
        tester,
        fri0519,
        marks: {
          'fajr': {
            DateTime(2026, 9, 9).toDateKey(): SquareState.complete,
            DateTime(2026, 9, 10).toDateKey(): SquareState.failed,
          },
        },
      );
      expect(
        plateOf(tester, 10),
        isNot(Colors.transparent),
        reason: 'a فشل settles its day at once, as the report counts it',
      );
      expect(plateOf(tester, 11), Colors.transparent);
    });

    testWidgets("today's فشل on the live Grid counts before the mirror has it",
        (tester) async {
      // Marked moments ago: the Grid already shows the فشل on the 11th, and
      // the year mirror every other cell reads has not caught up yet.
      await pump(
        tester,
        fri0519,
        grid: WeeklyGridState(
          weekStart: DateTime(2026, 9, 5),
          states: {
            DateTime(2026, 9, 11).toDateKey(): {'fajr': SquareState.failed},
          },
          notes: const {},
        ),
      );
      expect(
        plateOf(tester, 11),
        isNot(Colors.transparent),
        reason: 'judged from the mirror alone, today still read as open',
      );
    });

    testWidgets('the sheet behind an open blank day says the habit is due',
        (tester) async {
      await pump(tester, fri0519);
      await tester.tap(cellNumber(11));
      await settle(tester);
      expect(find.text(s.reportsDayScheduled), findsOneWidget);
      expect(find.text(SquareState.none.labelAr), findsNothing);
    });

    testWidgets('the sheet behind a closed blank day still says not done',
        (tester) async {
      await pump(tester, fri0519);
      await tester.tap(cellNumber(8));
      await settle(tester);
      expect(find.text(SquareState.none.labelAr), findsOneWidget);
      expect(find.text(s.reportsDayScheduled), findsNothing);
    });
  });
}
