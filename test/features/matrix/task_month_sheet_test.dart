// The Tasks page's month sheet (task_month_sheet.dart): the grid runs left
// to right with Saturday in the left column in Arabic too (Aziz's ruling for
// every month calendar), the markers say which days hold open tasks and
// which were all done, pick mode refuses the days that have gone, the
// «رجوع لليوم» footer shows only away from today, and the card fits the
// smallest phones this ships to in both languages.
//
// Under the real localization delegates, so DateFormat prints Arabic-Indic
// digits here the way it does in the app, and a raw pattern would show.
// "Today" is an injected clock (TaskMonthSheet.now), except in the one test
// that goes through showTaskMonthSheet, which reads the real one.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/core/utils/western_digits.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/widgets/task_month_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Wednesday 16 September 2026, mid-morning.
  final now = DateTime(2026, 9, 16, 10);
  const ar = S(Locale('ar'));
  const en = S(Locale('en'));

  MatrixTask task(
    String id, {
    String? plannedDay,
    bool isDone = false,
    DateTime? completedAt,
    DateTime? createdAt,
  }) =>
      MatrixTask(
        id: id,
        title: 'Task $id',
        quadrant: MatrixQuadrant.doFirst,
        isDone: isDone,
        createdAt: createdAt ?? DateTime(2026, 9, 10, 9),
        completedAt: completedAt,
        plannedDay: plannedDay,
        order: 0,
      );

  late Future<DateTime?> result;

  Future<void> open(
    WidgetTester tester, {
    Locale locale = const Locale('ar'),
    Size size = const Size(402, 874),
    double textScale = 1.0,
    required DateTime selected,
    List<MatrixTask> tasks = const [],
    bool pickMode = false,
    DateTime? clock,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              // The same presentation showTaskMonthSheet uses, with the
              // clock injected.
              onPressed: () => result = showModalBottomSheet<DateTime>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                useSafeArea: true,
                builder: (_) => TaskMonthSheet(
                  selected: selected,
                  tasks: tasks,
                  pickMode: pickMode,
                  now: clock ?? now,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder cell(DateTime day) => find.byWidgetPredicate(
        (w) =>
            w.runtimeType.toString() == '_DayCell' &&
            (w as dynamic).day == day,
      );

  testWidgets('Arabic: Saturday in the left column, its letter over it',
      (tester) async {
    await open(tester, selected: DateTime(2026, 9, 16));

    // Saturday 5 and Friday 11 September 2026 share a week.
    final sat = tester.getRect(cell(DateTime(2026, 9, 5)));
    final fri = tester.getRect(cell(DateTime(2026, 9, 11)));
    expect(sat.top, fri.top, reason: 'the same week, the same row');
    expect(sat.left, lessThan(fri.left),
        reason: 'Saturday leads on the left, as on the map');

    // The letters run the same way, each over its own column.
    final satLetter = DateFormat('EEEEE', 'ar').format(DateTime(2026, 9, 5));
    final friLetter = DateFormat('EEEEE', 'ar').format(DateTime(2026, 9, 11));
    final satLetterX = tester.getCenter(find.text(satLetter)).dx;
    final friLetterX = tester.getCenter(find.text(friLetter)).dx;
    expect(satLetterX, closeTo(sat.center.dx, 1));
    expect(friLetterX, closeTo(fri.center.dx, 1));

    // Western digits on the day numbers, under delegates that print
    // Arabic-Indic ones through DateFormat.
    expect(find.text('16'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) =>
          w is RichText && RegExp('[٠-٩]').hasMatch(w.text.toPlainText())),
      findsNothing,
    );
  });

  testWidgets('markers: a dot for open work, a tick for an all-done day',
      (tester) async {
    final handle = tester.ensureSemantics();
    await open(
      tester,
      locale: const Locale('en'),
      selected: DateTime(2026, 9, 16),
      tasks: [
        task('open', plannedDay: '2026-09-20'),
        task(
          'done',
          plannedDay: '2026-09-22',
          isDone: true,
          completedAt: DateTime(2026, 9, 22, 12),
        ),
        // Planned for the 25th, done early on the 23rd: both days show it,
        // and neither has anything open.
        task(
          'early',
          plannedDay: '2026-09-25',
          isDone: true,
          completedAt: DateTime(2026, 9, 23, 18),
        ),
      ],
    );

    Finder dotIn(DateTime day) => find.descendant(
          of: cell(day),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.constraints == const BoxConstraints.tightFor(width: 4, height: 4)),
        );
    Finder tickIn(DateTime day) => find.descendant(
          of: cell(day),
          matching: find.byIcon(Icons.check_rounded),
        );

    expect(dotIn(DateTime(2026, 9, 20)), findsOneWidget);
    expect(tickIn(DateTime(2026, 9, 20)), findsNothing);

    for (final day in [22, 23, 25]) {
      expect(tickIn(DateTime(2026, 9, day)), findsOneWidget,
          reason: 'September $day had tasks and all were done');
      expect(dotIn(DateTime(2026, 9, day)), findsNothing);
    }

    // An empty day draws nothing at all.
    expect(dotIn(DateTime(2026, 9, 24)), findsNothing);
    expect(tickIn(DateTime(2026, 9, 24)), findsNothing);

    // And each cell says so as one node, the full date first.
    expect(
      find.bySemanticsLabel(
          'Sunday, Sep 20 2026, ${en.matrixDayHasTasks}'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
          'Tuesday, Sep 22 2026, ${en.matrixDayAllDone}'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Thursday, Sep 24 2026'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('pick mode asks «لأي يوم؟» and refuses the days that have gone',
      (tester) async {
    await open(tester, selected: DateTime(2026, 9, 16), pickMode: true);
    expect(find.text(ar.matrixPickDay), findsOneWidget);

    // A past day is faded and a tap on it does nothing.
    expect(
      find.descendant(
        of: cell(DateTime(2026, 9, 10)),
        matching: find.byWidgetPredicate(
            (w) => w is Opacity && w.opacity == 0.35),
      ),
      findsOneWidget,
    );
    await tester.tap(cell(DateTime(2026, 9, 10)));
    await tester.pumpAndSettle();
    expect(find.text(ar.matrixPickDay), findsOneWidget,
        reason: 'a past day must not be pickable');

    // Today and later are.
    expect(
      find.descendant(
        of: cell(DateTime(2026, 9, 16)),
        matching: find.byWidgetPredicate(
            (w) => w is Opacity && w.opacity == 0.35),
      ),
      findsNothing,
    );
    await tester.tap(cell(DateTime(2026, 9, 20)));
    await tester.pumpAndSettle();
    expect(await result, DateTime(2026, 9, 20));
  });

  testWidgets('browsing has no heading and every day is open to a tap',
      (tester) async {
    await open(tester, selected: DateTime(2026, 9, 16));
    expect(find.text(ar.matrixPickDay), findsNothing);
    await tester.tap(cell(DateTime(2026, 9, 3)));
    await tester.pumpAndSettle();
    expect(await result, DateTime(2026, 9, 3));
  });

  // The grid is drawn left to right in Arabic too, but a screen reader
  // orders a row by the page's direction: right to left, so it read Friday
  // back to Saturday inside each week and then jumped about ten days ahead
  // at every row break. The days must be read in date order in both
  // languages, after the month's name and before the footer. The 30th is
  // selected so the «رجوع لليوم» footer is there to be read.
  for (final s in const [ar, en]) {
    final lang = s.locale.languageCode;
    testWidgets('$lang: a screen reader goes through the days in date order',
        (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, locale: s.locale, selected: DateTime(2026, 9, 30));
      final labels = [
        for (final node in tester.semantics.simulatedAccessibilityTraversal())
          node.label,
      ];
      final month = s.isAr ? 'سبتمبر' : 'Sep';
      final dayOf = s.isAr
          ? RegExp('^\\S+، (\\d+) $month')
          : RegExp('^\\S+, $month (\\d+)');
      final days = <int>[
        for (final label in labels)
          if (dayOf.firstMatch(label) case final m?) int.parse(m.group(1)!),
      ];
      expect(days, [for (var d = 1; d <= 30; d++) d]);

      final title = westernDate(DateTime(2026, 9), 'MMMM yyyy', lang);
      final first = labels.indexWhere((l) => dayOf.hasMatch(l));
      final last = labels.lastIndexWhere((l) => dayOf.hasMatch(l));
      expect(labels.indexOf(title), lessThan(first),
          reason: 'the month is named before its days');
      expect(labels.indexOf(s.matrixBackToToday), greaterThan(last),
          reason: 'the footer is read after the days');
      handle.dispose();
    });
  }

  group('«رجوع لليوم»', () {
    testWidgets('is hidden on today, in today\'s month', (tester) async {
      await open(tester, selected: DateTime(2026, 9, 16));
      expect(find.text(ar.matrixBackToToday), findsNothing);
    });

    testWidgets('shows when another day is selected, and returns today',
        (tester) async {
      await open(tester, selected: DateTime(2026, 9, 30));
      expect(find.text(ar.matrixBackToToday), findsOneWidget);
      await tester.tap(find.text(ar.matrixBackToToday));
      await tester.pumpAndSettle();
      expect(await result, DateTime(2026, 9, 16));
    });

    testWidgets('shows once the arrows leave today\'s month', (tester) async {
      await open(tester, selected: DateTime(2026, 9, 16));
      // The next-month arrow (drawn on the left in RTL, mirrored).
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.text(westernDate(DateTime(2026, 10), 'MMMM yyyy', 'ar')),
          findsOneWidget,
          reason: 'October is showing');
      expect(find.text(ar.matrixBackToToday), findsOneWidget);
    });
  });

  test('the range: the oldest task, at least three months back, a year ahead',
      () {
    final r = taskMonthRange(
      selected: DateTime(2026, 9, 16),
      tasks: [task('old', createdAt: DateTime(2025, 12, 30))],
      now: now,
    );
    expect(r.first, DateTime(2025, 12));
    expect(r.last, DateTime(2027, 9));

    final fresh = taskMonthRange(
      selected: DateTime(2026, 9, 16),
      tasks: const [],
      now: now,
    );
    expect(fresh.first, DateTime(2026, 6));

    // Pick mode starts at this month: older months would be all faded.
    final pick = taskMonthRange(
      selected: DateTime(2026, 9, 16),
      tasks: [task('old', createdAt: DateTime(2025, 12, 30))],
      now: now,
      pickMode: true,
    );
    expect(pick.first, DateTime(2026, 9));
    // Unless the selected day is older (a carried-over task being moved).
    final carried = taskMonthRange(
      selected: DateTime(2026, 7, 2),
      tasks: const [],
      now: now,
      pickMode: true,
    );
    expect(carried.first, DateTime(2026, 7));
  });

  test('taskDayTitle names today with its date and never says tomorrow', () {
    expect(taskDayTitle(DateTime(2026, 9, 16), ar, now: now),
        'اليوم، 16 سبتمبر');
    expect(taskDayTitle(DateTime(2026, 9, 16), en, now: now), 'Today, 16 Sep');
    expect(taskDayTitle(DateTime(2026, 9, 17), en, now: now),
        'Thursday, Sep 17');
    expect(taskDayTitle(DateTime(2026, 9, 17), ar, now: now),
        'الخميس، 17 سبتمبر');
    expect(taskDayTitle(DateTime(2027, 1, 4), en, now: now),
        'Monday, Jan 4, 2027');
    expect(taskDayTitle(DateTime(2027, 1, 4), ar, now: now),
        'الاثنين، 4 يناير 2027');
  });

  group('fits the smallest phones', () {
    // May 2026 starts on a Friday, the last column: six week rows, the
    // tallest a month gets. Pick mode adds the heading, and a selected day
    // away from today adds the footer.
    for (final size in const [Size(320, 568), Size(375, 667), Size(402, 874)]) {
      for (final locale in const [Locale('ar'), Locale('en')]) {
        for (final scale in const [1.0, 1.3]) {
          testWidgets(
              '${size.width.toInt()}x${size.height.toInt()} '
              '${locale.languageCode} at ${scale}x', (tester) async {
            await open(
              tester,
              locale: locale,
              size: size,
              textScale: scale,
              selected: DateTime(2026, 5, 20),
              clock: DateTime(2026, 5, 13, 10),
              pickMode: true,
              tasks: [task('a', plannedDay: '2026-05-20')],
            );
            expect(tester.takeException(), isNull);
            expect(cell(DateTime(2026, 5, 31)), findsOneWidget,
                reason: 'the sixth week row is built');
            final s = S(locale);
            final footer = tester.getRect(find.text(s.matrixBackToToday));
            expect(footer.bottom, lessThanOrEqualTo(size.height),
                reason: 'the footer is on screen');
            // The card scrolls rather than overflows: its last row can be
            // brought into view and tapped.
            await tester.ensureVisible(cell(DateTime(2026, 5, 31)));
            await tester.pumpAndSettle();
            await tester.tap(cell(DateTime(2026, 5, 31)));
            await tester.pumpAndSettle();
            expect(await result, DateTime(2026, 5, 31));
          });
        }
      }
    }
  });

  testWidgets('showTaskMonthSheet on the real clock returns the tapped day',
      (tester) async {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showTaskMonthSheet(
              context,
              selected: day,
              tasks: const [],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(en.matrixBackToToday), findsNothing);
    await tester.tap(cell(day));
    await tester.pumpAndSettle();
    expect(await result, day);
  });
}
