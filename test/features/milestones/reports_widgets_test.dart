// Widget tests for the reports hub's two shared cards, in both locales at a
// real phone width.
//
// These exist because every string on this screen is written twice, and the
// English side is the one nobody looks at on the simulator: "Completion",
// "Longest run" and "Best weekday: Wednesday" are all materially longer than
// their Arabic counterparts, in a card that divides its width three ways.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_period.dart';
import 'package:grow_daily_v2/features/milestones/reports/report_sections.dart';
import 'package:grow_daily_v2/shared/widgets/segmented_tabs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> host(
    WidgetTester tester,
    Widget child, {
    String locale = 'ar',
    double width = 375,
  }) async {
    tester.view.physicalSize = Size(width * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  const summary = PeriodSummary(
    totalDone: 128,
    expectedTotal: 200,
    bestDay: null,
    bestDayCount: 9,
    activeDays: 20,
    longestRun: 14,
  );

  group('SegmentedTabs', () {
    for (final locale in ['ar', 'en']) {
      testWidgets('three period labels fit at 375pt in $locale',
          (tester) async {
        final s = S(Locale(locale));
        await host(
          tester,
          SegmentedTabs(
            labels: [s.reportsWeekly, s.reportsMonthly, s.reportsYearly],
            selected: 0,
            onChanged: (_) {},
          ),
          locale: locale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text(s.reportsWeekly), findsOneWidget);
        expect(find.text(s.reportsYearly), findsOneWidget);
      });
    }

    testWidgets('tapping the selected segment emits nothing', (tester) async {
      // Callers rebuild a whole report body on change; re-selecting the
      // current tab would throw away a scroll position for no reason.
      var changes = 0;
      await host(
        tester,
        SegmentedTabs(
          labels: const ['A', 'B', 'C'],
          selected: 0,
          onChanged: (_) => changes++,
        ),
      );
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(changes, 0);
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(changes, 1);
    });
  });

  group('ReportHeaderCard', () {
    for (final locale in ['ar', 'en']) {
      testWidgets('renders its three stats without overflow in $locale',
          (tester) async {
        await host(
          tester,
          const ReportHeaderCard(summary: summary, locale: 'en', delta: 12),
          locale: locale,
        );
        expect(tester.takeException(), isNull);
        final s = S(Locale(locale));
        expect(find.text(s.reportsRate), findsOneWidget);
        expect(find.text(s.reportsLongestRun), findsOneWidget);
      });
    }

    testWidgets('the total is printed once, not twice', (tester) async {
      // The regression that prompted the merge of the headline card and the
      // summary row: "40" appeared as the headline AND as المجموع directly
      // under it.
      await host(
        tester,
        const ReportHeaderCard(summary: summary, locale: 'en'),
      );
      await tester.pumpAndSettle();
      expect(find.text('128'), findsOneWidget);
    });

    testWidgets('a null delta prints no change at all', (tester) async {
      await host(
        tester,
        const ReportHeaderCard(summary: summary, locale: 'en'),
      );
      expect(find.textContaining('+'), findsNothing);
    });
  });

  group('WeekdayRhythmCard', () {
    test('a flat period never qualifies for a card', () {
      // The card has no "no pattern" state any more, so the guard that
      // keeps it off screen lives in isMeaningful. On the yearly tab, where
      // weekday averages are almost always even, this is what stops a
      // screen-filling block from reporting nothing.
      const flat = WeekdayInsight(
        bestWeekday: DateTime.tuesday,
        worstWeekday: DateTime.thursday,
        bestAverage: 3.0,
        worstAverage: 2.9,
        occurrences: 40,
      );
      expect(flat.hasEnoughSamples, isTrue);
      expect(flat.isMeaningful, isFalse);
    });

    test('one week of samples never qualifies either', () {
      const thin = WeekdayInsight(
        bestWeekday: DateTime.tuesday,
        worstWeekday: DateTime.thursday,
        bestAverage: 6,
        worstAverage: 1,
        occurrences: 1,
      );
      expect(thin.isMeaningful, isFalse);
    });

    testWidgets('a real winner names the weekday, not a date', (tester) async {
      const insight = WeekdayInsight(
        bestWeekday: DateTime.tuesday,
        worstWeekday: DateTime.thursday,
        bestAverage: 6,
        worstAverage: 1,
        occurrences: 4,
      );
      await host(
        tester,
        const WeekdayRhythmCard(
          insight: insight,
          averages: {
            DateTime.saturday: 3,
            DateTime.sunday: 3,
            DateTime.monday: 3,
            DateTime.tuesday: 6,
            DateTime.wednesday: 3,
            DateTime.thursday: 1,
            DateTime.friday: 3,
          },
          locale: 'en',
          periodLabel: 'August 2026',
        ),
        locale: 'en',
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Best weekday: Tuesday'), findsOneWidget);
      expect(find.text('Weakest weekday: Thursday'), findsOneWidget);
    });

  });
}
