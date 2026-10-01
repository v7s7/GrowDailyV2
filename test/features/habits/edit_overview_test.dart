// Editing a habit opens on an overview of its three answers (canvas v8,
// board "Edit a habit", built 2026-10-01).
//
// It used to open on the name box with the keyboard up, and walk through
// both pages of the form to reach Save, whatever was being changed. Now the
// sheet says «تعديل العادة» over three rows, «العادة», «كم مرة» and
// «التذكير», each holding what is saved («قراءة», «كل يوم», «بدون تذكير»),
// with «احفظ التغييرات» and the Remove button under them. A row opens its
// step page with «تم» under it, which checks that step and comes back;
// saving happens on the overview. No step bar: an edit is not a walk through
// the steps.
//
// Harness as prayer_reminder_direction_test.dart learned it: the Hive boxes
// in memory, the habits seeded in setUp (never awaited in a test body), the
// sheet on a pushed route so Save's Navigator.pop has somewhere to go, and
// the notifications plugin registered with its channel mocked to refuse.
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show AndroidFlutterLocalNotificationsPlugin;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cue.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';

import 'support/add_habit_flow.dart';

void main() {
  const ar = S(Locale('ar'));
  late Directory tmp;
  late ProviderContainer container;

  /// «قراءة» every day with no reminder, and «رياضة» three times a week at
  /// 7:30.
  late IslamicHabitTemplate reading;
  late IslamicHabitTemplate sport;
  const sportCue = 'custom_time:07:30';

  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => false,
    );
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('edit_overview_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings', bytes: Uint8List(0));
    await Hive.openBox<dynamic>('box_daily_logs', bytes: Uint8List(0));
    await Hive.openBox<dynamic>('box_habits', bytes: Uint8List(0));
    const dpr = 3.0;
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(402 * dpr, 874 * dpr);
    view.devicePixelRatio = dpr;

    container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
    ]);
    await container.read(authStateProvider.future);
    container.read(customHabitsProvider);
    // The guest habit list loads from Hive once. Let it land before adding
    // to it, the way custom_habits_notifier_test does.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final notifier = container.read(customHabitsProvider.notifier);
    reading = notifier.add(
      name: 'قراءة',
      category: HabitCategory.learning,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
    );
    sport = notifier.add(
      name: 'رياضة',
      category: HabitCategory.health,
      cueAfter: sportCue,
      frequencyType: HabitFrequencyType.weekly,
      frequencyTarget: 3,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  tearDown(() async {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    container.dispose();
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  IslamicHabitTemplate stored(String id) =>
      container.read(customHabitsProvider).firstWhere((h) => h.id == id);

  /// The edit sheet for [existing] on a pushed route.
  Future<void> open(WidgetTester tester, IslamicHabitTemplate existing) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.dark,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: AddHabitSheet(existing: existing)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The value printed in the overview row labelled [label].
  Finder rowValue(String label, String value) => find.descendant(
        of: choice(label),
        matching: find.text(value),
      );

  testWidgets('the overview names the three answers: every day, no reminder',
      (tester) async {
    await open(tester, reading);

    expect(find.text(ar.editHabit), findsOneWidget);
    expect(find.text(ar.addHabitStepReminder), findsNothing,
        reason: 'no step bar on an edit');
    expect(find.byType(TextField), findsNothing,
        reason: 'it opens on the overview, not the name box');

    expect(rowValue(ar.addHabitStepWhat, 'قراءة'), findsOneWidget);
    expect(rowValue(ar.addHabitStepOften, ar.oftenEveryDay), findsOneWidget);
    expect(rowValue(ar.addHabitStepReminderShort, ar.noReminder),
        findsOneWidget);

    expect(find.text(ar.saveChanges), findsOneWidget);
    expect(find.text(ar.removeHabit), findsOneWidget);
    expect(find.text(ar.habitEditStepDone), findsNothing);
  });

  testWidgets('the overview names the three answers: a week count, a time',
      (tester) async {
    await open(tester, sport);

    expect(rowValue(ar.addHabitStepWhat, 'رياضة'), findsOneWidget);
    expect(ar.timesAWeekPhrase(3), '3 مرات بالأسبوع');
    expect(rowValue(ar.addHabitStepOften, ar.timesAWeekPhrase(3)),
        findsOneWidget);
    expect(
      rowValue(
        ar.addHabitStepReminderShort,
        HabitCue.fromStoredValue(sportCue).labelForLocale(true),
      ),
      findsOneWidget,
      reason: 'the reminder row says the saved moment',
    );
    expect(find.text(ar.noReminder), findsNothing);
  });

  testWidgets('a row opens its step, and «تم» comes back', (tester) async {
    await open(tester, reading);

    await openEditStep(tester, ar, 0);
    expect(find.byType(TextField), findsWidgets);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'قراءة',
    );
    expect(find.text(ar.habitEditStepDone), findsOneWidget,
        reason: 'a step page ends in «تم», not in save');
    expect(find.text(ar.saveChanges), findsNothing);
    expect(find.text(ar.continueAction), findsNothing);
    await editStepDone(tester, ar);
    expect(find.text(ar.saveChanges), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    // How often, changed on its page and carried back to the row.
    await openEditStep(tester, ar, 1);
    expect(find.text(ar.howOftenQuestion), findsOneWidget);
    expect(find.text(ar.back), findsNothing,
        reason: 'an edit\'s step page goes back with «تم», not «رجوع»');
    await pickOften(tester, ar.oftenTimesAWeek);
    await tester.tap(choice('3'));
    await tester.pumpAndSettle();
    await editStepDone(tester, ar);
    expect(find.text(ar.howOftenQuestion), findsNothing);
    expect(rowValue(ar.addHabitStepOften, ar.timesAWeekPhrase(3)),
        findsOneWidget,
        reason: 'the overview says the new answer');

    await openEditStep(tester, ar, 2);
    expect(find.text(ar.reminderQuestion), findsOneWidget);
    expect(find.text(ar.addHabitAction), findsNothing);
    await editStepDone(tester, ar);
    expect(find.text(ar.reminderQuestion), findsNothing);
    expect(rowValue(ar.addHabitStepReminderShort, ar.noReminder),
        findsOneWidget);
  });

  testWidgets('«احفظ التغييرات» saves a changed name', (tester) async {
    await open(tester, reading);

    await openEditStep(tester, ar, 0);
    await tester.enterText(find.byType(TextField).first, 'قراءة القرآن');
    await tester.pump();
    await editStepDone(tester, ar);
    expect(rowValue(ar.addHabitStepWhat, 'قراءة القرآن'), findsOneWidget,
        reason: 'the overview shows the name as typed before it is saved');
    expect(stored(reading.id).localName(true), 'قراءة',
        reason: '«تم» checks the step; only save writes');

    await saveEdit(tester, ar);

    expect(find.text(ar.saveChanges), findsNothing,
        reason: 'saving closes the sheet');
    expect(stored(reading.id).localName(true), 'قراءة القرآن');
    expect(stored(reading.id).frequencyType, HabitFrequencyType.daily,
        reason: 'and nothing else moved');
    expect(stored(reading.id).cueAfter ?? '', isEmpty);
  });
}
