// One record, one rate: «سنة» and «الكل» counted a habit with no saved start
// date from different days, so Aziz's record read 28% on one tab and 52% on
// the other (2026-09-21). A preset switched on before switch-on days were
// kept has no createdAt, and isScheduledFor reads that as alive forever:
// the year owed it from 1 January, «الكل» from the record's first square.
//
// The fix is one rule (habitWithKnownStart in report_period.dart): a habit
// with no known start begins on its first recorded square. The squares had
// it already; now every rate counts with it too, and «الكل» begins where the
// record begins (recordStartOf), so on a record inside one year the two tabs
// agree.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/milestones/reports/habit_detail_sheet.dart';
import 'package:grow_daily_v2/features/milestones/reports/period_report_section.dart';
import 'package:grow_daily_v2/features/milestones/reports/record_lifetime.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_sections.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/shared/widgets/segmented_tabs.dart';

class _Premium extends PremiumNotifier {
  _Premium() {
    state = true;
  }
}

class _LoadedDash extends DashboardNotifier {
  _LoadedDash({Map<String, int> habitTotals = const {}}) : super(null) {
    state = DashboardState(
      level: 1,
      currentLevelXp: 0,
      cumulativeXp: 0,
      gold: 0,
      streak: 0,
      completions: const {},
      habitTotalCompletions: habitTotals,
    );
  }
}

IslamicHabitTemplate _daily(String id, {DateTime? createdAt}) =>
    IslamicHabitTemplate(
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
      createdAt: createdAt,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final clock = DateTime(2026, 9, 21, 15);
  final today = DateTime(2026, 9, 21);
  String k(int m, int d) => DateTime(2026, m, d).toDateKey();

  // Like الصدقة ولو بالقليل: a preset with no saved start, first done on
  // 20 June.
  final legacy = _daily('sadaqa');
  final legacyMarks = {
    for (var d = 20; d <= 30; d++) k(6, d): SquareState.complete,
    for (var d = 1; d <= 31; d += 2) k(7, d): SquareState.complete,
    k(9, 14): SquareState.complete,
  };
  // A habit that does carry its start: made on 1 July.
  final dated = _daily('quran', createdAt: DateTime(2026, 7));
  final datedMarks = {
    for (var d = 1; d <= 31; d++) k(7, d): SquareState.complete,
    for (var d = 1; d <= 20; d++) k(9, d): SquareState.complete,
  };
  final history = {legacy.id: legacyMarks, dated.id: datedMarks};

  group('habitWithKnownStart', () {
    test('a habit with no saved start begins on its first square', () {
      final started = habitWithKnownStart(legacy, legacyMarks, today: today);
      expect(started.createdAt, DateTime(2026, 6, 20));
      expect(started.isScheduledFor(DateTime(2026, 6, 19)), isFalse);
      expect(started.isScheduledFor(DateTime(2026, 6, 20)), isTrue);
    });

    test('one that has recorded nothing begins today, owing no past', () {
      final started = habitWithKnownStart(legacy, const {}, today: today);
      expect(started.createdAt, today);
    });

    test('a saved start is kept as it is', () {
      expect(
          identical(
              habitWithKnownStart(dated, datedMarks, today: today), dated),
          isTrue);
    });

    test('an archived habit stays archived', () {
      final archived =
          legacy.withDates(createdAt: null, archivedAt: DateTime(2026, 8, 1));
      final started = habitWithKnownStart(archived, legacyMarks, today: today);
      expect(started.archivedAt, DateTime(2026, 8, 1));
    });
  });

  test('every rate counts such a habit from its first square', () {
    final year = elapsedDaysIn(
      start: DateTime(2026),
      end: DateTime(2026, 12, 31),
      today: today,
    );
    // The old reading, straight from the unchanged schedule check: owed
    // since 1 January, months before it was ever done.
    final fromJanuary =
        expectedCompletions(habit: legacy, days: year, now: clock);
    final stat = computeHabitPeriodStats(
      habits: [legacy],
      history: history,
      days: year,
      now: clock,
      windowEnd: DateTime(2026, 12, 31),
    ).single;
    final fromFirstSquare = expectedCompletions(
      habit: legacy.withDates(createdAt: DateTime(2026, 6, 20)),
      days: year,
      now: clock,
    );
    expect(stat.expected, fromFirstSquare);
    expect(stat.expected, lessThan(fromJanuary));
  });

  test('the record begins where its first habit or square does', () {
    final known = [
      habitWithKnownStart(legacy, legacyMarks, today: today),
      dated,
    ];
    expect(recordStartOf(known, DateTime(2026, 6, 20)), DateTime(2026, 6, 20));
    // A habit made before anything was marked starts the record earlier:
    // its unmarked days were owed, and a year counts them.
    final early = _daily('early', createdAt: DateTime(2026, 5, 3));
    expect(recordStartOf([...known, early], DateTime(2026, 6, 20)),
        DateTime(2026, 5, 3));
  });

  group('on screen', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('record_rates_agree_');
      Hive.init(tmp.path);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    testWidgets('«سنة» and «الكل» show one rate for a one-year record',
        (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 3200 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dayClockSourceProvider.overrideWithValue(() => clock),
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          premiumProvider.overrideWith((ref) => _Premium()),
          dashboardProvider.overrideWith((ref) => _LoadedDash()),
          allHabitsEverProvider.overrideWithValue([legacy, dated]),
          habitYearHistoryProvider.overrideWith((ref) async => history),
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
          home: const Scaffold(
            body: PeriodReportSection(initialTab: RecordTab.all),
          ),
        ),
      ));
      await settle(tester);

      PeriodSummary headline() => tester
          .widget<ReportHeaderCard>(find.byType(ReportHeaderCard))
          .summary;

      final all = headline();
      expect(find.text('منذ يونيو 2026'), findsOneWidget);

      tester
          .widget<SegmentedTabs>(find.byType(SegmentedTabs))
          .onChanged(RecordTab.year.index);
      await settle(tester);
      final year = headline();

      expect(year.totalDone, all.totalDone);
      expect(year.expectedTotal, all.expectedTotal,
          reason: 'both tabs owe each habit from its own start');
      expect((year.rate * 100).round(), (all.rate * 100).round());

      // And it is the number the Profile tile's provider holds.
      final lifetime = ProviderScope.containerOf(
              tester.element(find.byType(PeriodReportSection)))
          .read(recordLifetimeProvider)!;
      expect(lifetime.summary.expectedTotal, all.expectedTotal);
      expect(lifetime.start, DateTime(2026, 6, 20));
    });

    testWidgets('a habit\'s sheet counts its days from the record',
        (tester) async {
      // The stored per-habit counter says 11; the record holds 28 green
      // days. The sheet used to print the counter beside a year row that
      // counted the squares (Aziz: «11 يوم» against «15 يوم»).
      tester.view.physicalSize = const Size(400 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dayClockSourceProvider.overrideWithValue(() => clock),
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          premiumProvider.overrideWith((ref) => _Premium()),
          dashboardProvider.overrideWith(
              (ref) => _LoadedDash(habitTotals: {legacy.id: 11})),
          habitYearHistoryProvider.overrideWith((ref) async => history),
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
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHabitDetailSheet(context, legacy),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await settle(tester);
      await tester.tap(find.text('open'));
      await settle(tester);
      final greenDays = legacyMarks.values.where((m) => m.isGreen).length;
      expect(greenDays, 28);
      // «N يوم» under the big number; the bare digits also name calendar
      // days, so the label is what is checked.
      expect(find.text('$greenDays يوم'), findsOneWidget);
      expect(find.text('11 يوم'), findsNothing,
          reason: 'the drifted counter is no longer shown');
    });
  });
}
