// The Insights detail sheet's own lines, on the numbers of the screenshot
// that raised them (2026-09-18): «تحتاج دفعة: "تمرين"», done on 3 of its 11
// owed days, beside «قراءة القرآن» on 9 of 9.
//
// Three lines on that sheet were wrong:
//  * «أقل بـ73 نقطة من أثبت عاداتك» was a percentage-point gap, 100% less
//    27%, worded with نقطة, the word this app pays XP in, so it read as 73
//    XP. It was also only the two bars under it subtracted. The sentence now
//    quotes both rates, the same two the bars print.
//  * The window's dates came from DateFormat('MMM d'), which in Arabic puts
//    the month first and, once flutter_localizations has loaded its date
//    symbols (as the app does), prints Arabic-Indic digits: «آخر 8 أسابيع ·
//    يوليو ٢٥ – سبتمبر ١٨», two kinds of digit on one line.
//  * The count under the big percent put يوم after every number, so a habit
//    owed nine days read «9 من 9 يوم».
//
// The sheets are pumped under the real localization delegates on purpose:
// they are what swap the Arabic-Indic digits in, and a plain DateFormat call
// in a bare test process never shows them.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/insights/insight_engine.dart';
import 'package:grow_daily_v2/features/insights/insights_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ar = S(Locale('ar'));
  const en = S(Locale('en'));

  IslamicHabitTemplate habit(String id, String name) => IslamicHabitTemplate(
        id: id,
        name: name,
        description: '',
        category: HabitCategory.faith,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        scheduledWeekdays: const [],
        hasTimer: false,
        xpReward: 10,
        goldReward: 1,
        createdAt: DateTime(2026, 7, 1),
      );

  HabitPattern pattern(String id, int completed, int scheduled) =>
      HabitPattern(id)
        ..completed = completed
        ..scheduled = scheduled;

  Future<void> openSheet(
    WidgetTester tester, {
    required String locale,
    required InsightHeadline headline,
    required InsightsResult result,
    required List<IslamicHabitTemplate> habits,
  }) async {
    tester.view.physicalSize = const Size(400 * 3, 1400 * 3);
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
                headline: headline,
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

  final arabicIndic = RegExp('[٠-٩]');

  // The screenshot's sheet, and the other kind of habit sheet that carried
  // the same «نقطة» sentence.
  final exercise = habit('ex', 'تمرين');
  final quran = habit('qr', 'قراءة القرآن');
  final needsPush = InsightsResult(
    patterns: {'ex': pattern('ex', 3, 11), 'qr': pattern('qr', 9, 9)},
    strongestWeekday: null,
    overallScheduledByWeekday: const {},
    overallCompletedByWeekday: const {},
    mostConsistentHabitId: 'qr',
    needsPushHabitId: 'ex',
    totalSamples: 20,
  );
  InsightHeadline needsPushHeadline(S s, String name) =>
      (Icons.favorite_border_rounded, Colors.orange, s.insightNeedsPush(name),
          'ex', null);

  group('the comparison sentence', () {
    test('quotes both rates, never a gap worded as points', () {
      expect(ar.insightNeedsPushCompare('قراءة القرآن', 27, 100),
          '27% مقابل 100% في أثبت عاداتك، "قراءة القرآن".');
      expect(en.insightNeedsPushCompare('Reading Quran', 27, 100),
          '27% vs 100% for your most consistent habit, "Reading Quran".');
      expect(ar.insightMostConsistentCompare('الصدقة', 85, 65),
          '85% مقابل 65% في أقرب عادة لها، "الصدقة".');
      expect(en.insightMostConsistentCompare('Charity', 85, 65),
          '85% vs 65% for your next closest habit, "Charity".');
      for (final line in [
        ar.insightNeedsPushCompare('x', 1, 2),
        ar.insightMostConsistentCompare('x', 2, 1),
        en.insightNeedsPushCompare('x', 1, 2),
        en.insightMostConsistentCompare('x', 2, 1),
      ]) {
        expect(line, isNot(contains('نقطة')), reason: 'نقطة is the XP word');
        expect(line.toLowerCase(), isNot(contains('point')));
      }
    });

    testWidgets('needs a push: the numbers are the ones on the bars',
        (tester) async {
      await openSheet(
        tester,
        locale: 'ar',
        headline: needsPushHeadline(ar, 'تمرين'),
        result: needsPush,
        habits: [exercise, quran],
      );
      expect(find.text('27% مقابل 100% في أثبت عاداتك، "قراءة القرآن".'),
          findsOneWidget);
      expect(find.text('27%  ·  3/11'), findsOneWidget);
      expect(find.text('100%  ·  9/9'), findsOneWidget);
      expect(texts(tester).where((t) => t.contains('نقطة')), isEmpty,
          reason: 'nothing on this sheet is XP');
    });

    testWidgets('most consistent: itself against the runner-up, rounded '
        'as the bars round', (tester) async {
      // 6 of 7 is 85.7%, 5 of 8 exactly 62.5%: both round, and the sentence
      // has to land where the bars do (86 and 63), not a point either side.
      final result = InsightsResult(
        patterns: {
          'a': pattern('a', 6, 7),
          'b': pattern('b', 5, 8),
          'c': pattern('c', 1, 9),
        },
        strongestWeekday: null,
        overallScheduledByWeekday: const {},
        overallCompletedByWeekday: const {},
        mostConsistentHabitId: 'a',
        needsPushHabitId: 'c',
        totalSamples: 24,
      );
      await openSheet(
        tester,
        locale: 'en',
        headline: (Icons.verified_rounded, Colors.green,
            en.insightMostConsistent('Quran'), 'a', null),
        result: result,
        habits: [habit('a', 'Quran'), habit('b', 'Charity'), habit('c', 'Run')],
      );
      expect(
          find.text('86% vs 63% for your next closest habit, "Charity".'),
          findsOneWidget);
      expect(find.text('86%  ·  6/7'), findsOneWidget);
      expect(find.text('63%  ·  5/8'), findsOneWidget);
    });
  });

  group('the window line', () {
    testWidgets('Arabic: the day before the month, in the digits of the 8',
        (tester) async {
      await openSheet(
        tester,
        locale: 'ar',
        headline: needsPushHeadline(ar, 'تمرين'),
        result: needsPush,
        habits: [exercise, quran],
      );
      final line =
          texts(tester).singleWhere((t) => t.startsWith('آخر 8 أسابيع'));
      expect(line, isNot(matches(arabicIndic)));
      expect(line, matches(RegExp(r'^آخر 8 أسابيع · \d{1,2} \S+ – \d{1,2} \S+$')),
          reason: '«25 يوليو – 18 سبتمبر», not «يوليو 25 – سبتمبر 18»');
    });

    testWidgets('English keeps its month-first dates', (tester) async {
      await openSheet(
        tester,
        locale: 'en',
        headline: needsPushHeadline(en, 'Exercise'),
        result: needsPush,
        habits: [habit('ex', 'Exercise'), habit('qr', 'Reading Quran')],
      );
      final line =
          texts(tester).singleWhere((t) => t.startsWith('Last 8 weeks'));
      expect(line,
          matches(RegExp(r'^Last 8 weeks · [A-Z][a-z]{2} \d{1,2} – [A-Z][a-z]{2} \d{1,2}$')));
    });
  });

  group('the count under the big percent', () {
    test('أيام after 3 to 10, يوم after the rest', () {
      expect(ar.insightDetailRate(9, 9), '9 من 9 أيام');
      expect(ar.insightDetailRate(0, 3), '0 من 3 أيام');
      expect(ar.insightDetailRate(7, 10), '7 من 10 أيام');
      expect(ar.insightDetailRate(3, 11), '3 من 11 يوم',
          reason: 'the screenshot line, which was already right');
      expect(ar.insightDetailRate(20, 56), '20 من 56 يوم');
      expect(ar.insightDetailRate(90, 103), '90 من 103 أيام');
      expect(en.insightDetailRate(9, 9), '9 of 9 days');
    });

    testWidgets('on the sheet of a habit owed nine days', (tester) async {
      await openSheet(
        tester,
        locale: 'ar',
        headline: (Icons.verified_rounded, Colors.green,
            ar.insightMostConsistent('قراءة القرآن'), 'qr', null),
        result: needsPush,
        habits: [exercise, quran],
      );
      expect(find.text('9 من 9 أيام'), findsOneWidget);
      expect(find.text('9 من 9 يوم'), findsNothing);
    });
  });
}
