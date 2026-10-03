// The move sheet's «نقل ليوم ثاني» (move_task_sheet.dart): under the
// quadrant rows, a row that opens the month in pick mode and moves the task
// to the day picked, through MatrixNotifier.moveToDay, with an Undo that
// puts the previous schedule back. Hidden for a done task. When the task's
// own time has already gone on the day picked (today, at an earlier hour)
// the notifier refuses, and the sheet asks for a time on today's wheel,
// floored at the next minute. The title now carries the task's day and
// time, and the sheet fits a 568pt phone.
//
// The notifier here records calls instead of writing (a Hive write inside a
// testWidgets body never settles); the move rules themselves are pinned in
// matrix_day_move_test.dart. Days come from the real clock.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/core/utils/western_digits.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';
import 'package:grow_daily_v2/features/matrix/task_day.dart';
import 'package:grow_daily_v2/features/matrix/task_prayer.dart' show PrayerSlot;
import 'package:grow_daily_v2/features/matrix/widgets/move_task_sheet.dart';
import 'package:grow_daily_v2/features/matrix/widgets/task_month_sheet.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

class _Move {
  final String id;
  final DateTime day;
  final TimeOfDay? time;
  _Move(this.id, this.day, this.time);
}

class _Restore {
  final String id;
  final List<DateTime> reminderAts;
  final DateTime? anchor;
  final String? plannedDay;
  _Restore(this.id, this.reminderAts, this.anchor, this.plannedDay);
}

/// The tasks a test hands it, and a record of every move and Undo instead
/// of the writes. [refuseWithoutTime] answers a move with no time the way
/// moveToDay answers a timed task whose time has gone on the day picked.
class _RecordingMatrix extends MatrixNotifier {
  _RecordingMatrix(Ref ref, this.fixed, {this.refuseWithoutTime = false})
      : super(ref, null) {
    super.state = fixed;
  }

  final MatrixState fixed;
  final bool refuseWithoutTime;
  final moves = <_Move>[];
  final restores = <_Restore>[];

  @override
  set state(MatrixState value) => super.state = fixed;

  @override
  bool moveToDay(String id, DateTime day, {TimeOfDay? time}) {
    moves.add(_Move(id, day, time));
    return !(refuseWithoutTime && time == null);
  }

  @override
  void restoreSchedule(
    String id, {
    required List<DateTime> reminderAts,
    DateTime? anchor,
    PrayerSlot? prayer,
    String? plannedDay,
  }) =>
      restores.add(_Restore(id, reminderAts, anchor, plannedDay));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('move_task_sheet_day_test_');
    Hive.init(tmp.path);
    // MatrixNotifier's guest load reads this; opened out here, never inside
    // a testWidgets body.
    await LocalStoreService.settingsBox();
  });

  tearDownAll(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime inDays(int n) => DateTime(today.year, today.month, today.day + n);

  MatrixTask untimed({bool isDone = false, required DateTime day}) =>
      MatrixTask(
        id: 'u',
        title: 'رتّب الأوراق',
        quadrant: MatrixQuadrant.doFirst,
        isDone: isDone,
        createdAt: today,
        completedAt: isDone ? now : null,
        plannedDay: dayKey(day),
        order: 0,
      );

  MatrixTask timed(DateTime anchor) => MatrixTask(
        id: 't',
        title: 'اجتماع الفريق',
        quadrant: MatrixQuadrant.schedule,
        isDone: false,
        createdAt: today,
        reminderAts: [anchor],
        reminderAnchorAt: anchor,
        plannedDay: dayKey(anchor),
        order: 0,
      );

  late _RecordingMatrix fake;

  Future<void> open(
    WidgetTester tester,
    MatrixTask task, {
    Locale locale = const Locale('ar'),
    Size size = const Size(402, 874),
    double textScale = 1.0,
    bool refuseWithoutTime = false,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumAccessProvider.overrideWithValue(false),
        matrixProvider.overrideWith((ref) => fake = _RecordingMatrix(
              ref,
              MatrixState(tasks: [task], isLoading: false),
              refuseWithoutTime: refuseWithoutTime,
            )),
      ],
      child: MaterialApp(
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
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showMoveTaskSheet(context, task, (_) {}),
                child: const Text('open'),
              ),
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

  const ar = S(Locale('ar'));

  testWidgets('the another-day row is hidden for a done task', (tester) async {
    await open(tester, untimed(day: today, isDone: true));
    expect(find.text(ar.matrixMoveToQuadrant), findsOneWidget);
    expect(find.text(ar.matrixMoveToAnotherDay), findsNothing);
  });

  testWidgets('an open task shows its day, and its time when it has one',
      (tester) async {
    final day = inDays(3);
    await open(tester, untimed(day: day));
    expect(find.text(ar.matrixMoveToAnotherDay), findsOneWidget);
    expect(find.text(taskDayTitle(day, ar)), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    final at = DateTime(day.year, day.month, day.day, 16, 30);
    await open(tester, timed(at));
    expect(
      find.text('${taskDayTitle(day, ar)} · ${westernDate(at, 'h:mm a', 'ar')}'),
      findsOneWidget,
    );
    expect(find.textContaining('4:30'), findsOneWidget,
        reason: 'the time in Western digits');
  });

  testWidgets('a move calls moveToDay, closes, and its Undo puts it back',
      (tester) async {
    final from = inDays(1);
    // Another day in the month the sheet opens on (the task's own).
    final next = DateTime(from.year, from.month, from.day + 1);
    final target = next.month == from.month ? next : inDays(0);
    await open(tester, untimed(day: from));

    await tester.tap(find.text(ar.matrixMoveToAnotherDay));
    await tester.pumpAndSettle();
    expect(find.text(ar.matrixPickDay), findsOneWidget,
        reason: 'the month opens in pick mode');

    // The day it is already on changes nothing.
    await tester.tap(cell(from));
    await tester.pumpAndSettle();
    expect(fake.moves, isEmpty);
    expect(find.text(ar.matrixMoveToAnotherDay), findsOneWidget,
        reason: 'the move sheet stays open');

    await tester.tap(find.text(ar.matrixMoveToAnotherDay));
    await tester.pumpAndSettle();
    await tester.tap(cell(target));
    await tester.pumpAndSettle();

    expect(fake.moves, hasLength(1));
    expect(fake.moves.single.id, 'u');
    expect(fake.moves.single.day, target);
    expect(fake.moves.single.time, isNull);
    expect(find.text(ar.matrixMoveToQuadrant), findsNothing,
        reason: 'the sheet closes after a move');

    final message = target == today
        ? ar.matrixMovedToToday
        : ar.matrixMovedToDay(
            weekdayDateLabel(target, isAr: true, locale: 'ar'));
    expect(find.text(message), findsOneWidget);

    await tester.tap(find.text(ar.matrixUndo));
    await tester.pumpAndSettle();
    expect(fake.restores, hasLength(1));
    expect(fake.restores.single.id, 'u');
    expect(fake.restores.single.plannedDay, dayKey(from));
    expect(fake.restores.single.reminderAts, isEmpty);
  });

  testWidgets('a time that has gone today asks for one on today\'s wheel',
      (tester) async {
    final clock = DateTime.now();
    // At 23:59 no time is left today at all; nothing to pick.
    if (clock.hour == 23 && clock.minute == 59) return;
    final from = inDays(1);
    final anchor = DateTime(from.year, from.month, from.day, 0, 5);
    await open(tester, timed(anchor), refuseWithoutTime: true);

    await tester.tap(find.text(ar.matrixMoveToAnotherDay));
    await tester.pumpAndSettle();
    // Today, whichever month the sheet opened on.
    await tester.tap(find.text(ar.matrixBackToToday));
    await tester.pumpAndSettle();

    expect(fake.moves, hasLength(1), reason: 'the plain move was tried');
    expect(fake.moves.first.time, isNull);
    final wheel =
        tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
    expect(wheel.minimumDate, isNotNull,
        reason: 'today\'s wheel is floored at the next minute');

    await tester.tap(find.text(ar.matrixDone));
    await tester.pumpAndSettle();
    expect(fake.moves, hasLength(2));
    expect(fake.moves.last.day, today);
    expect(fake.moves.last.time, isNotNull);
    expect(find.text(ar.matrixMovedToToday), findsOneWidget);
  });

  group('fits a 568pt phone', () {
    for (final locale in const [Locale('ar'), Locale('en')]) {
      for (final scale in const [1.0, 1.3]) {
        testWidgets('${locale.languageCode} at ${scale}x', (tester) async {
          final day = inDays(2);
          await open(
            tester,
            timed(DateTime(day.year, day.month, day.day, 16, 30)),
            locale: locale,
            size: const Size(320, 568),
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          final s = S(locale);
          final row = find.text(s.matrixMoveToAnotherDay);
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
          expect(tester.getRect(row).bottom, lessThanOrEqualTo(568));
        });
      }
    }
  });
}
