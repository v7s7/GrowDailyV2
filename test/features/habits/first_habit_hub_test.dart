// The hub's half of the first-habit page (the form's half is
// first_habit_layout_test.dart).
//
// A brand new account tapping «إضافة عادة» used to meet the Plans / Add Goal
// pills first, pulsing, with a "choose one to continue" card and the form
// frosted over behind them. Now the sheet opens straight on the form: no
// pills, no hint, even when the App Guide's add-habit lesson is the thing
// that brought the person here. Plans stay one tap away through the link
// under the form, and taking that link brings the pills back so the way back
// to the form is the usual one. Opened on Plans directly, or with any habit
// already on the account, nothing changes.
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
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_hub_sheet.dart';

void main() {
  const dpr = 3.0;
  late Directory tmp;

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

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    testWidgets('[$tag] a first habit opens on the form, no pills, no hint',
        (tester) async {
      final container = await boot(habits: const [], midLesson: true);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale, HubTab.addGoal));
      await tester.pumpAndSettle();

      expect(find.text(s.hubTitle), findsOneWidget);
      expect(find.text(s.plansTab), findsNothing,
          reason: 'no pills above the first habit\'s form');
      expect(find.text(s.addGoalTitle), findsNothing,
          reason: 'neither the pill nor a second heading under the hub\'s');
      expect(hint(locale), findsNothing,
          reason: 'the lesson\'s "choose one" card has nothing to explain');
      expect(find.byType(TextField), findsWidgets,
          reason: 'the name box is right there');
      expect(find.text(s.readyPlansLink), findsOneWidget,
          reason: 'Plans stay one tap away, under the form');
    });

    testWidgets('[$tag] the Plans link brings the pills back, and back again',
        (tester) async {
      final container = await boot(habits: const []);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale, HubTab.addGoal));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(s.readyPlansLink));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.readyPlansLink));
      await tester.pumpAndSettle();

      expect(find.text(s.plansTab), findsOneWidget,
          reason: 'on Plans the pills are the way back to the form');
      expect(find.text(s.readyPlansLink), findsNothing,
          reason: 'the form is off screen while Plans shows');

      await tester.tap(find.text(s.addGoalTitle));
      await tester.pumpAndSettle();

      expect(find.text(s.plansTab), findsOneWidget,
          reason: 'once revealed the pills stay for the rest of the sheet');
      expect(find.text(s.readyPlansLink), findsNothing,
          reason: 'and the link steps aside: with pills on screen it would '
              'only repeat the Plans pill');
      expect(find.text(s.goalTypeQuitOption), findsOneWidget,
          reason: 'the Build / Quit switch is part of the form regardless');
    });

    testWidgets('[$tag] opened on Plans with no habits, the pills show',
        (tester) async {
      final container = await boot(habits: const []);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale, HubTab.plans));
      await tester.pumpAndSettle();

      expect(find.text(s.plansTab), findsOneWidget);
      expect(find.text(s.addGoalTitle), findsOneWidget);
    });

    testWidgets('[$tag] with a habit on the account nothing is hidden',
        (tester) async {
      final container = await boot(
          habits: [IslamicHabitCatalog.templates.first], midLesson: true);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale, HubTab.addGoal));
      // Not pumpAndSettle: the lesson's gold ring pulses forever, so the
      // frame count never settles. A second is past the hint's own fade.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(s.plansTab), findsOneWidget);
      expect(hint(locale), findsOneWidget,
          reason: 'the lesson still explains the pills when there are pills');
      expect(find.text(s.readyPlansLink), findsNothing,
          reason: 'with the pills on screen the Plans link would be a copy');
      expect(find.text(s.goalTypeQuitOption), findsOneWidget,
          reason: 'the Build / Quit switch is part of the form for everyone');
    });
  }
}
