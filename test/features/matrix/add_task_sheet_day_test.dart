// The Add sheet's day (add_task_sheet.dart): every task is added FOR A DAY,
// shown in a row under the title. The sheet opens on the day it is given,
// the reminder row opens only the time wheel on that day (no calendar step
// to disagree with the row), each add hands the day to the caller, the day
// stays across a multi-add while the time resets, and changing the day
// carries a set time along. The old «تظهر تحت «الكل»» line is gone: the
// Tasks page says where a task went instead.
//
// Days come from the real clock and sit a few days ahead, so the hour the
// suite runs at cannot matter; the pure carry rule is pinned with fixed
// dates.
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
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/widgets/add_task_sheet.dart';
import 'package:grow_daily_v2/features/matrix/widgets/reminder_picker.dart';
import 'package:grow_daily_v2/features/matrix/widgets/task_month_sheet.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

class _Added {
  final String title;
  final List<DateTime> reminderAts;
  final DateTime? anchor;
  final DateTime day;
  _Added(this.title, this.reminderAts, this.anchor, this.day);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ar = S(Locale('ar'));

  late Directory tmp;

  // MatrixNotifier's guest load reads the settings box (the sheet reaches
  // matrixProvider for its quadrant colour); opened here in the real async
  // zone, never inside a testWidgets body.
  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('add_task_sheet_day_test_');
    Hive.init(tmp.path);
    await LocalStoreService.settingsBox();
  });

  tearDownAll(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  // The real ask writes its answer to Hive, which never settles inside a
  // testWidgets body; a timed add would stall before the callback.
  late Future<bool> Function() realAsk;
  setUp(() {
    realAsk = addTaskPermissionAsk;
    addTaskPermissionAsk = () async => true;
  });
  tearDown(() => addTaskPermissionAsk = realAsk);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime inDays(int n) => DateTime(today.year, today.month, today.day + n);

  late List<_Added> added;

  Future<void> open(WidgetTester tester, {DateTime? day}) async {
    added = [];
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumAccessProvider.overrideWithValue(false),
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
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                // Presented the way matrix_screen.dart's _showAdd does.
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  useSafeArea: true,
                  builder: (_) => AddTaskSheet(
                    quadrant: MatrixQuadrant.schedule,
                    day: day,
                    onAddOnDay: (
                      title, {
                      description,
                      voiceNotes,
                      reminderAts,
                      reminderAnchorAt,
                      alarm,
                      required day,
                    }) =>
                        added.add(_Added(
                          title,
                          reminderAts ?? const [],
                          reminderAnchorAt,
                          day,
                        )),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// The reminder row, then the wheel it opens. The wheel is a bottom
  /// sheet and slides in a frame later than a dialog would.
  Future<void> openWheel(WidgetTester tester) async {
    await tester.tap(find.text(ar.matrixReminderLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> wheelDone(WidgetTester tester) async {
    await tester.tap(find.text(ar.matrixDone));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Enter on the keyboard: adds and keeps the sheet open.
  Future<void> typeAndEnter(WidgetTester tester, String title) async {
    await tester.enterText(find.byType(TextField).first, title);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('opens on the day it is given, named by its date',
      (tester) async {
    final day = inDays(3);
    await open(tester, day: day);
    expect(find.text(taskDayTitle(day, ar)), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('no day, or a day that has gone, opens on today',
      (tester) async {
    await open(tester);
    expect(find.text(taskDayTitle(today, ar)), findsOneWidget);
    expect(taskDayTitle(today, ar), startsWith('اليوم، '));
    await tester.pumpWidget(const SizedBox.shrink());

    await open(tester, day: inDays(-2));
    expect(find.text(taskDayTitle(today, ar)), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the reminder row opens only the time wheel, on the sheet\'s day',
      (tester) async {
    final day = inDays(3);
    await open(tester, day: day);
    await openWheel(tester);

    expect(find.byType(DatePickerDialog), findsNothing,
        reason: 'no calendar step: the day row already chose the day');
    final wheel =
        tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
    // A later day has no floor, and starts at 9 in the morning.
    expect(wheel.minimumDate, isNull);
    expect(wheel.initialDateTime, DateTime(day.year, day.month, day.day, 9));

    await wheelDone(tester);
    expect(
      find.text(formatReminderMoment(
          DateTime(day.year, day.month, day.day, 9), true)),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('on today the wheel carries its floor', (tester) async {
    final clock = DateTime.now();
    // The last minute of the day has no floor on today at all (it would
    // roll into tomorrow); nothing to check then.
    if (clock.hour == 23 && clock.minute == 59) return;
    await open(tester);
    await openWheel(tester);
    final wheel =
        tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
    expect(wheel.minimumDate, isNotNull);
    expect(wheel.minimumDate!.day, today.day);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('each add passes the day; after Enter the day stays, the time '
      'resets', (tester) async {
    final day = inDays(4);
    await open(tester, day: day);

    await openWheel(tester);
    await wheelDone(tester);
    await typeAndEnter(tester, 'اتصل بالمكتب');

    expect(added, hasLength(1));
    final nine = DateTime(day.year, day.month, day.day, 9);
    expect(added.single.day, day);
    expect(added.single.anchor, nine);
    expect(added.single.reminderAts, [nine]);

    // The sheet is still open on the same day, and the time is gone.
    expect(find.text(taskDayTitle(day, ar)), findsOneWidget);
    expect(find.text(ar.matrixReminderLabel), findsOneWidget);

    await typeAndEnter(tester, 'اشتر حليب');
    expect(added, hasLength(2));
    expect(added.last.day, day);
    expect(added.last.anchor, isNull);
    expect(added.last.reminderAts, isEmpty);

    // No "find it under All" line any more.
    expect(find.textContaining('«الكل»'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('changing the day carries a set time to it', (tester) async {
    final day = inDays(2);
    // Another day in the same month, so the month sheet shows it without
    // stepping; tomorrow when the 2nd day ahead is the month's last.
    final target = DateTime(day.year, day.month, day.day + 3).month == day.month
        ? DateTime(day.year, day.month, day.day + 3)
        : inDays(1);
    await open(tester, day: day);
    await openWheel(tester);
    await wheelDone(tester);

    await tester.tap(find.text(taskDayTitle(day, ar)));
    await tester.pumpAndSettle();
    expect(find.text(ar.matrixPickDay), findsOneWidget,
        reason: 'the day row opens the month in pick mode');
    await tester.tap(find.byWidgetPredicate(
      (w) =>
          w.runtimeType.toString() == '_DayCell' &&
          (w as dynamic).day == target,
    ));
    await tester.pumpAndSettle();

    final moved = DateTime(target.year, target.month, target.day, 9);
    expect(find.text(taskDayTitle(target, ar)), findsOneWidget);
    expect(find.text(formatReminderMoment(moved, true)), findsOneWidget,
        reason: 'the time moved with the day, same clock time');

    await typeAndEnter(tester, 'موعد');
    expect(added.single.day, target);
    expect(added.single.anchor, moved);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  group('carryReminderToDay', () {
    final clock = DateTime(2026, 9, 16, 12);

    test('keeps the clock time and the offsets on the new day', () {
      final r = carryReminderToDay(
        anchor: DateTime(2026, 9, 18, 17),
        offsets: {-60, 15},
        day: DateTime(2026, 9, 20),
        now: clock,
      );
      expect(r.anchor, DateTime(2026, 9, 20, 17));
      expect(r.offsets, {-60, 15});
      expect(r.cleared, isFalse);
    });

    test('drops an offset whose moment would already have passed', () {
      // 12:30 today with a 1-hour warning: 11:30 has gone at noon.
      final r = carryReminderToDay(
        anchor: DateTime(2026, 9, 18, 12, 30),
        offsets: {-60, -15},
        day: DateTime(2026, 9, 16),
        now: clock,
      );
      expect(r.anchor, DateTime(2026, 9, 16, 12, 30));
      expect(r.offsets, {-15});
    });

    test('clears a time that would land in the past, and says so', () {
      final r = carryReminderToDay(
        anchor: DateTime(2026, 9, 18, 9),
        offsets: {-15},
        day: DateTime(2026, 9, 16),
        now: clock,
      );
      expect(r.anchor, isNull);
      expect(r.offsets, isEmpty);
      expect(r.cleared, isTrue);
    });

    test('with no time set there is nothing to carry', () {
      final r = carryReminderToDay(
        anchor: null,
        offsets: const {},
        day: DateTime(2026, 9, 16),
        now: clock,
      );
      expect(r.anchor, isNull);
      expect(r.cleared, isFalse);
    });
  });

  group('reminderSuggestedTime', () {
    final clock = DateTime(2026, 9, 16, 14, 20);

    test('a later day starts at 9 in the morning', () {
      expect(
        reminderSuggestedTime(day: DateTime(2026, 9, 19), now: clock),
        DateTime(2026, 9, 19, 9),
      );
    });

    test('today starts an hour from now', () {
      expect(
        reminderSuggestedTime(day: DateTime(2026, 9, 16), now: clock),
        DateTime(2026, 9, 16, 15, 20),
      );
    });

    test('a set time keeps its clock time while it is still ahead', () {
      expect(
        reminderSuggestedTime(
          day: DateTime(2026, 9, 19),
          initial: DateTime(2026, 9, 18, 17, 30),
          now: clock,
        ),
        DateTime(2026, 9, 19, 17, 30),
      );
      // Moved to today at a time that has gone: the today default instead.
      expect(
        reminderSuggestedTime(
          day: DateTime(2026, 9, 16),
          initial: DateTime(2026, 9, 18, 9),
          now: clock,
        ),
        DateTime(2026, 9, 16, 15, 20),
      );
    });
  });
}
