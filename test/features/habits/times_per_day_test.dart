// The "N times a day" stepper, driven the way a person drives it.
//
// Option A from design/canvas.json: the row is on screen whenever Daily is
// selected, including at its resting value of 1, because a control nobody can
// see is a control nobody uses. The invariant that matters most here is the
// one about NOT changing anything: a habit left at one time a day must be
// byte-for-byte the habit that existed before this feature, so the tests
// below check the resting state as carefully as the counted one.
//
// What moved on 2026-09-09: the Repeat chips no longer open with Daily
// already lit, so "whenever Daily is selected" now begins at the tap that
// selects it. Every test below therefore picks Daily first, through the
// helper, and the one directly under this comment pins the state before
// that tap: chips offered, nothing underneath them yet.
//
// What moved on 2026-10-01 (the three-step sheet): how often is step 2,
// «كم مرة», one row of «كل يوم | مرات بالأسبوع | أيام معيّنة» with nothing
// lit, and the stepper sits in the panel under «كل يوم». The weekly
// dropdown became six number pills «1»..«6», so the weekly-leak test now
// picks one of them (5) before going back, which is the case it guards.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';

import 'support/add_habit_flow.dart';

void main() {
  late Directory tmp;
  late ProviderContainer container;

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('times_per_day_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
    container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
    ]);
    await container.read(authStateProvider.future);
  });

  tearDown(() => container.dispose());

  const ar = S(Locale('ar'));

  Widget app(Locale locale) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.light,
          home: const Scaffold(body: AddHabitSheet()),
        ),
      );

  /// The tappable cell of a choice, not its label (see the shared helper's
  /// [choice]): the strip at the top of the step prints the picked answer
  /// again, so a bare find.text would become ambiguous halfway through.
  Finder chip(String label) => choice(label);

  /// Walks the sheet to step 2, «كم مرة», and picks «كل يوم», which is what
  /// puts the stepper on screen. [pickDaily] false stops one tap short, for
  /// the test that pins what the step looks like before anything is chosen.
  Future<void> toWhen(WidgetTester tester, {bool pickDaily = true}) async {
    await tester.pumpWidget(app(const Locale('ar')));
    await toOften(tester, ar, name: 'الدواء');
    if (!pickDaily) return;
    await pickOften(tester, ar.oftenEveryDay);
  }

  Finder plus() => find.byIcon(Icons.add_rounded);
  Finder minus() => find.byIcon(Icons.remove_rounded);

  testWidgets('the step opens with no cadence picked and no stepper',
      (tester) async {
    await toWhen(tester, pickDaily: false);
    expect(find.text(ar.howOftenQuestion), findsOneWidget,
        reason: 'the question is asked');
    expect(find.text(ar.oftenEveryDay), findsOneWidget,
        reason: 'exactly the choice: with no cadence picked the strip at '
            'the top has no cadence to print, so this is unambiguous');
    expect(plus(), findsNothing,
        reason: 'the per-day count belongs to Daily, and Daily has not been '
            'chosen yet');
    expect(find.text(ar.timesPerDayLabel(1)), findsNothing);
    await _teardown(tester);
  });

  testWidgets('picking Daily is what brings the stepper', (tester) async {
    await toWhen(tester, pickDaily: false);
    expect(plus(), findsNothing);
    await tester.tap(chip(ar.oftenEveryDay));
    await tester.pump(const Duration(milliseconds: 400));
    expect(plus(), findsOneWidget);
    expect(find.text(ar.timesPerDayLabel(1)), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('Daily opens on one a day, and says so', (tester) async {
    await toWhen(tester);
    expect(plus(), findsOneWidget,
        reason: 'once Daily is chosen the stepper must be visible without '
            'being hunted for — that is the whole of Option A');
    expect(find.text(ar.timesPerDayLabel(1)), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    await _teardown(tester);
  });

  testWidgets('at one a day nothing extra is explained', (tester) async {
    await toWhen(tester);
    expect(find.text(ar.timesPerDayNote(1)), findsNothing,
        reason: 'the note is for a count that is actually a choice');
    expect(find.text(ar.timesPerDayHint(1)), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('plus counts up and the unit turns plural', (tester) async {
    await toWhen(tester);
    await tester.tap(plus());
    await tester.pump();
    expect(find.text('2'), findsWidgets);
    expect(find.text(ar.timesPerDayLabel(2)), findsOneWidget);
    expect(find.text(ar.timesPerDayLabel(1)), findsNothing);
    await _teardown(tester);
  });

  testWidgets('going multi explains the rule it just switched on',
      (tester) async {
    await toWhen(tester);
    await tester.tap(plus());
    await tester.pump();
    expect(find.text(ar.timesPerDayNote(2)), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets,
        reason: 'the note names the count, so it has to move with it');
    await _teardown(tester);
  });

  testWidgets('the count cannot go below one', (tester) async {
    await toWhen(tester);
    await tester.tap(minus());
    await tester.pump();
    expect(find.text(ar.timesPerDayLabel(1)), findsOneWidget,
        reason: 'minus at 1 must be inert, not wrap to 0 or below');
    await _teardown(tester);
  });

  testWidgets('the count stops at the stepper cap', (tester) async {
    await toWhen(tester);
    for (var i = 0; i < 20; i++) {
      // warnIfMissed: reaching the cap is supposed to make this button inert,
      // so the taps after the 11th genuinely hit nothing. That is the
      // assertion, not a flaw in it.
      await tester.tap(plus(), warnIfMissed: false);
      await tester.pump();
    }
    expect(find.text('12'), findsWidgets,
        reason: 'twenty taps must land on the cap, not past it');
    expect(find.text('13'), findsNothing);
    await _teardown(tester);
  });

  testWidgets('the stepper belongs to Daily and disappears with it',
      (tester) async {
    await toWhen(tester);
    expect(plus(), findsOneWidget);
    await tester.tap(chip(ar.oftenTimesAWeek));
    await tester.pump(const Duration(milliseconds: 300));
    expect(plus(), findsNothing,
        reason: 'a per-DAY count on a weekly habit is a contradiction');
    await _teardown(tester);
  });

  testWidgets('a weekly target never leaks in as a per-day count',
      (tester) async {
    // The bug this exists to prevent: frequencyTarget is one field meaning
    // two different things. Five times a WEEK carried across verbatim would
    // silently become five times a DAY.
    await toWhen(tester);
    await tester.tap(chip(ar.oftenTimesAWeek));
    await tester.pump(const Duration(milliseconds: 300));
    // The six number pills that replaced the dropdown.
    await tester.tap(chip('5'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(chip(ar.oftenEveryDay));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(ar.timesPerDayLabel(1)), findsOneWidget,
        reason: 'coming back from a number a week must rest at one a day, '
            'not inherit the 5 the week pills were holding');
    expect(find.text('5'), findsNothing);
    await _teardown(tester);
  });

  testWidgets('a count survives a trip through Specific Days and back',
      (tester) async {
    await toWhen(tester);
    await tester.tap(plus());
    await tester.pump();
    await tester.tap(plus());
    await tester.pump();
    expect(find.text('3'), findsWidgets);
    await tester.tap(chip(ar.oftenSetDays));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(chip(ar.oftenEveryDay));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('3'), findsWidgets,
        reason: 'Specific Days rewrites frequencyTarget to a number of '
            'weekdays; the per-day count is a separate field precisely so '
            'that cannot clobber it, and a count already chosen should still '
            'be there on the way back');
    expect(find.text(ar.timesPerDayLabel(3)), findsOneWidget);
    await _teardown(tester);
  });
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
