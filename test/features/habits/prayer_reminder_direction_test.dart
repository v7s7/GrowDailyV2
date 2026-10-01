// The reminder rows on Add Habit's reminder step for a habit anchored to a
// prayer, and the offset sheet each row opens, which is where such a
// reminder's «قبل | بعد» is set.
//
// Since 2026-10-01 that step is the third of three, «التذكير (اختياري)»: a
// new habit reaches it through «العادة» and «كم مرة», and an edit opens on
// an overview whose «التذكير» row opens it, with «تم» back to the overview
// and «احفظ التغييرات» there. Its two cards, «على ساعة معيّنة» and «مع وقت
// صلاة», took over from the timing switch and the «وقت مخصص» / «وقت الصلاة»
// chips. The rows and the sheet are unchanged, and are what this file is
// about. Custom text went with the chips: a new habit can no longer write
// its moment in words, and a habit saved with words opens on a card that
// keeps them («بكلماتك»). So the tests that switched into custom text, or
// tapped its own «قبل | بعد», now pin that card instead: it saves its words
// untouched, a prayer picked over it leans the sheet to بعد whatever the
// words say, and its × leaves no reminder. The round trips from words
// through a prayer and back to the words are gone, because once a clock
// time or a prayer is picked the words cannot be chosen again.
//
// Before 395968d (Aziz's IMG 1, 2026-09-11) the main step's «قبل | بعد» chips
// saved nothing for a prayer habit: the cue is stored as the bare key, the
// scheduler reads only the signed shifts, and a prayer habit reopened on بعد
// whatever its reminders said, so صلاة التهجد (45 before Fajr) opened under a
// lit بعد. The row said «قبل ٤٥ دقيقة» with no prayer in it, drew its time in
// Arabic-Indic digits while the sheet drew Latin ones, and its only tap cue, a
// grey chevron, sat outside the tap area. Under the step a preview sentence
// said «بعد الفجر، سأقوم بـ ...» whatever was lit.
//
// 395968d made the chips the reminders' side, but the sheet kept asking the
// same question, and on 2026-09-12 Aziz had the pair taken off the prayer
// step. The side is now chosen in the sheet alone and read back on the row.
// For a reminder with no side (on time, or being added) the sheet leans to
// the side the reminders were last on or last chosen in it, whether the last
// change was an edit, an add, a × or a switch from a clock time, and never to
// the «قبل» in a written cue's words. These drive the real sheet the way a
// person does, in Arabic, and read back what _submit handed the habits
// notifier.
//
// Three harness rules this file learned the hard way, each of which hung or
// failed it once:
//  * The Hive boxes are opened in memory. Save writes the habit and the
//    notification permission answer, and a file-backed write started inside
//    a testWidgets body (fake async) waits on real I/O that never finishes
//    there; the box keeps its write lock and tearDown's Hive.close() waits
//    forever, with no output at all.
//  * The habits and a Manama location are seeded in setUp, never awaited
//    inside a test body.
//  * Save asks for notification permission, and a test process registers no
//    notifications plugin, which threw a LateInitializationError mid-save.
//    The Android plugin is registered and its channel mocked to refuse.
// And the view is tall enough that nothing needs ensureVisible, which never
// returns on this sheet.
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:grow_daily_v2/features/settings/notifiers/notification_settings_notifier.dart';
import 'package:grow_daily_v2/shared/widgets/choice_chip_grid.dart';
import 'package:hive/hive.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'support/add_habit_flow.dart';

const _manama = NotificationLocation(
  lat: 26.2285,
  lng: 50.5860,
  label: 'Manama, Bahrain',
);

final _arabicIndic = RegExp('[٠-٩]');

void main() {
  const ar = S(Locale('ar'));
  late Directory tmp;
  late ProviderContainer container;

  /// Every habit a test opens, seeded once per test in [boot]: 45 before
  /// Fajr, 20 after it, on time, a quit habit, a single clock time shifted
  /// and on time, a clock time twice a day, two written cues (one with قبل,
  /// one without), and the Premium stacks: one on a prayer, one on a clock
  /// time.
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
    tmp = await Directory.systemTemp.createTemp('prayer_direction_');
    Hive.init(tmp.path);
    // In memory: see the harness rules at the top of this file.
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

  /// The container for one group, free or Premium, with or without a saved
  /// location, and the habits the tests open. Awaited from a group setUp,
  /// which runs after the root one has opened Hive.
  Future<void> boot({bool premium = false, bool location = true}) async {
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumAccessProvider.overrideWithValue(premium),
      ],
    );
    await container.read(authStateProvider.future);
    container.read(customHabitsProvider);
    await container.read(notificationSettingsProvider.notifier).update(
          (s) => location
              ? s.copyWith(location: _manama)
              : s.copyWith(clearLocation: true),
        );
    // The guest habit list loads from Hive once. Let it land before adding
    // to it, the way custom_habits_notifier_test does.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final notifier = container.read(customHabitsProvider.notifier);
    IslamicHabitTemplate add(
      String name, {
      String cue = 'fajr',
      required int offset,
      List<int> extras = const [],
      GoalType goalType = GoalType.build,
      int perDay = 1,
    }) =>
        notifier.add(
          name: name,
          category: HabitCategory.faith,
          cueAfter: cue,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: perDay,
          goalType: goalType,
          reminderOffsetMinutes: offset,
          extraReminderOffsets: extras,
        );
    habits = {
      'tahajjud': add('صلاة التهجد', offset: -45),
      'afterFajr': add('تسبيح', offset: 20),
      'onTime': add('قراءة', offset: 0),
      'quit': add('قهوة', offset: -15, goalType: GoalType.quit),
      'clock': add('بروتين', cue: 'custom_time:07:30', offset: -15),
      'clockOnTime': add('ماء', cue: 'custom_time:07:30', offset: 0),
      'twoTimes': add(
        'فيتامين',
        cue: 'custom_time:07:30,19:30',
        offset: 0,
        perDay: 2,
      ),
      'text': add('تخطيط', cue: 'قبل العمل', offset: 0),
      'textAfter': add('مراجعة', cue: 'العمل', offset: 0),
      'bothSides': add('ذكر', offset: -10, extras: [30]),
      'clockBothSides': add(
        'تمر',
        cue: 'custom_time:07:30',
        offset: -10,
        extras: [30],
      ),
    };
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  IslamicHabitTemplate stored(String id) =>
      container.read(customHabitsProvider).firstWhere((h) => h.id == id);

  /// The sheet on a pushed route, so Save's Navigator.pop has somewhere to
  /// return to. An existing habit is taken from its overview to the
  /// reminder step, through the overview's «التذكير» row.
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
    await openEditStep(tester, ar, 2);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  /// «تم» back to the overview and «احفظ التغييرات» there, then pump past
  /// what Save leaves on screen: the mocked permission refusal shows its
  /// SnackBar for four seconds. Plain taps, not the shared saveEdit: see the
  /// note on ensureVisible at the top of this file.
  Future<void> save(WidgetTester tester) async {
    await tapText(tester, ar.habitEditStepDone);
    await tapText(tester, ar.saveChanges);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  /// A new habit, «قراءة» every day, on the reminder step with «مع وقت
  /// صلاة» picked.
  Future<void> openNewInPrayerMode(WidgetTester tester) async {
    await open(tester);
    await toReminder(tester, ar);
    await pickPrayerKind(tester, ar);
  }

  /// «على ساعة معيّنة» on a habit that already has its time, so no time
  /// picker opens (the shared pickClockKind expects one when it confirms).
  Future<void> backToClock(WidgetTester tester) async {
    await tester.tap(choice(ar.reminderAtClock));
    await tester.pumpAndSettle();
  }

  /// That the step draws no «قبل | بعد» pair. Only with the offset sheet
  /// closed: the sheet's own pair uses the same two words.
  void expectNoRelationPair(WidgetTester tester, {String? reason}) {
    expect(find.text(ar.cueBeforeOption), findsNothing, reason: reason);
    expect(find.text(ar.cueAfterOption), findsNothing, reason: reason);
  }

  /// That nothing on the step offers to write the moment in words: no
  /// «نص مخصص» chip and no field to type a routine into.
  void expectNoWrittenCueOffered(WidgetTester tester) {
    expect(find.text(ar.customText), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == ar.afterWhatRoutine,
      ),
      findsNothing,
    );
  }

  /// The time a reminder row draws beside its sentence. Since 2026-10-01
  /// the prayer pills carry today's time under each name too, so on time
  /// the row's time and Fajr's own are the same text; the rows are Ink and
  /// the pills are not.
  Finder rowTime(String time) =>
      find.descendant(of: find.byType(Ink), matching: find.text(time));

  /// A chip inside the offset sheet, which the main step never uses.
  PlainChoiceChip sheetChip(WidgetTester tester, String label) =>
      tester.widget<PlainChoiceChip>(
        find.widgetWithText(PlainChoiceChip, label),
      );

  /// In the offset sheet: tap a chip and let the sheet close.
  Future<void> tapSheetChip(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(PlainChoiceChip, label));
    await tester.pumpAndSettle();
  }

  /// In the offset sheet: tap [side], keep the amount that is lit or typed,
  /// and press «حفظ».
  Future<void> flipInSheet(WidgetTester tester, String side) async {
    await tester.tap(find.widgetWithText(PlainChoiceChip, side));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, ar.habitOffsetSave));
    await tester.pumpAndSettle();
  }

  /// That a press on the row holding [label] can be seen. The InkWell paints
  /// its highlight on the nearest Material, so that Material has to be
  /// transparent and the row's fill has to be Ink painted on the same one. A
  /// filled Container, what the rows used to be, drew over the highlight.
  void expectPressShows(WidgetTester tester, Finder label) {
    final well = find.ancestor(of: label, matching: find.byType(InkWell)).first;
    final material =
        find.ancestor(of: well, matching: find.byType(Material)).first;
    expect(
      tester.widget<Material>(material).type,
      MaterialType.transparency,
      reason: 'the highlight paints on a transparent Material',
    );
    final ink = find.ancestor(of: well, matching: find.byType(Ink));
    expect(ink, findsWidgets, reason: 'the row\'s fill is Ink');
    expect(
      find
          .ancestor(of: ink.first, matching: find.byType(Material))
          .evaluate()
          .first,
      material.evaluate().single,
      reason: 'and the fill paints on that same Material, under the highlight',
    );
  }

  /// Today's Fajr in Manama shifted by [offset], labelled the way the offset
  /// sheet labels a time, and computed the way the form computes its anchor
  /// (_reminderAnchorTime). Pins the row to the sheet rather than to a date.
  String fajrPlus(int offset) {
    final settings = container.read(notificationSettingsProvider);
    final fajr = PrayerTimesService.calculateOfflineCorrected(
      latitude: _manama.lat,
      longitude: _manama.lng,
      date: DateTime.now(),
      countryCode: settings.resolvedCountryCode,
    ).forKey('fajr')!;
    final t = fajr.add(Duration(minutes: offset));
    return HabitCue.time(t.hour, t.minute).labelForLocale(true);
  }

  group('a prayer habit, free, with a location', () {
    setUp(() => boot());

    testWidgets(
        '45 before Fajr: no «قبل | بعد» on the step, and the row says the '
        'whole reminder', (tester) async {
      await open(tester, habits['tahajjud']);

      expectNoRelationPair(
        tester,
        reason: 'the sheet every row opens asks it, so the step does not',
      );
      expect(find.text('قبل الفجر بـ45 دقيقة'), findsOneWidget);
      expect(
        find.text(fajrPlus(-45)),
        findsOneWidget,
        reason: 'the row draws its time the way the sheet does',
      );
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(
          _arabicIndic.hasMatch(text.data ?? ''),
          isFalse,
          reason: 'Latin digits on this step: ${text.data}',
        );
      }
    });

    // A guard: this already held before the change.
    testWidgets('saved with no changes it stays fajr, 45 before, no extras',
        (tester) async {
      final habit = habits['tahajjud']!;
      await open(tester, habit);
      await save(tester);

      final saved = stored(habit.id);
      expect(saved.cueAfter, 'fajr');
      expect(saved.reminderOffsetMinutes, -45);
      expect(saved.extraReminderOffsets, isEmpty);
    });

    testWidgets('بعد in the sheet moves 45 before Fajr to 45 after',
        (tester) async {
      final habit = habits['tahajjud']!;
      await open(tester, habit);
      await tapText(tester, 'قبل الفجر بـ45 دقيقة');
      expect(sheetChip(tester, ar.offsetBeforeLabel).selected, isTrue);

      await flipInSheet(tester, ar.offsetAfterLabel);

      expect(find.text('بعد الفجر بـ45 دقيقة'), findsOneWidget);
      expect(
        find.text(fajrPlus(45)),
        findsOneWidget,
        reason: 'the time moves with it, right away',
      );

      await save(tester);
      expect(stored(habit.id).reminderOffsetMinutes, 45);
      expect(stored(habit.id).cueAfter, 'fajr');
    });

    testWidgets('20 after Fajr: the row says بعد and its sheet opens on بعد',
        (tester) async {
      await open(tester, habits['afterFajr']);
      expect(find.text('بعد الفجر بـ20 دقيقة'), findsOneWidget);
      expect(find.text(fajrPlus(20)), findsOneWidget);

      await tapText(tester, 'بعد الفجر بـ20 دقيقة');
      expect(sheetChip(tester, ar.offsetAfterLabel).selected, isTrue);
      expect(sheetChip(tester, ar.offsetBeforeLabel).selected, isFalse);
    });

    testWidgets(
        'reopened on قبل, its sheet still opens on قبل once the reminder is '
        'set back on time', (tester) async {
      await open(tester, habits['tahajjud']);
      await tapText(tester, 'قبل الفجر بـ45 دقيقة');
      await tapSheetChip(tester, ar.leadAtTime);
      expect(find.text('في وقت الفجر'), findsOneWidget);

      await tapText(tester, 'في وقت الفجر');
      expect(
        sheetChip(tester, ar.offsetBeforeLabel).selected,
        isTrue,
        reason: 'with no side left the sheet leans to the side the habit was '
            'opened on, which for 45 before Fajr is قبل, not to the بعد a '
            'bare prayer cue carries as its words',
      );
      expect(sheetChip(tester, ar.offsetAfterLabel).selected, isFalse);
    });

    testWidgets('tapping the chevron itself opens the sheet', (tester) async {
      await open(tester, habits['tahajjud']);

      final chevron = find.byIcon(Icons.chevron_right_rounded);
      expect(chevron, findsOneWidget);
      await tester.tap(chevron);
      await tester.pumpAndSettle();

      expect(
        find.text(ar.habitOffsetSave),
        findsOneWidget,
        reason: 'the chevron used to sit outside the tap area',
      );
      expect(find.text('بالنسبة لوقت الفجر، ${fajrPlus(0)}'), findsOneWidget);
      expect(sheetChip(tester, ar.offsetBeforeLabel).selected, isTrue);
    });

    testWidgets('the row reports itself as a button', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, habits['tahajjud']);

      expect(
        tester.getSemantics(
          find.bySemanticsLabel('قبل الفجر بـ45 دقيقة، ${fajrPlus(-45)}'),
        ),
        isSemantics(isButton: true, hasTapAction: true),
      );
      semantics.dispose();
    });

    testWidgets(
        'on time: «في وقت الفجر», the sheet opens on بعد, 15 saves 15 after, '
        'and قبل there keeps the 15', (tester) async {
      final habit = habits['onTime']!;
      await open(tester, habit);
      expect(find.text('في وقت الفجر'), findsOneWidget);
      expect(rowTime(fajrPlus(0)), findsOneWidget);

      await tapText(tester, 'في وقت الفجر');
      expect(
        sheetChip(tester, ar.offsetAfterLabel).selected,
        isTrue,
        reason: 'a prayer reminder with no side yet opens on بعد',
      );
      expect(sheetChip(tester, ar.offsetBeforeLabel).selected, isFalse);
      expect(sheetChip(tester, ar.leadAtTime).selected, isTrue);
      expect(find.text(ar.habitOffsetSave), findsOneWidget);

      await tapSheetChip(tester, '15');
      expect(
        find.text('بعد الفجر بـ15 دقيقة'),
        findsOneWidget,
        reason: 'one tap on 15 under a lit بعد is 15 after, as it reads',
      );
      expect(find.text(fajrPlus(15)), findsOneWidget);

      await tapText(tester, 'بعد الفجر بـ15 دقيقة');
      await flipInSheet(tester, ar.offsetBeforeLabel);
      expect(
        find.text('قبل الفجر بـ15 دقيقة'),
        findsOneWidget,
        reason: 'the flip keeps the amount',
      );
      expect(find.text(fajrPlus(-15)), findsOneWidget);

      await save(tester);
      expect(stored(habit.id).reminderOffsetMinutes, -15);
    });

    testWidgets(
        'the sheet leans to the side last chosen in it, also once that '
        'reminder is back on time', (tester) async {
      await open(tester, habits['onTime']);
      await tapText(tester, 'في وقت الفجر');
      await tester.tap(
        find.widgetWithText(PlainChoiceChip, ar.offsetBeforeLabel),
      );
      await tester.pumpAndSettle();
      await tapSheetChip(tester, '15');
      expect(find.text('قبل الفجر بـ15 دقيقة'), findsOneWidget);

      await tapText(tester, 'قبل الفجر بـ15 دقيقة');
      await tapSheetChip(tester, ar.leadAtTime);
      expect(find.text('في وقت الفجر'), findsOneWidget);

      await tapText(tester, 'في وقت الفجر');
      expect(
        sheetChip(tester, ar.offsetBeforeLabel).selected,
        isTrue,
        reason: 'قبل was chosen last, not the بعد the habit opened on',
      );
      expect(sheetChip(tester, ar.offsetAfterLabel).selected, isFalse);
    });

    testWidgets(
        'a clock habit switched to a prayer draws no pair, and keeps 15 '
        'before onto Fajr', (tester) async {
      final habit = habits['clock']!;
      await open(tester, habit);
      await pickPrayerKind(tester, ar);
      expectNoRelationPair(tester, reason: 'nor before a prayer is picked');

      await tapText(tester, 'الفجر');
      expect(
        find.text('قبل الفجر بـ15 دقيقة'),
        findsOneWidget,
        reason: 'a reminder brings its own side into prayer mode',
      );
      expectNoRelationPair(tester);

      await save(tester);
      expect(stored(habit.id).cueAfter, 'fajr');
      expect(stored(habit.id).reminderOffsetMinutes, -15);
    });

    testWidgets(
        'a clock habit switched to a prayer keeps قبل in its sheet once its '
        'reminder is on time', (tester) async {
      await open(tester, habits['clock']);
      await pickPrayerKind(tester, ar);
      await tapText(tester, 'الفجر');
      await tapText(tester, 'قبل الفجر بـ15 دقيقة');
      await tapSheetChip(tester, ar.leadAtTime);
      expect(find.text('في وقت الفجر'), findsOneWidget);

      await tapText(tester, 'في وقت الفجر');
      expect(
        sheetChip(tester, ar.offsetBeforeLabel).selected,
        isTrue,
        reason: 'the side came over with the reminder; a clock cue\'s default '
            'relation is بعد, and the sheet must not lean to that',
      );
      expect(sheetChip(tester, ar.offsetAfterLabel).selected, isFalse);
    });

    testWidgets(
        'a clock habit through a prayer and back to «على ساعة معيّنة» still '
        'reads 15 before', (tester) async {
      final habit = habits['clock']!;
      await open(tester, habit);
      await pickPrayerKind(tester, ar);
      await tapText(tester, 'الفجر');
      await backToClock(tester);

      expect(find.text('قبل 15 دقيقة'), findsOneWidget);
      expect(find.text('بعد 15 دقيقة'), findsNothing);

      await save(tester);
      expect(stored(habit.id).reminderOffsetMinutes, -15);
      expect(stored(habit.id).cueAfter, startsWith('custom_time:'));
    });

    testWidgets('no preview sentence on an existing habit', (tester) async {
      await open(tester, habits['onTime']);
      expect(find.textContaining('سأقوم'), findsNothing);
      expect(find.textContaining('الفجر،'), findsNothing);
    });

    testWidgets('no preview sentence on a new habit once a prayer is picked',
        (tester) async {
      await openNewInPrayerMode(tester);
      await tapText(tester, 'الفجر');

      expect(
        find.text('في وقت الفجر'),
        findsOneWidget,
        reason: 'sanity: Fajr is picked and its reminder row is up',
      );
      expect(
        find.textContaining('سأقوم'),
        findsNothing,
        reason: 'the «بعد الفجر، سأقوم بـ ...» sentence is gone',
      );
      expect(find.textContaining('الفجر،'), findsNothing);
    });

    // Until 2026-10-01 this ended in custom text, which kept a pair of its
    // own. A new habit is no longer offered custom text at all.
    testWidgets(
        'a new habit: no pair in prayer mode before or after a prayer is '
        'picked, and no written cue to turn to', (tester) async {
      await openNewInPrayerMode(tester);
      expect(
        find.text('الفجر'),
        findsOneWidget,
        reason: 'sanity: prayer mode is open, its prayers drawn',
      );
      expectNoRelationPair(tester);

      await tapText(tester, 'الفجر');
      expect(find.text('في وقت الفجر'), findsOneWidget);
      expectNoRelationPair(tester);

      await tapText(tester, 'في وقت الفجر');
      expect(
        sheetChip(tester, ar.offsetAfterLabel).selected,
        isTrue,
        reason: 'the side is set here now, and a first reminder opens on بعد',
      );
      await tapSheetChip(tester, ar.leadAtTime);

      expectNoRelationPair(tester);
      expectNoWrittenCueOffered(tester);
      expect(find.text(ar.habitWrittenMoment), findsNothing);
    });

    // A guard: this already held before the change.
    testWidgets('the add row still opens the Premium gate', (tester) async {
      await open(tester, habits['tahajjud']);
      await tapText(tester, ar.habitAddReminderRow);
      expect(find.text(ar.reminderGateTitle), findsOneWidget);
    });

    // Only an account whose Premium ended holds a stack on the free tier,
    // and until 2026-09-26 it could move every reminder in it (Aziz: a
    // lapsed account "just edits the premium"). The primary is the one
    // reminder free includes; the extra is Premium's, removable, not
    // movable.
    testWidgets(
        'a stack kept from an ended Premium: the extra wears a lock and '
        'opens the gate, the primary still moves, the × still removes',
        (tester) async {
      final habit = habits['bothSides']!;
      await open(tester, habit);
      final extra = find.text('بعد الفجر بـ30 دقيقة');
      expect(extra, findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(of: extra, matching: find.byType(Ink)).first,
          matching: find.byIcon(Icons.lock_outline_rounded),
        ),
        findsOneWidget,
        reason: 'the extra row says it is locked before the tap',
      );
      expect(
        find.byIcon(Icons.chevron_right_rounded),
        findsOneWidget,
        reason: 'the primary row keeps its chevron',
      );

      await tapText(tester, 'بعد الفجر بـ30 دقيقة');
      expect(find.text(ar.reminderGateTitle), findsOneWidget);
      Navigator.of(tester.element(find.text(ar.reminderGateTitle))).pop();
      await tester.pumpAndSettle();
      expect(find.text(ar.habitOffsetSave), findsNothing,
          reason: 'no offset sheet opened behind the gate');

      await tapText(tester, 'قبل الفجر بـ10 دقائق');
      await flipInSheet(tester, ar.offsetAfterLabel);
      expect(find.text('بعد الفجر بـ10 دقائق'), findsOneWidget);

      final extraRow =
          find.ancestor(of: extra, matching: find.byType(Ink)).first;
      await tester.tap(find.descendant(
        of: extraRow,
        matching: find.byIcon(Icons.close_rounded),
      ));
      await tester.pumpAndSettle();
      expect(extra, findsNothing);

      await save(tester);
      expect(stored(habit.id).reminderOffsetMinutes, 10);
      expect(stored(habit.id).extraReminderOffsets, isEmpty);
    });

    testWidgets('a quit habit behaves the same', (tester) async {
      final habit = habits['quit']!;
      await open(tester, habit);
      expectNoRelationPair(tester);
      expect(find.text('قبل الفجر بـ15 دقيقة'), findsOneWidget);

      await tapText(tester, 'قبل الفجر بـ15 دقيقة');
      await flipInSheet(tester, ar.offsetAfterLabel);
      expect(find.text('بعد الفجر بـ15 دقيقة'), findsOneWidget);

      await save(tester);
      expect(stored(habit.id).reminderOffsetMinutes, 15);
      expect(stored(habit.id).goalType, GoalType.quit);
    });

    testWidgets(
        'a single clock time keeps its words in Latin digits, and its '
        'chevrons are inside their tap areas', (tester) async {
      await open(tester, habits['clock']);

      expect(
        find.text('قبل 15 دقيقة'),
        findsOneWidget,
        reason: 'a clock-time row keeps the words it always had, with the '
            'digits of the time beside it',
      );
      expect(
        find.text('7:15 ص'),
        findsOneWidget,
        reason: 'its time in Latin digits, as the sheet draws it',
      );
      expect(find.text(ar.cueBeforeOption), findsNothing);
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(
          _arabicIndic.hasMatch(text.data ?? ''),
          isFalse,
          reason: 'Latin digits on this step: ${text.data}',
        );
      }

      final chevrons = find.byIcon(Icons.chevron_right_rounded);
      expect(
        chevrons,
        findsNWidgets(2),
        reason: 'one on the time row, one on the reminder row',
      );
      await tester.tap(chevrons.first);
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
    });

    testWidgets('a press shows on the time row and on the reminder row',
        (tester) async {
      await open(tester, habits['clock']);
      expectPressShows(tester, find.text('7:30 ص'));
      expectPressShows(tester, find.text('قبل 15 دقيقة'));
    });

    testWidgets(
        'a clock time on time still opens the sheet on قبل: 15 saves 15 '
        'before', (tester) async {
      final habit = habits['clockOnTime']!;
      await open(tester, habit);
      await tapText(tester, ar.leadAtTime);

      expect(
        sheetChip(tester, ar.offsetBeforeLabel).selected,
        isTrue,
        reason: 'the lean is only for a prayer; a clock time opens on قبل '
            'whatever its default relation, بعد, says',
      );
      expect(sheetChip(tester, ar.offsetAfterLabel).selected, isFalse);

      await tapSheetChip(tester, '15');
      expect(find.text('قبل 15 دقيقة'), findsOneWidget);

      await save(tester);
      expect(stored(habit.id).reminderOffsetMinutes, -15);
    });

    // Until 2026-10-01 this went on into custom text, whose chips had to
    // stay on بعد: a clock reminder's side is not a relation for a typed
    // cue. Custom text is not offered any more, so what is left to pin is
    // that the move saves on the clock time and nothing turns it into words.
    testWidgets(
        'a clock reminder moved in the sheet saves on its time, with no '
        'written cue to turn to', (tester) async {
      final habit = habits['clock']!;
      await open(tester, habit);
      await tapText(tester, 'قبل 15 دقيقة');
      await tapSheetChip(tester, '30');
      expect(find.text('قبل 30 دقيقة'), findsOneWidget);
      expectNoRelationPair(tester);
      expectNoWrittenCueOffered(tester);

      await save(tester);
      expect(stored(habit.id).cueAfter, 'custom_time:07:30');
      expect(stored(habit.id).reminderOffsetMinutes, -30);
    });

    // The review of 395968d caught three bugs here: the prayer chips' side
    // and the custom text relation were one field, so an edit in the offset
    // sheet rewrote the typed cue («العمل» through a prayer set 15 before
    // and back saved «قبل العمل»; «قبل العمل» set 15 after saved «العمل»;
    // 45 before Fajr switched to custom text lit قبل). Those round trips
    // cannot be made since 2026-10-01: words are no longer offered, and a
    // habit that has them keeps them only until a clock time or a prayer is
    // picked over them. What still holds is pinned below: the words saved
    // untouched, a prayer over «قبل العمل» leaning بعد, and a reminder's
    // side never turning into words.
    testWidgets('«العمل» opens on its words and saves them untouched',
        (tester) async {
      final habit = habits['textAfter']!;
      await open(tester, habit);

      expect(find.text(ar.habitWrittenMoment), findsOneWidget);
      expect(find.text('العمل'), findsOneWidget);
      expectNoRelationPair(
        tester,
        reason: 'custom text\'s own pair went with custom text',
      );
      expectNoWrittenCueOffered(tester);

      await save(tester);
      expect(stored(habit.id).cueAfter, 'العمل');
      expect(stored(habit.id).reminderOffsetMinutes, 0);
    });

    testWidgets(
        '«قبل العمل» given a prayer: the sheet still opens on بعد, and 15 '
        'after saves on Fajr', (tester) async {
      final habit = habits['text']!;
      await open(tester, habit);
      await pickPrayerKind(tester, ar);
      expect(
        find.text(ar.habitWrittenMoment),
        findsNothing,
        reason: 'a prayer picked over the words replaces them',
      );
      expectNoRelationPair(tester);
      await tapText(tester, 'الفجر');
      await tapText(tester, 'في وقت الفجر');
      expect(
        sheetChip(tester, ar.offsetAfterLabel).selected,
        isTrue,
        reason: 'the typed قبل is words in a cue, not a side for the sheet '
            'to lean to',
      );
      await tapSheetChip(tester, '15');
      expect(find.text('بعد الفجر بـ15 دقيقة'), findsOneWidget);

      await save(tester);
      expect(stored(habit.id).cueAfter, 'fajr');
      expect(stored(habit.id).reminderOffsetMinutes, 15);
    });

    testWidgets(
        '45 before Fajr given a clock time keeps 45 before and saves a time, '
        'never words', (tester) async {
      final habit = habits['tahajjud']!;
      await open(tester, habit);
      expectNoWrittenCueOffered(tester);

      // No time yet, so the card opens the picker; OK keeps its time.
      await pickClockKind(tester, ar);
      expect(
        find.text('قبل 45 دقيقة'),
        findsOneWidget,
        reason: 'the reminder brings its side over from the prayer',
      );
      expectNoRelationPair(tester);

      await save(tester);
      expect(stored(habit.id).cueAfter, startsWith('custom_time:'));
      expect(stored(habit.id).reminderOffsetMinutes, -45);
    });

    testWidgets(
        '× on the words leaves no reminder, and nothing offers to write '
        'them again', (tester) async {
      final habit = habits['textAfter']!;
      await open(tester, habit);
      await tester.tap(find.byTooltip(ar.habitReminderRemove));
      await tester.pumpAndSettle();

      expect(find.text(ar.habitWrittenMoment), findsNothing);
      expect(find.text('العمل'), findsNothing);
      expectNoWrittenCueOffered(tester);
      expectNoRelationPair(tester);

      await save(tester);
      expect(stored(habit.id).cueAfter, anyOf(isNull, isEmpty));
      expect(stored(habit.id).reminderOffsetMinutes, 0);
    });

    testWidgets('a two-time habit: «مخصص» on a row opens the sheet with «حفظ»',
        (tester) async {
      await open(tester, habits['twoTimes']);
      expect(
        find.text(HabitCue.time(19, 30).labelForLocale(true)),
        findsOneWidget,
        reason: 'sanity: both times have a row',
      );

      // Arabic runs each row right to left: the clock sits at the right
      // edge and the shift chip at the left, each in its own inset. The
      // clock sat 6pt in while a one-time row put it 14pt in. Ink counts its
      // 0.5pt border as padding, so each inset reads half a point more. The
      // rows are Ink; the «على ساعة معيّنة» card above them, which wears the
      // same clock, is not.
      final clocks = find.descendant(
        of: find.byType(Ink),
        matching: find.byIcon(Icons.schedule_rounded),
      );
      final shifts = find.byIcon(Icons.expand_more_rounded);
      expect(clocks, findsNWidgets(2));
      expect(shifts, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final box = tester.getRect(
          find.ancestor(of: clocks.at(i), matching: find.byType(Ink)).first,
        );
        expect(box.right - tester.getRect(clocks.at(i)).right, 14 + 0.5);
        expect(tester.getRect(shifts.at(i)).left - box.left, 12 + 0.5);
      }

      await tester.tap(find.text(ar.leadAtTime).first);
      await tester.pumpAndSettle();
      await tapText(tester, ar.leadCustomOption);

      expect(
        find.widgetWithText(FilledButton, ar.habitOffsetSave),
        findsOneWidget,
        reason: 'opened on an occurrence that exists',
      );
      expect(
        find.widgetWithText(FilledButton, ar.customReminderAdd),
        findsNothing,
      );
    });

    // It used to open in custom text with قبل lit, its chip first and so on
    // the right under RTL. That pair is gone (2026-10-01); the words are now
    // shown as they were written, on the card that keeps them.
    testWidgets('a «قبل العمل» text habit is unchanged', (tester) async {
      final habit = habits['text']!;
      await open(tester, habit);

      expect(find.text(ar.habitWrittenMoment), findsOneWidget);
      expect(
        find.text('قبل العمل'),
        findsOneWidget,
        reason: 'the words whole, قبل included',
      );
      expectNoRelationPair(tester);

      await save(tester);
      expect(stored(habit.id).cueAfter, 'قبل العمل');
      expect(stored(habit.id).reminderOffsetMinutes, 0);
    });
  });

  group('a prayer habit, Premium', () {
    setUp(() => boot(premium: true));

    testWidgets(
        '10 before and 30 after: a row for each with its own chevron and ×, '
        'and no pair above them', (tester) async {
      final habit = habits['bothSides']!;
      await open(tester, habit);

      expectNoRelationPair(
        tester,
        reason: 'one pair cannot stand for both sides; it used to refuse '
            'every tap on this habit',
      );
      expect(find.text('قبل الفجر بـ10 دقائق'), findsOneWidget);
      expect(find.text('بعد الفجر بـ30 دقيقة'), findsOneWidget);
      expect(
        find.byIcon(Icons.chevron_right_rounded),
        findsNWidgets(2),
        reason: 'every row keeps its chevron beside its ×',
      );
      expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));

      await save(tester);
      expect(stored(habit.id).reminderOffsetMinutes, -10);
      expect(stored(habit.id).extraReminderOffsets, [30]);
    });

    testWidgets(
        'a clock time on both sides, through a prayer and back, keeps both '
        'reminders where they were', (tester) async {
      final habit = habits['clockBothSides']!;
      await open(tester, habit);
      expect(find.text('قبل 10 دقائق'), findsOneWidget);
      expect(find.text('بعد 30 دقيقة'), findsOneWidget);

      await pickPrayerKind(tester, ar);
      expectNoRelationPair(tester);
      await tapText(tester, 'الفجر');
      expect(find.text('قبل الفجر بـ10 دقائق'), findsOneWidget);
      expect(find.text('بعد الفجر بـ30 دقيقة'), findsOneWidget);

      await backToClock(tester);
      expect(find.text('قبل 10 دقائق'), findsOneWidget);
      expect(find.text('بعد 30 دقيقة'), findsOneWidget);

      await save(tester);
      expect(stored(habit.id).cueAfter, startsWith('custom_time:'));
      expect(stored(habit.id).reminderOffsetMinutes, -10);
      expect(stored(habit.id).extraReminderOffsets, [30]);
    });

    testWidgets(
        'a sentence too long for one line takes a second instead of «…», '
        'and the time beside it is textSec 13 w700', (tester) async {
      // 300pt wide. The test font draws Arabic narrower than the phone does,
      // so at the harness's 402pt this sentence still fits on one line
      // (106.8pt of the 186pt it gets); under about 323pt it needs two.
      tester.view.physicalSize =
          Size(300 * 3.0, tester.view.physicalSize.height);
      await open(tester, habits['bothSides']);
      final sentence = find.text('بعد الفجر بـ30 دقيقة');
      final style = tester.widget<Text>(sentence).style!;
      final paragraph = tester.renderObject<RenderParagraph>(sentence);
      expect(
        paragraph.size.height,
        greaterThan(style.fontSize! * style.height! * 1.5),
        reason: 'sanity: beside its time, chevron and ×, this one needs two '
            'lines on this view',
      );
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: 'one line cut the amount off behind «…»',
      );

      final time = tester.widget<Text>(find.text(fajrPlus(30))).style!;
      expect(time.fontSize, 13);
      expect(time.fontWeight, FontWeight.w700);
      expect(time.color, tester.element(sentence).gp.textSec);
    });

    testWidgets('each × stands after a thin divider, in a 44pt target',
        (tester) async {
      await open(tester, habits['bothSides']);
      final label = find.text('بعد الفجر بـ30 دقيقة');
      final row = find.ancestor(of: label, matching: find.byType(Ink)).first;
      final divider = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (w) =>
              w is ColoredBox && w.color == tester.element(row).gp.divider,
        ),
      );
      expect(divider, findsOneWidget);
      expect(tester.getSize(divider), const Size(0.5, 24));

      final edit = tester.getRect(
        find.ancestor(of: label, matching: find.byType(InkWell)).first,
      );
      final close = find
          .ancestor(
            of: find.descendant(
              of: row,
              matching: find.byIcon(Icons.close_rounded),
            ),
            matching: find.byType(InkWell),
          )
          .first;
      // Right to left: the row's tap area, then the divider, then the ×.
      expect(tester.getRect(divider).right, lessThanOrEqualTo(edit.left));
      expect(
        tester.getRect(divider).left,
        greaterThanOrEqualTo(tester.getRect(close).right),
      );
      expect(tester.getSize(close).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(close).height, greaterThanOrEqualTo(44));
    });

    testWidgets('each × is a button a screen reader calls «احذف التذكير»',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, habits['bothSides']);

      final removes = find.bySemanticsLabel(ar.habitReminderRemove);
      expect(removes, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        expect(
          tester.getSemantics(removes.at(i)),
          isSemantics(isButton: true, hasTapAction: true),
        );
      }
      semantics.dispose();
    });

    testWidgets(
        '× on the after row, then the one left set on time: the next sheet '
        'opens on قبل', (tester) async {
      await open(tester, habits['bothSides']);
      final afterRow = find
          .ancestor(
            of: find.text('بعد الفجر بـ30 دقيقة'),
            matching: find.byType(Ink),
          )
          .first;
      await tester.tap(
        find.descendant(
          of: afterRow,
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('بعد الفجر بـ30 دقيقة'), findsNothing);

      await tapText(tester, 'قبل الفجر بـ10 دقائق');
      await tapSheetChip(tester, ar.leadAtTime);
      expect(find.text('في وقت الفجر'), findsOneWidget);

      await tapText(tester, 'في وقت الفجر');
      expect(
        sheetChip(tester, ar.offsetBeforeLabel).selected,
        isTrue,
        reason: 'a × returns no value, so a lean that followed only returned '
            'values would still say بعد here, with nothing chosen',
      );
      expect(sheetChip(tester, ar.offsetAfterLabel).selected, isFalse);
    });

    testWidgets(
        '«أضف تذكير» on an on-time Fajr habit opens on بعد, says «إضافة», '
        'and 15 adds 15 after', (tester) async {
      final habit = habits['onTime']!;
      await open(tester, habit);

      await tapText(tester, ar.habitAddReminderRow);
      expect(
        sheetChip(tester, ar.offsetAfterLabel).selected,
        isTrue,
        reason: 'a prayer habit whose reminders have had no side leans بعد',
      );
      expect(sheetChip(tester, ar.offsetBeforeLabel).selected, isFalse);
      expect(
        find.widgetWithText(FilledButton, ar.customReminderAdd),
        findsOneWidget,
      );

      await tapSheetChip(tester, '15');
      expect(find.text('في وقت الفجر'), findsOneWidget);
      expect(find.text('بعد الفجر بـ15 دقيقة'), findsOneWidget);

      await save(tester);
      expect(stored(habit.id).reminderOffsetMinutes, 0);
      expect(stored(habit.id).extraReminderOffsets, [15]);
    });

    testWidgets(
        'a reminder added before, then set on time: the next sheet opens on '
        'قبل', (tester) async {
      await open(tester, habits['onTime']);
      await tapText(tester, ar.habitAddReminderRow);
      await tester.tap(
        find.widgetWithText(PlainChoiceChip, ar.offsetBeforeLabel),
      );
      await tester.pumpAndSettle();
      await tapSheetChip(tester, '15');
      expect(find.text('قبل الفجر بـ15 دقيقة'), findsOneWidget);

      await tapText(tester, 'قبل الفجر بـ15 دقيقة');
      await tapSheetChip(tester, ar.leadAtTime);
      expect(find.text('في وقت الفجر'), findsOneWidget);
      expect(find.text('قبل الفجر بـ15 دقيقة'), findsNothing);

      await tapText(tester, 'في وقت الفجر');
      expect(
        sheetChip(tester, ar.offsetBeforeLabel).selected,
        isTrue,
        reason: 'the side of the reminder that was added, not the بعد the '
            'habit opened on',
      );
      expect(sheetChip(tester, ar.offsetAfterLabel).selected, isFalse);
    });

    testWidgets(
        'on both sides, an on-time row opens on the side last chosen in the '
        'sheet', (tester) async {
      await open(tester, habits['onTime']);

      await tapText(tester, ar.habitAddReminderRow);
      await tester.tap(
        find.widgetWithText(PlainChoiceChip, ar.offsetBeforeLabel),
      );
      await tester.pumpAndSettle();
      await tapSheetChip(tester, '10');
      expect(find.text('قبل الفجر بـ10 دقائق'), findsOneWidget);

      await tapText(tester, ar.habitAddReminderRow);
      expect(
        sheetChip(tester, ar.offsetBeforeLabel).selected,
        isTrue,
        reason: 'the reminders are before, so a new one leans قبل',
      );
      await tester.tap(
        find.widgetWithText(PlainChoiceChip, ar.offsetAfterLabel),
      );
      await tester.pumpAndSettle();
      await tapSheetChip(tester, '30');
      expect(find.text('بعد الفجر بـ30 دقيقة'), findsOneWidget);

      await tapText(tester, 'في وقت الفجر');
      expect(
        sheetChip(tester, ar.offsetAfterLabel).selected,
        isTrue,
        reason: 'the reminders are on both sides, so the sheet leans to the '
            'side chosen last, 30 after',
      );
      expect(sheetChip(tester, ar.offsetBeforeLabel).selected, isFalse);
    });
  });

  group('a prayer habit with no location saved', () {
    setUp(() => boot(location: false));

    testWidgets('the row names the prayer and shows no time', (tester) async {
      await open(tester, habits['tahajjud']);

      expect(find.text('قبل الفجر بـ45 دقيقة'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'\d{1,2}:\d{2}').hasMatch(w.data ?? ''),
        ),
        findsNothing,
      );
      expect(find.text(ar.remindPreviewNeedsLocation), findsOneWidget);

      await tapText(tester, 'قبل الفجر بـ45 دقيقة');
      expect(find.text('بالنسبة لوقت الفجر'), findsOneWidget);
    });
  });
}
