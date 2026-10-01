// Add Habit's first step «العادة» leads with the name box, for everyone.
//
// It used to open on the Build / Quit switch and, on a brand new account, a
// grid of suggestions and an "or write your own" label before the box, with
// the hub's Plans / Add Goal pills above all of it: three things to answer
// before the one thing to do, on a phone screen the keyboard then halves.
// Reported from Android as "it asks the option first, then the input, then
// the category". From 2026-09-08 the order was the same for every account:
// the switch, the box, a 3x3 category grid under it, and the suggestions
// under that once a category was picked.
//
// 2026-10-01, the three-step page (canvas v8): the page is type-first. The
// switch, the box, then «متابعة», and nothing to pick on the way. The 3x3
// category grid and its label are gone: the category is read from the name
// and shown as one line under the box («الفئة: …» with «تغيير», which opens
// a sideways row of category pills). The old «أو اختر خطة جاهزة» link is
// gone.
//
// Later the same day the inline ideas door «تبي أفكار أو خطة جاهزة؟» (a
// Plans card, a category row with a hint, then that category's suggestion
// chips, all opening under the box) went too (Aziz: "I don't like the
// design"). In its place is one card under the box, Doum with his idea and
// «أفكار وخطط جاهزة» inside the hub for a habit to build, «أفكار لعاداتك»
// anywhere else, and it opens the ideas page over the form. So:
//  * "the door opens to Plans, the categories and the hint, then the
//    suggestions after a category" is gone. The categories are only under
//    «تغيير» now, and what the door held lives on the ideas page, whose own
//    order (plans first, then single habits) is pinned here once, from the
//    card, and in full in habit_ideas_page_test.dart. With it went the one
//    thing a first habit did differently on this step, the suggestions'
//    label («أسرع طريقة تبدأ» against «اقتراحات ذكية»): the step is now the
//    same for every account, which the first test still checks for both.
//  * "standalone, the door offers ideas only" is the card's title now.
//  * "a suggestion fills the name and closes the door" is an idea from the
//    page: it fills the name and the category, and moves on to «كم مرة».
//
// These lock the ORDER and which controls lead, in both locales, plus the
// step bar above it all, whose past labels take a new habit back a step.
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
import 'package:grow_daily_v2/features/habits/catalog/habit_ideas.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';
import 'package:grow_daily_v2/features/habits/widgets/habit_ideas_page.dart';

import 'support/add_habit_flow.dart';

void main() {
  const dpr = 3.0;
  late Directory tmp;

  /// «صدقة يومية», read from the same file the page reads: a faith habit
  /// to build, every day, with no reminder.
  final charity = parseHabitIdeas(File(kHabitIdeasAsset).readAsStringSync())
      .firstWhere((i) => i.id == 'daily_charity');

  setUpAll(preloadIdeas);

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('first_habit_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
    // A phone, not the 800x600 default: tall enough that the whole first
    // step is on screen and the ideas card under it can be tapped without
    // scrolling.
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

  /// A container whose habit list is exactly [habits]: an empty account or
  /// a returning one.
  Future<ProviderContainer> containerWith(
      List<IslamicHabitTemplate> habits) async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      habitListProvider.overrideWithValue(habits),
    ]);
    await c.read(authStateProvider.future);
    return c;
  }

  /// The sheet standalone. [inHub] hands it a plan callback the way
  /// AddHabitHub does, which is what lets the ideas page offer plans.
  Widget app(
    ProviderContainer container,
    Locale locale, {
    bool inHub = false,
  }) =>
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
          theme: GameTheme.light,
          home: Scaffold(
            body: AddHabitSheet(onOpenPlan: inHub ? (_) {} : null),
          ),
        ),
      );

  const broadCategories = [
    HabitCategory.faith,
    HabitCategory.health,
    HabitCategory.learning,
    HabitCategory.focus,
    HabitCategory.sleep,
    HabitCategory.money,
    HabitCategory.mind,
    HabitCategory.social,
    HabitCategory.custom,
  ];

  /// Vertical position of the sheet's name box, whatever it is labelled.
  double fieldTop(WidgetTester tester) =>
      tester.getTopLeft(find.byType(TextField).first).dy;

  double topOf(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  /// The name box's text, read from its controller.
  String typedName(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!.text;

  FilledButton primary(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton).last);

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    /// A category pill under «تغيير», by name.
    Future<void> tapCategory(WidgetTester tester, HabitCategory cat) async {
      final pill = choice(cat.localizedName(s.isAr));
      await tester.ensureVisible(pill);
      await tester.pumpAndSettle();
      await tester.tap(pill);
      await tester.pumpAndSettle();
    }

    for (final empty in const [true, false]) {
      final who = empty ? 'an empty account' : 'a returning account';

      testWidgets('[$tag] $who: the switch, the box, the ideas card, '
          '«متابعة»', (tester) async {
        final container = await containerWith(
            empty ? const [] : [IslamicHabitCatalog.templates.first]);
        addTearDown(container.dispose);
        await tester.pumpWidget(app(container, locale));
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsOneWidget,
            reason: 'one box on the page: the name');
        expect(find.text(s.habitNameHintBuild), findsOneWidget,
            reason: 'the box shows an example, not a question');

        // Above the box: the heading, the step bar and the switch, nothing
        // else.
        final above = find.byType(Text).evaluate().where((e) {
          final box = e.renderObject as RenderBox?;
          return box != null &&
              box.hasSize &&
              box.localToGlobal(Offset.zero).dy < fieldTop(tester);
        });
        expect(above.length, lessThanOrEqualTo(6),
            reason: 'only the heading, the three step names and the two '
                'switch labels sit above the box');
        expect(find.text(s.hubTitle), findsOneWidget);
        for (final step in [
          s.addHabitStepWhat,
          s.addHabitStepOften,
          s.addHabitStepReminder,
        ]) {
          expect(find.text(step), findsOneWidget,
              reason: 'the step bar names all three steps');
        }
        expect(find.text(s.goalTypeBuildOption), findsOneWidget);
        expect(find.text(s.goalTypeQuitOption), findsOneWidget);
        expect(topOf(tester, s.goalTypeBuildOption), lessThan(fieldTop(tester)),
            reason: 'the kind of habit is decided right above the box');

        // Under it: the ideas card, and the button.
        expect(find.text(s.ideasEntryTitleNoPlans), findsOneWidget,
            reason: 'standalone there is no Plans tab to offer');
        expect(find.text(s.ideasEntryBodyNoPlans), findsOneWidget);
        expect(find.text(s.ideasEntryTitle), findsNothing);
        expect(topOf(tester, s.ideasEntryTitleNoPlans),
            greaterThan(fieldTop(tester)),
            reason: 'the box first, the help under it');
        expect(find.byType(HabitIdeasPage), findsNothing,
            reason: 'the ideas wait on a page of their own until asked for');
        expect(find.text(s.continueAction), findsOneWidget);
        expect(primary(tester).onPressed, isNull,
            reason: 'no name, nothing to continue with');

        // No category grid, no category section, no suggestions, no link.
        for (final cat in broadCategories) {
          expect(find.text(cat.localizedName(s.isAr)), findsNothing,
              reason: 'the 3x3 category grid is gone, and the row under '
                  '«تغيير» waits for a name');
        }
        expect(find.text(s.category), findsNothing);
        expect(find.textContaining(s.habitCategoryLine('')), findsNothing,
            reason: 'the category line waits for a name');
        expect(find.text(charity.name(s.isAr)), findsNothing,
            reason: 'no suggestion is drawn on the step itself');
      });
    }

    testWidgets('[$tag] inside the hub the card offers plans too, and its '
        'page puts them before the single habits', (tester) async {
      final container = await containerWith(const []);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale, inHub: true));
      await tester.pumpAndSettle();

      expect(find.text(s.ideasEntryTitle), findsOneWidget,
          reason: 'inside the hub the card names the plans as well');
      expect(find.text(s.ideasEntryBody), findsOneWidget);
      expect(find.text(s.ideasEntryTitleNoPlans), findsNothing);
      expect(topOf(tester, s.ideasEntryTitle), greaterThan(fieldTop(tester)),
          reason: 'under the box, never before it');

      await typeName(tester, 'قراءة');
      await openIdeas(tester, s, withPlans: true);

      expect(find.byType(HabitIdeasPage), findsOneWidget);
      expect(find.text(s.ideasPageTitle), findsOneWidget);
      expect(find.text(s.ideasPlansTitle), findsOneWidget,
          reason: 'inside the hub the page leads with the plans');
      expect(find.text(s.ideasHabitsTitle), findsOneWidget);
      expect(topOf(tester, s.ideasPlansTitle),
          lessThan(topOf(tester, s.ideasHabitsTitle)),
          reason: 'plans first, then the single habits');

      // The page's back button leaves the form as it was.
      await closeIdeas(tester);
      expect(find.byType(HabitIdeasPage), findsNothing);
      expect(typedName(tester), 'قراءة',
          reason: 'a look at the ideas changes nothing that was typed');
      expect(find.text(s.continueAction), findsOneWidget,
          reason: 'still on the first step');
      expect(
        find.text(s.habitCategoryLine(
            HabitCategory.learning.localizedName(s.isAr))),
        findsOneWidget,
        reason: 'and the category is still the one read from the name',
      );
    });

    testWidgets('[$tag] standalone, the card offers ideas only',
        (tester) async {
      final container = await containerWith(const []);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale));
      await tester.pumpAndSettle();

      expect(find.text(s.ideasEntryTitle), findsNothing);
      expect(find.text(s.ideasEntryBodyNoPlans), findsOneWidget);
      await openIdeas(tester, s);

      expect(find.byType(HabitIdeasPage), findsOneWidget);
      expect(find.text(s.ideasPlansTitle), findsNothing,
          reason: 'Plans are a hub tab; standalone there is none to open');
      expect(find.text(s.ideasHabitsTitle), findsOneWidget);
    });

    testWidgets('[$tag] an idea fills the name and its category, and moves '
        'on to «كم مرة»', (tester) async {
      final container = await containerWith(const []);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale, inHub: true));
      await tester.pumpAndSettle();

      await openIdeas(tester, s, withPlans: true);
      // Under «مختارة لك» while it is featured (the admin's call), and
      // always under its category.
      if (find.text(charity.name(s.isAr)).evaluate().isEmpty) {
        await tester.tap(find.descendant(
          of: find.byType(HabitIdeasPage),
          matching: find.text(HabitCategory.faith.localizedName(s.isAr)),
        ));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(charity.name(s.isAr)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.ideasEditFirst));
      await tester.pumpAndSettle();

      expect(find.byType(HabitIdeasPage), findsNothing,
          reason: 'the page closed behind the pick');
      expect(find.text(s.howOftenQuestion), findsOneWidget,
          reason: 'the name is answered, so the form moves on');

      await tester.tap(find.text(s.addHabitStepWhat));
      await tester.pumpAndSettle();

      expect(typedName(tester), charity.name(s.isAr),
          reason: 'the idea is the name');
      expect(
        find.text(s.habitCategoryLine(
            HabitCategory.faith.localizedName(s.isAr))),
        findsOneWidget,
        reason: 'the idea\'s category is the habit\'s',
      );
      expect(find.text(HabitCategory.health.localizedName(s.isAr)),
          findsNothing,
          reason: 'the category row stays closed');
      expect(find.text(s.ideasEntryTitle), findsOneWidget,
          reason: 'the card itself stays, for another look');
      expect(primary(tester).onPressed, isNotNull,
          reason: 'with a name, «متابعة» is live');
    });

    testWidgets('[$tag] the switch flips the box\'s example and back',
        (tester) async {
      final container = await containerWith(const []);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale, inHub: true));
      await tester.pumpAndSettle();

      expect(find.text(s.habitNameHintBuild), findsOneWidget,
          reason: 'the box gives a habit to build to start with');
      expect(find.text(s.quitStyleQuestion), findsNothing);
      expect(find.text(s.ideasEntryTitle), findsOneWidget);

      await tester.tap(find.text(s.goalTypeQuitOption));
      await tester.pumpAndSettle();

      expect(find.text(s.habitNameHintQuit), findsOneWidget,
          reason: 'the box now gives a habit to quit');
      expect(find.text(s.habitNameHintBuild), findsNothing);
      // In Arabic the quit heading and the switch's label are the same words.
      expect(find.text(s.hubTitle), findsNothing,
          reason: 'the heading follows the switch');
      expect(find.text(s.hubTitleQuit), findsWidgets);
      expect(find.text(s.quitStyleQuestion), findsOneWidget,
          reason: 'and the quit fully / limit question appears');
      expect(find.text(s.ideasEntryTitleNoPlans), findsOneWidget,
          reason: 'a plan is a set of habits to build, so no Plans for quit');
      expect(find.text(s.ideasEntryTitle), findsNothing);
      expect(find.text(s.goalTypeBuildOption), findsOneWidget,
          reason: 'both picks stay on screen; the other is the way back');

      await tester.tap(find.text(s.goalTypeBuildOption));
      await tester.pumpAndSettle();

      expect(find.text(s.habitNameHintBuild), findsOneWidget);
      expect(find.text(s.habitNameHintQuit), findsNothing);
      expect(find.text(s.quitStyleQuestion), findsNothing);
      expect(find.text(s.ideasEntryTitle), findsOneWidget);
    });

    testWidgets('[$tag] a name brings the category line, «تغيير» opens the row',
        (tester) async {
      final container = await containerWith(const []);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale));
      await tester.pumpAndSettle();

      final line = find.textContaining(s.habitCategoryLine(''));
      expect(line, findsNothing);
      expect(find.text(s.habitCategoryChange), findsNothing);

      await typeName(tester, 'قراءة');
      expect(line, findsOneWidget,
          reason: 'a name, so a category read from it, on one line');
      expect(find.text(s.habitCategoryChange), findsOneWidget);
      expect(find.text(HabitCategory.sleep.localizedName(s.isAr)),
          findsNothing,
          reason: 'the row waits for «تغيير»');

      await tester.tap(find.text(s.habitCategoryChange));
      await tester.pumpAndSettle();
      for (final cat in broadCategories) {
        expect(find.text(cat.localizedName(s.isAr)), findsOneWidget,
            reason: '«تغيير» opens the category row');
      }

      await tapCategory(tester, HabitCategory.sleep);

      expect(
        find.text(s.habitCategoryLine(
            HabitCategory.sleep.localizedName(s.isAr))),
        findsOneWidget,
        reason: 'the line says the picked category',
      );
      expect(find.text(HabitCategory.health.localizedName(s.isAr)),
          findsNothing,
          reason: 'and the row closes behind the pick');
    });

    testWidgets('[$tag] the step bar\'s past label takes a new habit back',
        (tester) async {
      final container = await containerWith(const []);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container, locale));
      await tester.pumpAndSettle();

      // A step not reached yet is not a way forward.
      await tester.tap(find.text(s.addHabitStepOften));
      await tester.pumpAndSettle();
      expect(find.text(s.howOftenQuestion), findsNothing,
          reason: 'a step ahead cannot be skipped to');
      expect(find.text(s.habitNameHintBuild), findsOneWidget);

      await toReminder(tester, s, name: 'قراءة');
      expect(find.text(s.reminderQuestion), findsOneWidget,
          reason: 'sanity: on the third step');

      await tester.tap(find.text(s.addHabitStepOften));
      await tester.pumpAndSettle();
      expect(find.text(s.howOftenQuestion), findsOneWidget,
          reason: 'the past label went back one step');
      expect(find.text(s.reminderQuestion), findsNothing);

      // The step just left is ahead again, so it is not a link now.
      await tester.tap(find.text(s.addHabitStepReminder));
      await tester.pumpAndSettle();
      expect(find.text(s.howOftenQuestion), findsOneWidget);

      await tester.tap(find.text(s.addHabitStepWhat));
      await tester.pumpAndSettle();
      expect(find.text(s.howOftenQuestion), findsNothing);
      expect(typedName(tester), 'قراءة',
          reason: 'back on the first step, with the name still typed');
      expect(find.text(s.continueAction), findsOneWidget);
    });
  }
}
