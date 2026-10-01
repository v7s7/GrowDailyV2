// Step 3, «التذكير (اختياري)»: two cards, and nothing picked.
//
// Whether a habit has a MOMENT at all is its own question, asked last and
// marked optional, and the resting answer is none. Under the question sit two
// cards, «على ساعة معيّنة» and «مع وقت صلاة», with neither lit for any new
// habit: the mode a habit ends up with is one somebody chose.
//
// What this replaced is worth stating, because it is the bug being fixed
// rather than a style change. The picker used to open with a mode already
// selected (Prayer for anything that read as faith, Custom Text for a quit
// goal) and a line of small print under it explaining that you could skip
// this if it did not apply. So the honest, common answer ("no particular
// time") was reachable only by leaving a control alone and believing a
// sentence that asked you not to use it, while the guess sat there looking
// like an answer already given. From 2026-09-09 the answer sat behind a
// timing SWITCH, off by default, with three mode chips under it.
//
// 2026-10-01 (the three-step sheet, canvas v8): the switch is gone, and so is
// the third chip, «نص مخصص», with its «قبل | بعد» pair. A new habit can no
// longer be given a written cue; an edited habit that already has one opens
// on a card showing its words, with an × that drops it. A card is taken back
// by tapping it again, which is what turning the switch off used to be, and
// the clock card opens the time picker the moment it is tapped, since the
// time is what was just asked for. For a habit counted more than once a day
// the prayer card opens a prayer per time (prayer_per_time_test.dart).
//
// timing_toggle_test.dart pinned the switch; this file replaces it and keeps
// its intent: nothing chosen on arrival, a choice only once it is made, a
// faith habit not handed a prayer, an edit opening on what was saved, and
// taking the reminder away actually dropping the cue on save.
//
// The harness is prayer_reminder_direction_test's, because two tests here
// save: the Hive boxes are in memory (a file-backed write inside a
// testWidgets body never finishes), the habits and a Manama location are
// seeded in setUp, the notifications channel is mocked to refuse, and the
// view is tall enough that the whole step is on screen.
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
import 'package:grow_daily_v2/features/habits/widgets/reminder_kind_card.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:grow_daily_v2/features/settings/notifiers/notification_settings_notifier.dart';

import 'support/add_habit_flow.dart';

const _manama = NotificationLocation(
  lat: 26.2285,
  lng: 50.5860,
  label: 'Manama, Bahrain',
);

const _prayerKeys = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];

void main() {
  const ar = S(Locale('ar'));
  late Directory tmp;
  late ProviderContainer container;

  /// The habits the edit tests open, seeded once per test: one reminded at
  /// Fajr, one with no reminder, one saved with its moment in words (before
  /// 2026-09-30 a new habit could still be given one), and one at 07:30 with
  /// its reminder 15 minutes before.
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
    tmp = await Directory.systemTemp.createTemp('reminder_step_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings', bytes: Uint8List(0));
    await Hive.openBox<dynamic>('box_daily_logs', bytes: Uint8List(0));
    await Hive.openBox<dynamic>('box_habits', bytes: Uint8List(0));
    // 430 wide, a large phone: the test font draws Latin letters a full em
    // wide, about twice what the phone's font does, and at 402 the English
    // «ذكّرني» style row (reminder_style_choice.dart) ran 3pt over.
    const dpr = 3.0;
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(430 * dpr, 2400 * dpr);
    view.devicePixelRatio = dpr;

    // Premium, so the habit cap never answers before the form does. A
    // saved place, so picking a prayer never goes off looking for one.
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
    final notifier = container.read(customHabitsProvider.notifier);
    IslamicHabitTemplate add(String name, String cue, {int offset = 0}) =>
        notifier.add(
          name: name,
          category: HabitCategory.faith,
          cueAfter: cue,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
          reminderOffsetMinutes: offset,
        );
    habits = {
      'prayer': add('قراءة القرآن', 'fajr'),
      'none': add('تسبيح', ''),
      'written': add('تخطيط', 'بعد العمل'),
      'clock': add('بروتين', 'custom_time:07:30', offset: -15),
    };
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

  /// The one habit a test created, beside the seeded ones.
  IslamicHabitTemplate created() =>
      container.read(customHabitsProvider).singleWhere(
            (h) => !habits.values.any((seeded) => seeded.id == h.id),
          );

  /// The sheet on a pushed route, so a save's Navigator.pop has somewhere to
  /// return to. A new habit opens on step 1; an edit on its overview.
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

  /// Past what a finished save leaves on screen: the burst over the button,
  /// and for a habit with a reminder the mocked permission refusal's
  /// SnackBar.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  /// Whether the card labelled [label] is the picked one. The card says so
  /// in its Semantics, which is also what a screen reader reads.
  bool picked(WidgetTester tester, String label) =>
      tester
          .widget<Semantics>(
            find
                .ancestor(
                  of: find.text(label),
                  matching: find.byWidgetPredicate(
                    (w) => w is Semantics && (w.properties.button ?? false),
                  ),
                )
                .first,
          )
          .properties
          .selected ??
      false;

  String prayerLabel(String key, S s) =>
      HabitCue.preset(key).labelForLocale(s.isAr);

  /// The five prayers, as a set: they arrive together and leave together.
  void expectPrayers(S s, Matcher matcher) {
    for (final key in _prayerKeys) {
      expect(find.text(prayerLabel(key, s)), matcher, reason: key);
    }
  }

  /// That the step has its question and its two cards, with neither lit
  /// and nothing under them.
  void expectNothingPicked(WidgetTester tester, S s) {
    expect(find.text(s.reminderQuestion), findsOneWidget);
    expect(find.text(s.reminderOptionalNote), findsOneWidget,
        reason: 'no reminder is said to be a real answer');
    expect(find.text(s.reminderAtClock), findsOneWidget);
    expect(find.text(s.reminderWithPrayer), findsOneWidget);
    expect(picked(tester, s.reminderAtClock), isFalse);
    expect(picked(tester, s.reminderWithPrayer), isFalse);
    expectPrayers(s, findsNothing);
    expect(find.text(s.pickATime), findsNothing,
        reason: 'no time rows until a card is tapped');
    expect(find.text(s.remindMeSection), findsNothing);
    expect(find.text(s.habitWrittenMoment), findsNothing);
  }

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    testWidgets('[$tag] a new habit reaches step 3 with nothing picked',
        (tester) async {
      await open(tester, locale);
      await toReminder(tester, s, name: s.isAr ? 'قراءة' : 'Read');

      expect(find.text(s.addHabitAction), findsOneWidget,
          reason: 'sanity: this is the last step');
      expectNothingPicked(tester, s);
      // Each card wears a small scene over its label (2026-10-01).
      expect(
        find.byWidgetPredicate(
            (w) => w is ReminderKindCard && w.kind == ReminderKind.clock),
        findsOneWidget,
        reason: 'the clock card',
      );
      expect(
        find.byWidgetPredicate(
            (w) => w is ReminderKindCard && w.kind == ReminderKind.prayer),
        findsOneWidget,
        reason: 'the prayer card',
      );
      // What the step used to be. None of it is drawn any more.
      expect(find.byType(Switch), findsNothing);
      expect(find.text(s.timingToggle), findsNothing);
      expect(find.text(s.customTime), findsNothing);
      expect(find.text(s.cuePrayerOption), findsNothing);
      expect(find.text(s.customText), findsNothing,
          reason: 'a new habit can no longer be given a written cue');
      expect(find.text(s.cueBeforeOption), findsNothing);
      expect(find.text(s.cueAfterOption), findsNothing);
    });
  }

  testWidgets('a quit habit reaches it with nothing picked too',
      (tester) async {
    await open(tester, const Locale('ar'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(choice(ar.goalTypeQuitOption));
    await tester.pumpAndSettle();
    await toReminder(tester, ar, name: 'القهوة');

    expect(find.text(ar.addHabitAction), findsOneWidget);
    expectNothingPicked(tester, ar);
    expect(find.text(ar.timingToggleQuit), findsNothing);
    expect(find.text(ar.customTriggerOptional), findsNothing,
        reason: 'the freeform trigger field used to be open by default for '
            'a quit goal');
  });

  // Until 2026-10-01 the card was taken off for such a habit, since a
  // prayer is one moment. Now it is a prayer per time; the flow itself is
  // pinned in prayer_per_time_test.dart.
  testWidgets('the prayer card is offered for a habit counted twice a day, '
      'unpicked', (tester) async {
    await open(tester, const Locale('ar'));
    await toOften(tester, ar);
    await pickOften(tester, ar.oftenEveryDay);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ar.continueAction));
    await tester.pumpAndSettle();

    expect(find.text(ar.reminderAtClock), findsOneWidget);
    expect(find.text(ar.reminderWithPrayer), findsOneWidget);
    expect(picked(tester, ar.reminderWithPrayer), isFalse);
    expect(find.text(ar.prayerPerTimeNote), findsNothing,
        reason: 'no rows until the card is tapped');
  });

  testWidgets(
      'the prayer card shows the five prayers, and tapped again takes them '
      'away and saves no cue', (tester) async {
    await open(tester, const Locale('ar'));
    await toReminder(tester, ar);

    await pickPrayerKind(tester, ar);
    expect(picked(tester, ar.reminderWithPrayer), isTrue);
    expect(picked(tester, ar.reminderAtClock), isFalse);
    expectPrayers(ar, findsOneWidget);
    expect(find.text(ar.pickAPrayer), findsNothing,
        reason: 'the prayers are their own question now, with no label');
    expect(find.text(ar.remindMeSection), findsNothing,
        reason: 'no reminder rows until a prayer is picked');

    await tester.tap(find.text(prayerLabel('fajr', ar)));
    await tester.pumpAndSettle();
    expect(find.text(ar.remindMeSection), findsOneWidget);
    expect(find.text('قراءة · ${ar.oftenEveryDay} · ${prayerLabel('fajr', ar)}'),
        findsOneWidget,
        reason: 'the strip says the reminder, from the cue the save writes');

    await pickPrayerKind(tester, ar);
    expect(picked(tester, ar.reminderWithPrayer), isFalse);
    expectPrayers(ar, findsNothing);
    expect(find.text(ar.remindMeSection), findsNothing);
    expect(find.text('قراءة · ${ar.oftenEveryDay}'), findsOneWidget,
        reason: 'taken back, so the strip has no reminder to say');

    await addHabit(tester, ar);
    await settle(tester);
    final habit = created();
    expect(habit.cueAfter ?? '', isEmpty,
        reason: 'Fajr was picked and then taken back with its card');
    expect(habit.reminderOffsetMinutes, 0);
    expect(habit.extraReminderOffsets, isEmpty);
    expect(habit.alarm, isFalse);
  });

  testWidgets('the clock card opens the time picker at once, and the picked '
      'time shows', (tester) async {
    await open(tester, const Locale('ar'));
    await toReminder(tester, ar);

    final before = TimeOfDay.now();
    await pickClockKind(tester, ar, confirm: false);
    expect(find.byType(TimePickerDialog), findsOneWidget,
        reason: 'the time is what was just asked for');
    expect(picked(tester, ar.reminderAtClock), isTrue);

    await tester.tap(find.text(
      MaterialLocalizations.of(tester.element(find.byType(TimePickerDialog)))
          .okButtonLabel,
    ));
    await tester.pumpAndSettle();
    final after = TimeOfDay.now();

    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.text(ar.pickATime), findsNothing,
        reason: 'the row holds the picked time, not the empty prompt');
    // The picker opens on the current time, so OK picks that. Either side
    // of a minute boundary, in case the clock turned over between the two.
    final labels = {
      for (final t in [before, after])
        HabitCue.time(t.hour, t.minute).labelForLocale(true),
    };
    expect(
      labels.any((label) => find.text(label).evaluate().isNotEmpty),
      isTrue,
      reason: 'one of $labels is on the time row',
    );
    expect(find.text(ar.remindMeSection), findsOneWidget,
        reason: 'a time picked, so its reminder rows follow');
    expect(picked(tester, ar.reminderWithPrayer), isFalse);
  });

  testWidgets('a faith habit is not handed a prayer nobody picked',
      (tester) async {
    // The old default: category faith opened the Prayer picker, and its five
    // chips were on screen whether or not the person ever went near them.
    await open(tester, const Locale('ar'));
    await typeName(tester, 'أذكار الصباح');
    expect(
      find.text(ar.habitCategoryLine(HabitCategory.faith.localizedName(true))),
      findsOneWidget,
      reason: 'sanity: the name reads as faith',
    );
    await tester.tap(find.text(ar.continueAction));
    await tester.pumpAndSettle();
    await pickOften(tester, ar.oftenEveryDay);
    await tester.tap(find.text(ar.continueAction));
    await tester.pumpAndSettle();

    expectNothingPicked(tester, ar);
  });

  // ── An edited habit opens step 3 on what it was saved with ────────────

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    testWidgets('[$tag] saved with a prayer, it reopens with the prayer lit',
        (tester) async {
      await open(tester, locale, existing: habits['prayer']);
      expect(find.text(prayerLabel('fajr', s)), findsOneWidget,
          reason: 'the overview names the reminder');
      await openEditStep(tester, s, 2);

      expect(picked(tester, s.reminderWithPrayer), isTrue,
          reason: 'editing is the one path where a card arrives lit');
      expect(picked(tester, s.reminderAtClock), isFalse);
      expectPrayers(s, findsOneWidget);
      expect(
        tester.widget<Text>(find.text(prayerLabel('fajr', s))).style?.fontWeight,
        FontWeight.w800,
        reason: 'Fajr is the lit prayer',
      );
      expect(
        tester.widget<Text>(find.text(prayerLabel('isha', s))).style?.fontWeight,
        FontWeight.w600,
      );
      expect(find.text(s.remindMeSection), findsOneWidget);
      expect(find.text(s.habitEditStepDone), findsOneWidget);
    });

    testWidgets('[$tag] saved without a reminder, it reopens with none',
        (tester) async {
      await open(tester, locale, existing: habits['none']);
      expect(find.text(s.noReminder), findsOneWidget,
          reason: 'the overview says so');
      await openEditStep(tester, s, 2);

      expectNothingPicked(tester, s);
    });

    testWidgets('[$tag] saved with its moment in words, it reopens on them',
        (tester) async {
      await open(tester, locale, existing: habits['written']);
      await openEditStep(tester, s, 2);

      expect(find.text(s.habitWrittenMoment), findsOneWidget);
      expect(find.text('بعد العمل'), findsOneWidget,
          reason: 'the words as they were typed, in either language');
      expect(find.byTooltip(s.habitReminderRemove), findsOneWidget);
      expect(picked(tester, s.reminderAtClock), isFalse,
          reason: 'words are neither a clock time nor a prayer');
      expect(picked(tester, s.reminderWithPrayer), isFalse);
      expect(find.text(s.customText), findsNothing,
          reason: 'kept as a card, not as the old mode with its field');
    });
  }

  // ── Taking the reminder away drops it on save ──────────────────────────

  testWidgets('tapping the lit card off drops the cue the habit had',
      (tester) async {
    final habit = habits['clock']!;
    await open(tester, const Locale('ar'), existing: habit);
    await openEditStep(tester, ar, 2);
    expect(picked(tester, ar.reminderAtClock), isTrue);
    expect(find.textContaining('7:30'), findsWidgets,
        reason: 'the time is on its row and in the strip');

    await tester.tap(choice(ar.reminderAtClock));
    await tester.pumpAndSettle();
    expect(picked(tester, ar.reminderAtClock), isFalse);
    expect(find.textContaining('7:30'), findsNothing,
        reason: 'off means off: the strip is built by the same method the '
            'save writes, and the time has left it');
    expect(find.byType(TimePickerDialog), findsNothing,
        reason: 'taking a card back never opens the picker');

    await editStepDone(tester, ar);
    expect(find.text(ar.noReminder), findsOneWidget);

    // The one tap that could put the cue back behind the step's back. The
    // per-day stepper carries a single moment onto the clock time when the
    // count goes above one, and the picked time is kept in memory while no
    // card is lit, so without the guard on that carry this tap would
    // resurrect «7:30» into a habit whose step says it has no reminder.
    await openEditStep(tester, ar, 1);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await editStepDone(tester, ar);
    expect(find.text(ar.noReminder), findsOneWidget,
        reason: 'no reminder stays no reminder through the stepper');
    expect(find.textContaining('7:30'), findsNothing);

    await saveEdit(tester, ar);
    await settle(tester);
    final saved = stored(habit.id);
    expect(saved.cueAfter ?? '', isEmpty);
    expect(saved.reminderOffsetMinutes, 0,
        reason: 'the 15 minutes before went with the time it was before');
    expect(saved.extraReminderOffsets, isEmpty);
    expect(saved.frequencyTarget, 2, reason: 'sanity: the stepper took');
  });

  testWidgets('the × on a moment in words drops it on save', (tester) async {
    final habit = habits['written']!;
    await open(tester, const Locale('ar'), existing: habit);
    await openEditStep(tester, ar, 2);

    await tester.tap(find.byTooltip(ar.habitReminderRemove));
    await tester.pumpAndSettle();
    expectNothingPicked(tester, ar);
    expect(find.text('بعد العمل'), findsNothing);

    await editStepDone(tester, ar);
    expect(find.text(ar.noReminder), findsOneWidget);
    await saveEdit(tester, ar);
    await settle(tester);
    expect(stored(habit.id).cueAfter ?? '', isEmpty);
    expect(stored(habit.id).reminderOffsetMinutes, 0);
  });
}
