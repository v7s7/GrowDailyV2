// Step 3 for a habit counted several times a day: a prayer per time (Aziz,
// 2026-10-01: "option 2, but user can set like 30 min before fajr, and 30
// after fajr, so it should be well designed to do that").
//
// «مع وقت صلاة» used to be taken off the step for such a habit, since a
// prayer is one moment. Now it opens one row per time, and a row opens one
// sheet asking the prayer and the side together (showPrayerSlotSheet). The
// rows save as one cue, `custom_time:fajr-30,fajr+30` (see
// HabitCue.prayerSlots); one row set saves as the bare prayer with its
// shift in the habit's own field, the shape a once-a-day prayer habit has
// always had.
//
// The harness is reminder_step_test's: in-memory Hive boxes, a Manama place
// so every prayer has a time, the notifications channel mocked to refuse,
// and a view tall enough for the whole step.
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
import 'package:grow_daily_v2/core/l10n/reminder_copy.dart'
    show reminderOffsetLabel;
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/core/utils/western_digits.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cue.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';
import 'package:grow_daily_v2/features/habits/widgets/habit_offset_sheet.dart'
    show habitReminderSentence;
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:grow_daily_v2/features/settings/notifiers/notification_settings_notifier.dart';

import 'support/add_habit_flow.dart';

const _manama = NotificationLocation(
  lat: 26.2285,
  lng: 50.5860,
  label: 'Manama, Bahrain',
);

void main() {
  late Directory tmp;
  late ProviderContainer container;

  /// Seeded per test: a habit twice a day, 30 before Fajr and 30 after it.
  late IslamicHabitTemplate fajrPair;

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
    tmp = await Directory.systemTemp.createTemp('prayer_per_time_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings', bytes: Uint8List(0));
    await Hive.openBox<dynamic>('box_daily_logs', bytes: Uint8List(0));
    await Hive.openBox<dynamic>('box_habits', bytes: Uint8List(0));
    const dpr = 3.0;
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(430 * dpr, 2400 * dpr);
    view.devicePixelRatio = dpr;

    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumAccessProvider.overrideWithValue(true),
      ],
    );
    await container.read(authStateProvider.future);
    container.read(customHabitsProvider);
    await container
        .read(notificationSettingsProvider.notifier)
        .update((s) => s.copyWith(location: _manama));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    fajrPair = container.read(customHabitsProvider.notifier).add(
          name: 'ماء',
          category: HabitCategory.health,
          cueAfter: 'custom_time:fajr-30,fajr+30',
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 2,
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

  IslamicHabitTemplate created() => container
      .read(customHabitsProvider)
      .singleWhere((h) => h.id != fajrPair.id);

  Future<void> open(
    WidgetTester tester,
    Locale locale, {
    IslamicHabitTemplate? existing,
  }) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          locale: locale,
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

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  String prayer(String key, S s) => HabitCue.preset(key).labelForLocale(s.isAr);

  String row(S s, String key, int offset) =>
      habitReminderSentence(offset, s, prayer: prayer(key, s));

  /// Inside the open slot sheet only: the step behind it names prayers too.
  Finder inSheet(Finder f) =>
      find.descendant(of: find.byType(BottomSheet), matching: f);

  /// To step 3 of a new habit counted [times] a day, the prayer card picked.
  Future<void> toPrayerRows(WidgetTester tester, S s, {int times = 2}) async {
    await toOften(tester, s, name: s.isAr ? 'ماء' : 'Water');
    await pickOften(tester, s.oftenEveryDay);
    for (var i = 1; i < times; i++) {
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(s.continueAction));
    await tester.pumpAndSettle();
    await pickPrayerKind(tester, s);
  }

  /// Opens row [i] (0-based), whatever it says now.
  Future<void> openRow(WidgetTester tester, S s, int i) async {
    await tester.tap(find.text(s.prayerSlotTitle(i + 1)).evaluate().isEmpty
        ? find.byIcon(Icons.mosque_outlined).at(i)
        : find.text(s.prayerSlotTitle(i + 1)));
    await tester.pumpAndSettle();
  }

  /// In the open sheet: [key]'s pill, the side, and the amount chip, which
  /// saves and closes.
  Future<void> setRow(
    WidgetTester tester,
    S s, {
    required String key,
    required int offset,
  }) async {
    await tester.tap(inSheet(find.text(prayer(key, s))));
    await tester.pumpAndSettle();
    if (offset == 0) {
      await tester.tap(inSheet(find.text(s.leadAtTime)));
    } else {
      await tester.tap(inSheet(find.text(
          offset < 0 ? s.offsetBeforeLabel : s.offsetAfterLabel)));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.text(
          toWesternDigits(reminderOffsetLabel(offset.abs(), s.isAr)))));
    }
    await tester.pumpAndSettle();
  }

  /// Whether the pill labelled [label] in the open sheet is the lit one.
  bool lit(WidgetTester tester, String label) =>
      tester
          .widget<Semantics>(
            find
                .ancestor(
                  of: inSheet(find.text(label)),
                  matching: find.byWidgetPredicate(
                    (w) => w is Semantics && (w.properties.button ?? false),
                  ),
                )
                .first,
          )
          .properties
          .selected ??
      false;

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    testWidgets('[$tag] twice a day: the prayer card is offered and opens a '
        'row per time', (tester) async {
      await open(tester, locale);
      await toPrayerRows(tester, s);

      expect(find.text(s.prayerPerTimeNote), findsOneWidget);
      expect(find.text(s.pickAPrayer), findsNWidgets(2),
          reason: 'two times, two rows, neither set');
      for (final key in ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha']) {
        expect(find.text(prayer(key, s)), findsNothing,
            reason: 'no row of five prayers on the step: they are in the '
                'sheet a row opens');
      }
    });

    testWidgets('[$tag] 30 before Fajr and 30 after it, in two taps a row',
        (tester) async {
      await open(tester, locale);
      await toPrayerRows(tester, s);

      await openRow(tester, s, 0);
      expect(find.text(s.prayerSlotTitle(1)), findsOneWidget);
      expect(lit(tester, prayer('fajr', s)), isTrue,
          reason: 'the first row opens on Fajr');
      await setRow(tester, s, key: 'fajr', offset: -30);
      expect(find.text(row(s, 'fajr', -30)), findsOneWidget);

      await openRow(tester, s, 1);
      expect(lit(tester, prayer('fajr', s)), isTrue,
          reason: 'after a row set BEFORE Fajr, the next opens on Fajr');
      // The side leans after, so the amount alone saves it.
      await tester.tap(inSheet(find.text(
          toWesternDigits(reminderOffsetLabel(30, s.isAr)))));
      await tester.pumpAndSettle();
      expect(find.text(row(s, 'fajr', 30)), findsOneWidget);

      await addHabit(tester, s);
      await settle(tester);
      final habit = created();
      expect(habit.cueAfter, 'custom_time:fajr-30,fajr+30');
      expect(habit.frequencyTarget, 2);
      expect(habit.reminderOffsetMinutes, 0,
          reason: 'each time carries its own shift in the cue');
      expect(habit.extraReminderOffsets, isEmpty);
    });
  }

  final ar = const S(Locale('ar'));

  testWidgets('after a row on or after a prayer, the next opens on the next '
      'prayer', (tester) async {
    await open(tester, const Locale('ar'));
    await toPrayerRows(tester, ar, times: 3);

    await openRow(tester, ar, 0);
    await setRow(tester, ar, key: 'dhuhr', offset: 0);
    await openRow(tester, ar, 1);
    expect(lit(tester, prayer('asr', ar)), isTrue);
    await setRow(tester, ar, key: 'asr', offset: 10);
    await openRow(tester, ar, 2);
    expect(lit(tester, prayer('maghrib', ar)), isTrue);
    // Closed without a pick: the row stays empty.
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.text(ar.pickAPrayer), findsOneWidget);

    await addHabit(tester, ar);
    await settle(tester);
    expect(created().cueAfter, 'custom_time:dhuhr,asr+10',
        reason: 'the row left empty is no reminder, never a block');
  });

  testWidgets('one row set saves as the plain prayer with its shift',
      (tester) async {
    await open(tester, const Locale('ar'));
    await toPrayerRows(tester, ar);

    await openRow(tester, ar, 1);
    await setRow(tester, ar, key: 'asr', offset: 15);
    await addHabit(tester, ar);
    await settle(tester);
    final habit = created();
    expect(habit.cueAfter, 'asr');
    expect(habit.reminderOffsetMinutes, 15);
    expect(habit.frequencyTarget, 2);
  });

  testWidgets('the same prayer and side twice is flagged and saved once',
      (tester) async {
    await open(tester, const Locale('ar'));
    await toPrayerRows(tester, ar);

    await openRow(tester, ar, 0);
    await setRow(tester, ar, key: 'isha', offset: 0);
    expect(find.text(ar.habitDuplicateTime), findsNothing);
    await openRow(tester, ar, 1);
    await setRow(tester, ar, key: 'isha', offset: 0);
    expect(find.text(ar.habitDuplicateTime), findsOneWidget,
        reason: 'on the later row only');

    await addHabit(tester, ar);
    await settle(tester);
    expect(created().cueAfter, 'isha');
  });

  testWidgets('a row\'s reminder can be taken off in its sheet',
      (tester) async {
    await open(tester, const Locale('ar'));
    await toPrayerRows(tester, ar);

    await openRow(tester, ar, 0);
    expect(inSheet(find.text(ar.prayerSlotClear)), findsNothing,
        reason: 'an empty row has nothing to take off');
    await setRow(tester, ar, key: 'fajr', offset: 0);
    await openRow(tester, ar, 0);
    await tester.tap(inSheet(find.text(ar.prayerSlotClear)));
    await tester.pumpAndSettle();
    expect(find.text(ar.pickAPrayer), findsNWidgets(2));
  });

  testWidgets('an edit opens on its rows and saves them as they were',
      (tester) async {
    await open(tester, const Locale('ar'), existing: fajrPair);

    expect(find.text(prayer('fajr', ar)), findsOneWidget,
        reason: 'the overview names the prayer once');
    expect(
      find.textContaining(row(ar, 'fajr', -30)),
      findsOneWidget,
      reason: 'and says each reminder under it',
    );

    await openEditStep(tester, ar, 2);
    expect(find.text(row(ar, 'fajr', -30)), findsOneWidget);
    expect(find.text(row(ar, 'fajr', 30)), findsOneWidget);
    await editStepDone(tester, ar);
    await saveEdit(tester, ar);
    await settle(tester);

    final saved = stored(fajrPair.id);
    expect(saved.cueAfter, 'custom_time:fajr-30,fajr+30');
    expect(saved.frequencyTarget, 2);
  });

  testWidgets('a prayer picked once a day becomes the first row, and stays '
      'when the count comes back down', (tester) async {
    await open(tester, const Locale('ar'));
    await toReminder(tester, ar, name: 'ماء');
    await pickPrayerKind(tester, ar);
    await tester.tap(find.text(prayer('maghrib', ar)));
    await tester.pumpAndSettle();

    // Back to step 2, up to three a day.
    await tester.tap(find.text(ar.back));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ar.continueAction));
    await tester.pumpAndSettle();

    final onTime = row(ar, 'maghrib', 0);
    expect(find.text(onTime), findsOneWidget, reason: 'row 1 is the prayer');
    expect(find.text(ar.pickAPrayer), findsNWidgets(2));

    // And back to once a day: the prayer is the prayer again.
    await tester.tap(find.text(ar.back));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ar.continueAction));
    await tester.pumpAndSettle();
    await addHabit(tester, ar);
    await settle(tester);
    expect(created().cueAfter, 'maghrib');
    expect(created().frequencyTarget, 1);
  });
}
