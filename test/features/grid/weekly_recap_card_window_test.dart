// The weekly recap card under a pinned day clock: when it shows, which week
// it counts, and what it reads that week from.
//
// Aziz, 2026-09-18: the card showed all Friday, "and user can still change
// it by doing friday tasks". It now shows once the week has sealed, Saturday
// from kDayCutoffHour to midnight (recapWeekStartAt), and counts the week
// that has just ended against the one before it. weekly_recap_test.dart pins
// the window and the arithmetic on their own; this mounts the real card.
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
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/widgets/weekly_recap_card.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

class _Premium extends PremiumNotifier {
  _Premium(bool value) {
    state = value;
  }
}

class _LoadedDash extends DashboardNotifier {
  _LoadedDash(Map<String, int> dailyGreenCounts) : super(null) {
    state = DashboardState(
      level: 1,
      currentLevelXp: 0,
      cumulativeXp: 0,
      gold: 0,
      streak: 0,
      completions: const {},
      dailyGreenCounts: dailyGreenCounts,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('weekly_recap_card_window_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  const s = S(Locale('ar'));

  // The sealed week, Sat 12 to Fri 18 Sep: three greens a day Saturday to
  // Thursday and five on Friday, 23. The week before, Sat 5 to Fri 11: two a
  // day, 14. Before that one a day, 7, and 22 to 28 Aug empty. And six on
  // Saturday 19 Sep, the new week's first day, which no part of the recap
  // may count.
  final counts = <String, int>{
    for (var d = 12; d <= 17; d++) DateTime(2026, 9, d).toDateKey(): 3,
    DateTime(2026, 9, 18).toDateKey(): 5,
    for (var d = 5; d <= 11; d++) DateTime(2026, 9, d).toDateKey(): 2,
    for (var i = 0; i < 7; i++) DateTime(2026, 8, 29 + i).toDateKey(): 1,
    DateTime(2026, 9, 19).toDateKey(): 6,
  };

  IslamicHabitTemplate habit(String id, {DateTime? createdAt}) =>
      IslamicHabitTemplate(
        id: id,
        name: id,
        description: '',
        category: HabitCategory.fitness,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        scheduledWeekdays: const [],
        hasTimer: false,
        xpReward: 10,
        goldReward: 5,
        createdAt: createdAt ?? DateTime(2026, 8),
      );
  final gym = habit('gym');

  // gym in the sealed week: done Saturday to Tuesday, then three blank days.
  final sealed = RecapWeek(
    days: [for (var d = 12; d <= 18; d++) DateTime(2026, 9, d)],
    states: {
      for (var d = 12; d <= 15; d++)
        DateTime(2026, 9, d).toDateKey(): {'gym': SquareState.complete},
    },
  );

  late List<DateTime> asked;

  Future<void> pumpCard(
    WidgetTester tester,
    DateTime clock, {
    bool premium = false,
    List<IslamicHabitTemplate>? habits,
    RecapWeek? week,
  }) async {
    asked = [];
    tester.view.physicalSize = const Size(400 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dayClockSourceProvider.overrideWithValue(() => clock),
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumProvider.overrideWith((ref) => _Premium(premium)),
        dashboardProvider.overrideWith((ref) => _LoadedDash(counts)),
        allHabitsEverProvider.overrideWithValue(habits ?? [gym]),
        recapWeekProvider.overrideWith((ref, weekStart) async {
          asked.add(weekStart);
          return week;
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
        home: Scaffold(
          body: ListView(children: const [WeeklyRecapCard()]),
        ),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  final title = find.text(s.weeklyRecapTitle);

  test('the calendar these tests rest on', () {
    expect(DateTime(2026, 9, 12).weekday, DateTime.saturday);
    expect(DateTime(2026, 9, 18).weekday, DateTime.friday);
    expect(DateTime(2026, 9, 19).weekday, DateTime.saturday);
  });

  testWidgets('Friday evening: nothing, the week is still being lived',
      (tester) async {
    await pumpCard(tester, DateTime(2026, 9, 18, 20), week: sealed);
    expect(title, findsNothing);
    expect(asked, isEmpty, reason: 'no week is read while the card is away');
  });

  testWidgets('Saturday before the cutoff: nothing, Friday is still payable',
      (tester) async {
    await pumpCard(tester, DateTime(2026, 9, 19, kDayCutoffHour - 1, 59),
        week: sealed);
    expect(title, findsNothing);
  });

  testWidgets('Saturday at the cutoff: the sealed week against the one before',
      (tester) async {
    await pumpCard(tester, DateTime(2026, 9, 19, kDayCutoffHour),
        week: sealed);
    expect(title, findsOneWidget);
    expect(asked.toSet(), {DateTime(2026, 9, 12)},
        reason: 'the squares read are the sealed week, not the new one');
    // 23 against 14, day by day with every day closed: +9. The six greens on
    // the new week's Saturday count nowhere.
    expect(find.text('23'), findsWidgets);
    expect(find.text('+9'), findsOneWidget);
    expect(find.text('14'), findsWidgets);
    expect(find.text('29'), findsNothing);
    expect(find.text(s.weeklyRecapThisWeek), findsWidgets);
    expect(find.text(s.weeklyRecapLastWeek), findsOneWidget);
    expect(find.text(s.weeklyRecapUp), findsOneWidget);
    expect(find.text('الجمعة'), findsOneWidget, reason: 'best day: 5 greens');
  });

  testWidgets('the new words', (tester) async {
    await pumpCard(tester, DateTime(2026, 9, 19, 12), week: sealed);
    expect(find.text('أسبوعك'), findsWidgets);
    expect(find.text('الأسبوع اللي قبله'), findsOneWidget);
    expect(find.text('أقوى من الأسبوع اللي قبله. استمر.'), findsOneWidget);
    expect(find.text('هالأسبوع'), findsNothing);
    expect(find.text('الأسبوع الماضي'), findsNothing);
  });

  testWidgets('still there at 23:59 on the Saturday', (tester) async {
    await pumpCard(tester, DateTime(2026, 9, 19, 23, 59), week: sealed);
    expect(title, findsOneWidget);
  });

  testWidgets('gone at midnight', (tester) async {
    await pumpCard(tester, DateTime(2026, 9, 20), week: sealed);
    expect(title, findsNothing);
  });

  testWidgets(
      "the rows and the needs-attention line read the sealed week's squares",
      (tester) async {
    await pumpCard(tester, DateTime(2026, 9, 19, kDayCutoffHour),
        premium: true, week: sealed);
    expect(find.text(s.weeklyRecapNeedsLove('gym')), findsOneWidget,
        reason: 'three closed blank days in the sealed week');
    expect(find.text(s.weeklyRecapPerHabit), findsOneWidget);
    expect(find.text('4/7'), findsOneWidget);
    // The trend ends on the sealed week, tagged «أسبوعك» rather than dated;
    // the three before it keep their dates.
    expect(find.text('5-11'), findsOneWidget);
    expect(find.text('29-4'), findsOneWidget);
    expect(find.text('22-28'), findsOneWidget);
    expect(find.text('12-18'), findsNothing);
  });

  testWidgets('a habit added on the Saturday gets no row in the week before',
      (tester) async {
    await pumpCard(
      tester,
      DateTime(2026, 9, 19, kDayCutoffHour),
      premium: true,
      habits: [gym, habit('fresh', createdAt: DateTime(2026, 9, 19, 8))],
      week: sealed,
    );
    expect(find.text('gym'), findsOneWidget);
    expect(find.text('fresh'), findsNothing);
  });

  testWidgets('until the week has been read, no rows and no line, only guesses '
      'withheld', (tester) async {
    await pumpCard(tester, DateTime(2026, 9, 19, kDayCutoffHour),
        premium: true);
    expect(title, findsOneWidget);
    expect(find.text('23'), findsWidgets, reason: 'the totals need no read');
    expect(find.text(s.weeklyRecapPerHabit), findsNothing);
    expect(find.text(s.weeklyRecapNeedsLove('gym')), findsNothing);
    expect(find.text(s.weeklyRecapTrend), findsOneWidget);
  });
}
