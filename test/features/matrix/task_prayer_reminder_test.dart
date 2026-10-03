// A task reminder set by a prayer, the habit way (Aziz, 2026-10-03: "he
// can choose, like 15 before, it should be well designed and easy to use,
// same as habit reminder", and the task should remember the prayer).
//
// Pinned:
//  * what is stored: MatrixTask.reminderPrayer as 'asr+15', read back
//    leniently, gone with the time, and cleared on Firestore by a sentinel;
//  * the moment: the prayer's time on the task's day plus the amount;
//  * the moves: a task moved to another day goes to THAT day's prayer, a
//    clock time given in a move drops the prayer, Undo brings it back;
//  * the sheet: the Add sheet's unset reminder is two ways in, «تعيين
//    تذكير» and «مع وقت صلاة»; the second is Add Habit's prayer sheet, and
//    «العصر» then «15» sets «بعد العصر بـ15 دقيقة» and hands the prayer on
//    with the add; a pair whose time has gone is refused in the sheet.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/bahrain_prayer_table.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/habit_offset_sheet.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/notifiers/matrix_notifier.dart';
import 'package:grow_daily_v2/features/matrix/task_day.dart';
import 'package:grow_daily_v2/features/matrix/task_prayer.dart';
import 'package:grow_daily_v2/features/matrix/widgets/add_task_sheet.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:grow_daily_v2/features/settings/notifiers/notification_settings_notifier.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

/// Settings changed in memory only (see prayer_today_card_test.dart).
class _Settings extends NotificationSettingsNotifier {
  _Settings(NotificationSettings initial)
      : super(firestore: FakeFirebaseFirestore()) {
    state = initial;
  }

  @override
  Future<void> update(
    NotificationSettings Function(NotificationSettings current) mutator,
  ) async {
    state = mutator(state);
  }
}

const _manama = NotificationLocation(
  lat: 26.2285,
  lng: 50.5860,
  label: 'Manama, Bahrain',
);
const _settings = NotificationSettings(location: _manama);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ar = S(Locale('ar'));
  late Directory tmp;

  // Everything with real I/O here, never inside a test (fake async): the
  // settings and Tasks notifiers read Hive as they start, and Bahrain's
  // official table is an asset the app loads long before this sheet opens.
  setUpAll(() async {
    tz_data.initializeTimeZones();
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
    BahrainPrayerTable.resetForTest();
    await BahrainPrayerTable.ensureLoaded();
    tmp = Directory.systemTemp.createTempSync('task_prayer_reminder');
    Hive.init(tmp.path);
    await LocalStoreService.settingsBox();
  });
  tearDownAll(() async {
    await Hive.close();
    tmp.deleteSync(recursive: true);
  });

  final now = DateTime.now();
  DateTime inDays(int n) => DateTime(now.year, now.month, now.day + n);

  DateTime asrOn(DateTime day) => prayerMomentOn('asr', day, _settings)!;

  group('what a task stores', () {
    test('one short string, read back leniently', () {
      const after = (prayer: 'asr', offset: 15);
      const before = (prayer: 'fajr', offset: -30);
      const onTime = (prayer: 'isha', offset: 0);
      expect(encodeTaskPrayer(after), 'asr+15');
      expect(encodeTaskPrayer(before), 'fajr-30');
      expect(encodeTaskPrayer(onTime), 'isha+0');
      for (final p in [after, before, onTime]) {
        expect(decodeTaskPrayer(encodeTaskPrayer(p)), p);
      }
      for (final junk in ['asr15', 'zuhr+5', 'asr+999', 'asr+', '', 5, null]) {
        expect(decodeTaskPrayer(junk), isNull, reason: '$junk');
      }
    });

    MatrixTask timed({PrayerSlot? prayer}) {
      final at = asrOn(inDays(2)).add(const Duration(minutes: 15));
      return MatrixTask.create(
        'Call the bank',
        MatrixQuadrant.schedule,
        reminderAts: [at],
        reminderAnchorAt: at,
        reminderPrayer: prayer,
      );
    }

    test('kept by the guest store and by Firestore, and cleared there', () {
      final task = timed(prayer: (prayer: 'asr', offset: 15));
      expect(task.toMap()['reminderPrayer'], 'asr+15');
      expect(
        MatrixTask.fromMap(task.toMap()).reminderPrayer,
        (prayer: 'asr', offset: 15),
      );
      expect(task.toFirestore()['reminderPrayer'], 'asr+15');

      final clock = timed();
      expect(clock.toMap().containsKey('reminderPrayer'), isFalse);
      expect(
        clock.toFirestore()['reminderPrayer'],
        FieldValue.delete(),
        reason: 'a merge-set must take an old prayer off',
      );
    });

    test('only ever with a time', () {
      final task = timed(prayer: (prayer: 'asr', offset: 15));
      expect(
        task
            .copyWith(reminderAts: const [], clearReminderAnchorAt: true)
            .reminderPrayer,
        isNull,
      );
      expect(task.copyWith(clearReminderPrayer: true).reminderPrayer, isNull);
      expect(
        task.copyWith(title: 'x').reminderPrayer,
        task.reminderPrayer,
        reason: 'any other edit keeps it',
      );
      final untimed = MatrixTask.create(
        'x',
        MatrixQuadrant.schedule,
        reminderPrayer: (prayer: 'asr', offset: 15),
      );
      expect(untimed.reminderPrayer, isNull);
      expect(
        MatrixTask.fromMap({...untimed.toMap(), 'reminderPrayer': 'asr+15'})
            .reminderPrayer,
        isNull,
      );
    });
  });

  group('the moment', () {
    test('the prayer on that day plus the amount, on the minute', () {
      final day = inDays(3);
      final asr = asrOn(day);
      expect(asr.second, 0);
      expect(DateTime(asr.year, asr.month, asr.day), day);
      expect(
        taskPrayerMoment((prayer: 'asr', offset: 15), day, _settings),
        asr.add(const Duration(minutes: 15)),
      );
      expect(
        taskPrayerMoment((prayer: 'asr', offset: -10), day, _settings),
        asr.subtract(const Duration(minutes: 10)),
      );
      expect(
        taskPrayerMoment(
          (prayer: 'asr', offset: 0),
          day,
          const NotificationSettings(),
        ),
        isNull,
        reason: 'no place, no time',
      );
    });

    test('the sheet opens on the next prayer of the day', () {
      final day = inDays(1);
      DateTime clock(int h, int m) =>
          DateTime(now.year, now.month, now.day, h, m);
      final dhuhr = prayerMomentOn('dhuhr', day, _settings)!;
      final isha = prayerMomentOn('isha', day, _settings)!;
      expect(
        nextTaskPrayer(day, _settings, clock(dhuhr.hour, dhuhr.minute + 1)),
        'asr',
      );
      expect(
        nextTaskPrayer(day, _settings, clock(isha.hour, isha.minute + 1)),
        'fajr',
      );
      expect(nextTaskPrayer(day, _settings, clock(0, 1)), 'fajr');
    });
  });

  group('moving a task', () {
    final from = inDays(2);
    final to = inDays(5);
    MatrixTask atAsr() {
      final at = asrOn(from).add(const Duration(minutes: 15));
      return MatrixTask.create(
        'Call the bank',
        MatrixQuadrant.schedule,
        reminderAts: [at.subtract(const Duration(minutes: 10)), at],
        reminderAnchorAt: at,
        reminderPrayer: (prayer: 'asr', offset: 15),
      );
    }

    DateTime? prayerAt(PrayerSlot p, DateTime day) =>
        taskPrayerMoment(p, day, _settings);

    test("goes to that day's prayer, with its offsets", () {
      final moved = taskMovedToDay(atAsr(), to, now: now, prayerAt: prayerAt)!;
      final anchor = asrOn(to).add(const Duration(minutes: 15));
      expect(moved.reminderAnchorAt, anchor);
      expect(
        moved.reminderAts,
        [anchor.subtract(const Duration(minutes: 10)), anchor],
      );
      expect(moved.reminderPrayer, (prayer: 'asr', offset: 15));
      expect(moved.plannedDay, dayKey(to));
    });

    test('a clock time given in the move drops the prayer', () {
      final moved = taskMovedToDay(
        atAsr(),
        to,
        time: const TimeOfDay(hour: 20, minute: 0),
        now: now,
        prayerAt: prayerAt,
      )!;
      expect(moved.reminderAnchorAt, DateTime(to.year, to.month, to.day, 20));
      expect(moved.reminderPrayer, isNull);
    });

    test('with no prayer time to be had, the clock time moves as before', () {
      final task = atAsr();
      final moved =
          taskMovedToDay(task, to, now: now, prayerAt: (_, __) => null)!;
      final was = task.reminderAnchorAt!;
      expect(
        moved.reminderAnchorAt,
        DateTime(to.year, to.month, to.day, was.hour, was.minute),
      );
    });

    test('Undo brings the prayer back with the time, never without it', () {
      final task = atAsr();
      final moved = taskMovedToDay(task, to, now: now, prayerAt: prayerAt)!;
      final back = taskWithRestoredSchedule(
        moved,
        reminderAts: task.reminderAts,
        anchor: task.reminderAnchorAt,
        prayer: task.reminderPrayer,
        plannedDay: task.plannedDay,
        now: now,
      );
      expect(back.reminderAnchorAt, task.reminderAnchorAt);
      expect(back.reminderPrayer, (prayer: 'asr', offset: 15));

      final gone = taskWithRestoredSchedule(
        moved,
        reminderAts: task.reminderAts,
        anchor: task.reminderAnchorAt,
        prayer: task.reminderPrayer,
        plannedDay: task.plannedDay,
        now: task.reminderAnchorAt!.add(const Duration(minutes: 1)),
      );
      expect(gone.reminderAnchorAt, isNull);
      expect(gone.reminderPrayer, isNull);
    });

    test("the Add sheet's day row carries it to the new day's prayer", () {
      final anchor = asrOn(from).add(const Duration(minutes: 15));
      final carried = carryReminderToDay(
        anchor: anchor,
        offsets: {-10},
        day: to,
        now: now,
        at: taskPrayerMoment((prayer: 'asr', offset: 15), to, _settings),
      );
      expect(carried.anchor, asrOn(to).add(const Duration(minutes: 15)));
      expect(carried.offsets, {-10});
      expect(carried.cleared, isFalse);
    });
  });

  group('the sheet', () {
    late List<({DateTime? anchor, PrayerSlot? prayer, List<DateTime> at})>
        added;

    // The real permission ask writes to Hive, which never settles inside a
    // testWidgets body (see add_task_sheet_day_test.dart).
    late Future<bool> Function() realAsk;
    setUp(() {
      realAsk = addTaskPermissionAsk;
      addTaskPermissionAsk = () async => true;
    });
    tearDown(() => addTaskPermissionAsk = realAsk);

    Future<void> openAdd(WidgetTester tester, {required DateTime day}) async {
      added = [];
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
            premiumAccessProvider.overrideWithValue(false),
            notificationSettingsProvider
                .overrideWith((ref) => _Settings(_settings)),
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
                          reminderPrayer,
                          alarm,
                          required day,
                        }) =>
                            added.add(
                          (
                            anchor: reminderAnchorAt,
                            prayer: reminderPrayer,
                            at: reminderAts ?? const [],
                          ),
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets(
        'two ways in, and «العصر» then «15» is after Asr by 15, handed on '
        'with the add', (tester) async {
      final day = inDays(3);
      await openAdd(tester, day: day);
      expect(find.text(ar.matrixReminderLabel), findsOneWidget);
      expect(find.text(ar.reminderWithPrayer), findsOneWidget);

      await tester.tap(find.text(ar.reminderWithPrayer));
      await settle(tester);
      // Add Habit's prayer sheet: the five prayers with that day's times,
      // then before or after (after lit), then the amounts.
      for (final name in ['الفجر', 'الظهر', 'العصر', 'المغرب', 'العشاء']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text(ar.prayerSlotWhen), findsOneWidget);
      await tester.tap(find.text('العصر'));
      await settle(tester);
      await tester.tap(find.text('15'));
      await settle(tester);

      // Back on the Add sheet: the row says the prayer, then the moment.
      expect(find.text(ar.prayerSlotWhen), findsNothing, reason: 'closed');
      expect(find.text('بعد العصر بـ15 دقيقة'), findsOneWidget);
      expect(find.byIcon(Icons.mosque_rounded), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'اتصل بالبنك');
      await tester.pump();
      await tester.tap(find.text(ar.matrixAddTask));
      await settle(tester);
      final at = asrOn(day).add(const Duration(minutes: 15));
      expect(added, hasLength(1));
      expect(added.single.prayer, (prayer: 'asr', offset: 15));
      expect(added.single.anchor, at);
      expect(added.single.at, [at]);

      // The next task starts clean: both ways in again.
      expect(find.text(ar.reminderWithPrayer), findsOneWidget);
    });

    testWidgets('a clock time picked afterwards takes the prayer off',
        (tester) async {
      await openAdd(tester, day: inDays(3));
      await tester.tap(find.text(ar.reminderWithPrayer));
      await settle(tester);
      await tester.tap(find.text('15'));
      await settle(tester);
      expect(find.byIcon(Icons.mosque_rounded), findsOneWidget);

      // The row's ×, then the clock.
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await settle(tester);
      expect(find.text(ar.reminderWithPrayer), findsOneWidget);
      await tester.tap(find.text(ar.matrixReminderLabel));
      await settle(tester);
      await tester.tap(find.text(ar.matrixDone));
      await settle(tester);
      expect(find.byIcon(Icons.mosque_rounded), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'x');
      await tester.pump();
      await tester.tap(find.text(ar.matrixAddTask));
      await settle(tester);
      expect(added.single.anchor, isNotNull);
      expect(added.single.prayer, isNull);
    });

    testWidgets('a time that has gone is refused in the sheet, which stays',
        (tester) async {
      Future<({PrayerSlot? slot})?>? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.dark,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = showPrayerSlotSheet(
                context,
                title: ar.reminderWithPrayer,
                prayers: const [
                  (
                    key: 'asr',
                    label: 'العصر',
                    at: TimeOfDay(hour: 15, minute: 0),
                  ),
                ],
                prayer: 'asr',
                current: null,
                // Before has gone; after is ahead.
                refuse: (_, offset) =>
                    offset < 0 ? ar.matrixReminderPast : null,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);

      await tester.tap(find.text(ar.offsetBeforeLabel));
      await settle(tester);
      await tester.tap(find.text('15'));
      await settle(tester);
      expect(find.text(ar.matrixReminderPast), findsOneWidget);
      expect(
        find.text(ar.prayerSlotWhen),
        findsOneWidget,
        reason: 'still open',
      );

      await tester.tap(find.text(ar.offsetAfterLabel));
      await settle(tester);
      expect(
        find.text(ar.matrixReminderPast),
        findsNothing,
        reason: 'a change clears it',
      );
      await tester.tap(find.text('15'));
      await settle(tester);
      expect((await result)!.slot, (prayer: 'asr', offset: 15));
    });
  });
}
