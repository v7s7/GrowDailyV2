// The hub's half of the Add Habit page (the form's half is
// first_habit_layout_test.dart).
//
// A brand new account tapping «إضافة عادة» used to meet the Plans / Add Goal
// pills first, pulsing, with a "choose one to continue" card and the form
// frosted over behind them. From 2026-09-08 a first habit opened straight on
// the form instead, and since the three-step page (canvas v8, 2026-10-01)
// EVERY account does: no pills, no hint, even when the App Guide's add-habit
// lesson is the thing that brought the person here, and whether or not the
// account already has habits. (The "pills hidden for a first habit only"
// rule these used to pin is gone with it.) The old «أو اختر خطة جاهزة» link
// is gone too. Opened on Plans directly the pills show from the start, and
// during the lesson the "choose one" card explains them.
//
// Plans are one tap from the form through step 1's ideas card, «أفكار وخطط
// جاهزة», which opens the ideas page with its plans first. It replaced the
// inline ideas door «تبي أفكار أو خطة جاهزة؟» and its Plans card on
// 2026-10-01, so the two tests that opened the door now look for the card,
// and the trip to Plans starts from a plan picked on the page: that switches
// the hub to its Plans tab and brings the pills back for the rest of the
// sheet, so the way back to the form is the usual one.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/app_guide_provider.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_ideas.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_hub_sheet.dart';
import 'package:grow_daily_v2/features/habits/widgets/habit_ideas_page.dart';

import 'support/add_habit_flow.dart';

void main() {
  const dpr = 3.0;
  late Directory tmp;

  setUpAll(preloadIdeas);

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('first_habit_hub_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(390 * dpr, 844 * dpr);
    view.devicePixelRatio = dpr;
  });

  tearDown(() async {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  Future<ProviderContainer> boot({
    required List<IslamicHabitTemplate> habits,
    bool midLesson = false,
  }) async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      habitListProvider.overrideWithValue(habits),
    ]);
    await c.read(authStateProvider.future);
    if (midLesson) {
      c.read(activeAppGuideLessonProvider.notifier).state =
          AppGuideLesson.addHabit;
    }
    return c;
  }

  Widget app(ProviderContainer container, Locale locale, HubTab tab) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.dark,
          home: Scaffold(body: AddHabitHub(initialTab: tab)),
        ),
      );

  Finder hint(Locale locale) => find.textContaining(
      locale.languageCode == 'ar' ? 'اختر إحدى' : 'Choose one');

  /// The name box's text, read from its controller.
  String typedName(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!.text;

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    for (final withHabit in const [false, true]) {
      final who = withHabit ? 'an account with habits' : 'an empty account';

      testWidgets('[$tag] $who opens on the form, no pills, no hint',
          (tester) async {
        final container = await boot(
          habits: withHabit ? [IslamicHabitCatalog.templates.first] : const [],
          midLesson: true,
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(app(container, locale, HubTab.addGoal));
        await tester.pumpAndSettle();

        expect(find.text(s.hubTitle), findsOneWidget);
        expect(find.text(s.plansTab), findsNothing,
            reason: 'no pills above the form, and no ideas page over it');
        expect(find.text(s.addGoalTitle), findsNothing,
            reason: 'neither the pill nor a second heading under the hub\'s');
        expect(hint(locale), findsNothing,
            reason: 'the lesson\'s "choose one" card has no pills to explain');
        expect(find.byType(TextField), findsWidgets,
            reason: 'the name box is right there');
        expect(find.text(s.goalTypeQuitOption), findsOneWidget,
            reason: 'the Build / Quit switch is part of the form for everyone');
        expect(find.text(s.ideasEntryTitle), findsOneWidget,
            reason: 'Plans stay one tap away, through the ideas card');
        expect(find.byType(HabitIdeasPage), findsNothing,
            reason: 'the ideas page waits for a tap on the card');
      });
    }

    testWidgets(
        '[$tag] a plan picked on the ideas page brings the pills back, and '
        'back to the form keeps what was typed', (tester) async {
      final container = await boot(habits: const []);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale, HubTab.addGoal));
      await tester.pumpAndSettle();

      await typeName(tester, 'قراءة');
      await openIdeas(tester, s, withPlans: true);
      final plan = shownPlans().first.name(s.isAr);
      expect(find.text(plan), findsOneWidget,
          reason: 'the page opens with the plans first');
      await tester.tap(find.text(plan));
      await tester.pumpAndSettle();

      expect(find.byType(HabitIdeasPage), findsNothing);
      expect(find.text(s.plansTab), findsOneWidget,
          reason: 'on Plans the pills are the way back to the form');
      expect(find.text(s.addGoalTitle), findsOneWidget);
      expect(find.text(s.ideasEntryTitle), findsNothing,
          reason: 'the form is off screen while Plans shows');

      await tester.tap(find.text(s.addGoalTitle));
      await tester.pumpAndSettle();

      // The Add Goal pill is the one place that label is drawn.
      expect(find.text(s.addGoalTitle), findsOneWidget,
          reason: 'once revealed the pills stay for the rest of the sheet');
      expect(find.text(s.plansTab), findsOneWidget);
      expect(find.text(s.goalTypeQuitOption), findsOneWidget,
          reason: 'back on the form');
      expect(typedName(tester), 'قراءة',
          reason: 'a trip to Plans and back keeps what was typed');
    });

    for (final withHabit in const [false, true]) {
      final who = withHabit ? 'with habits' : 'with no habits';

      testWidgets('[$tag] opened on Plans $who, the pills show from the start',
          (tester) async {
        final container = await boot(
          habits: withHabit ? [IslamicHabitCatalog.templates.first] : const [],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(app(container, locale, HubTab.plans));
        await tester.pumpAndSettle();

        expect(find.text(s.plansTab), findsOneWidget);
        expect(find.text(s.addGoalTitle), findsOneWidget,
            reason: 'on the second tab, the first one is the way to the form');
        expect(hint(locale), findsNothing,
            reason: 'no lesson running, nothing to explain');
      });
    }

    testWidgets('[$tag] opened on Plans during the lesson, the hint explains '
        'the pills', (tester) async {
      final container = await boot(habits: const [], midLesson: true);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale, HubTab.plans));
      // Not pumpAndSettle: the lesson's gold ring pulses forever, so the
      // frame count never settles. A second is past the hint's own fade.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(s.plansTab), findsOneWidget);
      expect(find.text(s.addGoalTitle), findsOneWidget);
      expect(hint(locale), findsOneWidget,
          reason: 'the lesson still explains the pills when there are pills');
    });
  }
}
