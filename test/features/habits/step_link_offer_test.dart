// The steps offer in Add Habit: where it is, and what it is set to.
//
// Reported from a device: "when user add a habit and its walking ... it should
// show a clear that the message of the apple health, because now its appear
// but down, if user click okay without linking it wont work."
//
// Both halves of that were true and both were measurable. The card rendered
// AFTER the whole name + 3x3 category grid + suggestions block, and on an
// iPhone 17 Pro with the Arabic keyboard open there is about 210pt of sheet
// left under the name field: somebody typing "المشي" saw the field, one row
// of category chips and the Continue button, and nothing else. And the switch
// on that card was off, so the primary button they could see saved a walking
// habit with no link and no way to know one had been offered.
//
// So: the card sits right under the name field, and its switch comes up ON
// for a name that reads as walking. The switch grants nothing by itself (the
// OS permission is still asked at Save, which these tests never reach), which
// is what makes an on-by-default switch honest rather than a pre-ticked
// consent box.
//
// These lock the POSITION and the DEFAULT, plus the two ways the default has
// to yield: a switch somebody touched, and a name that stops being about
// walking.
//
// The three-step sheet (2026-10-01) took the 3x3 category grid away. The
// category is now one line under the name, «الفئة: الصحة» with «تغيير»
// beside it, and the categories open in a row under that line. Ideas are a
// card further down, «أفكار لعاداتك» (outside the hub), which opens a page
// of their own; until later that day it was an inline ideas door holding
// the categories and suggestions. So the card's position is pinned as:
// under the name and its category line, above the ideas card. The category
// a name lands in is read off that line instead of a lit chip. A category
// picked by hand is picked through «تغيير», which needs a name on the line
// first: the case that picked one before typing, through the door, is now
// a walking name moved by hand and then typed on. An edit opens on an
// overview, so the edit tests open its first row, «العادة», where the card
// lives.
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
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';

import 'support/add_habit_flow.dart';

void main() {
  late Directory tmp;
  late ProviderContainer container;

  const ar = S(Locale('ar'));
  const en = S(Locale('en'));

  setUp(() async {
    NotificationService.instance.celebrationsEnabled = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('step_link_offer_test_');
    Hive.init(tmp.path);
    // All three, exactly as main() opens them - opening a subset makes these
    // fail intermittently depending on which notifier touches which box first.
    await Hive.openBox<dynamic>('box_settings');
    await Hive.openBox<dynamic>('box_daily_logs');
    await Hive.openBox<dynamic>('box_habits');
    container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      // Not an empty list: an account with habits is the ordinary path
      // through the sheet. (An empty one used to put the suggestions ABOVE
      // the name field; today the step is the same for both, see
      // first_habit_layout_test.)
      habitListProvider.overrideWithValue([IslamicHabitCatalog.templates.first]),
    ]);
    await container.read(authStateProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  Widget app(Locale locale, {IslamicHabitTemplate? existing}) =>
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
          home: Scaffold(body: AddHabitSheet(existing: existing)),
        ),
      );

  /// The card's title, which is what "the card is on screen" means here.
  /// Platform-split in the widget, so the expectation has to split the same
  /// way: under `flutter test` the host is macOS, so this is the Health
  /// Connect wording, and pinning the iOS one would pass nowhere.
  Finder cardTitle(S s) => find.text(s.stepLinkTitle(Platform.isIOS));

  Finder switchFinder() => find.byType(Switch);

  bool switchIsOn(WidgetTester tester) =>
      tester.widget<Switch>(switchFinder().first).value;

  /// The line under the name box that says which category the habit is
  /// in, «الفئة: الصحة».
  Finder categoryLine(HabitCategory category, S s) =>
      find.text(s.habitCategoryLine(category.localizedName(s.isAr)));

  group('where the offer is', () {
    testWidgets('the card lands under the name and above the ideas card',
        (tester) async {
      await tester.pumpWidget(app(const Locale('ar')));
      await tester.pumpAndSettle();

      expect(cardTitle(ar), findsNothing,
          reason: 'nothing has been typed yet, so there is nothing to offer');

      await tester.enterText(find.byType(TextField).first, 'المشي اليومي');
      await tester.pumpAndSettle();

      final title = cardTitle(ar);
      expect(title, findsOneWidget);

      final fieldBottom =
          tester.getBottomLeft(find.byType(TextField).first).dy;
      final line = categoryLine(HabitCategory.health, ar);
      expect(line, findsOneWidget);
      // A sheet opened outside the hub has no Plans, so its ideas card
      // offers ideas only.
      final ideas = find.text(ar.ideasEntryTitleNoPlans);
      expect(ideas, findsOneWidget);

      expect(tester.getTopLeft(title).dy, greaterThan(fieldBottom),
          reason: 'the offer is about the name that was just typed, so it '
              'sits under it');
      expect(tester.getTopLeft(title).dy,
          greaterThan(tester.getBottomLeft(line).dy),
          reason: 'under the one category line too, which is all that is '
              'left of the category grid on this step');
      expect(tester.getTopLeft(title).dy,
          lessThan(tester.getTopLeft(ideas).dy),
          reason: 'and ABOVE the ideas card: what used to bury it below '
              'the fold (the categories and suggestions) must not come back '
              'between it and the name');
    });

    testWidgets('and it is fully visible with the keyboard open',
        (tester) async {
      // The reported failure, reproduced by measurement rather than by a
      // screenshot. Read off the real thing on an iPhone 17 Pro with the
      // Arabic keyboard open: AddHabitHub sizes itself to `screenHeight -
      // keyboard - 16` (874 - 336 - 16 = 522), and its own chrome (drag
      // handle, "إضافة عادة", the Plans/Add Goal tab row) takes about 170 of
      // that before this form starts. So the form gets ~350pt, and inside
      // that its title and footer button leave a scroll viewport of roughly
      // 240pt: enough for the goal-type toggle, the name field and one and a
      // half rows of category chips. That is exactly what the before
      // screenshot shows, and it is why a card rendered after the whole 3x3
      // grid was not "hard to see" but off the sheet entirely.
      //
      // Both halves of the fix are under test here: the card being adjacent
      // to the field, and _revealStepCard scrolling it the rest of the way.
      // Verified to FAIL with either half removed (before 2026-10-01).
      //
      // Since the three-step sheet (2026-10-01) this lays out the hub's own
      // form, `embedded: true`, which is what the 350pt above is: the hub
      // writes the heading, and the form draws the step bar and the footer
      // around its page. And it measures against that page's scroll
      // viewport rather than the whole form, because the step bar sits
      // between the two now: a title scrolled up under the step bar was
      // still "inside the sheet". (The standalone sheet, a room's, opens at
      // the full height above the keyboard, not at 350pt, and would also
      // put its own heading above the step bar here.)
      const sheetHeight = 350.0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
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
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: sheetHeight,
                  width: 402,
                  child: AddHabitSheet(embedded: true),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'المشي');
      await tester.pumpAndSettle();

      // The page's own scroll viewport: what is left between the step bar
      // and the footer.
      final page = tester.getRect(find
          .ancestor(of: cardTitle(ar), matching: find.byType(Scrollable))
          .first);
      final card = tester.getRect(cardTitle(ar));

      expect(card.top, greaterThanOrEqualTo(page.top),
          reason: 'not scrolled off the top either');
      expect(card.bottom, lessThanOrEqualTo(page.bottom),
          reason: 'the title has to be inside the space the keyboard leaves');
      // And the control that the whole report is about.
      final knob = tester.getRect(switchFinder());
      expect(knob.top, greaterThanOrEqualTo(page.top));
      expect(knob.bottom, lessThanOrEqualTo(page.bottom),
          reason: 'a switch below the fold is a switch nobody turns on');
    });

    testWidgets('[en] the same, in English', (tester) async {
      await tester.pumpWidget(app(const Locale('en')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'walk every day');
      await tester.pumpAndSettle();

      expect(cardTitle(en), findsOneWidget);
      final top = tester.getTopLeft(cardTitle(en)).dy;
      expect(top,
          greaterThan(tester
              .getBottomLeft(categoryLine(HabitCategory.health, en))
              .dy));
      expect(top,
          lessThan(
              tester.getTopLeft(find.text(en.ideasEntryTitleNoPlans)).dy));
    });
  });

  group('what the offer is set to', () {
    testWidgets('the switch comes up on, and says the prompt is coming',
        (tester) async {
      await tester.pumpWidget(app(const Locale('ar')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'امشي كل يوم');
      await tester.pumpAndSettle();

      expect(switchFinder(), findsOneWidget,
          reason: 'the steps switch is the only one on this step');
      expect(switchIsOn(tester), isTrue,
          reason: 'off by default is what lost the link for anybody who did '
              'not scroll');
      expect(find.text(ar.stepLinkAskNext(false)), findsOneWidget,
          reason: 'an on switch has to say that the OS will ask, or the '
              'permission sheet arrives out of nowhere');
    });

    testWidgets('a switch turned off stays off while the name keeps changing',
        (tester) async {
      await tester.pumpWidget(app(const Locale('ar')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'مشي');
      await tester.pumpAndSettle();
      expect(switchIsOn(tester), isTrue);

      await tester.tap(switchFinder());
      await tester.pumpAndSettle();
      expect(switchIsOn(tester), isFalse);

      await tester.enterText(find.byType(TextField).first, 'مشي الصبح');
      await tester.pumpAndSettle();

      expect(cardTitle(ar), findsOneWidget,
          reason: 'the card stays, so the decision can be reversed');
      expect(switchIsOn(tester), isFalse,
          reason: 'an answer given by hand outranks one read off the name');
    });

    testWidgets('a name that stops being about walking takes the offer with it',
        (tester) async {
      await tester.pumpWidget(app(const Locale('ar')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'walking');
      await tester.pumpAndSettle();
      expect(cardTitle(ar), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'قراءة قرآن');
      await tester.pumpAndSettle();

      expect(cardTitle(ar), findsNothing,
          reason: 'a half-typed "walk" on the way to something else must not '
              'leave a live link behind');
    });

    testWidgets('switching to a quit habit turns the link off, not just away',
        (tester) async {
      await tester.pumpWidget(app(const Locale('ar')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'المشي');
      await tester.pumpAndSettle();
      expect(switchIsOn(tester), isTrue);

      // The Build / Quit switch sits above the box (2026-09-08), so it is
      // always on screen and can simply be tapped.
      await tester.tap(find.text(ar.goalTypeQuitOption));
      await tester.pumpAndSettle();
      expect(cardTitle(ar), findsNothing,
          reason: 'the card is for habits being built');

      await tester.tap(find.text(ar.goalTypeBuildOption));
      await tester.pumpAndSettle();

      expect(cardTitle(ar), findsOneWidget);
      expect(switchIsOn(tester), isFalse,
          reason: 'the answer left with the card. A switch still on behind a '
              'hidden card is a link _submit would silently skip, and on an '
              'edited habit it wrote clearStepGoal: true');
    });
  });

  group('the category a walking name lands in', () {
    // Reported the same day: "link the walk to the health category even if
    // custom text, it should be smart system." The keyword list only ever
    // matched whole words, so "walking" reached Health and "المشي" (definite
    // article), "walkk" and "10k steps" all fell through to Custom - a habit
    // the app was about to offer a step link for, filed as uncategorised.
    for (final name in const [
      'المشي اليومي',
      'امشي شوي كل يوم',
      'walkk every morning',
      'خطواتي',
      '10k steps',
      'jogging',
    ]) {
      testWidgets('"$name" is a Health habit', (tester) async {
        await tester.pumpWidget(app(const Locale('ar')));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, name);
        await tester.pumpAndSettle();

        expect(categoryLine(HabitCategory.health, ar), findsOneWidget,
            reason: '$name reads as walking, so it belongs under Health');
        expect(categoryLine(HabitCategory.custom, ar), findsNothing);
      });
    }

    testWidgets('a name that is mostly about something else still wins',
        (tester) async {
      // The detector counts as ONE health keyword, it does not override.
      await tester.pumpWidget(app(const Locale('ar')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextField).first, 'قراءة كتاب ودراسة');
      await tester.pumpAndSettle();

      expect(categoryLine(HabitCategory.learning, ar), findsOneWidget);
      expect(categoryLine(HabitCategory.health, ar), findsNothing);
    });

    testWidgets('a category picked by hand is never overruled', (tester) async {
      // Picked by hand over a name that had already read as walking, then
      // typed on. Before the three-step sheet this picked the category
      // before any name, from the grid, and then from the ideas door; the
      // categories only open from «تغيير» now, which comes with a name.
      await tester.pumpWidget(app(const Locale('ar')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'المشي');
      await tester.pumpAndSettle();
      expect(categoryLine(HabitCategory.health, ar), findsOneWidget,
          reason: 'sanity: the name read as walking first');

      await tester.tap(choice(ar.habitCategoryChange));
      await tester.pumpAndSettle();
      await tester.tap(choice(HabitCategory.mind.localizedName(true)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'المشي اليومي');
      await tester.pumpAndSettle();

      expect(categoryLine(HabitCategory.mind, ar), findsOneWidget,
          reason: 'a tap on a category is a decision, and typing is not a '
              'reason to undo it');
      expect(categoryLine(HabitCategory.health, ar), findsNothing);
    });

    testWidgets('nor is one changed with «تغيير» once a name is there',
        (tester) async {
      // Picked after the name: the line's own «تغيير», which opens the
      // categories as a row under it.
      await tester.pumpWidget(app(const Locale('ar')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'قراءة');
      await tester.pumpAndSettle();
      expect(categoryLine(HabitCategory.learning, ar), findsOneWidget);

      await tester.tap(choice(ar.habitCategoryChange));
      await tester.pumpAndSettle();
      await tester.tap(choice(HabitCategory.mind.localizedName(true)));
      await tester.pumpAndSettle();
      expect(categoryLine(HabitCategory.mind, ar), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'المشي اليومي');
      await tester.pumpAndSettle();

      expect(categoryLine(HabitCategory.mind, ar), findsOneWidget,
          reason: 'a walking name is a reason to offer the link, not to '
              'move the habit out of the category somebody chose');
      expect(cardTitle(ar), findsOneWidget,
          reason: 'the offer itself still follows the name');
    });
  });

  group('editing a habit that already exists', () {
    /// The catalog's walking preset, which is the one habit this whole
    /// feature was built for.
    IslamicHabitTemplate walkPreset() =>
        IslamicHabitCatalog.findById('daily_walk')!;

    testWidgets('an unlinked walking habit opens with the offer on',
        (tester) async {
      // It is switched on from the Grid and applied from Plans, neither of
      // which opens this sheet, so it arrives here unlinked having never
      // shown the card once. "Unlinked" here cannot be told apart from
      // "never asked", so it gets the offer a new habit gets.
      final preset = walkPreset();
      expect(preset.stepGoal, isNull, reason: 'no preset ships a live link');

      await tester.pumpWidget(app(const Locale('ar'), existing: preset));
      await tester.pumpAndSettle();
      // The overview already says the link is on, in one line, before
      // anything is opened.
      expect(find.text(ar.stepLinkRecap(preset.suggestedStepGoal!)),
          findsOneWidget);
      await openEditStep(tester, ar, 0);

      expect(cardTitle(ar), findsOneWidget);
      expect(switchIsOn(tester), isTrue);
      expect(find.text(ar.stepLinkGoal(preset.suggestedStepGoal!)),
          findsOneWidget,
          reason: 'and it opens on the goal the preset itself suggests, not '
              'the generic default');
    });

    testWidgets('a habit that is already linked opens on its own goal',
        (tester) async {
      final linked = IslamicHabitTemplate(
        id: 'custom-walk',
        name: 'Walk',
        nameAr: 'مشي',
        description: '',
        category: HabitCategory.health,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        hasTimer: false,
        xpReward: 10,
        goldReward: 5,
        stepGoal: 7500,
      );

      await tester.pumpWidget(app(const Locale('ar'), existing: linked));
      await tester.pumpAndSettle();
      await openEditStep(tester, ar, 0);

      expect(switchIsOn(tester), isTrue);
      expect(find.text(ar.stepLinkGoal(7500)), findsOneWidget);
    });

    testWidgets('the armed card fits an iPhone-sized sheet', (tester) async {
      // The card grew: an icon disc, a permission line and the goal chips
      // are all in the tree at once now, and it moved ABOVE the category
      // grid rather than below it. Step 0 is the step that got taller. The
      // edit's Remove button, the extra ~48pt that tipped this sheet over
      // once before (see edit_preset_habit_test's own overflow group), sits
      // under the overview's footer since 2026-10-01, so the overview is
      // laid out at this size first and then step 0 is opened from it. The
      // default 800x600 test surface is too generous to catch any of it.
      //
      // A RenderFlex overflow raises a FlutterError that the binding records
      // as a test exception, so laying this out IS the assertion.
      const dpr = 3.0;
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
      view.physicalSize = const Size(402 * dpr, 874 * dpr);
      view.devicePixelRatio = dpr;
      addTearDown(() {
        view.resetPhysicalSize();
        view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(app(const Locale('ar'), existing: walkPreset()));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(ar.removeHabit), findsOneWidget);
      await openEditStep(tester, ar, 0);

      expect(cardTitle(ar), findsOneWidget);
      expect(switchIsOn(tester), isTrue);
      // And the goal chips under it, which are the tallest part.
      expect(find.text('10000'), findsOneWidget);
    });

    testWidgets('a habit with nothing to do with walking is offered nothing',
        (tester) async {
      final other = IslamicHabitCatalog.templates
          .firstWhere((t) => !t.id.contains('walk') && t.stepGoal == null);

      await tester.pumpWidget(app(const Locale('ar'), existing: other));
      await tester.pumpAndSettle();
      await openEditStep(tester, ar, 0);

      expect(cardTitle(ar), findsNothing);
      expect(switchFinder(), findsNothing);
    });
  });
}
