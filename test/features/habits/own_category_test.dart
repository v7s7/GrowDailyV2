// A category of one's own (Aziz, 2026-10-01: "let the user choose the
// custom category, and it be saved so he can use it later, so maybe a pop up
// where user can add a name and choose an icon").
//
// «فئة جديدة» leads the category row «تغيير» opens on step 1, the only
// category row left there. It opens a sheet with a name box, an icon grid
// and the pill drawn live; saving picks the category for the habit.
// Underneath it is HabitCategory.custom with two more fields on the habit,
// so points, counts and charts read it as «مخصص» always was. The list the
// rows offer is read back from the person's habits, which is what "saved for
// later" is: no separate store to sync.
//
// A category of one's own is never offered with the ideas. That was pinned
// against the inline ideas door's category row; since the door became the
// ideas page (2026-10-01) it is pinned against the page: its filter has the
// app's categories only, and no «فئة جديدة».
//
// The harness is quit_limit_row_alignment_test's (itself
// prayer_reminder_direction_test's): Hive in memory, Premium so the habit
// cap never answers first, the notifications channel mocked.
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
import 'package:grow_daily_v2/features/habits/models/own_category.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';
import 'package:grow_daily_v2/features/habits/widgets/habit_ideas_page.dart';
import 'package:grow_daily_v2/features/habits/widgets/own_category_sheet.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

import 'support/add_habit_flow.dart';

IslamicHabitTemplate _habit({
  String id = 'h1',
  HabitCategory category = HabitCategory.custom,
  String? ownName,
  String? ownIcon,
  DateTime? createdAt,
}) =>
    IslamicHabitTemplate(
      id: id,
      name: 'مشي',
      description: '',
      category: category,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 20,
      goldReward: 8,
      ownCategoryName: ownName,
      ownCategoryIcon: ownIcon,
      createdAt: createdAt,
    );

void main() {
  group('the model', () {
    test('a custom habit keeps its own name and icon through storage', () {
      final saved = _habit(ownName: 'رياضة', ownIcon: 'gym').toFirestore();
      expect(saved['category'], 'custom');
      expect(saved['ownCategoryName'], 'رياضة');
      expect(saved['ownCategoryIcon'], 'gym');
      final back = IslamicHabitTemplate.fromMap('h1', saved);
      expect(back.ownCategory, const OwnCategory(name: 'رياضة', icon: 'gym'));
      expect(back.ownCategory!.icon, 'gym');
    });

    test('one of the app\'s categories carries none, whatever is set', () {
      final h = _habit(
        category: HabitCategory.health,
        ownName: 'رياضة',
        ownIcon: 'gym',
      );
      expect(h.ownCategory, isNull);
      expect(h.toFirestore().containsKey('ownCategoryName'), isFalse);
      expect(h.toFirestore().containsKey('ownCategoryIcon'), isFalse);
    });

    test('a blank name is no category, and an unknown icon is the star', () {
      expect(_habit(ownName: '   ', ownIcon: 'gym').ownCategory, isNull);
      expect(ownCategoryIcon('not-an-icon'), Icons.star_rounded);
      expect(_habit(ownName: 'x').ownCategory!.icon, 'star');
    });

    test('the list is one per name, oldest habit first, archived included',
        () {
      final list = ownCategoriesFrom([
        _habit(id: 'c', ownName: 'قراءة', ownIcon: 'book',
            createdAt: DateTime(2026, 9, 3)),
        _habit(id: 'a', ownName: 'رياضة', ownIcon: 'gym',
            createdAt: DateTime(2026, 9, 1)),
        _habit(id: 'b', ownName: ' رياضة ', ownIcon: 'run',
            createdAt: DateTime(2026, 9, 2)),
        _habit(id: 'd', category: HabitCategory.faith,
            createdAt: DateTime(2026, 9, 4)),
      ]);
      expect([for (final c in list) c.name], ['رياضة', 'قراءة']);
      expect(list.first.icon, 'gym',
          reason: 'the first habit to use a name sets its icon');
    });
  });

  group('the sheet', () {
    const dpr = 3.0;
    const ar = S(Locale('ar'));
    late Directory tmp;
    late ProviderContainer container;

    setUpAll(() async {
      await preloadIdeas();
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
      tmp = await Directory.systemTemp.createTemp('own_category_test_');
      Hive.init(tmp.path);
      await Hive.openBox<dynamic>('box_settings', bytes: Uint8List(0));
      await Hive.openBox<dynamic>('box_daily_logs', bytes: Uint8List(0));
      await Hive.openBox<dynamic>('box_habits', bytes: Uint8List(0));
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
      view.physicalSize = const Size(390 * dpr, 844 * dpr);
      view.devicePixelRatio = dpr;
      container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          premiumAccessProvider.overrideWithValue(true),
        ],
      );
      await container.read(authStateProvider.future);
      container.read(customHabitsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
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

    /// The sheet on a pushed route, so a save's pop has somewhere to go.
    Future<void> open(
      WidgetTester tester, {
      IslamicHabitTemplate? existing,
    }) async {
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
    }

    /// Types [name] into the new category sheet, picks [icon], saves.
    Future<void> makeCategory(
      WidgetTester tester, {
      required String name,
      required IconData icon,
    }) async {
      await tester.tap(choice(ar.ownCategoryNew).last);
      await tester.pumpAndSettle();
      expect(find.byType(OwnCategorySheet), findsOneWidget);
      final save = find.widgetWithText(FilledButton, ar.ownCategorySave);
      expect(tester.widget<FilledButton>(save).onPressed, isNull,
          reason: 'nothing to save before a name is typed');
      await tester.enterText(
        find.descendant(
          of: find.byType(OwnCategorySheet),
          matching: find.byType(TextField),
        ),
        name,
      );
      await tester.pump();
      await tester.tap(find.descendant(
        of: find.byType(OwnCategorySheet),
        matching: find.byIcon(icon),
      ).last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(OwnCategorySheet),
          matching: find.text(name),
        ),
        findsWidgets,
        reason: 'the pill at the top is drawn from what is typed',
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(OwnCategorySheet), findsNothing);
    }

    testWidgets('a category made in the sheet is saved with the habit',
        (tester) async {
      await open(tester);
      // Not a walking name: that would arm the steps link, whose save asks
      // the platform for Health access.
      await typeName(tester, 'تمارين الصبح');
      await tester.tap(find.text(ar.habitCategoryChange));
      await tester.pumpAndSettle();
      await makeCategory(
        tester,
        name: 'رياضتي',
        icon: Icons.fitness_center_rounded,
      );

      expect(find.text(ar.habitCategoryLine('رياضتي')), findsOneWidget,
          reason: 'the line under the name says the category just made');

      await tester.tap(find.text(ar.continueAction));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.fitness_center_rounded), findsWidgets,
          reason: 'the strip on step 2 wears its icon');
      await pickOften(tester, ar.oftenEveryDay);
      await tester.tap(find.text(ar.continueAction));
      await tester.pumpAndSettle();
      await addHabit(tester, ar);

      final created = container
          .read(customHabitsProvider)
          .firstWhere((h) => h.name == 'تمارين الصبح');
      expect(created.category, HabitCategory.custom);
      expect(created.ownCategoryName, 'رياضتي');
      expect(created.ownCategoryIcon, 'gym');
      expect(container.read(ownCategoriesProvider),
          contains(const OwnCategory(name: 'رياضتي', icon: 'gym')),
          reason: 'saved, so the next habit is offered it');
    });

    testWidgets('the next habit is offered it under «تغيير», never on the '
        'ideas page', (tester) async {
      container.read(customHabitsProvider.notifier).add(
            name: 'رسم',
            category: HabitCategory.custom,
            ownCategory: const OwnCategory(name: 'رياضتي', icon: 'gym'),
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
          );
      await open(tester);

      // The page is for ideas, and a category of one's own has none (Aziz,
      // 2026-10-01: "it should only appear in the changing").
      await openIdeas(tester, ar);
      expect(find.byType(HabitIdeasPage), findsOneWidget);
      expect(find.text(ar.ideasFilterAll), findsOneWidget,
          reason: 'sanity: the filter row is up');
      expect(find.text('رياضتي'), findsNothing,
          reason: 'the filter is the app\'s categories only');
      expect(find.text(ar.ownCategoryNew), findsNothing,
          reason: 'and nothing is made from the ideas page');
      await closeIdeas(tester);

      await typeName(tester, 'سباحة');
      await tester.tap(find.text(ar.habitCategoryChange));
      await tester.pumpAndSettle();
      expect(find.text(ar.ownCategoryNew), findsOneWidget);
      expect(find.text('رياضتي'), findsOneWidget);
      await tester.tap(choice('رياضتي'));
      await tester.pumpAndSettle();
      expect(find.text(ar.habitCategoryLine('رياضتي')), findsOneWidget);

      await typeName(tester, 'سباحة الصبح');
      expect(find.text(ar.habitCategoryLine('رياضتي')), findsOneWidget,
          reason: 'picked by hand, so typing does not move it');
    });

    testWidgets('an edit moved to one of the app\'s categories drops its own',
        (tester) async {
      final habit = container.read(customHabitsProvider.notifier).add(
            name: 'رسم',
            category: HabitCategory.custom,
            ownCategory: const OwnCategory(name: 'رياضتي', icon: 'gym'),
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
          );
      await open(tester, existing: habit);
      await openEditStep(tester, ar, 0);
      expect(find.text(ar.habitCategoryLine('رياضتي')), findsOneWidget);

      await tester.tap(find.text(ar.habitCategoryChange));
      await tester.pumpAndSettle();
      // The row scrolls sideways and starts with «فئة جديدة» and the
      // person's own, so the app's categories can sit past its edge.
      final health = choice(HabitCategory.health.localizedName(true));
      await tester.ensureVisible(health);
      await tester.pumpAndSettle();
      await tester.tap(health);
      await tester.pumpAndSettle();
      expect(
        find.text(ar.habitCategoryLine(HabitCategory.health.localizedName(true))),
        findsOneWidget,
      );
      await editStepDone(tester, ar);
      await saveEdit(tester, ar);

      final saved = container
          .read(customHabitsProvider)
          .firstWhere((h) => h.id == habit.id);
      expect(saved.category, HabitCategory.health);
      expect(saved.ownCategory, isNull);
      expect(saved.toFirestore().containsKey('ownCategoryName'), isFalse);
    });

    testWidgets('an edit that leaves it alone keeps it', (tester) async {
      final habit = container.read(customHabitsProvider.notifier).add(
            name: 'رسم',
            category: HabitCategory.custom,
            ownCategory: const OwnCategory(name: 'رياضتي', icon: 'run'),
            frequencyType: HabitFrequencyType.daily,
            frequencyTarget: 1,
          );
      await open(tester, existing: habit);
      expect(find.byIcon(Icons.directions_run_rounded), findsWidgets,
          reason: 'the overview\'s habit row wears its icon');
      await saveEdit(tester, ar);

      final saved = container
          .read(customHabitsProvider)
          .firstWhere((h) => h.id == habit.id);
      expect(saved.ownCategory, const OwnCategory(name: 'رياضتي', icon: 'run'));
      expect(saved.ownCategoryIcon, 'run');
    });
  });
}
