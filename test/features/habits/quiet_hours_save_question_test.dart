// Saving a habit whose reminder falls inside quiet hours asks whether to turn
// them off (Aziz, 2026-09-28), and only then: quiet hours are off by default
// now, and a reminder that will ring needs no question.
//
// Driven through the real sheet in Arabic, the way a person saves one, and
// read back from what _submit handed the habits notifier and the settings.
// The harness is prayer_reminder_direction_test's, for the same reasons: the
// Hive boxes are in memory (a file-backed write inside a testWidgets body
// never finishes), the habits and a Manama location are seeded outside the
// test bodies, and the notifications channel is mocked to refuse, since Save
// asks for permission.
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
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/services/prayer_times_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cue.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';
import 'package:grow_daily_v2/features/habits/widgets/quiet_hours_conflict_dialog.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:grow_daily_v2/features/settings/notifiers/notification_settings_notifier.dart';
import 'package:grow_daily_v2/shared/widgets/choice_chip_grid.dart';
import 'package:hive/hive.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const _manama = NotificationLocation(
  lat: 26.2285,
  lng: 50.5860,
  label: 'Manama, Bahrain',
);

void main() {
  const ar = S(Locale('ar'));
  late Directory tmp;
  late ProviderContainer container;
  late Map<String, IslamicHabitTemplate> habits;

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
    tmp = await Directory.systemTemp.createTemp('quiet_question_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings', bytes: Uint8List(0));
    await Hive.openBox<dynamic>('box_daily_logs', bytes: Uint8List(0));
    await Hive.openBox<dynamic>('box_habits', bytes: Uint8List(0));
    const dpr = 3.0;
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(402 * dpr, 2400 * dpr);
    view.devicePixelRatio = dpr;
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

  /// Premium, so the habit cap never answers first; a Manama location, so
  /// Fajr has a clock time (it always falls between 22:00 and 07:00 there);
  /// quiet hours as the test says. Four habits to edit: 45 before Fajr, 15
  /// before a 07:30 clock time, 07:30 with a second reminder at 06:30, and
  /// twice a day with the morning time's own shift putting it at 06:30.
  Future<void> boot({
    required bool quietOn,
    bool prayerToo = true,
  }) async {
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumAccessProvider.overrideWithValue(true),
      ],
    );
    await container.read(authStateProvider.future);
    container.read(customHabitsProvider);
    await container.read(notificationSettingsProvider.notifier).update(
          (s) => s.copyWith(
            location: _manama,
            quietHoursEnabled: quietOn,
            quietHoursAppliesToPrayer: prayerToo,
          ),
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final notifier = container.read(customHabitsProvider.notifier);
    habits = {
      'tahajjud': notifier.add(
        name: 'صلاة التهجد',
        category: HabitCategory.faith,
        cueAfter: 'fajr',
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        reminderOffsetMinutes: -45,
      ),
      'clock': notifier.add(
        name: 'بروتين',
        category: HabitCategory.health,
        cueAfter: 'custom_time:07:30',
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        reminderOffsetMinutes: -15,
      ),
      // On time at 07:30, and a second reminder an hour before, at 06:30.
      'stacked': notifier.add(
        name: 'تمر',
        category: HabitCategory.health,
        cueAfter: 'custom_time:07:30',
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        extraReminderOffsets: [-60],
      ),
      // Twice a day, each time with its own shift: 07:30 an hour early, so
      // 06:30, and 19:30 on time.
      'twice': notifier.add(
        name: 'فيتامين',
        category: HabitCategory.health,
        cueAfter: 'custom_time:07:30-60,19:30',
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 2,
      ),
    };
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  NotificationSettings settings() => container.read(notificationSettingsProvider);

  List<IslamicHabitTemplate> all() => container.read(customHabitsProvider);

  IslamicHabitTemplate stored(String id) =>
      all().firstWhere((h) => h.id == id);

  /// The one habit the test created, beside the two seeded.
  IslamicHabitTemplate created() => all().singleWhere(
        (h) => !habits.values.any((seeded) => seeded.id == h.id),
      );

  Future<void> open(
    WidgetTester tester, [
    IslamicHabitTemplate? existing,
  ]) async {
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
    if (existing == null) return;
    await tester.tap(find.text(ar.continueAction));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  /// A new habit, «قراءة» daily, reminded at Fajr.
  Future<void> openNewAtFajr(WidgetTester tester) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).first, 'قراءة');
    await tester.pump();
    await tapText(tester, ar.continueAction);
    await tester.tap(
      find
          .ancestor(of: find.text(ar.daily), matching: find.byType(InkWell))
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tapText(tester, ar.cuePrayerOption);
    await tapText(tester, 'الفجر');
  }

  /// Presses the sheet's own button, and stops there: what comes next is
  /// what the test is about.
  Future<void> pressSave(WidgetTester tester, {bool existing = false}) =>
      tapText(tester, existing ? ar.saveChanges : ar.createGoal);

  /// Past what a finished save leaves on screen: the mocked permission
  /// refusal shows its SnackBar for four seconds.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  Finder question() => find.byType(QuietHoursConflictCard);

  /// The question's own words, never the line under the time, which says
  /// «ضمن ساعات الهدوء» too.
  String questionBody(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: question(),
          matching: find.textContaining('ضمن ساعات الهدوء'),
        ),
      )
      .data!;

  /// Today's Fajr in Manama, written the way the sheet writes a time.
  String fajrLabel() {
    final fajr = PrayerTimesService.calculateOfflineCorrected(
      latitude: _manama.lat,
      longitude: _manama.lng,
      date: DateTime.now(),
      countryCode: settings().resolvedCountryCode,
    ).forKey('fajr')!;
    return HabitCue.time(fajr.hour, fajr.minute).labelForLocale(true);
  }

  group('quiet hours off, the new default', () {
    setUp(() => boot(quietOn: false));

    test('a fresh install starts with them off', () {
      expect(const NotificationSettings().quietHoursEnabled, isFalse);
    });

    testWidgets('a Fajr reminder saves with no question', (tester) async {
      await openNewAtFajr(tester);
      expect(find.text(ar.quietHoursConflictWarning), findsNothing,
          reason: 'off, the reminder rings, so nothing under the time either',);
      await pressSave(tester);
      expect(question(), findsNothing);
      await settle(tester);
      expect(created().cueAfter, 'fajr');
    });
  });

  group('quiet hours on, prayers included', () {
    setUp(() => boot(quietOn: true));

    testWidgets('saving asks, with the time and the window', (tester) async {
      await openNewAtFajr(tester);
      await pressSave(tester);

      expect(question(), findsOneWidget);
      expect(find.text(ar.quietConflictTitle), findsOneWidget);
      expect(find.text(ar.quietConflictQuestion), findsOneWidget);
      final body = questionBody(tester);
      expect(body, startsWith('الساعة ${fajrLabel()} '),
          reason: 'the time that would go quiet',);
      expect(body, contains('من 10:00 م إلى 7:00 ص'),
          reason: 'the window, in the clock format the sheet uses',);
      expect(all(), hasLength(habits.length),
          reason: 'nothing is saved while it asks',);
    });

    testWidgets('«إيه، وقّفها» turns quiet hours off and saves', (tester) async {
      await openNewAtFajr(tester);
      await pressSave(tester);
      await tapText(tester, ar.quietConflictTurnOff);
      await settle(tester);

      expect(settings().quietHoursEnabled, isFalse);
      expect(created().cueAfter, 'fajr');
      expect(created().ignoreQuietHours, isFalse,
          reason: 'nothing to let through once they are off',);
    });

    testWidgets('«خلّ هذا التذكير يوصل» lets only this habit through',
        (tester) async {
      await openNewAtFajr(tester);
      await pressSave(tester);
      await tapText(tester, ar.quietConflictAllowThis);
      await settle(tester);

      expect(settings().quietHoursEnabled, isTrue);
      expect(created().ignoreQuietHours, isTrue);
    });

    testWidgets('«لا، خلّها» saves it as it is', (tester) async {
      await openNewAtFajr(tester);
      await pressSave(tester);
      await tapText(tester, ar.quietConflictKeep);
      await settle(tester);

      expect(settings().quietHoursEnabled, isTrue);
      expect(created().ignoreQuietHours, isFalse);
    });

    testWidgets('closing it keeps the form open and saves nothing',
        (tester) async {
      await openNewAtFajr(tester);
      await pressSave(tester);
      expect(question(), findsOneWidget);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(question(), findsNothing);
      expect(find.text(ar.createGoal), findsOneWidget,
          reason: 'still on the form, so the time can be changed',);
      expect(all(), hasLength(habits.length));
      expect(settings().quietHoursEnabled, isTrue);
    });

    testWidgets('the line under the time is an answer: no question after it',
        (tester) async {
      await openNewAtFajr(tester);
      await tapText(tester, ar.quietHoursAllowAnywayAction);
      await pressSave(tester);
      expect(question(), findsNothing);
      await settle(tester);
      expect(created().ignoreQuietHours, isTrue);
    });

    testWidgets('choosing «احترم ساعات الهدوء» there is an answer too',
        (tester) async {
      // Let through, then back: they know it will not ring, and said so.
      await openNewAtFajr(tester);
      await tapText(tester, ar.quietHoursAllowAnywayAction);
      await tapText(tester, ar.quietHoursRespectAction);
      await pressSave(tester);
      expect(question(), findsNothing);
      await settle(tester);
      expect(created().ignoreQuietHours, isFalse);
    });

    testWidgets('an edit that leaves the reminder alone is not asked again',
        (tester) async {
      final habit = habits['tahajjud']!;
      await open(tester, habit);
      expect(find.text(ar.quietHoursConflictWarning), findsOneWidget,
          reason: 'sanity: 45 before Fajr is inside quiet hours',);
      await pressSave(tester, existing: true);
      expect(question(), findsNothing);
      await settle(tester);
      expect(stored(habit.id).reminderOffsetMinutes, -45);
    });
  });

  group('quiet hours on, prayers left alone', () {
    setUp(() => boot(quietOn: true, prayerToo: false));

    testWidgets('a Fajr reminder rings through them, so no question',
        (tester) async {
      await openNewAtFajr(tester);
      await pressSave(tester);
      expect(question(), findsNothing);
      await settle(tester);
      expect(created().cueAfter, 'fajr');
    });

    testWidgets('a second reminder inside them is seen, not only the first',
        (tester) async {
      // The warning used to look at the main shift alone: 07:30 is after
      // quiet hours end, so the 06:30 reminder beside it went quiet unsaid.
      final habit = habits['stacked']!;
      await open(tester, habit);
      expect(find.text(ar.quietHoursConflictWarning), findsOneWidget);
      await pressSave(tester, existing: true);
      expect(question(), findsNothing,
          reason: 'already silent when the sheet opened, and left as it was',);
      await settle(tester);
      expect(stored(habit.id).extraReminderOffsets, [-60]);
    });

    testWidgets('a time\'s own shift counts on a habit done several times',
        (tester) async {
      // Several times a day has no line under the time (each row carries
      // its own chips), so this goes by the save question: opened with quiet
      // hours off, nothing was silent then; on before saving, the morning
      // time, 07:30 an hour early, is. Adding the habit-level shift instead,
      // 0 for a habit like this, finds 07:30 and 19:30 both outside.
      final settingsNotifier =
          container.read(notificationSettingsProvider.notifier);
      settingsNotifier
          .update((s) => s.copyWith(quietHoursEnabled: false))
          .ignore();
      final habit = habits['twice']!;
      await open(tester, habit);
      settingsNotifier
          .update((s) => s.copyWith(quietHoursEnabled: true))
          .ignore();
      await tester.pumpAndSettle();
      await pressSave(tester, existing: true);

      expect(question(), findsOneWidget);
      expect(questionBody(tester), startsWith('الساعة 6:30 ص '));
    });

    testWidgets('an edit that moves a clock reminder into them is asked',
        (tester) async {
      final habit = habits['clock']!;
      await open(tester, habit);
      expect(find.text(ar.quietHoursConflictWarning), findsNothing,
          reason: 'sanity: 07:15 is after quiet hours end',);

      // 15 before 07:30 to an hour before it: 06:30.
      await tapText(tester, 'قبل 15 دقيقة');
      await tester.tap(find.widgetWithText(PlainChoiceChip, 'ساعة'));
      await tester.pumpAndSettle();
      await pressSave(tester, existing: true);

      expect(question(), findsOneWidget);
      expect(questionBody(tester), startsWith('الساعة 6:30 ص '));
      await tapText(tester, ar.quietConflictKeep);
      await settle(tester);
      expect(stored(habit.id).reminderOffsetMinutes, -60);
    });
  });
}
