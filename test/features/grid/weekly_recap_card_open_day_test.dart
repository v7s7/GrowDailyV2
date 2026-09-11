// The Friday recap card under a pinned day clock.
//
// weekly_recap_test.dart pins computeWeeklyRecap's day-by-day change on its
// own. It cannot see the card handing it no clock: `now: null` compares a
// Friday morning in full, and the card said «أسبوع أهدى» beside a -3 before
// Thursday, let alone Friday, had closed. This mounts the real card.
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
    tmp = await Directory.systemTemp.createTemp('weekly_recap_card_open_day_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  const s = S(Locale('ar'));

  // Last week, Sat 29 Aug to Fri 4 Sep: two greens a day, 14. This week: two
  // a day Saturday to Wednesday, one on Thursday, none yet on Friday, 11.
  final counts = <String, int>{
    for (var i = 0; i < 7; i++) DateTime(2026, 8, 29 + i).toDateKey(): 2,
    for (var d = 5; d <= 9; d++) DateTime(2026, 9, d).toDateKey(): 2,
    DateTime(2026, 9, 10).toDateKey(): 1,
  };

  final gym = IslamicHabitTemplate(
    id: 'gym',
    name: 'gym',
    description: '',
    category: HabitCategory.fitness,
    frequencyType: HabitFrequencyType.daily,
    frequencyTarget: 1,
    scheduledWeekdays: const [],
    hasTimer: false,
    xpReward: 10,
    goldReward: 5,
    createdAt: DateTime(2026, 8),
  );

  Future<void> pumpCard(WidgetTester tester, DateTime clock) async {
    tester.view.physicalSize = const Size(400 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dayClockSourceProvider.overrideWithValue(() => clock),
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumProvider.overrideWith((ref) => _Premium(false)),
        dashboardProvider.overrideWith((ref) => _LoadedDash(counts)),
        allHabitsEverProvider.overrideWithValue([gym]),
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

  test('the calendar these tests rest on', () {
    expect(DateTime(2026, 9, 11).weekday, DateTime.friday);
    expect(DateTime(2026, 9, 5).weekday, DateTime.saturday);
  });

  testWidgets('at 05:19 on Friday the week reads level, not down',
      (tester) async {
    await pumpCard(tester, DateTime(2026, 9, 11, 5, 19));
    expect(find.text(s.weeklyRecapSame), findsOneWidget,
        reason: 'Thursday and Friday are both still open');
    expect(find.text(s.weeklyRecapDown), findsNothing);
    expect(find.text('-3'), findsNothing,
        reason: 'the whole-week difference, with two days still to play');
    expect(find.text('-1'), findsNothing);
  });

  testWidgets('at 10:00 Thursday has closed on 1 against 2', (tester) async {
    await pumpCard(tester, DateTime(2026, 9, 11, kDayCutoffHour));
    expect(find.text('-1'), findsOneWidget);
    expect(find.text(s.weeklyRecapDown), findsOneWidget);
  });
}
