// سجلّي's tabs are zoom levels, and a tap goes one level down: a year card
// on «الكل» opens «سنة», a month there opens «شهر», whose calendar is the
// map's own month (lib/features/milestones/reports/period_report_section.dart,
// record_views.dart).
//
// Aziz, 2026-09-21, on the first design, where «الكل» was one long scroll of
// months: "still hard for the user to go back 3 years to search for a square
// in a month, day". And the one number: the Profile said 244 while the map
// said 216, so «الكل» and the Profile now read one provider.
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
import 'package:grow_daily_v2/features/grid/screens/monthly_heatmap_screen.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/milestones/reports/period_report_section.dart';
import 'package:grow_daily_v2/features/milestones/reports/record_lifetime.dart';
import 'package:grow_daily_v2/features/milestones/reports/record_views.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_sections.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/shared/widgets/segmented_tabs.dart';

class _Premium extends PremiumNotifier {
  _Premium() {
    state = true;
  }
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('record_zoom_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  final habit = IslamicHabitTemplate(
    id: 'quran',
    name: 'quran',
    description: '',
    category: HabitCategory.faith,
    frequencyType: HabitFrequencyType.daily,
    frequencyTarget: 1,
    scheduledWeekdays: const [],
    hasTimer: false,
    xpReward: 10,
    goldReward: 1,
    createdAt: DateTime(2025, 11),
  );
  // Two squares last December and one this September: a record that spans
  // two years, so «الكل» has two cards.
  final history = {
    habit.id: {
      DateTime(2025, 12, 10).toDateKey(): SquareState.complete,
      DateTime(2025, 12, 11).toDateKey(): SquareState.complete,
      DateTime(2026, 9, 14).toDateKey(): SquareState.complete,
    },
  };

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<ProviderContainer> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400 * 3, 3200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dayClockSourceProvider
            .overrideWithValue(() => DateTime(2026, 9, 21, 15)),
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumProvider.overrideWith((ref) => _Premium()),
        dashboardProvider.overrideWith((ref) => _LoadedDash()),
        allHabitsEverProvider.overrideWithValue([habit]),
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
    return ProviderScope.containerOf(
        tester.element(find.byType(PeriodReportSection)));
  }

  int selectedTab(WidgetTester tester) =>
      tester.widget<SegmentedTabs>(find.byType(SegmentedTabs)).selected;

  /// The period the pinned line under the tabs names.
  String periodLine(WidgetTester tester) =>
      tester.widget<ReportPeriodHeader>(find.byType(ReportPeriodHeader)).label;

  testWidgets('«الكل» lists every year, newest first, and names the start',
      (tester) async {
    await mount(tester);
    expect(selectedTab(tester), RecordTab.all.index);
    expect(
      tester
          .widgetList<RecordYearCard>(find.byType(RecordYearCard))
          .map((c) => (c.year, c.total))
          .toList(),
      [(2026, 1), (2025, 2)],
    );
    // The habit was made on 1 November and first done on 10 December: the
    // record begins with the habit (recordStartOf), so its November days
    // count as owed on «الكل» exactly as they do on «سنة».
    expect(find.text('منذ نوفمبر 2025'), findsOneWidget);
    // A label, not a control. It opened a month list once, and picking a
    // month there moved Aziz off «الكل» onto «شهر»: "why can I choose here,
    // and it sends me there".
    expect(
      tester.widget<RecordSinceHeader>(find.byType(RecordSinceHeader)).onTap,
      isNull,
    );
    expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
  });

  testWidgets('a year card opens that year, a month opens the map\'s month',
      (tester) async {
    await mount(tester);

    await tester.tap(find.byWidgetPredicate(
        (w) => w is RecordYearCard && w.year == 2025));
    await settle(tester);
    expect(selectedTab(tester), RecordTab.year.index);
    expect(
        tester.widget<YearMonthsGrid>(find.byType(YearMonthsGrid)).year, 2025);
    expect(find.text('2025'), findsOneWidget, reason: 'the period line');

    await tester.tap(find.text('ديسمبر'));
    await settle(tester);
    expect(selectedTab(tester), RecordTab.month.index);
    final month =
        tester.widget<HeatmapMonthSection>(find.byType(HeatmapMonthSection));
    expect(month.month, DateTime(2025, 12));
    expect(month.showHeader, isFalse,
        reason: 'the period line above already names the month');
    expect(find.text('ديسمبر 2025'), findsOneWidget);
  });

  testWidgets('«الكل» and the Profile tile read one lifetime total',
      (tester) async {
    final container = await mount(tester);
    final lifetime = container.read(recordLifetimeProvider);
    expect(lifetime, isNotNull);
    expect(lifetime!.summary.totalDone, 3);
    final card =
        tester.widget<ReportHeaderCard>(find.byType(ReportHeaderCard));
    expect(card.summary.totalDone, lifetime.summary.totalDone);
    expect(lifetime.totalIn(2025) + lifetime.totalIn(2026),
        lifetime.summary.totalDone,
        reason: 'the year cards add up to the lifetime total');
  });

  testWidgets('opening this year keeps today, so «شهر» is this month',
      (tester) async {
    // Anchored on 1 January, the tab beside it opened an empty January.
    await mount(tester);
    await tester.tap(find.byWidgetPredicate(
        (w) => w is RecordYearCard && w.year == 2026));
    await settle(tester);
    tester
        .widget<SegmentedTabs>(find.byType(SegmentedTabs))
        .onChanged(RecordTab.month.index);
    await settle(tester);
    expect(periodLine(tester), 'سبتمبر 2026');
  });

  testWidgets('a past year opens on its last month', (tester) async {
    await mount(tester);
    await tester.tap(find.byWidgetPredicate(
        (w) => w is RecordYearCard && w.year == 2025));
    await settle(tester);
    tester
        .widget<SegmentedTabs>(find.byType(SegmentedTabs))
        .onChanged(RecordTab.month.index);
    await settle(tester);
    expect(periodLine(tester), 'ديسمبر 2025');
  });

  testWidgets('a month still to come cannot be opened', (tester) async {
    await mount(tester);
    await tester.tap(find.byWidgetPredicate(
        (w) => w is RecordYearCard && w.year == 2026));
    await settle(tester);
    await tester.tap(find.text('نوفمبر'));
    await settle(tester);
    expect(selectedTab(tester), RecordTab.year.index,
        reason: 'November 2026 has no lived days yet');
  });
}
