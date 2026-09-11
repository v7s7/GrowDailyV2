// The Insights screen under a pinned day clock, and its weekday wave.
//
// insight_engine_test pins computeInsights' still-open rule on its own. It
// cannot see the screen handing the engine no clock: `now: null` counts a
// blank today, and a blank yesterday before 10:00, as misses again, names a
// habit as needing a push for a day that can still be marked, and every
// pure test stays green. This mounts the real InsightsScreen.
//
// Dated on a fixed day long past, Wednesday 18 June 2025, not off the real
// calendar: the screen reads its 56 daily documents back from the day
// clock's own day (loadInsightsWindow), so the fixture and the pinned clocks
// agree whenever the test runs, and a screen that went back to reading the
// wall clock for its window would find none of them.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/insights/insight_engine.dart';
import 'package:grow_daily_v2/features/insights/insights_screen.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

class _Premium extends PremiumNotifier {
  _Premium(bool value) {
    state = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  const s = S(Locale('en'));

  Widget app(Widget home, {List<Override> overrides = const []}) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.dark,
          home: home,
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  group('the weekday wave', () {
    test('a weekday that owed nothing has no rate, never 0.0', () {
      expect(
        weekdayWaveRates(
          scheduledByWeekday: const {DateTime.monday: 4, DateTime.thursday: 4},
          completedByWeekday: const {DateTime.monday: 3},
        ),
        [0.75, null, null, 0.0, null, null, null],
        reason: 'Monday to Sunday; Thursday was owed and missed, the other '
            'five were never owed',
      );
    });

    testWidgets('prints a placeholder for a weekday that owed nothing',
        (tester) async {
      // A Monday-and-Thursday habit that slips on Thursdays.
      final pattern = HabitPattern('mt')
        ..scheduled = 8
        ..completed = 3
        ..scheduledByWeekday.addAll({DateTime.monday: 4, DateTime.thursday: 4})
        ..completedByWeekday.addAll({DateTime.monday: 3});
      final result = InsightsResult(
        patterns: {'mt': pattern},
        strongestWeekday: null,
        overallScheduledByWeekday: const {
          DateTime.monday: 4,
          DateTime.thursday: 4,
        },
        overallCompletedByWeekday: const {DateTime.monday: 3},
        mostConsistentHabitId: null,
        needsPushHabitId: null,
        totalSamples: 8,
      );
      tester.view.physicalSize = const Size(400 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showInsightDetailSheet(
                context,
                headline: (
                  Icons.trending_down_rounded,
                  Colors.red,
                  'mt slips on Thursdays',
                  'mt',
                  DateTime.thursday,
                ),
                result: result,
                habits: const [],
                locale: 'en',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);

      expect(find.text('75%'), findsOneWidget, reason: 'Monday');
      expect(find.text('0%'), findsOneWidget,
          reason: 'Thursday, owed four times and missed four');
      expect(find.text('–'), findsNWidgets(5),
          reason: 'the five weekdays this habit never runs on');
    });
  });

  group('the screen, at 05:19 and at 10:00 today', () {
    final today = DateTime(2025, 6, 18);
    DateTime daysAgo(int n) =>
        DateTime(today.year, today.month, today.day - n);
    final at0519 = DateTime(today.year, today.month, today.day, 5, 19);
    final at1000 =
        DateTime(today.year, today.month, today.day, kDayCutoffHour);

    // Two daily habits started eight days ago. A is done every day up to and
    // including yesterday; B every day up to the day before yesterday. Today
    // is blank for both.
    IslamicHabitTemplate daily(String id) => IslamicHabitTemplate(
          id: id,
          name: id,
          description: '',
          category: HabitCategory.faith,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
          scheduledWeekdays: const [],
          hasTimer: false,
          xpReward: 10,
          goldReward: 1,
          createdAt: daysAgo(8),
        );
    final habits = [daily('A'), daily('B')];

    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('insights_open_day_');
      Hive.init(tmp.path);
      // Written here, not inside a test: a testWidgets body runs on fake
      // time, where a Hive write never completes. Opening the box here also
      // leaves the screen's own reads nothing real to wait on.
      for (var n = 1; n <= 8; n++) {
        await LocalStoreService.putDailyMap(daysAgo(n).toDateKey(), {
          'squareStates': {
            'A': SquareState.complete.name,
            if (n >= 2) 'B': SquareState.complete.name,
          },
        });
      }
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    Future<void> pumpScreen(WidgetTester tester, DateTime clock) async {
      tester.view.physicalSize = const Size(400 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(
        const InsightsScreen(),
        overrides: [
          dayClockSourceProvider.overrideWithValue(() => clock),
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          premiumProvider.overrideWith((ref) => _Premium(false)),
          allHabitsEverProvider.overrideWithValue(habits),
        ],
      ));
      await settle(tester);
    }

    String strongestYesterday() => s.insightStrongestDay(
          DateFormat('EEEE', 'en').format(daysAgo(1)),
        );

    testWidgets('at 05:19 a blank yesterday and today are not misses yet',
        (tester) async {
      await pumpScreen(tester, at0519);
      expect(find.text(s.insightMostConsistent('A')), findsOneWidget);
      expect(find.text(s.insightNeedsPush('B')), findsNothing,
          reason: 'B has not missed a day that has closed');
      expect(find.text(strongestYesterday()), findsNothing,
          reason: "yesterday's weekday holds three closed or answered days, "
              'below the four a strongest day needs');
    });

    testWidgets('at 10:00 yesterday has closed blank for B, and counts',
        (tester) async {
      await pumpScreen(tester, at1000);
      expect(find.text(s.insightNeedsPush('B')), findsOneWidget);
      expect(find.text(strongestYesterday()), findsOneWidget,
          reason: "yesterday's weekday now holds four: three of them done");
    });
  });
}
