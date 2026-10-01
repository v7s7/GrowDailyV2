// A quit habit's limit, as the three-step sheet asks it (canvas v8,
// 2026-10-01): «تتركه تمامًا أو تحدّه؟», and after «أحدّه» one line of
// [amount] [unit] «في اليوم», with a line under it that says what the unit
// box is for until «متابعة» is pressed with no number, when it becomes the
// refusal, in the error colour.
//
// Two things pinned here.
//
// The line lines up. It was reported from the device in its old shape
// («الحد الأقصى» and a unit dropdown under a row of avoid / limit picks): the
// two did not sit on one line, because the amount field carried its
// required-number note as a helperText, which made it taller than the
// dropdown, and a Row centres its children. The note lives under the row now
// and the unit is typed into a box like the amount, so the two boxes are the
// same rectangle twice over in every state, with «في اليوم» on their line.
// The old checks against the avoid / limit picks above are gone with those
// picks; the choice is a joined two-way row now and the boxes do not share
// its columns.
//
// The typed unit saves as the unit it names. The dropdown of four units was
// replaced by a box (Aziz, 2026-09-30: "custom only no need for chips, user
// set what he wants"), so _typedUnit reads the words back: a stock unit's
// word in either language is that unit, an empty box is «مرات» (its own
// placeholder), and anything else is a custom unit carrying the person's own
// word. These walk a new habit through all three steps and read back what
// _submit handed the habits notifier, and open an edited cups habit to see
// its unit as a word.
//
// The harness is prayer_reminder_direction_test's, because these save: the
// Hive boxes are in memory (a file-backed write inside a testWidgets body
// never finishes), the edited habit is seeded in setUp, and the
// notifications channel is mocked to refuse, since saving a quit habit asks
// for notification permission for its evening check-in.
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
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

import 'support/add_habit_flow.dart';

void main() {
  const dpr = 3.0;
  const ar = S(Locale('ar'));
  late Directory tmp;
  late ProviderContainer container;

  /// A quit habit already limited to 3 cups a day, for the edit test.
  late IslamicHabitTemplate cups;

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
    tmp = await Directory.systemTemp.createTemp('quit_limit_row_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings', bytes: Uint8List(0));
    await Hive.openBox<dynamic>('box_daily_logs', bytes: Uint8List(0));
    await Hive.openBox<dynamic>('box_habits', bytes: Uint8List(0));
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(390 * dpr, 844 * dpr);
    view.devicePixelRatio = dpr;

    // Premium, so the habit cap never answers before the form does.
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumAccessProvider.overrideWithValue(true),
      ],
    );
    await container.read(authStateProvider.future);
    container.read(customHabitsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    cups = container.read(customHabitsProvider.notifier).add(
          name: 'قهوة',
          category: HabitCategory.health,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
          goalType: GoalType.quit,
          reductionType: ReductionType.limit,
          limitAmount: 3,
          limitUnit: LimitUnit.cups,
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

  /// The sheet on a pushed route, so a save's Navigator.pop has somewhere to
  /// return to.
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

  /// The [amount] [unit] «في اليوم» line: the Row holding the words.
  Finder limitRow(S s) => find
      .ancestor(of: find.text(s.limitPerDay), matching: find.byType(Row))
      .first;

  /// The amount box, first on the line.
  Finder amountBox(S s) => find
      .descendant(of: limitRow(s), matching: find.byType(TextField))
      .first;

  /// The unit box, second on the line.
  Finder unitBox(S s) => find
      .descendant(of: limitRow(s), matching: find.byType(TextField))
      .last;

  /// Quit, then «أحدّه», on a new habit's first step.
  Future<void> toLimit(WidgetTester tester, S s) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(choice(s.goalTypeQuitOption));
    await tester.pumpAndSettle();
    await tester.tap(choice(s.quitLimitOption));
    await tester.pumpAndSettle();
  }

  /// Both boxes and «في اليوم» on one line: the same top, the same height,
  /// the words centred on the boxes, and after the unit box in reading
  /// order.
  ///
  /// Top and height within a hairline rather than exactly: each box takes
  /// its height from its own text line, and the number and the unit are
  /// drawn in different weights. A point is invisible; the 11.5pt the old
  /// row was off by was not. Their centres are exact, since the Row centres
  /// them.
  void expectOneLine(WidgetTester tester, S s, String state) {
    final amount = tester.getRect(amountBox(s));
    final unit = tester.getRect(unitBox(s));
    final perDay = tester.getRect(find.text(s.limitPerDay));

    expect(unit.center.dy, moreOrLessEquals(amount.center.dy, epsilon: 0.5),
        reason: '$state: both boxes sit on the same line');
    expect(unit.top, moreOrLessEquals(amount.top, epsilon: 1),
        reason: '$state: both boxes start on the same line');
    expect(unit.height, moreOrLessEquals(amount.height, epsilon: 1.5),
        reason: '$state: the same box height on both sides');
    expect(perDay.center.dy, moreOrLessEquals(amount.center.dy, epsilon: 1),
        reason: '$state: «${s.limitPerDay}» sits on the boxes\' line');
    if (s.isAr) {
      expect(perDay.right, lessThanOrEqualTo(unit.left),
          reason: '$state: right to left, the words come after the unit');
      expect(unit.right, lessThanOrEqualTo(amount.left));
    } else {
      expect(perDay.left, greaterThanOrEqualTo(unit.right),
          reason: '$state: the words come after the unit');
      expect(unit.left, greaterThanOrEqualTo(amount.right));
    }
  }

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    testWidgets('[$tag] after «${s.quitLimitOption}» the boxes are level, with '
        '«${s.limitPerDay}» on their line', (tester) async {
      await open(tester, locale);
      await toLimit(tester, s);

      expect(find.text(s.quitStyleQuestion), findsOneWidget);
      expect(
        find.descendant(of: limitRow(s), matching: find.byType(TextField)),
        findsNWidgets(2),
        reason: 'the amount and the unit, both typed: the unit is not '
            'picked from a dropdown any more',
      );
      expect(
        tester.widget<TextField>(unitBox(s)).decoration?.hintText,
        s.limitUnitLabel(LimitUnit.times.name),
        reason: 'an empty unit box shows what it saves as',
      );
      expect(find.byType(DropdownButtonFormField<LimitUnit>), findsNothing);
      expect(find.text(s.limitUnitHelp), findsOneWidget,
          reason: 'until a press is refused, the line says what the unit '
              'box is for');
      expectOneLine(tester, s, 'resting');

      // The state the drift used to show up in: a refused press with the
      // number still empty. The name is only here because the button is
      // dead without one.
      await tester.enterText(find.byType(TextField).first, 'قهوة');
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.continueAction));
      await tester.pumpAndSettle();
      final refusal = find.text(s.limitAmountRequired);
      expect(refusal, findsOneWidget,
          reason: 'refused, so the line says what the box is owed');
      expect(tester.widget<Text>(refusal).style?.color,
          tester.element(refusal).gp.errorInk);
      expect(find.text(s.limitUnitHelp), findsNothing);
      expect(find.text(s.quitStyleQuestion), findsOneWidget,
          reason: 'and the step is still here');
      expectOneLine(tester, s, 'refused');

      await tester.enterText(amountBox(s), '30');
      await tester.pumpAndSettle();
      expect(find.text(s.limitAmountRequired), findsNothing);
      expectOneLine(tester, s, 'filled');
    });
  }

  // ── The typed unit, saved ──────────────────────────────────────────────

  /// A new quit habit «قهوة», limited to [amount] [unit] a day, through all
  /// three steps on the Arabic sheet, and the habit that was saved.
  Future<IslamicHabitTemplate> addLimit(
    WidgetTester tester, {
    required String amount,
    required String unit,
  }) async {
    await open(tester, const Locale('ar'));
    await toLimit(tester, ar);
    await tester.enterText(find.byType(TextField).first, 'قهوة');
    await tester.pump();
    await tester.enterText(amountBox(ar), amount);
    await tester.enterText(unitBox(ar), unit);
    await tester.pump();
    await tester.tap(find.text(ar.continueAction));
    await tester.pumpAndSettle();
    await pickOften(tester, ar.oftenEveryDay);
    await tester.tap(find.text(ar.continueAction));
    await tester.pumpAndSettle();
    await addHabit(tester, ar);
    // Past the burst and the mocked permission refusal's SnackBar.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final created = container
        .read(customHabitsProvider)
        .singleWhere((h) => h.id != cups.id);
    expect(created.goalType, GoalType.quit, reason: 'sanity');
    expect(created.reductionType, ReductionType.limit, reason: 'sanity');
    return created;
  }

  testWidgets('«أكواب» saves as cups', (tester) async {
    final habit = await addLimit(tester, amount: '2', unit: 'أكواب');
    expect(habit.limitAmount, 2);
    expect(habit.limitUnit, LimitUnit.cups);
    expect(habit.customUnitLabel, isNull,
        reason: 'a stock unit carries no word of its own');
  });

  testWidgets('«cups» saves as cups, on the Arabic sheet too', (tester) async {
    final habit = await addLimit(tester, amount: '2', unit: 'cups');
    expect(habit.limitUnit, LimitUnit.cups,
        reason: 'a stock word in either language is that unit');
    expect(habit.customUnitLabel, isNull);
  });

  testWidgets('an empty unit box saves as times, its own placeholder',
      (tester) async {
    final habit = await addLimit(tester, amount: '3', unit: '');
    expect(habit.limitAmount, 3);
    expect(habit.limitUnit, LimitUnit.times);
    expect(habit.customUnitLabel, isNull);
  });

  testWidgets('«سجائر» saves as a custom unit carrying the word',
      (tester) async {
    final habit = await addLimit(tester, amount: '5', unit: 'سجائر');
    expect(habit.limitAmount, 5);
    expect(habit.limitUnit, LimitUnit.custom);
    expect(habit.customUnitLabel, 'سجائر');
  });

  testWidgets('an amount typed in Arabic-Indic digits «٢» saves 2',
      (tester) async {
    final habit = await addLimit(tester, amount: '٢', unit: 'أكواب');
    expect(habit.limitAmount, 2);
    expect(habit.limitUnit, LimitUnit.cups);
  });

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    testWidgets('[$tag] an edited cups habit shows «${s.limitUnitLabel('cups')}» '
        'in the unit box, and saves cups again', (tester) async {
      await open(tester, locale, existing: cups);
      await openEditStep(tester, s, 0);

      expect(
        tester.widget<TextField>(amountBox(s)).controller!.text,
        '3',
      );
      expect(
        tester.widget<TextField>(unitBox(s)).controller!.text,
        s.limitUnitLabel(LimitUnit.cups.name),
        reason: 'a stock unit is shown as its word, so the box reads back '
            'as the same unit',
      );

      await editStepDone(tester, s);
      await saveEdit(tester, s);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final saved =
          container.read(customHabitsProvider).firstWhere((h) => h.id == cups.id);
      expect(saved.limitUnit, LimitUnit.cups,
          reason: 'untouched, it must not come back as a custom «أكواب»');
      expect(saved.customUnitLabel, isNull);
      expect(saved.limitAmount, 3);
    });
  }
}
