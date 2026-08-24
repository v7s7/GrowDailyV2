// The question between onboarding and the Grid.
//
// The thing under test is not the layout, it is the contract: two real
// answers, and only one of them arms anything. «ورّيني أول خطوة» has to arm
// the app's REAL coach mark on the REAL add-habit button, through the same
// entry point Settings and the Get Started card use, because the alternative
// (a bespoke overlay over the guide card) is a coach mark pointing at a
// coach-mark launcher, which is the artefact this app already deleted once.
// «بعدين» has to arm nothing at all, so the Grid it lands on is byte for byte
// the Grid everybody else gets.
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
import 'package:grow_daily_v2/core/providers/first_run_offer_provider.dart';
import 'package:grow_daily_v2/core/providers/home_tab_provider.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/onboarding/notifiers/guide_steps_provider.dart';
import 'package:grow_daily_v2/features/onboarding/screens/first_run_offer_screen.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('first_run_offer_screen_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
  });

  // No Hive.deleteFromDisk() here, on purpose. Answering the question writes
  // to the settings box, and inside testWidgets that write runs in the fake
  // async zone, so its real file IO never completes. Awaiting a delete on a
  // box with an outstanding write then hangs the whole run rather than failing
  // it. Each test gets its own temp directory, so there is nothing to clean.

  // The guide is always stubbed, never derived.
  //
  // guideStepsProvider watches dashboardProvider, which reaches for Firebase
  // the moment it is constructed. This screen only ever asks the guide one
  // question ("is there a next step, and which one"), so stubbing the answer
  // keeps the test about the screen instead of about the whole progression
  // system booting.
  const fresh = [
    GuideStep(AppGuideLesson.addHabit, false),
    GuideStep(AppGuideLesson.colorSquare, false),
    GuideStep(AppGuideLesson.addTask, false),
    GuideStep(AppGuideLesson.discoverRooms, false),
  ];

  Future<ProviderContainer> containerWith({
    required List<IslamicHabitTemplate> habits,
    List<GuideStep> steps = fresh,
  }) async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      habitListProvider.overrideWithValue(habits),
      firstRunOfferAskedProvider.overrideWith((ref) => false),
      guideStepsProvider.overrideWithValue(steps),
    ]);
    await c.read(authStateProvider.future);
    return c;
  }

  Future<void> pump(WidgetTester tester, ProviderContainer c,
      [Locale locale = const Locale('ar')]) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.light,
        home: const FirstRunOfferScreen(),
      ),
    ));
    // pumpAndSettle alone is not enough here. flutter_animate implements
    // `delay:` with a plain Timer, and a pending Timer schedules no frames, so
    // pumpAndSettle returns at t=0 with every staggered entrance still queued
    // and then the harness fails the test for leaving a timer behind. One
    // explicit second of fake time drains all of them (the last entrance
    // starts at 380ms and runs 300ms).
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    testWidgets('[$tag] both answers are on screen, and neither is a corner X',
        (tester) async {
      final c = await containerWith(habits: const []);
      addTearDown(c.dispose);
      await pump(tester, c, locale);

      expect(find.text(s.firstRunOfferTitle), findsOneWidget);
      expect(find.text(s.firstRunOfferYes), findsOneWidget);
      expect(find.text(s.firstRunOfferLater), findsOneWidget);
      // A corner escape is what turns a question into an ad you flick past
      // without reading. Onboarding has one; this deliberately does not.
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.text(s.onboardingSkip), findsNothing);
    });
  }

  testWidgets('nothing is armed until somebody answers', (tester) async {
    final c = await containerWith(habits: const []);
    addTearDown(c.dispose);
    await pump(tester, c);

    expect(c.read(activeAppGuideLessonProvider), isNull);
    expect(c.read(firstRunAnswerProvider), isNull);
    expect(c.read(firstRunOfferAskedProvider), isFalse);
  });

  testWidgets('yes arms the REAL add-habit coach mark, not a card spotlight',
      (tester) async {
    final c = await containerWith(habits: const []);
    addTearDown(c.dispose);
    await pump(tester, c);

    await tester.tap(find.text(S(const Locale('ar')).firstRunOfferYes));
    await tester.pump();

    expect(c.read(activeAppGuideLessonProvider), AppGuideLesson.addHabit,
        reason: 'the promise on the button is the first step, and the first '
            'step is the real button on the real screen');
    expect(c.read(firstRunAnswerProvider), FirstRunAnswer.yes);
    expect(c.read(firstRunOfferAskedProvider), isTrue,
        reason: 'the gate has to move on the same frame');
    // startGuideLesson also asks for a tab, and HomeShell reads that request
    // with ref.listen, which only fires on a change while it is already
    // listening. HomeShell does not exist yet here, so a request left behind
    // is one nobody ever consumes, and the next caller asking for the same
    // tab is not a change and so does nothing.
    expect(c.read(requestedHomeTabProvider), isNull,
        reason: 'a tab request nobody can hear has to be cleared, or it '
            'silently swallows the next one');
  });

  testWidgets('later arms nothing at all', (tester) async {
    final c = await containerWith(habits: const []);
    addTearDown(c.dispose);
    await pump(tester, c);

    await tester.tap(find.text(S(const Locale('ar')).firstRunOfferLater));
    await tester.pump();

    expect(c.read(activeAppGuideLessonProvider), isNull,
        reason: 'declining must leave the Grid exactly as it ships');
    expect(c.read(firstRunAnswerProvider), FirstRunAnswer.later);
    expect(c.read(firstRunOfferAskedProvider), isTrue);
  });

  testWidgets('yes on a restored account does not circle a done step',
      (tester) async {
    // A reinstall into an account Firestore is about to restore: the guide is
    // already finished, so there is nothing to point at, and circling "add a
    // habit" for somebody who has eleven would be the app arguing with what
    // it can plainly see.
    final c = await containerWith(
      habits: [IslamicHabitCatalog.templates.first],
      steps: const [
        GuideStep(AppGuideLesson.addHabit, true),
        GuideStep(AppGuideLesson.colorSquare, true),
        GuideStep(AppGuideLesson.addTask, true),
        GuideStep(AppGuideLesson.discoverRooms, true),
      ],
    );
    addTearDown(c.dispose);
    await pump(tester, c);

    await tester.tap(find.text(S(const Locale('ar')).firstRunOfferYes));
    await tester.pump();

    expect(c.read(activeAppGuideLessonProvider), isNull);
    expect(c.read(firstRunOfferAskedProvider), isTrue,
        reason: 'still answered, just nothing left to show');
  });

  testWidgets('a double tap cannot answer twice', (tester) async {
    final c = await containerWith(habits: const []);
    addTearDown(c.dispose);
    await pump(tester, c);

    final yes = find.text(S(const Locale('ar')).firstRunOfferYes);
    await tester.tap(yes);
    await tester.tap(yes, warnIfMissed: false);
    await tester.pump();

    expect(c.read(firstRunAnswerProvider), FirstRunAnswer.yes);
  });
}
