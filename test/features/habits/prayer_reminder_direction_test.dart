// The «قبل | بعد» chips on Add Habit's main step, and the reminder rows under
// them, for a habit anchored to a prayer.
//
// Before this (Aziz's IMG 1, 2026-09-11) the chips saved nothing for a prayer
// habit: the cue is stored as the bare key, the scheduler reads only the
// signed shifts, and a prayer habit reopened on بعد whatever its reminders
// said, so صلاة التهجد (45 before Fajr) opened under a lit بعد. The row said
// «قبل ٤٥ دقيقة» with no prayer in it, drew its time in Arabic-Indic digits
// while the sheet drew Latin ones, and its only tap cue, a grey chevron, sat
// outside the tap area. Under the step a preview sentence said «بعد الفجر،
// سأقوم بـ ...» whatever was lit.
//
// Now the chips are the reminders' side: they light from the signs and move
// the reminders when tapped. Once every reminder is back on time they stay on
// the side the reminders were last on, whether the last change was an edit,
// an add, a × or a switch from a clock time. That side is never the «قبل» in
// a custom text cue's words: a trip through prayer mode and back saves the
// typed cue as it was. These drive the real sheet the way a person does, in
// Arabic, and read back what _submit handed the habits notifier.
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
  /// and on time, a clock time twice a day, two custom text cues (one with
  /// قبل, one without), and the Premium stacks: two on a prayer, one on a
  /// clock time.
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
      // Primary 30 before, extra 10 before: after a mirror the primary is
      // no longer the earliest, so "keeps the primary" and "the earliest
      // becomes the primary" save different things.
      'twoBefore': add('صدقة', offset: -30, extras: [-10]),
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
  /// return to, then on to the When step for an existing habit.
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

  /// Save, then pump past what Save leaves on screen: the mocked permission
  /// refusal shows its SnackBar for four seconds.
  Future<void> save(WidgetTester tester) async {
    await tapText(tester, ar.saveChanges);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  /// Whether the main step's chip is lit. _SmallPick carries its state in
  /// the label's weight.
  bool lit(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style?.fontWeight ==
      FontWeight.w800;

  /// Custom text mode's cue field, labelled with [S.afterWhatRoutine] on a
  /// habit being built.
  TextField cueField(WidgetTester tester) => tester.widget<TextField>(
        find.byWidgetPredicate(
          (w) =>
              w is TextField && w.decoration?.labelText == ar.afterWhatRoutine,
        ),
      );

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
      madhab: settings.madhab,
      countryCode: settings.resolvedCountryCode,
    ).forKey('fajr')!;
    final t = fajr.add(Duration(minutes: offset));
    return HabitCue.time(t.hour, t.minute).labelForLocale(true);
  }

  group('a prayer habit, free, with a location', () {
    setUp(() => boot());

    testWidgets(
        '45 before Fajr reopens on قبل and the row says the whole reminder',
        (tester) async {
      await open(tester, habits['tahajjud']);

      expect(
        lit(tester, ar.cueBeforeOption),
        isTrue,
        reason: 'صلاة التهجد used to reopen under a lit بعد',
      );
      expect(lit(tester, ar.cueAfterOption), isFalse);
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

    testWidgets('tapping بعد moves the reminder to 45 after', (tester) async {
      final habit = habits['tahajjud']!;
      await open(tester, habit);
      await tapText(tester, ar.cueAfterOption);

      expect(lit(tester, ar.cueAfterOption), isTrue);
      expect(lit(tester, ar.cueBeforeOption), isFalse);
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

    testWidgets(
        'tapping قبل when قبل is already lit moves nothing: the saved '
        'reminder keeps its time', (tester) async {
      final habit = habits['tahajjud']!;
      await open(tester, habit);
      await tapText(tester, ar.cueBeforeOption);

      expect(lit(tester, ar.cueBeforeOption), isTrue);
      expect(find.text('قبل الفجر بـ45 دقيقة'), findsOneWidget);
      expect(find.text(fajrPlus(-45)), findsOneWidget);

      await save(tester);
      expect(
        stored(habit.id).reminderOffsetMinutes,
        -45,
        reason: 'only a tap on the other side mirrors the reminders',
      );
    });

    testWidgets(
        'tapping بعد when بعد is already lit moves nothing: the saved '
        'reminder keeps its time', (tester) async {
      final habit = habits['afterFajr']!;
      await open(tester, habit);
      expect(lit(tester, ar.cueAfterOption), isTrue);
      expect(find.text('بعد الفجر بـ20 دقيقة'), findsOneWidget);

      await tapText(tester, ar.cueAfterOption);

      expect(lit(tester, ar.cueAfterOption), isTrue);
      expect(find.text('بعد الفجر بـ20 دقيقة'), findsOneWidget);
      expect(find.text(fajrPlus(20)), findsOneWidget);

      await save(tester);
      expect(stored(habit.id).reminderOffsetMinutes, 20);
    });

    testWidgets(
        'reopened on قبل, it stays on قبل once its reminder is set back on '
        'time', (tester) async {
      await open(tester, habits['tahajjud']);
      await tapText(tester, 'قبل الفجر بـ45 دقيقة');
      await tapSheetChip(tester, ar.leadAtTime);

      expect(find.text('في وقت الفجر'), findsOneWidget);
      expect(
        lit(tester, ar.cueBeforeOption),
        isTrue,
        reason: 'with no side left the chips fall back to the side the habit '
            'was opened on, which for 45 before Fajr is قبل',
      );
      expect(lit(tester, ar.cueAfterOption), isFalse);

      await tapText(tester, 'في وقت الفجر');
      expect(
        sheetChip(tester, ar.offsetBeforeLabel).selected,
        isTrue,
        reason: 'and the sheet opens on the side the chips show, not on the '
            'بعد a bare prayer cue carries as its words',
      );
    });

    testWidgets('قبل is the first chip, and in Arabic that is the right',
        (tester) async {
      await open(tester, habits['tahajjud']);

      final before = find.text(ar.cueBeforeOption);
      final after = find.text(ar.cueAfterOption);
      final row = tester.widget<Row>(
        find.ancestor(of: before, matching: find.byType(Row)).first,
      );
      expect(
        find.descendant(
          of: find.byWidget(row.children.first),
          matching: before,
        ),
        findsOneWidget,
        reason: 'قبل is the Row\'s first child',
      );
      expect(
        tester.getCenter(before).dx,
        greaterThan(tester.getCenter(after).dx),
        reason: 'and a first child lays out on the right under RTL',
      );
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
        'and قبل then moves it', (tester) async {
      final habit = habits['onTime']!;
      await open(tester, habit);
      expect(lit(tester, ar.cueAfterOption), isTrue);
      expect(find.text('في وقت الفجر'), findsOneWidget);
      expect(find.text(fajrPlus(0)), findsOneWidget);

      await tapText(tester, 'في وقت الفجر');
      expect(
        sheetChip(tester, ar.offsetAfterLabel).selected,
        isTrue,
        reason: 'the sheet opens on the side the main step shows',
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
      expect(lit(tester, ar.cueAfterOption), isTrue);

      await tapText(tester, ar.cueBeforeOption);
      expect(find.text('قبل الفجر بـ15 دقيقة'), findsOneWidget);
      expect(find.text(fajrPlus(-15)), findsOneWidget);
      expect(lit(tester, ar.cueBeforeOption), isTrue);

      await save(tester);
      expect(stored(habit.id).reminderOffsetMinutes, -15);
    });

    testWidgets(
        'the chip follows the side the sheet returned, also once that '
        'reminder is back on time', (tester) async {
      await open(tester, habits['onTime']);
      await tapText(tester, ar.cueBeforeOption);
      expect(
        lit(tester, ar.cueBeforeOption),
        isTrue,
        reason: 'on time has no side, so the tapped chip stays lit',
      );

      await tapText(tester, 'في وقت الفجر');
      expect(sheetChip(tester, ar.offsetBeforeLabel).selected, isTrue);
      await tester.tap(
        find.widgetWithText(PlainChoiceChip, ar.offsetAfterLabel),
      );
      await tester.pumpAndSettle();
      await tapSheetChip(tester, '15');
      expect(find.text('بعد الفجر بـ15 دقيقة'), findsOneWidget);
      expect(lit(tester, ar.cueAfterOption), isTrue);

      await tapText(tester, 'بعد الفجر بـ15 دقيقة');
      await tapSheetChip(tester, ar.leadAtTime);
      expect(find.text('في وقت الفجر'), findsOneWidget);
      expect(
        lit(tester, ar.cueAfterOption),
        isTrue,
        reason: 'the side last chosen in the sheet, not the chip tapped '
            'before it',
      );
      expect(lit(tester, ar.cueBeforeOption), isFalse);
    });

    testWidgets(
        'a clock habit switched to a prayer keeps قبل once its reminder is '
        'on time', (tester) async {
      await open(tester, habits['clock']);
      await tapText(tester, ar.cuePrayerOption);
      await tapText(tester, 'الفجر');
      expect(find.text('قبل الفجر بـ15 دقيقة'), findsOneWidget);
      expect(lit(tester, ar.cueBeforeOption), isTrue);

      await tapText(tester, 'قبل الفجر بـ15 دقيقة');
      await tapSheetChip(tester, ar.leadAtTime);
      expect(find.text('في وقت الفجر'), findsOneWidget);
      expect(
        lit(tester, ar.cueBeforeOption),
        isTrue,
        reason: 'the clock cue carried بعد in as its default, and the chips '
            'jumped to it with nothing tapped',
      );
      expect(lit(tester, ar.cueAfterOption), isFalse);
    });

    // The last review of this change caught these: before a prayer is picked
    // no reminder row is drawn, yet a chip tap moved the reminders anyway.
    testWidgets(
        'a clock habit: بعد tapped before a prayer is picked, then back to '
        '«وقت مخصص», still reads 15 before', (tester) async {
      final habit = habits['clock']!;
      await open(tester, habit);
      await tapText(tester, ar.cuePrayerOption);
      expect(lit(tester, ar.cueBeforeOption), isTrue);

      await tapText(tester, ar.cueAfterOption);
      expect(lit(tester, ar.cueAfterOption), isTrue);
      expect(lit(tester, ar.cueBeforeOption), isFalse);

      await tapText(tester, ar.customTime);
      expect(
        find.text('قبل 15 دقيقة'),
        findsOneWidget,
        reason: 'no row was on screen to move, so the tap moved none: it '
            'used to come back «بعد 15 دقيقة»',
      );
      expect(find.text('بعد 15 دقيقة'), findsNothing);

      await save(tester);
      expect(stored(habit.id).reminderOffsetMinutes, -15);
      expect(stored(habit.id).cueAfter, startsWith('custom_time:'));
    });

    testWidgets(
        'a clock habit: بعد and then الفجر opens the row 15 after Fajr, '
        'under the chip that was tapped', (tester) async {
      final habit = habits['clock']!;
      await open(tester, habit);
      await tapText(tester, ar.cuePrayerOption);
      await tapText(tester, ar.cueAfterOption);
      await tapText(tester, 'الفجر');

      expect(find.text('بعد الفجر بـ15 دقيقة'), findsOneWidget);
      expect(find.text('قبل الفجر بـ15 دقيقة'), findsNothing);
      expect(
        lit(tester, ar.cueAfterOption),
        isTrue,
        reason: 'the chips come before the prayers on screen, so this is the '
            'order a person taps them in, and the pick must not put out the '
            'chip just tapped',
      );
      expect(lit(tester, ar.cueBeforeOption), isFalse);

      await save(tester);
      expect(stored(habit.id).cueAfter, 'fajr');
      expect(stored(habit.id).reminderOffsetMinutes, 15);
    });

    testWidgets('no preview sentence on an existing habit', (tester) async {
      await open(tester, habits['onTime']);
      expect(find.textContaining('سأقوم'), findsNothing);
      expect(find.textContaining('الفجر،'), findsNothing);
    });

    testWidgets('no preview sentence on a new habit once a prayer is picked',
        (tester) async {
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

    // A guard: this already held before the change.
    testWidgets('the add row still opens the Premium gate', (tester) async {
      await open(tester, habits['tahajjud']);
      await tapText(tester, ar.habitAddReminderRow);
      expect(find.text(ar.reminderGateTitle), findsOneWidget);
    });

    testWidgets('a quit habit behaves the same', (tester) async {
      final habit = habits['quit']!;
      await open(tester, habit);
      expect(lit(tester, ar.cueBeforeOption), isTrue);
      expect(find.text('قبل الفجر بـ15 دقيقة'), findsOneWidget);

      await tapText(tester, ar.cueAfterOption);
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
        reason: 'the lean is for a prayer: this step has no chips to agree '
            'with, and its default relation is بعد',
      );
      expect(sheetChip(tester, ar.offsetAfterLabel).selected, isFalse);

      await tapSheetChip(tester, '15');
      expect(find.text('قبل 15 دقيقة'), findsOneWidget);

      await save(tester);
      expect(stored(habit.id).reminderOffsetMinutes, -15);
    });

    testWidgets(
        'a clock reminder moved in the sheet leaves the custom text chips '
        'alone', (tester) async {
      await open(tester, habits['clock']);
      await tapText(tester, 'قبل 15 دقيقة');
      await tapSheetChip(tester, '30');
      expect(find.text('قبل 30 دقيقة'), findsOneWidget);

      await tapText(tester, ar.customText);
      expect(
        lit(tester, ar.cueAfterOption),
        isTrue,
        reason: 'a clock reminder\'s side is not a relation for a typed cue',
      );
      expect(lit(tester, ar.cueBeforeOption), isFalse);
    });

    // The review of this change caught these three: the prayer chips' side
    // and the custom text relation were one field, so an edit in the offset
    // sheet rewrote the typed cue. Before the change each saved as below.
    testWidgets(
        '«العمل» through a prayer set 15 before and back saves «العمل»',
        (tester) async {
      final habit = habits['textAfter']!;
      await open(tester, habit);
      await tapText(tester, ar.cuePrayerOption);
      await tapText(tester, 'الفجر');
      await tapText(tester, 'في وقت الفجر');
      expect(sheetChip(tester, ar.offsetAfterLabel).selected, isTrue);
      await tester.tap(
        find.widgetWithText(PlainChoiceChip, ar.offsetBeforeLabel),
      );
      await tester.pumpAndSettle();
      await tapSheetChip(tester, '15');
      expect(find.text('قبل الفجر بـ15 دقيقة'), findsOneWidget);
      expect(lit(tester, ar.cueBeforeOption), isTrue);

      await tapText(tester, ar.customText);
      expect(cueField(tester).controller!.text, 'العمل');
      expect(
        lit(tester, ar.cueAfterOption),
        isTrue,
        reason: 'the reminder\'s قبل lit here, under a field reading «العمل»',
      );
      expect(lit(tester, ar.cueBeforeOption), isFalse);

      await save(tester);
      expect(
        stored(habit.id).cueAfter,
        'العمل',
        reason: 'it saved «قبل العمل», words nobody typed',
      );
    });

    testWidgets(
        '«قبل العمل» through a prayer set 15 after and back keeps its قبل',
        (tester) async {
      final habit = habits['text']!;
      await open(tester, habit);
      await tapText(tester, ar.cuePrayerOption);
      await tapText(tester, 'الفجر');
      expect(
        lit(tester, ar.cueBeforeOption),
        isTrue,
        reason: 'prayer mode starts from the answer the chips showed',
      );
      await tapText(tester, 'في وقت الفجر');
      expect(sheetChip(tester, ar.offsetBeforeLabel).selected, isTrue);
      await tester.tap(
        find.widgetWithText(PlainChoiceChip, ar.offsetAfterLabel),
      );
      await tester.pumpAndSettle();
      await tapSheetChip(tester, '15');
      expect(find.text('بعد الفجر بـ15 دقيقة'), findsOneWidget);
      expect(lit(tester, ar.cueAfterOption), isTrue);

      await tapText(tester, ar.customText);
      expect(cueField(tester).controller!.text, 'قبل العمل');
      expect(lit(tester, ar.cueBeforeOption), isTrue);
      expect(lit(tester, ar.cueAfterOption), isFalse);

      await save(tester);
      expect(
        stored(habit.id).cueAfter,
        'قبل العمل',
        reason: 'it saved «العمل», dropping the typed قبل',
      );
    });

    testWidgets(
        '45 before Fajr switched to custom text starts on بعد, and a typed '
        'routine saves without قبل', (tester) async {
      final habit = habits['tahajjud']!;
      await open(tester, habit);
      expect(lit(tester, ar.cueBeforeOption), isTrue);

      await tapText(tester, ar.customText);
      expect(
        lit(tester, ar.cueAfterOption),
        isTrue,
        reason: 'the reminders\' side lit قبل here and saved «قبل العمل»',
      );
      expect(lit(tester, ar.cueBeforeOption), isFalse);

      await tester.enterText(find.byWidget(cueField(tester)), 'العمل');
      await tester.pump();
      await save(tester);
      expect(stored(habit.id).cueAfter, 'العمل');
    });

    // A guard: a chip TAPPED in one mode is still lit in the other, as the
    // one shared answer always was. Only the reminders' side stays out.
    testWidgets('a chip tapped in prayer mode is lit in custom text, and back',
        (tester) async {
      await open(tester, habits['onTime']);
      await tapText(tester, ar.cueBeforeOption);
      expect(lit(tester, ar.cueBeforeOption), isTrue);

      await tapText(tester, ar.customText);
      expect(lit(tester, ar.cueBeforeOption), isTrue);
      expect(lit(tester, ar.cueAfterOption), isFalse);

      await tapText(tester, ar.cueAfterOption);
      await tapText(tester, ar.cuePrayerOption);
      expect(lit(tester, ar.cueAfterOption), isTrue);
      expect(lit(tester, ar.cueBeforeOption), isFalse);
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
      // 0.5pt border as padding, so each inset reads half a point more.
      final clocks = find.byIcon(Icons.schedule_rounded);
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

    testWidgets('a «قبل العمل» text habit is unchanged, with قبل first',
        (tester) async {
      final habit = habits['text']!;
      await open(tester, habit);

      expect(lit(tester, ar.cueBeforeOption), isTrue);
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .any((f) => f.controller?.text == 'قبل العمل'),
        isTrue,
      );
      expect(
        tester.getCenter(find.text(ar.cueBeforeOption)).dx,
        greaterThan(tester.getCenter(find.text(ar.cueAfterOption)).dx),
        reason: 'the same order in custom text mode',
      );

      await save(tester);
      expect(stored(habit.id).cueAfter, 'قبل العمل');
      expect(stored(habit.id).reminderOffsetMinutes, 0);
    });
  });

  group('a prayer habit, Premium', () {
    setUp(() => boot(premium: true));

    testWidgets(
        '10 before and 30 after: both chips lit, and a chip tap changes '
        'nothing and says why under the chips', (tester) async {
      final habit = habits['bothSides']!;
      await open(tester, habit);

      expect(lit(tester, ar.cueBeforeOption), isTrue);
      expect(lit(tester, ar.cueAfterOption), isTrue);
      expect(find.text('قبل الفجر بـ10 دقائق'), findsOneWidget);
      expect(find.text('بعد الفجر بـ30 دقيقة'), findsOneWidget);
      expect(
        find.byIcon(Icons.chevron_right_rounded),
        findsNWidgets(2),
        reason: 'every row keeps its chevron beside its ×',
      );
      expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));

      await tester.tap(find.text(ar.cueAfterOption));
      await tester.pump();
      expect(find.text(ar.habitReminderBothSides), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(ar.habitReminderBothSides)).dy,
        lessThan(tester.getTopLeft(find.text(ar.pickAPrayer)).dy),
        reason: 'drawn under the chips it refused, above the prayers',
      );
      expect(find.text('قبل الفجر بـ10 دقائق'), findsOneWidget);
      expect(find.text('بعد الفجر بـ30 دقيقة'), findsOneWidget);

      // The notice's own dwell, so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text(ar.habitReminderBothSides), findsNothing);

      await save(tester);
      expect(stored(habit.id).reminderOffsetMinutes, -10);
      expect(stored(habit.id).extraReminderOffsets, [30]);
    });

    testWidgets(
        'the both-sides refusal writes no relation: custom text next still '
        'lights بعد', (tester) async {
      await open(tester, habits['bothSides']);
      // قبل, the side a prayer habit's relation does not default to, so a
      // refused tap that wrote it would show.
      await tester.tap(find.text(ar.cueBeforeOption));
      await tester.pump();
      expect(find.text(ar.habitReminderBothSides), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tapText(tester, ar.customText);
      expect(lit(tester, ar.cueAfterOption), isTrue);
      expect(lit(tester, ar.cueBeforeOption), isFalse);
    });

    testWidgets(
        'a clock time on both sides: chips tapped before a prayer is picked '
        'say nothing and move nothing', (tester) async {
      final habit = habits['clockBothSides']!;
      await open(tester, habit);
      expect(find.text('قبل 10 دقائق'), findsOneWidget);
      expect(find.text('بعد 30 دقيقة'), findsOneWidget);
      await tapText(tester, ar.cuePrayerOption);

      for (final (tap, other) in [
        (ar.cueBeforeOption, ar.cueAfterOption),
        (ar.cueAfterOption, ar.cueBeforeOption),
      ]) {
        await tester.tap(find.text(tap));
        await tester.pump();
        expect(
          find.text(ar.habitReminderBothSides),
          findsNothing,
          reason: 'no rows are drawn yet, so there is nothing to refuse',
        );
        expect(lit(tester, tap), isTrue);
        expect(lit(tester, other), isFalse);
      }
      await tester.pumpAndSettle();

      await tapText(tester, ar.customTime);
      expect(find.text('قبل 10 دقائق'), findsOneWidget);
      expect(find.text('بعد 30 دقيقة'), findsOneWidget);

      await save(tester);
      expect(stored(habit.id).reminderOffsetMinutes, -10);
      expect(stored(habit.id).extraReminderOffsets, [30]);
    });

    testWidgets(
        'a clock time on both sides: قبل tapped, then الفجر, lights both and '
        'keeps both rows', (tester) async {
      final habit = habits['clockBothSides']!;
      await open(tester, habit);
      await tapText(tester, ar.cuePrayerOption);
      await tapText(tester, ar.cueBeforeOption);
      await tapText(tester, 'الفجر');

      expect(find.text('قبل الفجر بـ10 دقائق'), findsOneWidget);
      expect(find.text('بعد الفجر بـ30 دقيقة'), findsOneWidget);
      expect(lit(tester, ar.cueBeforeOption), isTrue);
      expect(lit(tester, ar.cueAfterOption), isTrue);
      expect(find.text(ar.habitReminderBothSides), findsNothing);

      await save(tester);
      expect(stored(habit.id).cueAfter, 'fajr');
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
        '× on the after row, then the one left set on time: قبل stays lit',
        (tester) async {
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
      expect(lit(tester, ar.cueBeforeOption), isTrue);
      expect(lit(tester, ar.cueAfterOption), isFalse);

      await tapText(tester, 'قبل الفجر بـ10 دقائق');
      await tapSheetChip(tester, ar.leadAtTime);

      expect(find.text('في وقت الفجر'), findsOneWidget);
      expect(
        lit(tester, ar.cueBeforeOption),
        isTrue,
        reason: 'the × did not move the fallback, so the chips jumped to بعد '
            'with nothing tapped',
      );
      expect(lit(tester, ar.cueAfterOption), isFalse);
    });

    testWidgets(
        '«أضف تذكير» opens on the side the main step shows, says «إضافة», '
        'and 15 adds 15 after', (tester) async {
      final habit = habits['onTime']!;
      await open(tester, habit);
      expect(lit(tester, ar.cueAfterOption), isTrue);

      await tapText(tester, ar.habitAddReminderRow);
      expect(
        sheetChip(tester, ar.offsetAfterLabel).selected,
        isTrue,
        reason: 'بعد lit on the main step is بعد lit in the sheet',
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
        'a reminder added before, then set on time: قبل stays lit',
        (tester) async {
      await open(tester, habits['onTime']);
      await tapText(tester, ar.habitAddReminderRow);
      await tester.tap(
        find.widgetWithText(PlainChoiceChip, ar.offsetBeforeLabel),
      );
      await tester.pumpAndSettle();
      await tapSheetChip(tester, '15');
      expect(find.text('قبل الفجر بـ15 دقيقة'), findsOneWidget);
      expect(lit(tester, ar.cueBeforeOption), isTrue);

      await tapText(tester, 'قبل الفجر بـ15 دقيقة');
      await tapSheetChip(tester, ar.leadAtTime);

      expect(find.text('في وقت الفجر'), findsOneWidget);
      expect(find.text('قبل الفجر بـ15 دقيقة'), findsNothing);
      expect(
        lit(tester, ar.cueBeforeOption),
        isTrue,
        reason: 'the side of the reminder that was added, not the بعد the '
            'habit opened on',
      );
      expect(lit(tester, ar.cueAfterOption), isFalse);
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
      expect(lit(tester, ar.cueBeforeOption), isTrue);
      expect(lit(tester, ar.cueAfterOption), isTrue);

      await tapText(tester, 'في وقت الفجر');
      expect(
        sheetChip(tester, ar.offsetAfterLabel).selected,
        isTrue,
        reason: 'both chips are lit, so the sheet leans to the side chosen '
            'last, 30 after',
      );
      expect(sheetChip(tester, ar.offsetBeforeLabel).selected, isFalse);
    });

    testWidgets('30 and 10 before: mirroring keeps the old primary as primary',
        (tester) async {
      final habit = habits['twoBefore']!;
      await open(tester, habit);
      expect(lit(tester, ar.cueBeforeOption), isTrue);

      await tapText(tester, ar.cueAfterOption);
      expect(find.text('بعد الفجر بـ10 دقائق'), findsOneWidget);
      expect(find.text('بعد الفجر بـ30 دقيقة'), findsOneWidget);

      await save(tester);
      expect(
        stored(habit.id).reminderOffsetMinutes,
        30,
        reason: 'notification slot 0 stays the same reminder, not whichever '
            'is earliest after the flip',
      );
      expect(stored(habit.id).extraReminderOffsets, [10]);
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
