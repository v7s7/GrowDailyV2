// The "N times a day" stepper, driven the way a person drives it.
//
// Option A from design/canvas.json: the row is on screen whenever Daily is
// selected, including at its resting value of 1, because a control nobody can
// see is a control nobody uses. The invariant that matters most here is the
// one about NOT changing anything: a habit left at one time a day must be
// byte-for-byte the habit that existed before this feature, so the tests
// below check the resting state as carefully as the counted one.
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

  /// Walks the sheet to the frequency step, where the stepper lives.
  Future<void> toWhen(WidgetTester tester) async {
    await tester.pumpWidget(app(const Locale('ar')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).first, 'الدواء');
    await tester.pump();
    await tester.tap(find.byType(FilledButton).last);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder plus() => find.byIcon(Icons.add_rounded);
  Finder minus() => find.byIcon(Icons.remove_rounded);

  testWidgets('Daily opens on one a day, and says so', (tester) async {
    await toWhen(tester);
    expect(plus(), findsOneWidget,
        reason: 'the stepper must be visible without being hunted for — '
            'that is the whole of Option A');
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
    await tester.tap(find.text(ar.weekly));
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
    await tester.tap(find.text(ar.weekly));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(ar.daily));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(ar.timesPerDayLabel(1)), findsOneWidget,
        reason: 'coming back from Weekly must rest at one a day, not inherit '
            'whatever the weekly dropdown was holding');
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
    await tester.tap(find.text(ar.specificDays));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(ar.daily));
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
