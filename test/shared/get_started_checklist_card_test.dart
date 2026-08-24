// The Get Started card shows the whole guide, not just the next line of it.
//
// It used to render exactly one row - whichever step was next - above a "2 of
// 4" counter. So a new user could be told they were on step 2 of 4 without
// ever being shown what steps 3 and 4 were, or what step 1 had been. A guide
// that hides its own contents is a prompt, not a guide: you cannot tell how
// long it is, what you already did, or whether it is worth starting.
//
// These lock in that all four steps are on screen at once, that the three
// states stay distinguishable by more than colour (the next step is the only
// one with a subtitle and a chevron), and that the card still retires itself
// when the guide is finished.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/app_guide_provider.dart';
import 'package:grow_daily_v2/core/providers/get_started_checklist_provider.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart'
    show habitsStillLoadingProvider;
import 'package:grow_daily_v2/features/onboarding/notifiers/guide_steps_provider.dart';
import 'package:grow_daily_v2/shared/widgets/get_started_checklist_card.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('guide_card_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
    await Hive.openBox<dynamic>('box_tasks');
  });

  /// The four lessons in the order the guide teaches them.
  const lessons = [
    AppGuideLesson.addHabit,
    AppGuideLesson.colorSquare,
    AppGuideLesson.addTask,
    AppGuideLesson.discoverRooms,
  ];

  /// A container whose guide is exactly [doneCount] steps in.
  Future<ProviderContainer> containerAt(int doneCount) async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      habitsStillLoadingProvider.overrideWithValue(false),
      guideStepsProvider.overrideWithValue([
        for (var i = 0; i < lessons.length; i++)
          GuideStep(lessons[i], i < doneCount),
      ]),
    ]);
    await c.read(authStateProvider.future);
    return c;
  }

  Future<void> pumpCard(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(child: GetStartedChecklistCard()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('every step is on screen, done or not', (tester) async {
    final c = await containerAt(2);
    addTearDown(c.dispose);
    await pumpCard(tester, c);

    for (final lesson in lessons) {
      expect(find.text(appGuideLessonTitle(lesson, true)), findsOneWidget,
          reason: 'the guide has to be readable in full, not one line at a '
              'time: $lesson is missing');
    }
  });

  testWidgets('the steps stay in the guide\'s own order', (tester) async {
    final c = await containerAt(1);
    addTearDown(c.dispose);
    await pumpCard(tester, c);

    final tops = [
      for (final lesson in lessons)
        tester.getTopLeft(find.text(appGuideLessonTitle(lesson, true))).dy,
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]),
          reason: 'step ${i + 1} must sit below step $i');
    }
  });

  testWidgets('progress is stated three ways, not just as a number',
      (tester) async {
    final c = await containerAt(2);
    addTearDown(c.dispose);
    await pumpCard(tester, c);

    // The bar.
    final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.5, 0.001));

    // The ticks: one per finished step, and only those.
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.circle_outlined), findsNWidgets(2));
  });

  testWidgets('only the next step gets a subtitle', (tester) async {
    final c = await containerAt(2);
    addTearDown(c.dispose);
    await pumpCard(tester, c);

    // Step 3 is next. A done step has nothing left to teach and a later step
    // should be skippable by eye, so neither carries its subtitle.
    expect(find.text(appGuideLessonSubtitle(AppGuideLesson.addTask, true)),
        findsOneWidget);
    expect(find.text(appGuideLessonSubtitle(AppGuideLesson.addHabit, true)),
        findsNothing);
    expect(
        find.text(appGuideLessonSubtitle(AppGuideLesson.discoverRooms, true)),
        findsNothing);
  });

  testWidgets('every row is a real target, not just the next one',
      (tester) async {
    // This used to assert exactly one chevron, because exactly one row was
    // meant to be actionable. It was the wrong invariant: the card rendered
    // four rows that all LOOKED like menu items while a single tap handler
    // wrapped the whole card and always armed whatever step was next, so
    // tapping «انضم لغرفة» did not go to Rooms. Four rows, four chevrons,
    // four destinations.
    final c = await containerAt(2);
    addTearDown(c.dispose);
    await pumpCard(tester, c);

    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(4));
    for (final lesson in lessons) {
      final row = find.ancestor(
        of: find.text(appGuideLessonTitle(lesson, true)),
        matching: find.byType(InkWell),
      );
      expect(row, findsWidgets, reason: '$lesson is not tappable');
      expect(tester.getSize(row.first).height, greaterThanOrEqualTo(44),
          reason: '$lesson is under Apple\'s 44pt minimum target');
    }
  });

  /// The snackbar holds a six second timer, and the harness fails a test that
  /// leaves one pending. Pumping past it is the drain; pumpAndSettle would do
  /// the same thing but reads as if the test cared about settling.
  Future<void> drainSnackBar(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 7));

  group('the X is not a one-way door', () {
    testWidgets('dismissing offers an undo, not silence', (tester) async {
      // The X is a 16pt grey glyph in the corner where every app puts "close
      // this notice", and it removed the only thing teaching a first-time
      // user what to do, forever, on that device, with no confirmation. A
      // person who taps it by reflex had no route back except Settings, which
      // is exactly where a reflex-dismisser will not look.
      final c = await containerAt(1);
      addTearDown(c.dispose);
      await pumpCard(tester, c);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(c.read(getStartedDismissedProvider), isTrue,
          reason: 'the dismissal itself still has to work');
      expect(find.text(S(const Locale('ar')).undo), findsOneWidget,
          reason: 'and it has to be takeable back');
      expect(find.text(S(const Locale('ar')).guideHiddenUndoHint),
          findsOneWidget,
          reason: 'the message has to say where it went, for the person who '
              'did not mean to tap it');
      await drainSnackBar(tester);
    });

    testWidgets('undo actually brings it back', (tester) async {
      final c = await containerAt(1);
      addTearDown(c.dispose);
      await pumpCard(tester, c);

      await tester.tap(find.byIcon(Icons.close_rounded));
      // The snackbar slides up from off screen, so at t=0 its button is
      // findable but not yet anywhere a tap can land. Pump the entrance
      // through before pressing it. Not pumpAndSettle: the thing has a six
      // second timer and settling would wait it out and then dismiss it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text(S(const Locale('ar')).undo));
      await tester.pump();

      expect(c.read(getStartedDismissedProvider), isFalse);
      await drainSnackBar(tester);
    });
  });

  testWidgets('a finished guide leaves no card behind', (tester) async {
    final c = await containerAt(4);
    addTearDown(c.dispose);
    await pumpCard(tester, c);

    for (final lesson in lessons) {
      expect(find.text(appGuideLessonTitle(lesson, true)), findsNothing);
    }
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
