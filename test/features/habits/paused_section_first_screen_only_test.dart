// The resume list belongs to the FIRST screen of the Add Habit hub, and to
// nothing after it.
//
// The section exists for one moment: somebody opens this sheet to "get a
// habit", and should meet the habit they already built and paused before they
// meet the catalog. That argument is entirely about the instant BEFORE they
// start building. It kept rendering after it, so on the second step of Add
// Goal — «متى وكيف ستتابع؟», with a name already typed — «تمرين · استئناف» sat
// above the form offering to throw the whole thing away, while holding a
// quarter of a sheet whose primary button had already been fighting for room.
//
// The switcher directly below it had this rule already (hide once Add Goal has
// moved on, for the same "don't invite a tap that discards their work" reason),
// so this is one predicate governing both: see _AddHabitHubState._onChooserStep.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_hub_sheet.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('paused_section_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  IslamicHabitTemplate pausedHabit() => IslamicHabitTemplate(
        id: 'h-train',
        name: 'Exercise',
        nameAr: 'تمرين',
        description: '',
        category: HabitCategory.custom,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        hasTimer: false,
        xpReward: 10,
        goldReward: 5,
      ).withDates(
        createdAt: DateTime(2026, 1, 1),
        archivedAt: DateTime(2026, 8, 24),
      );

  Future<ProviderContainer> boot() async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      pausedHabitsProvider.overrideWithValue([pausedHabit()]),
    ]);
    await c.read(authStateProvider.future);
    return c;
  }

  Widget app(ProviderContainer container, Locale locale) =>
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
          home: const Scaffold(
            body: AddHabitHub(initialTab: HubTab.addGoal),
          ),
        ),
      );

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    testWidgets('[$tag] the resume list shows on the first step and not after',
        (tester) async {
      final container = await boot();
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale));
      await tester.pumpAndSettle();

      // Step one: the offer is exactly where it belongs.
      expect(find.text(s.habitPausedSection), findsOneWidget,
          reason: 'this is the moment the section exists for');
      expect(find.text(s.habitResume), findsWidgets);

      // Typing a name is what unlocks Continue, so this is also the point
      // where the user has something to lose.
      await tester.enterText(find.byType(TextField).first, 'قراءة');
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.continueAction));
      await tester.pumpAndSettle();

      // Step two: on the «when and how» screen.
      expect(find.text(s.createGoal), findsOneWidget,
          reason: 'sanity: the form really did advance');
      expect(find.text(s.habitPausedSection), findsNothing,
          reason: 'the resume list must not sit on top of a form in progress');
      expect(find.text(s.habitResume), findsNothing,
          reason: 'and neither must a button that would discard it');

      // Going back is a real return to the choosing surface, so the offer
      // comes back with it — this is a gate, not a one-way dismissal.
      await tester.tap(find.text(s.back));
      await tester.pumpAndSettle();
      expect(find.text(s.habitPausedSection), findsOneWidget);
    });

    testWidgets('[$tag] the switcher and the resume list hide together',
        (tester) async {
      // One predicate governs both (see _onChooserStep). Pinned so a later
      // change cannot split them and leave the sheet showing half a chooser
      // above a form.
      final container = await boot();
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale));
      await tester.pumpAndSettle();

      expect(find.text(s.plansTab), findsOneWidget);
      expect(find.text(s.habitPausedSection), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'قراءة');
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.continueAction));
      await tester.pumpAndSettle();

      expect(find.text(s.plansTab), findsNothing);
      expect(find.text(s.habitPausedSection), findsNothing);
    });
  }
}
