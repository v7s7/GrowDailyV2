// The 14-day score line on ProgressHubScreen
// (lib/features/profile/screens/progress_day_chart.dart).
//
// ── What is actually at risk here ────────────────────────────────────────
// The axis MIRRORS: oldest day at the start of the reading direction, today
// at the end. Left-to-right in English, right-to-left in Arabic, matching
// the Grid's week header and the reports matrix, which both run newest
// toward the leading edge.
//
// That makes the tap index a trap, because two independent things have to
// mirror together: the painter's own `isRtl` (Canvas coordinates are always
// literal pixels and never auto-mirror) and the hit test's `width - dx`.
// Fix one and forget the other and every tap silently opens the WRONG DAY,
// with no crash and nothing on screen to show for it. year_strip.dart keeps
// the same pair in step deliberately (YearStripPainter's index mirror against
// yearStripDayAt's `1 - dxFraction`). These tests are the alarm.
//
// So the tests that matter assert BOTH ends in BOTH directions.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/utils/western_digits.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/milestones/reports/day_score.dart';
import 'package:grow_daily_v2/features/milestones/reports/habit_day_marks.dart';
import 'package:grow_daily_v2/features/profile/screens/progress_day_chart.dart';
import 'package:grow_daily_v2/features/profile/screens/progress_hub_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // The scrub readout prints a real weekday and month name through
    // DateFormat, which throws for any locale whose symbol data has not
    // been loaded. Nothing else in this file needed it until the readout
    // existed.
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  final days = [for (var i = 0; i < 14; i++) DateTime(2026, 8, 22 + i)];

  List<DayScore> scoresOf(List<int> done, {List<int>? owed}) => [
        for (var i = 0; i < done.length; i++)
          DayScore(
            day: days[i],
            done: done[i],
            credit: done[i].toDouble(),
            owed: owed?[i] ?? 10,
            failed: 0,
            rested: 0,
          ),
      ];

  // The real fortnight off Aziz's account on 4 Sep 2026, the numbers the old
  // bar chart printed, so the fixture is a shape that actually happened.
  final real = scoresOf(const [2, 2, 2, 3, 1, 1, 3, 0, 0, 3, 2, 4, 2, 2]);

  // A real locale, not a bare Directionality: the readout prints Arabic
  // copy and Arabic weekday names through S and DateFormat, so a test that
  // only flipped the direction would assert against English strings while
  // believing it was exercising the Arabic path.
  Future<void> pump(
    WidgetTester tester, {
    required List<DayScore> scores,
    required void Function(DayScore) onTap,
    TextDirection direction = TextDirection.rtl,
    double width = 340,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          locale: Locale(direction == TextDirection.rtl ? 'ar' : 'en'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: DayScoreChart(
                  scores: scores,
                  todayIndex: scores.length - 1,
                  onDayTap: onTap,
                ),
              ),
            ),
          ),
        ),
      );

  group('the axis mirrors with the reading direction', () {
    testWidgets('[LTR] oldest is on the left, today on the right',
        (tester) async {
      DayScore? tapped;
      await pump(
        tester,
        scores: real,
        onTap: (s) => tapped = s,
        direction: TextDirection.ltr,
      );
      final box = tester.getRect(find.byType(DayScoreChart));

      await tester.tapAt(Offset(box.left + 2, box.center.dy));
      await tester.pump();
      expect(tapped?.day, days.first);

      await tester.tapAt(Offset(box.right - 2, box.center.dy));
      await tester.pump();
      expect(tapped?.day, days.last);
    });

    testWidgets('[RTL] today is on the left, oldest on the right',
        (tester) async {
      // The whole point of the mirror. In Arabic the Grid's week header runs
      // Saturday-on-the-right and the reports matrix puts the newest column
      // leftmost, so a chart with the past on the left was the one surface
      // in the app where moving left meant going BACK in time.
      DayScore? tapped;
      await pump(
        tester,
        scores: real,
        onTap: (s) => tapped = s,
        direction: TextDirection.rtl,
      );
      final box = tester.getRect(find.byType(DayScoreChart));

      await tester.tapAt(Offset(box.left + 2, box.center.dy));
      await tester.pump();
      expect(tapped?.day, days.last, reason: 'newest leads in RTL');

      await tester.tapAt(Offset(box.right - 2, box.center.dy));
      await tester.pump();
      expect(tapped?.day, days.first);
    });

    for (final direction in TextDirection.values) {
      testWidgets('[$direction] every column opens its own day, in order',
          (tester) async {
        // The off-by-one guard, and the guard against mirroring the paint
        // without the tap. A `.round()` instead of `.floor()`, or an index
        // taken against (n - 1) rather than n, still passes both edge tests
        // above and is wrong for every column in between. A half-applied
        // mirror passes neither, but this is what says so loudly.
        final opened = <DateTime>[];
        await pump(
          tester,
          scores: real,
          onTap: (s) => opened.add(s.day),
          direction: direction,
        );

        final box = tester.getRect(find.byType(DayScoreChart));
        final columnWidth = box.width / real.length;
        for (var i = 0; i < real.length; i++) {
          await tester.tapAt(
            Offset(box.left + columnWidth * (i + 0.5), box.center.dy),
          );
          await tester.pump();
        }

        expect(
          opened,
          direction == TextDirection.rtl ? days.reversed.toList() : days,
        );
      });
    }
  });

  group('what the reader sees', () {
    testWidgets('each day prints its own done count, ASCII in Arabic too',
        (tester) async {
      await pump(tester, scores: scoresOf(const [4, 7, 9, 3, 7]), onTap: (_) {});
      // Interpolated, never DateFormat: routed through intl this axis painted
      // Arabic-Indic digits directly above ASCII ones on the same columns.
      for (final label in ['4', '7', '9', '3']) {
        expect(find.text(label), findsWidgets);
      }
      // And the day-of-month row underneath.
      expect(find.text('22'), findsOneWidget);
      expect(find.text('26'), findsOneWidget);
    });

    testWidgets('an all-zero fortnight still renders every column',
        (tester) async {
      await pump(tester, scores: scoresOf(List.filled(14, 0)), onTap: (_) {});
      expect(find.text('0'), findsNWidgets(14));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a single day does not divide by zero', (tester) async {
      await pump(tester, scores: scoresOf(const [1]), onTap: (_) {});
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty window renders nothing rather than throwing',
        (tester) async {
      await pump(tester, scores: const [], onTap: (_) {});
      expect(tester.takeException(), isNull);
    });
  });

  group('the shared axis', () {
    test('is the tallest thing in the window, obligation or achievement', () {
      expect(
        DayScoreLinePainter.axisMaxOf(scoresOf(const [1, 2], owed: const [3, 9])),
        9,
      );
    });

    test('never falls below 1, so an empty window cannot divide by zero', () {
      expect(
        DayScoreLinePainter.axisMaxOf(scoresOf(const [0, 0], owed: const [0, 0])),
        1,
      );
    });

    test('grows to fit a day that beat its own obligation', () {
      // A quota habit done on a day it did not owe puts credit above owed.
      // Without this the point would be clamped flat against the ceiling.
      final beat = [
        DayScore(
          day: days.first,
          done: 4,
          credit: 4,
          owed: 2,
          failed: 0,
          rested: 0,
        ),
      ];
      expect(DayScoreLinePainter.axisMaxOf(beat), 4);
    });
  });

  group('the day sheet row glyph is keyed on the MARK, never a tap count', () {
    // The regression this group exists for, found on device on 27 August:
    // the row icon fell through to `completions > 0` for anything that was
    // not skipped/failed/bonus. A habit finished by painting a green square
    // on the Grid records NO completion count, so the sheet drew a hollow
    // circle against it while its own header counted it as done. Three green
    // habits, one checkmark, and a header reading «تم إنجاز 3 من 6».
    test('nothing that earned credit renders as the empty glyph', () {
      for (final mark in SquareState.values) {
        if (markCredit(mark) <= 0) continue;
        expect(
          markRowIcon(mark),
          isNot(kUnmarkedRowIcon),
          reason: '$mark earns credit and must not look untouched',
        );
      }
    });

    test('only an unmarked habit gets the empty glyph', () {
      for (final mark in SquareState.values) {
        expect(
          markRowIcon(mark) == kUnmarkedRowIcon,
          mark == SquareState.none,
          reason: '$mark',
        );
      }
    });

    test('every mark is visually distinguishable from every other', () {
      final glyphs = {for (final m in SquareState.values) markRowIcon(m)};
      expect(glyphs.length, SquareState.values.length);
    });

    test('a rest and a failure never look like a plain blank', () {
      // These two are the states the app spent a whole design pass making
      // distinct from an empty square; collapsing them here would undo it.
      expect(markRowIcon(SquareState.skipped), isNot(kUnmarkedRowIcon));
      expect(markRowIcon(SquareState.failed), isNot(kUnmarkedRowIcon));
      expect(
        markRowIcon(SquareState.skipped),
        isNot(markRowIcon(SquareState.failed)),
      );
    });
  });

  group('the range filter and how the chart thins out for it', () {
    test('the three ranges are the ones that need no premium wall', () {
      // historyFloorFor returns null by construction for any window shorter
      // than about two months, so 7/14/30 are exactly the spans that can be
      // free with no muted days and no explaining. A 90-day segment would be
      // free in July and walled in December with nothing on screen to say
      // why, which is the reason there isn't one.
      expect(ProgressRange.values.map((r) => r.days), [7, 14, 30]);
      for (final range in ProgressRange.values) {
        expect(range.days, lessThan(59));
      }
    });

    testWidgets('a week keeps every done-count and every day number',
        (tester) async {
      await pump(
        tester,
        scores: scoresOf(const [4, 7, 9, 3, 7, 0, 6]),
        onTap: (_) {},
      );
      for (final label in ['4', '7', '9', '3', '6']) {
        expect(find.text(label), findsWidgets);
      }
      for (var i = 0; i < 7; i++) {
        expect(find.text('${days[i].day}'), findsWidgets);
      }
    });

    testWidgets('a month drops the done-counts rather than crowding them',
        (tester) async {
      // At 340pt a month is about 11pt per column, which cannot hold two
      // digits. Thinning the counts instead of dropping them would leave
      // numbers hovering over some points and not others, which reads as
      // missing data rather than as a sampled axis.
      final month = [
        for (var i = 0; i < 30; i++)
          DayScore(
            day: DateTime(2026, 8, 6 + i),
            done: 5,
            credit: 5,
            owed: 10,
            failed: 0,
            rested: 0,
          ),
      ];
      await pump(tester, scores: month, onTap: (_) {});
      expect(find.text('5'), findsNothing, reason: 'counts are dropped');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a month still labels today, and thins the rest',
        (tester) async {
      final month = [
        for (var i = 0; i < 30; i++)
          DayScore(
            day: DateTime(2026, 8, 6 + i),
            done: 0,
            credit: 0,
            owed: 4,
            failed: 0,
            rested: 0,
          ),
      ];
      await pump(tester, scores: month, onTap: (_) {});
      // An axis with no labels at all cannot be read, so the day numbers
      // thin rather than vanish, counted BACK from today so today always
      // survives whatever the step lands on.
      expect(find.text('${month.last.day.day}'), findsOneWidget);
      final shown = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => (t.data ?? '').isNotEmpty)
          .length;
      expect(shown, lessThan(30), reason: 'thinned');
      expect(shown, greaterThan(4), reason: 'but still readable as an axis');
    });

    testWidgets('every column of a month is still tappable, in order',
        (tester) async {
      final month = [
        for (var i = 0; i < 30; i++)
          DayScore(
            day: DateTime(2026, 8, 6 + i),
            done: 1,
            credit: 1,
            owed: 3,
            failed: 0,
            rested: 0,
          ),
      ];
      final opened = <DateTime>[];
      await pump(
        tester,
        scores: month,
        onTap: (s) => opened.add(s.day),
        direction: TextDirection.rtl,
      );
      final box = tester.getRect(find.byType(DayScoreChart));
      final columnWidth = box.width / month.length;
      for (var i = 0; i < month.length; i++) {
        await tester.tapAt(
          Offset(box.left + columnWidth * (i + 0.5), box.center.dy),
        );
        await tester.pump();
      }
      // Dropping the counts must not cost the day sheet, which is where the
      // exact figure for any one day lives once the numbers are off screen.
      expect(opened, month.reversed.map((s) => s.day).toList());
    });
  });

  group('DayAxis: the single flip the painter and the tap both go through', () {
    // The bug this class exists to make impossible: mirror the paint and
    // forget the tap (or the reverse) and the chart is drawn one way and
    // read the other. Every tap opens the wrong day, nothing crashes, and
    // nothing on screen says so.
    DayAxis axis(bool isRtl) => DayAxis(width: 280, count: 14, isRtl: isRtl);

    test('LTR puts the oldest day at the left edge', () {
      expect(axis(false).center(0), lessThan(140));
      expect(axis(false).center(13), greaterThan(140));
    });

    test('RTL puts the oldest day at the RIGHT edge', () {
      expect(axis(true).center(0), greaterThan(140));
      expect(axis(true).center(13), lessThan(140));
    });

    test('a point and a tap on that point agree, in both directions', () {
      // The round trip. This is the assertion that fails the instant one
      // half of the mirror is removed, whichever half it is.
      for (final isRtl in [false, true]) {
        final a = axis(isRtl);
        for (var i = 0; i < 14; i++) {
          expect(a.indexAt(a.center(i)), i, reason: 'isRtl=$isRtl index=$i');
        }
      }
    });

    test('the two directions really are mirror images of each other', () {
      for (var i = 0; i < 14; i++) {
        expect(axis(true).center(i), closeTo(280 - axis(false).center(i), 1e-9));
      }
    });

    test('a hit outside the plot clamps instead of throwing', () {
      for (final isRtl in [false, true]) {
        expect(axis(isRtl).indexAt(-40), inInclusiveRange(0, 13));
        expect(axis(isRtl).indexAt(9999), inInclusiveRange(0, 13));
      }
    });
  });

  group('the trend line under the title', () {
    final en = S(const Locale('en'));

    List<DayScore> run(List<double> credit) => [
          for (var i = 0; i < credit.length; i++)
            DayScore(
              day: DateTime(2026, 8, 22 + i),
              done: credit[i].round(),
              credit: credit[i],
              owed: 4,
              failed: 0,
              rested: 0,
            ),
        ];

    String line(List<DayScore> scores,
            {bool isLoading = false, bool hasError = false}) =>
        progressTrendLine(en, scores,
            isLoading: isLoading, hasError: hasError);

    test('an empty window says so instead of congratulating anyone', () {
      // `later >= earlier` alone scores an empty window as 0 >= 0 and comes
      // out as "holding strong", which is the app congratulating someone on
      // a chart with nothing in it. That makes every other encouraging line
      // on the screen read as noise.
      expect(line(run(const [0, 0, 0, 0, 0, 0])), en.noProgressYet);
    });

    test('a failed read is not an empty window', () {
      // A network failure produces exactly the zeros an empty fortnight
      // does, and an empty state is an assertion about the person.
      expect(line(run(const [0, 0]), hasError: true), en.monthlyStoryLoadFailed);
      expect(line(run(const [3, 3]), isLoading: true), en.loadingReport);
    });

    test('improving reads as holding, declining reads as start again', () {
      expect(line(run(const [1, 1, 1, 3, 3, 3])), en.holdingStrong);
      expect(line(run(const [3, 3, 3, 1, 1, 1])), en.startAgain);
    });

    test('it compares CREDIT, so half days are not free', () {
      // Same done-count on both halves, but the later half is all جزئي.
      // Counting whole habits would call that level; it is not.
      final scores = [
        ...run(const [1, 1, 1]),
        ...run(const [0.5, 0.5, 0.5]),
      ];
      expect(line(scores), en.startAgain);
    });

    test('the two halves are equal in length on an odd window', () {
      // 7 days split 3 against 4 would tilt every week toward good news by
      // construction. The middle day is dropped instead.
      final week = run(const [3, 3, 3, 0, 1, 1, 1]);
      expect(line(week), en.startAgain,
          reason: 'first three total 9, last three total 3');
    });

    test('a one-day window does not divide itself in half', () {
      expect(line(run(const [2])), en.holdingStrong);
      expect(() => line(const []), returnsNormally);
    });
  });

  group('the scrub readout: what makes a month readable', () {
    // At 30 days a column is about 11pt, so the per-day counts are dropped
    // and the day labels thin to every other one. Without this row a month
    // is a shape with nothing to read off it, which is the whole reason the
    // readout exists.
    List<DayScore> month() => [
          for (var i = 0; i < 30; i++)
            DayScore(
              day: DateTime(2026, 8, 6 + i),
              done: i,
              credit: i.toDouble(),
              owed: 30,
              failed: 0,
              rested: 0,
            ),
        ];

    String dateOf(DayScore score, {bool isAr = true}) => weekdayDateLabel(
          score.day,
          isAr: isAr,
          locale: isAr ? 'ar' : 'en',
        );

    testWidgets('it opens on today, so the row is never blank',
        (tester) async {
      final scores = month();
      await pump(tester, scores: scores, onTap: (_) {});
      expect(find.text(dateOf(scores.last)), findsOneWidget);
      expect(find.text('29 من 30'), findsOneWidget);
    });

    testWidgets('dragging moves it to the day under the finger, in RTL',
        (tester) async {
      final scores = month();
      await pump(
        tester,
        scores: scores,
        onTap: (_) {},
        direction: TextDirection.rtl,
      );
      final box = tester.getRect(find.byType(DayScoreChart));

      // In Arabic the oldest day is at the RIGHT edge, so dragging there
      // has to walk the readout backwards in time.
      final gesture = await tester.startGesture(
        Offset(box.center.dx, box.center.dy),
      );
      await tester.pump();
      await gesture.moveTo(Offset(box.right - 2, box.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(find.text(dateOf(scores.first)), findsOneWidget);
      expect(find.text('0 من 30'), findsOneWidget);
    });

    testWidgets('the selection is sticky once the finger lifts',
        (tester) async {
      // Snapping back to today on release would mean you can never actually
      // read the day you scrubbed to, which defeats the point.
      final scores = month();
      await pump(tester, scores: scores, onTap: (_) {});
      final box = tester.getRect(find.byType(DayScoreChart));

      // RIGHT edge, because pump() defaults to Arabic and the mirror puts
      // the OLDEST day there. Dragging to the left edge would land back on
      // today, which is where the readout already started and would prove
      // nothing about stickiness.
      final gesture = await tester.startGesture(box.center);
      await tester.pump();
      await gesture.moveTo(Offset(box.right - 2, box.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text(dateOf(scores.first)), findsOneWidget,
          reason: 'still showing the scrubbed day, not today');
    });

    testWidgets('a DRAG must not open the day sheet', (tester) async {
      // BaseTapGestureRecognizer fires onTapDown from didExceedDeadline as
      // well as from acceptGesture, so a finger that rests for 100ms before
      // moving gets a down callback even though the horizontal drag wins.
      // With the sheet on onTapDown, every unhurried scrub opened a modal
      // over the chart it was scrubbing.
      final opened = <DateTime>[];
      await pump(tester, scores: month(), onTap: (s) => opened.add(s.day));
      final box = tester.getRect(find.byType(DayScoreChart));

      final gesture = await tester.startGesture(box.center);
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.moveTo(Offset(box.left + 2, box.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(opened, isEmpty);
    });

    testWidgets('a TAP still opens the day sheet', (tester) async {
      final scores = month();
      final opened = <DateTime>[];
      await pump(tester, scores: scores, onTap: (s) => opened.add(s.day));
      final box = tester.getRect(find.byType(DayScoreChart));
      await tester.tapAt(Offset(box.left + 2, box.center.dy));
      await tester.pump();
      expect(opened, [scores.last.day], reason: 'RTL: leading edge is today');
    });

    testWidgets('tapping the readout opens whatever it is showing',
        (tester) async {
      // The precise route into a day at a month's density, where an 11pt
      // tap target is a coin toss between two neighbours: scrub until the
      // readout says the day you meant, then open it from there.
      final scores = month();
      final opened = <DateTime>[];
      await pump(tester, scores: scores, onTap: (s) => opened.add(s.day));
      final box = tester.getRect(find.byType(DayScoreChart));

      final gesture = await tester.startGesture(box.center);
      await tester.pump();
      await gesture.moveTo(Offset(box.right - 2, box.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(opened, isEmpty);

      await tester.tap(find.text(dateOf(scores.first)));
      await tester.pump();
      expect(opened, [scores.first.day]);
    });

    testWidgets('a day that owed nothing never reads as a zero',
        (tester) async {
      await pump(
        tester,
        scores: [
          DayScore(
            day: days.first,
            done: 0,
            credit: 0,
            owed: 0,
            failed: 0,
            rested: 0,
          ),
        ],
        onTap: (_) {},
      );
      expect(find.text('0 من 0'), findsNothing);
      expect(find.text(S(const Locale('ar')).progressNothingDueShort),
          findsOneWidget);
    });

    testWidgets('a rest day says so rather than "nothing due"',
        (tester) async {
      // A rest is a choice somebody made. Folding it into "nothing was due"
      // is the exact erasure the تخطّي state exists to prevent.
      await pump(
        tester,
        scores: [
          DayScore(
            day: days.first,
            done: 0,
            credit: 0,
            owed: 0,
            failed: 0,
            rested: 3,
          ),
        ],
        onTap: (_) {},
      );
      expect(find.text(S(const Locale('ar')).progressRestedShort),
          findsOneWidget);
    });
  });
}
