// The Insights detail sheet for a habit that does not run every day, on the
// numbers of Aziz's screenshot (2026-09-18): «"الصدقة ولو بالقليل" تنقطع
// أكثر يوم الخميس», a Monday and Thursday habit, 63%, 10 of 16, over «آخر 8
// أسابيع · 25 يوليو – 18 سبتمبر». The old sheet drew it on the seven-day wave:
// five «–» and two lone dots. It now draws the habit's own two days, each
// week of the window a dated square.
//
// Also pinned: a weekly quota's card and sheet (weeks against the target),
// and that a daily habit's weekday sheet still draws the wave.
//
// Pumped under the real localization delegates, as insight_detail_sheet_test
// does: they are what turn a formatted date's digits Arabic-Indic, and a
// bare test process never shows them.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/insights/insight_engine.dart';
import 'package:grow_daily_v2/features/insights/insights_screen.dart';

IslamicHabitTemplate habit(
  String id,
  String name, {
  HabitFrequencyType type = HabitFrequencyType.daily,
  int target = 1,
  List<int> weekdays = const [],
}) =>
    IslamicHabitTemplate(
      id: id,
      name: name,
      nameAr: name,
      description: '',
      category: HabitCategory.faith,
      frequencyType: type,
      frequencyTarget: target,
      scheduledWeekdays: weekdays,
      hasTimer: false,
      xpReward: 10,
      goldReward: 1,
      createdAt: DateTime(2026, 6, 1),
    );

/// Saturday 25 July to Friday 18 September 2026, newest first.
final end = DateTime(2026, 9, 18);
List<DateTime> windowDays() => [
      for (var i = 0; i < 56; i++) DateTime(end.year, end.month, end.day - i),
    ];

List<(DateTime, Map<String, dynamic>)> docs(
  Map<String, Map<DateTime, SquareState>> marksById,
) =>
    [
      for (final d in windowDays())
        (
          d,
          {
            'squareStates': {
              for (final e in marksById.entries)
                if (e.value[d] != null) e.key: e.value[d]!.name,
            },
          },
        ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // buildInsightCards names weekdays before anything is pumped. The sheets
  // then run on the symbols flutter_localizations installs over these, the
  // ones that bring the Arabic-Indic digits.
  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  const ar = S(Locale('ar'));
  const en = S(Locale('en'));
  final at1400 = DateTime(2026, 9, 18, 14);
  final arabicIndic = RegExp('[٠-٩]');

  final sadaqa = habit(
    'sadaqa',
    'الصدقة ولو بالقليل',
    type: HabitFrequencyType.weekly,
    target: 2,
    weekdays: const [DateTime.monday, DateTime.thursday],
  );
  // Monday 6 of 8 (3 August and 7 September empty), Thursday 4 of 8.
  final sadaqaMarks = <DateTime, SquareState>{
    for (final d in [
      DateTime(2026, 7, 27),
      DateTime(2026, 8, 10),
      DateTime(2026, 8, 17),
      DateTime(2026, 8, 24),
      DateTime(2026, 8, 31),
      DateTime(2026, 9, 14),
      DateTime(2026, 7, 30),
      DateTime(2026, 8, 20),
      DateTime(2026, 8, 27),
      DateTime(2026, 9, 10),
    ])
      d: SquareState.complete,
  };

  Future<void> openSheet(
    WidgetTester tester, {
    required String locale,
    required (InsightHeadline, InsightKind) card,
    required InsightsResult result,
    required List<IslamicHabitTemplate> habits,
    bool passKind = true,
  }) async {
    tester.view.physicalSize = const Size(402 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        locale: Locale(locale),
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
              onPressed: () => showInsightDetailSheet(
                context,
                headline: card.$1,
                kind: passKind ? card.$2 : null,
                result: result,
                habits: habits,
                locale: locale,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Iterable<String> texts(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((t) => t.isNotEmpty);

  Finder recordCells() => find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_RecordCell');

  group("the screenshot's Monday and Thursday habit", () {
    final result = computeInsights(
      habits: [sadaqa],
      days: docs({'sadaqa': sadaqaMarks}),
      now: at1400,
    );

    (InsightHeadline, InsightKind) weekdayCard(S s, String locale) =>
        buildInsightCards(result: result, habits: [sadaqa], s: s, locale: locale)
            .singleWhere((c) => c.$2 == InsightKind.weekdayMiss);

    test('its card still names Thursday, the weaker of its two days', () {
      final card = weekdayCard(ar, 'ar');
      expect(card.$1.$3, '"الصدقة ولو بالقليل" تنقطع أكثر يوم الخميس');
      expect(card.$1.$4, 'sadaqa');
      expect(card.$1.$5, DateTime.thursday);
    });

    testWidgets('Arabic: its own two days, eight dated weeks each',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await openSheet(
        tester,
        locale: 'ar',
        card: weekdayCard(ar, 'ar'),
        result: result,
        habits: [sadaqa],
      );

      expect(find.text(ar.insightDetailOwnDays), findsOneWidget);
      expect(find.text(ar.insightDetailByDay), findsNothing,
          reason: 'no seven-day wave for a two-day habit');
      expect(find.text('–'), findsNothing,
          reason: 'the five weekdays it never runs on are not drawn at all');
      expect(find.text('الاثنين'), findsOneWidget);
      expect(find.text('الخميس'), findsOneWidget);
      expect(find.text('6 من 8'), findsOneWidget);
      expect(find.text('4 من 8'), findsOneWidget);
      expect(recordCells(), findsNWidgets(16));
      // The header the rows add up to.
      expect(find.text('63%'), findsOneWidget);
      expect(find.text(ar.insightDetailRate(10, 16)), findsOneWidget);

      // Every square is a real day, oldest first, named in full.
      expect(find.bySemanticsLabel('الاثنين 27 يوليو · مكتمل'), findsOneWidget);
      expect(find.bySemanticsLabel('الاثنين 3 أغسطس · فارغ'), findsOneWidget);
      expect(find.bySemanticsLabel('الخميس 17 سبتمبر · فارغ'), findsOneWidget);
      expect(find.bySemanticsLabel('الخميس 10 سبتمبر · مكتمل'), findsOneWidget);

      for (final t in texts(tester)) {
        expect(t, isNot(matches(arabicIndic)), reason: t);
      }
      semantics.dispose();
    });

    testWidgets('a tapped square names its day underneath', (tester) async {
      final semantics = tester.ensureSemantics();
      await openSheet(
        tester,
        locale: 'ar',
        card: weekdayCard(ar, 'ar'),
        result: result,
        habits: [sadaqa],
      );
      expect(find.text(ar.habitStatsDayHint), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('الخميس 6 أغسطس · فارغ'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.text('الخميس 6 أغسطس · فارغ'), findsOneWidget);
      expect(find.text(ar.habitStatsDayHint), findsNothing);
      semantics.dispose();
    });

    testWidgets('English reads the same record left to right', (tester) async {
      await openSheet(
        tester,
        locale: 'en',
        card: weekdayCard(en, 'en'),
        result: result,
        habits: [sadaqa],
      );
      expect(find.text(en.insightDetailOwnDays), findsOneWidget);
      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('Thursday'), findsOneWidget);
      expect(find.text('6 of 8'), findsOneWidget);
      expect(find.text('4 of 8'), findsOneWidget);
      expect(recordCells(), findsNWidgets(16));
      // Oldest on the reading side: 27 July left of 14 September.
      final monday = tester.getCenter(find.text('Monday'));
      Offset cell(String day) => tester.getCenter(find.descendant(
            of: recordCells(),
            matching: find.text(day),
          ).first);
      expect(cell('27').dx, lessThan(cell('14').dx));
      expect(monday.dx, lessThan(cell('27').dx));
    });

    testWidgets('Arabic mirrors it: oldest on the right, under the name',
        (tester) async {
      await openSheet(
        tester,
        locale: 'ar',
        card: weekdayCard(ar, 'ar'),
        result: result,
        habits: [sadaqa],
      );
      final monday = tester.getCenter(find.text('الاثنين'));
      final count = tester.getCenter(find.text('6 من 8'));
      Offset cell(String day) => tester.getCenter(find.descendant(
            of: recordCells(),
            matching: find.text(day),
          ).first);
      expect(monday.dx, greaterThan(cell('27').dx));
      expect(cell('27').dx, greaterThan(cell('14').dx));
      expect(cell('14').dx, greaterThan(count.dx));
    });
  });

  group('a weekly quota', () {
    // «تمرين», four a week, done Saturday, Sunday and Monday: three of four.
    final training = habit('ex', 'تمرين', type: HabitFrequencyType.weekly, target: 4);
    final marks = <DateTime, SquareState>{
      for (final d in windowDays())
        if (d.weekday == DateTime.saturday ||
            d.weekday == DateTime.sunday ||
            d.weekday == DateTime.monday)
          d: SquareState.complete,
    };
    final quran = habit('qr', 'قراءة القرآن');
    final result = computeInsights(
      habits: [training, quran],
      days: docs({
        'ex': marks,
        'qr': {for (final d in windowDays()) d: SquareState.complete},
      }),
      now: at1400,
    );

    test('gets a weeks card, and never a weekday one', () {
      final cards =
          buildInsightCards(result: result, habits: [training, quran], s: ar, locale: 'ar');
      expect(cards.where((c) => c.$2 == InsightKind.weekdayMiss), isEmpty,
          reason: 'its blank days are the ends of short weeks, not a weekday');
      final weeks = cards.singleWhere((c) => c.$2 == InsightKind.quotaWeeks);
      expect(weeks.$1.$3, '"تمرين" وصلت هدفها 0 من 7 أسابيع');
      expect(weeks.$1.$4, 'ex');
      expect(weeks.$1.$5, isNull);
      // buildInsightHeadlines is the same list without the kinds.
      expect(
        buildInsightHeadlines(result: result, habits: [training, quran], s: ar, locale: 'ar'),
        cards.map((c) => c.$1).toList(),
      );
    });

    testWidgets('its sheet: sessions a week against the target, week by week',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final card =
          buildInsightCards(result: result, habits: [training, quran], s: ar, locale: 'ar')
              .singleWhere((c) => c.$2 == InsightKind.quotaWeeks);
      await openSheet(
        tester,
        locale: 'ar',
        card: card,
        result: result,
        habits: [training, quran],
      );
      expect(find.text(ar.insightDetailByWeek), findsOneWidget);
      expect(find.text(ar.insightQuotaAverage(4)), findsOneWidget);
      expect(find.text(ar.insightTipQuotaWeeks), findsOneWidget);
      expect(find.text(ar.insightDetailByDay), findsNothing);
      expect(find.text(ar.insightDetailCompare), findsNothing,
          reason: 'the weeks card is not the habit-vs-habit card');
      // Eight weeks, each three of four.
      expect(find.bySemanticsLabel('25 يوليو · 3 من 4'), findsOneWidget);
      expect(find.bySemanticsLabel('12 سبتمبر · 3 من 4'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'· 3 من 4$')), findsNWidgets(8));
      for (final t in texts(tester)) {
        expect(t, isNot(matches(arabicIndic)), reason: t);
      }
      semantics.dispose();
    });
  });

  testWidgets("a daily habit's weekday sheet keeps the wave", (tester) async {
    final daily = habit('d', 'أذكار الصباح');
    final result = computeInsights(
      habits: [daily],
      days: docs({
        'd': {
          for (final d in windowDays())
            if (d.weekday != DateTime.thursday) d: SquareState.complete,
        },
      }),
      now: at1400,
    );
    final card =
        buildInsightCards(result: result, habits: [daily], s: ar, locale: 'ar')
            .singleWhere((c) => c.$2 == InsightKind.weekdayMiss);
    await openSheet(
      tester,
      locale: 'ar',
      card: card,
      result: result,
      habits: [daily],
    );
    expect(find.text(ar.insightDetailByDay), findsOneWidget);
    expect(find.text(ar.insightDetailOwnDays), findsNothing);
    expect(recordCells(), findsNothing);
  });

  testWidgets('a caller that passes no kind still opens the right sheet',
      (tester) async {
    final result = computeInsights(
      habits: [sadaqa],
      days: docs({'sadaqa': sadaqaMarks}),
      now: at1400,
    );
    final card =
        buildInsightCards(result: result, habits: [sadaqa], s: ar, locale: 'ar')
            .singleWhere((c) => c.$2 == InsightKind.weekdayMiss);
    await openSheet(
      tester,
      locale: 'ar',
      card: card,
      result: result,
      habits: [sadaqa],
      passKind: false,
    );
    expect(find.text(ar.insightDetailOwnDays), findsOneWidget);
    expect(recordCells(), findsNWidgets(16));
  });
}
