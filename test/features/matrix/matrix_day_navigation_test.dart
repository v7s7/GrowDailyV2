// The Tasks page's day navigator (matrix_screen.dart, Aziz's option B): the
// page title gave way to [previous][the day ⌄][next], the «اليوم» segment is
// the way back to today (no separate today button: "we already have a
// button for today"), the date opens the month, and every board, the
// expanded quadrant and the adds all file a task by task_day.dart's rule.
//
// Everything is measured off the real MatrixScreen. Days come from the real
// clock (the screen reads dayClockSourceProvider, which is DateTime.now
// here), and every assertion names its days relative to that same today, so
// the hour the suite runs at does not matter.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/core/utils/western_digits.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';
import 'package:grow_daily_v2/features/matrix/screens/matrix_screen.dart';
import 'package:grow_daily_v2/features/matrix/task_day.dart';
import 'package:grow_daily_v2/features/matrix/widgets/add_task_sheet.dart';
import 'package:grow_daily_v2/features/matrix/widgets/quadrant_card.dart';
import 'package:grow_daily_v2/features/matrix/widgets/task_month_sheet.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

const _ar = S(Locale('ar'));
const _en = S(Locale('en'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ProviderContainer container;

  // One guest store for the file, opened once in the real async zone (the
  // same arrangement as matrix_filter_row_layout_test.dart, and for the
  // same reason: a Hive open or delete awaited around a testWidgets body
  // deadlocks). Each test empties the board before it seeds it.
  setUpAll(() async {
    // matrixRowMeta's pure tests format dates before any MaterialApp has
    // loaded the localization delegates' date symbols.
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
    tmp = await Directory.systemTemp.createTemp('matrix_day_nav_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
  });

  late Future<bool> Function() realAsk;
  // The wall clock the screen reads (dayClockSourceProvider): the real one
  // unless a test sets it.
  DateTime? wall;
  setUp(() async {
    // The real ask writes its answer to Hive; never inside a test body.
    realAsk = addTaskPermissionAsk;
    addTaskPermissionAsk = () async => true;
    wall = null;
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumAccessProvider.overrideWithValue(false),
        dayClockSourceProvider
            .overrideWithValue(() => wall ?? DateTime.now()),
      ],
    );
    await container.read(authStateProvider.future);
  });

  tearDown(() {
    addTaskPermissionAsk = realAsk;
    container.dispose();
  });

  tearDownAll(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime inDays(int n) => DateTime(today.year, today.month, today.day + n);

  MatrixTask task(
    String title, {
    MatrixQuadrant quadrant = MatrixQuadrant.doFirst,
    DateTime? planned,
    DateTime? createdAt,
    DateTime? anchor,
    bool isFav = false,
  }) =>
      MatrixTask(
        id: title,
        title: title,
        quadrant: quadrant,
        isDone: false,
        createdAt: createdAt ?? now,
        isFav: isFav,
        reminderAts: anchor == null ? const [] : [anchor],
        reminderAnchorAt: anchor,
        plannedDay: planned == null ? null : dayKey(planned),
        order: 0,
      );

  /// Fixed frames, never pumpAndSettle: an empty quadrant's "+" pulses
  /// forever (same helper as matrix_add_task_test.dart).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpMatrix(
    WidgetTester tester, {
    Locale locale = const Locale('ar'),
    Size size = const Size(402, 874),
    double? textScale,
    List<MatrixTask> tasks = const [],
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    if (textScale != null) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    final notifier = container.read(matrixProvider.notifier);
    // Let the load land first, then empty the board and seed it. Seeding
    // before it landed used to make the load stand aside, which is what hid
    // the tasks earlier tests had saved to the shared store; the load merges
    // now (mergeLoadedTasks), so they would come back. Not by awaiting the
    // box in setUp: an earlier test's save is still queued there, inside its
    // fake-async zone, and never completes.
    await tester.pump();
    notifier.deleteMany(
      container.read(matrixProvider).tasks.map((t) => t.id).toSet(),
    );
    notifier.restoreMany(tasks);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ar'), Locale('en')],
          theme: GameTheme.light,
          home: const MatrixScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  /// Ends a test with the tree gone, so the screen's own midnight timer is
  /// cancelled and the snackbar and sheet animations finish.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await settle(tester);
  }

  Finder next(S s) => find.byTooltip(s.matrixNextDay);
  Finder prev(S s) => find.byTooltip(s.matrixPrevDay);

  /// The colour a segment's label is drawn in: goldInk when lit, textSec
  /// when not (see _FilterSegment).
  Color? labelColor(WidgetTester tester, Finder f) =>
      DefaultTextStyle.of(tester.element(f)).style.color;

  /// The header title's own colour: textPrimary on the day lens, textSec
  /// (dimmed) under Fav, All or a chip.
  Color? titleColor(WidgetTester tester, String title) =>
      tester.widget<Text>(find.text(title)).style?.color;

  /// Steps forward with the arrow until the header shows a Wednesday that
  /// is not today, the longest weekday name in both languages. Returns it.
  Future<DateTime> stepToWednesday(WidgetTester tester, S s) async {
    var day = today;
    do {
      await tester.tap(next(s));
      await tester.pump(const Duration(milliseconds: 50));
      day = DateTime(day.year, day.month, day.day + 1);
    } while (day.weekday != DateTime.wednesday);
    await settle(tester);
    return day;
  }

  group('the header', () {
    testWidgets('names today by its date, where the page title was',
        (tester) async {
      await pumpMatrix(tester);
      final title = taskDayTitle(today, _ar);
      expect(title, startsWith('اليوم، '));
      expect(title, contains('${today.day}'),
          reason: 'Western digits, never Arabic-Indic');
      expect(find.text(title), findsOneWidget);
      expect(find.text(_ar.goalsMatrix), findsNothing);
      // The History button is still at the far end.
      expect(find.byTooltip(_ar.matrixCompletedTitle), findsOneWidget);
      await finish(tester);
    });

    testWidgets(
        'the next arrow shows the next day\'s board and unlights «اليوم»; '
        '«اليوم» brings today back', (tester) async {
      await pumpMatrix(tester, tasks: [
        task('مهمة اليوم', planned: today),
        task('مهمة الغد', planned: inDays(1)),
      ]);
      final gp = tester.element(find.byType(MatrixScreen)).gp;
      expect(find.text('مهمة اليوم'), findsOneWidget);
      expect(find.text('مهمة الغد'), findsNothing,
          reason: 'a later day\'s task waits under «قادمة»');
      expect(labelColor(tester, find.text(_ar.matrixToday)), gp.goldInk);

      await tapAndSettle(tester, next(_ar));
      expect(find.text(taskDayTitle(inDays(1), _ar)), findsOneWidget);
      expect(find.text('مهمة الغد'), findsOneWidget);
      expect(find.text('مهمة اليوم'), findsNothing);
      expect(labelColor(tester, find.text(_ar.matrixToday)), gp.textSec,
          reason: '«اليوم» lit over another day would be a false claim');

      await tapAndSettle(tester, find.text(_ar.matrixToday));
      expect(find.text(taskDayTitle(today, _ar)), findsOneWidget);
      expect(find.text('مهمة اليوم'), findsOneWidget);
      expect(find.text('مهمة الغد'), findsNothing);
      expect(labelColor(tester, find.text(_ar.matrixToday)), gp.goldInk);
      await finish(tester);
    });

    testWidgets('at midnight the board turns to the new day by itself',
        (tester) async {
      // Nothing else rebuilds the page at midnight: no task changes, no
      // tap. The screen's own timer has to.
      final tuesday = DateTime(2026, 9, 29);
      final wednesday = DateTime(2026, 9, 30);
      wall = DateTime(2026, 9, 29, 23, 59, 30);
      await pumpMatrix(tester, tasks: [
        task('مهمة الثلاثاء', planned: tuesday),
        task('مهمة الأربعاء', planned: wednesday),
      ]);
      expect(find.text(taskDayTitle(tuesday, _ar, now: tuesday)),
          findsOneWidget);
      expect(find.text('مهمة الثلاثاء'), findsOneWidget);
      expect(find.text('مهمة الأربعاء'), findsNothing);

      wall = DateTime(2026, 9, 30, 0, 0, 1);
      await tester.pump(const Duration(seconds: 31));
      await settle(tester);
      expect(find.text(taskDayTitle(wednesday, _ar, now: wednesday)),
          findsOneWidget);
      expect(find.text('مهمة الأربعاء'), findsOneWidget);
      expect(find.text('مهمة الثلاثاء'), findsNothing,
          reason: 'Tuesday\'s open task is carried over now');
      await finish(tester);
    });

    testWidgets('the date opens the month, and a picked day shows its board',
        (tester) async {
      // A day of this month other than today, so no month stepping.
      final target = today.day > 15
          ? DateTime(today.year, today.month, 3)
          : DateTime(today.year, today.month, 20);
      await pumpMatrix(tester, tasks: [task('مهمة الهدف', planned: target)]);
      expect(find.text('مهمة الهدف'), findsNothing);

      await tapAndSettle(tester, find.text(taskDayTitle(today, _ar)));
      expect(find.byType(TaskMonthSheet), findsOneWidget);
      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byType(TaskMonthSheet),
          matching: find.text('${target.day}'),
        ),
      );
      expect(find.byType(TaskMonthSheet), findsNothing);
      expect(find.text(taskDayTitle(target, _ar)), findsOneWidget);
      expect(find.text('مهمة الهدف'), findsOneWidget);
      await finish(tester);
    });

    for (final s in const [_ar, _en]) {
      final lang = s.locale.languageCode;
      testWidgets('$lang: the previous-day arrow is on the reading start',
          (tester) async {
        await pumpMatrix(tester, locale: s.locale);
        final p = tester.getCenter(prev(s)).dx;
        final n = tester.getCenter(next(s)).dx;
        if (s.isAr) {
          expect(p, greaterThan(n), reason: 'RTL: previous on the right');
        } else {
          expect(p, lessThan(n), reason: 'LTR: previous on the left');
        }
        await finish(tester);
      });
    }

    for (final s in const [_ar, _en]) {
      final lang = s.locale.languageCode;
      testWidgets('$lang: the arrows hold still while the days change',
          (tester) async {
        // Quick taps on "next" must keep landing on "next": a title slot
        // sized to each day's name moved the arrow by most of its width
        // between a short weekday and a long one, onto the title.
        await pumpMatrix(tester, locale: s.locale);
        final start = tester.getCenter(next(s)).dx;
        final prevStart = tester.getCenter(prev(s)).dx;
        var drift = 0.0;
        for (var i = 0; i < 14; i++) {
          await tester.tap(next(s));
          await tester.pump(const Duration(milliseconds: 400));
          final d = (tester.getCenter(next(s)).dx - start).abs();
          if (d > drift) drift = d;
          expect(tester.getCenter(prev(s)).dx, closeTo(prevStart, 0.01));
        }
        // The day is centred in the bar (Aziz, 2026-09-29), so any change
        // in the slot's width would move BOTH arrows; the slot keeps room
        // for a whole year of titles plus today's «اليوم، …», and these
        // 14 days (from today, across Sep/Oct) must not move either arrow.
        // Sized per month, the first step off today moved them 1.1 (en)
        // and 3.3 (ar); sized per title, 39 in English.
        expect(drift, lessThan(0.01), reason: 'the slot never changes width');
        await finish(tester);
      });
    }

    for (final s in const [_ar, _en]) {
      final lang = s.locale.languageCode;
      testWidgets('$lang: the day sits in the centre of the bar',
          (tester) async {
        await pumpMatrix(tester, locale: s.locale);
        final screenMid = tester.view.physicalSize.width /
            tester.view.devicePixelRatio /
            2;
        final between =
            (tester.getCenter(prev(s)).dx + tester.getCenter(next(s)).dx) / 2;
        expect(between, closeTo(screenMid, 0.5),
            reason: 'midway between the arrows is the middle of the bar');
        await finish(tester);
      });
    }

    for (final s in const [_ar, _en]) {
      final lang = s.locale.languageCode;
      testWidgets('$lang: the arrows hold still on the days of another year',
          (tester) async {
        // A day in another year names its year, so the room the slot keeps
        // has to name it too, or every such title outgrows the slot and the
        // arrow moves with each weekday name again.
        wall = DateTime(2026, 12, 30, 12);
        await pumpMatrix(tester, locale: s.locale);
        for (var i = 0; i < 2; i++) {
          await tester.tap(next(s));
          await tester.pump(const Duration(milliseconds: 400));
        }
        await settle(tester);
        final jan1 = DateTime(2027);
        expect(find.text(taskDayTitle(jan1, s, now: wall)), findsOneWidget);
        expect(taskDayTitle(jan1, s, now: wall), contains('2027'));

        final start = tester.getCenter(next(s)).dx;
        var drift = 0.0;
        for (var i = 0; i < 13; i++) {
          await tester.tap(next(s));
          await tester.pump(const Duration(milliseconds: 400));
          final d = (tester.getCenter(next(s)).dx - start).abs();
          if (d > drift) drift = d;
        }
        expect(drift, lessThan(1), reason: 'one month, one slot');
        await finish(tester);
      });
    }

    testWidgets('Fav and All dim the day, and an arrow brings the day lens back',
        (tester) async {
      await pumpMatrix(tester, tasks: [
        task('مهمة اليوم', planned: today),
        task('مهمة الغد', planned: inDays(1)),
      ]);
      final gp = tester.element(find.byType(MatrixScreen)).gp;
      final todayTitle = taskDayTitle(today, _ar);
      expect(titleColor(tester, todayTitle), gp.textPrimary);

      await tapAndSettle(tester, find.text('${_ar.matrixFav} · 0'));
      expect(find.text(todayTitle), findsOneWidget,
          reason: 'the header still names the day the arrows step from');
      expect(titleColor(tester, todayTitle), gp.textSec);

      await tapAndSettle(tester, next(_ar));
      final tomorrowTitle = taskDayTitle(inDays(1), _ar);
      expect(titleColor(tester, tomorrowTitle), gp.textPrimary);
      expect(find.text('مهمة الغد'), findsOneWidget);
      expect(labelColor(tester, find.text('${_ar.matrixFav} · 0')), gp.textSec,
          reason: 'the arrow switched back to the day lens');

      await tapAndSettle(tester, find.text(_ar.matrixAll));
      expect(titleColor(tester, tomorrowTitle), gp.textSec);
      // All holds both days' tasks.
      expect(find.text('مهمة اليوم'), findsOneWidget);
      expect(find.text('مهمة الغد'), findsOneWidget);

      await tapAndSettle(tester, prev(_ar));
      expect(titleColor(tester, todayTitle), gp.textPrimary);
      expect(find.text('مهمة اليوم'), findsOneWidget);
      expect(find.text('مهمة الغد'), findsNothing);
      await finish(tester);
    });

    testWidgets(
        'changing the day ends a selection, so Delete cannot reach tasks '
        'that are off the board', (tester) async {
      await pumpMatrix(tester, tasks: [
        task('مهمة اليوم', planned: today),
        task('مهمة الغد', planned: inDays(1)),
      ]);
      final oneSelected = find.text(_ar.matrixSelectedCount(1));

      await tester.longPress(find.text('مهمة اليوم'));
      await settle(tester);
      expect(oneSelected, findsOneWidget);
      await tapAndSettle(tester, next(_ar));
      expect(find.text('مهمة الغد'), findsOneWidget);
      expect(oneSelected, findsNothing,
          reason: 'the selected task is not on this board');

      // «اليوم» back from another day changes the board too.
      await tester.longPress(find.text('مهمة الغد'));
      await settle(tester);
      expect(oneSelected, findsOneWidget);
      await tapAndSettle(tester, find.text(_ar.matrixToday));
      expect(find.text('مهمة اليوم'), findsOneWidget);
      expect(oneSelected, findsNothing);

      // Picking the day already showing leaves the selection alone.
      await tester.longPress(find.text('مهمة اليوم'));
      await settle(tester);
      await tapAndSettle(tester, find.text(taskDayTitle(today, _ar)));
      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byType(TaskMonthSheet),
          matching: find.text('${today.day}'),
        ),
      );
      expect(oneSelected, findsOneWidget);

      expect(container.read(matrixProvider).tasks, hasLength(2),
          reason: 'nothing was deleted along the way');
      await finish(tester);
    });

    testWidgets('the expanded quadrant shows the same day as the board',
        (tester) async {
      await pumpMatrix(tester, tasks: [
        task('مهمة اليوم', planned: today),
        task('مهمة الغد', planned: inDays(1)),
      ]);
      await tapAndSettle(tester, next(_ar));
      await tapAndSettle(tester, find.byTooltip(_ar.matrixExpandQuadrant).first);
      expect(find.byType(QuadrantExpandedScreen), findsOneWidget);
      expect(find.text('مهمة الغد'), findsOneWidget);
      expect(find.text('مهمة اليوم'), findsNothing);
      await finish(tester);
    });

    testWidgets(
        'a past day: no count pill, a quiet empty body, and + adds for today',
        (tester) async {
      await pumpMatrix(tester, tasks: [
        task('مهمة أمس', createdAt: inDays(-1).add(const Duration(hours: 9))),
        task('مهمة اليوم', planned: today),
      ]);
      // Today: Do First counts its open task.
      expect(find.text('1'), findsOneWidget);
      expect(find.text(_ar.matrixTapToAdd), findsNWidgets(3));

      await tapAndSettle(tester, prev(_ar));
      expect(find.text(taskDayTitle(inDays(-1), _ar)), findsOneWidget);
      expect(find.text('مهمة أمس'), findsOneWidget);
      expect(find.text('1'), findsNothing,
          reason: 'on Do First the tinted pill would read as an overdue count');
      expect(find.text(_ar.matrixNoTasksThatDay), findsNWidgets(3));
      expect(find.text(_ar.matrixTapToAdd), findsNothing);
      expect(find.text(_ar.matrixAddAnother), findsNothing);

      // The header's + still adds, for today.
      await tapAndSettle(tester, find.byIcon(Icons.add_rounded).first);
      expect(find.byType(AddTaskSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AddTaskSheet),
          matching: find.text(taskDayTitle(today, _ar)),
        ),
        findsOneWidget,
      );
      await finish(tester);
    });
  });

  group('the header fits on one line', () {
    const sizes = [Size(320, 568), Size(360, 640), Size(402, 874)];
    for (final size in sizes) {
      for (final s in const [_ar, _en]) {
        for (final scale in [1.0, if (size.width == 320) 1.3]) {
          final lang = s.locale.languageCode;
          testWidgets('${size.width.toInt()} · $lang · x$scale', (tester) async {
            await pumpMatrix(tester,
                locale: s.locale, size: size, textScale: scale);
            final wednesday = await stepToWednesday(tester, s);
            final title = taskDayTitle(wednesday, s);
            expect(find.text(title), findsOneWidget);
            expect(tester.takeException(), isNull);

            final para = tester.renderObject<RenderParagraph>(find.text(title));
            expect(para.didExceedMaxLines, isFalse);
            expect(para.size.height, lessThan(15 * scale * 2),
                reason: 'one line, never wrapped');

            final titleRect = tester.getRect(find.text(title));
            final prevRect = tester.getRect(prev(s));
            final nextRect = tester.getRect(next(s));
            final history = tester.getRect(find.byTooltip(s.matrixCompletedTitle));
            for (final r in [titleRect, prevRect, nextRect, history]) {
              expect(r.left, greaterThanOrEqualTo(0));
              expect(r.right, lessThanOrEqualTo(size.width));
            }
            // The title sits between its arrows without running under them,
            // and the navigator never reaches the History button.
            final lo = s.isAr ? nextRect : prevRect;
            final hi = s.isAr ? prevRect : nextRect;
            expect(titleRect.left, greaterThanOrEqualTo(lo.right - 0.5));
            expect(titleRect.right, lessThanOrEqualTo(hi.left + 0.5));
            if (s.isAr) {
              expect(history.right, lessThanOrEqualTo(lo.left));
            } else {
              expect(history.left, greaterThanOrEqualTo(hi.right));
            }
            await finish(tester);
          });
        }
      }
    }
  });

  group('the row time line', () {
    testWidgets('a timed task shows its time, an untimed one nothing',
        (tester) async {
      final at = DateTime(inDays(1).year, inDays(1).month, inDays(1).day, 16, 30);
      await pumpMatrix(tester, tasks: [
        task('موعد', planned: inDays(1), anchor: at),
        task('بدون وقت', planned: inDays(1)),
      ]);
      await tapAndSettle(tester, next(_ar));
      expect(find.text('موعد'), findsOneWidget);
      expect(find.text('بدون وقت'), findsOneWidget);
      final time = westernDate(at, 'h:mm a', 'ar');
      expect(find.text(time), findsOneWidget);
      expect(time, contains('4:30'));
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_rounded), findsNothing,
          reason: 'an untimed task on its own day says nothing');
      await finish(tester);
    });

    testWidgets('under All, a later day\'s task shows its date', (tester) async {
      final later = inDays(3);
      final at = DateTime(later.year, later.month, later.day, 9, 15);
      await pumpMatrix(tester, tasks: [
        task('بعد ثلاث', planned: later),
        task('بعد ثلاث بوقت', planned: later, anchor: at),
      ]);
      await tapAndSettle(tester, find.text(_ar.matrixAll));
      var date = westernDate(later, 'd MMMM', 'ar');
      if (later.year != today.year) date = '$date ${later.year}';
      expect(find.text(date), findsOneWidget);
      expect(find.text('$date · ${westernDate(at, 'h:mm a', 'ar')}'),
          findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_rounded), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
      await finish(tester);
    });

    // Six timed rows in one quadrant, long and short titles, at two phone
    // sizes, two text scales and both languages, in the grid and expanded:
    // every row is sized for its line, or a RenderFlex overflow is thrown.
    const titles = [
      'اتصال',
      'مراجعة ملف العرض قبل الاجتماع مع الفريق',
      'دفع الفاتورة',
      'Call the bank about the card before it closes for the day',
      'موعد الطبيب',
      'شراء هدية',
    ];
    for (final size in const [Size(320, 568), Size(375, 667)]) {
      for (final s in const [_ar, _en]) {
        for (final scale in const [1.0, 1.3]) {
          final lang = s.locale.languageCode;
          testWidgets(
              'six timed rows fit · ${size.width.toInt()} · $lang · x$scale',
              (tester) async {
            final day = inDays(1);
            await pumpMatrix(
              tester,
              locale: s.locale,
              size: size,
              textScale: scale,
              tasks: [
                for (var i = 0; i < titles.length; i++)
                  task(
                    titles[i],
                    planned: day,
                    anchor: DateTime(day.year, day.month, day.day, 8 + i, 45),
                  ),
              ],
            );
            await tapAndSettle(tester, next(s));
            expect(tester.takeException(), isNull, reason: 'compact grid');
            expect(find.byIcon(Icons.notifications_none_rounded),
                findsWidgets);

            await tapAndSettle(
                tester, find.byTooltip(s.matrixExpandQuadrant).first);
            expect(find.byType(QuadrantExpandedScreen), findsOneWidget);
            expect(tester.takeException(), isNull, reason: 'expanded view');
            final locale = s.isAr ? 'ar' : 'en';
            for (var i = 0; i < titles.length; i++) {
              final at = DateTime(day.year, day.month, day.day, 8 + i, 45);
              expect(find.text(westernDate(at, 'h:mm a', locale)),
                  findsOneWidget);
            }
            await finish(tester);
          });
        }
      }
    }
  });

  group('adding', () {
    Future<void> typeAndEnter(WidgetTester tester, String title) async {
      await tester.enterText(find.byType(TextField).first, title);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> closeSheet(WidgetTester tester) async {
      Navigator.of(tester.element(find.byType(AddTaskSheet))).pop();
      await settle(tester);
    }

    MatrixTask added(String title) =>
        container.read(matrixProvider).tasks.firstWhere((t) => t.title == title);

    testWidgets('from a later day\'s board, the task is for that day',
        (tester) async {
      await pumpMatrix(tester);
      final wednesday = await stepToWednesday(tester, _ar);
      await tapAndSettle(tester, find.byIcon(Icons.add_rounded).first);
      expect(
        find.descendant(
          of: find.byType(AddTaskSheet),
          matching: find.text(taskDayTitle(wednesday, _ar)),
        ),
        findsOneWidget,
      );
      await typeAndEnter(tester, 'مهمة الأربعاء');
      await closeSheet(tester);

      expect(added('مهمة الأربعاء').plannedDay, dayKey(wednesday));
      expect(taskDay(added('مهمة الأربعاء')), wednesday);
      expect(find.text('مهمة الأربعاء'), findsOneWidget);
      expect(find.text(_ar.matrixShowDay), findsNothing,
          reason: 'the task is on the board already, nothing to announce');
      await finish(tester);
    });

    testWidgets(
        'under Fav, a task for a later day is announced, and «عرض» opens it',
        (tester) async {
      await pumpMatrix(tester);
      await tapAndSettle(tester, find.text('${_ar.matrixFav} · 0'));
      await tapAndSettle(tester, find.byIcon(Icons.add_rounded).first);
      // Fav has no day of its own: the sheet opens on today.
      final dayRow = find.descendant(
        of: find.byType(AddTaskSheet),
        matching: find.text(taskDayTitle(today, _ar)),
      );
      expect(dayRow, findsOneWidget);

      final target = inDays(2);
      await tapAndSettle(tester, dayRow);
      expect(find.byType(TaskMonthSheet), findsOneWidget);
      if (target.month != today.month) {
        final ctx = tester.element(find.byType(TaskMonthSheet));
        await tapAndSettle(tester,
            find.byTooltip(MaterialLocalizations.of(ctx).nextMonthTooltip));
      }
      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byType(TaskMonthSheet),
          matching: find.text('${target.day}'),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(AddTaskSheet),
          matching: find.text(taskDayTitle(target, _ar)),
        ),
        findsOneWidget,
      );
      await typeAndEnter(tester, 'مهمة لاحقة');
      await closeSheet(tester);

      expect(added('مهمة لاحقة').plannedDay, dayKey(target));
      expect(find.text('مهمة لاحقة'), findsNothing,
          reason: 'not a starred task, and not today\'s');
      final message = _ar.matrixAddedForDay(
          weekdayDateLabel(target, isAr: true, locale: 'ar'));
      expect(find.text(message), findsOneWidget);

      await tapAndSettle(tester, find.text(_ar.matrixShowDay));
      expect(find.text(taskDayTitle(target, _ar)), findsOneWidget);
      expect(find.text('مهمة لاحقة'), findsOneWidget);
      await finish(tester);
    });
  });

  group('matrixRowMeta', () {
    final t0 = DateTime(2026, 9, 29);
    MatrixTask at(DateTime? anchor, {DateTime? planned, bool done = false}) =>
        MatrixTask(
          id: 'x',
          title: 'x',
          quadrant: MatrixQuadrant.doFirst,
          isDone: done,
          createdAt: DateTime(2026, 9, 20),
          reminderAts: anchor == null ? const [] : [anchor],
          reminderAnchorAt: anchor,
          plannedDay: planned == null ? null : dayKey(planned),
          order: 0,
        );

    test('the day lens says only the time', () {
      expect(
        matrixRowMeta(at(DateTime(2026, 9, 30, 16, 30)),
            dayLens: true, today: t0, isAr: true),
        '4:30 م',
      );
      expect(
        matrixRowMeta(at(null, planned: DateTime(2026, 9, 30)),
            dayLens: true, today: t0, isAr: true),
        isNull,
      );
    });

    test('mixed boards add the date for another day, and the year when it '
        'differs', () {
      expect(
        matrixRowMeta(at(DateTime(2026, 9, 30, 16, 30)),
            dayLens: false, today: t0, isAr: true),
        '30 سبتمبر · 4:30 م',
      );
      expect(
        matrixRowMeta(at(null, planned: DateTime(2026, 9, 30)),
            dayLens: false, today: t0, isAr: false),
        'Sep 30',
      );
      expect(
        matrixRowMeta(at(DateTime(2026, 9, 29, 17)),
            dayLens: false, today: t0, isAr: false),
        '5:00 PM',
        reason: 'today\'s task: just the time',
      );
      expect(
        matrixRowMeta(at(null, planned: DateTime(2027, 1, 2)),
            dayLens: false, today: t0, isAr: true),
        '2 يناير 2027',
      );
    });

    test('done tasks say nothing', () {
      expect(
        matrixRowMeta(at(DateTime(2026, 9, 30, 16, 30), done: true),
            dayLens: false, today: t0, isAr: true),
        isNull,
      );
    });
  });
}
