// The ideas page (habit_ideas_page.dart, the "Habit ideas page" canvas Aziz
// approved on 2026-10-01: "that is perfect") and the card on Add Habit's
// first step that opens it.
//
// The card replaced an inline ideas door «تبي أفكار أو خطة جاهزة؟» that
// opened under the name box with a Plans card, a category row, a hint and
// suggestion chips (Aziz: "I don't like the design"). It is one card with
// Doum holding his idea: «أفكار وخطط جاهزة» inside the Add Habit hub for a
// habit to build, since that is where the Plans tab lives, and «أفكار
// لعاداتك» anywhere else and for a habit to quit (a plan is a set of habits
// to build).
//
// The page has two sections, each saying what it is, so a whole plan is
// never mistaken for one habit: «خطط جاهزة», wide cards (only in the hub,
// only on the build side, and not while searching), then «عادات بمفردها»
// with a filter that opens on «مختارة لك», then «الكل» and one pill per
// category. A search box replaces the filter and the plans while it has
// words in it. Every idea card has a «+» that adds the idea as suggested,
// and the card itself opens the idea in full: the hadith with its source,
// the easy ways to start, what is suggested, and «أضفها لعاداتي» or
// «عدّلها قبل الإضافة», which fills the form and stops on «كم مرة» with the
// idea's answer lit and a note saying it is a suggestion. A plan picked on
// the page opens on the hub's Plans tab, expanded.
//
// Only the faith ideas are named here (more categories are being written),
// and their words are read from the same file the page reads, so a rewrite
// of an idea's text does not break these. So is which ideas are featured,
// which the admin can change: an idea is brought on screen through its
// category's pill when it is not under «مختارة لك».
//
// The harness is reminder_step_test's, because these save: the Hive boxes
// are in memory (a file-backed write inside a testWidgets body never
// finishes), Premium so the habit cap never answers first, a Manama
// location so an Isha reminder never goes off looking for one, the
// notifications channel mocked to refuse, and the view tall enough that the
// page's first cards are all on screen. The ideas file is read once in
// setUpAll (see preloadIdeas for why).
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show AndroidFlutterLocalNotificationsPlugin;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_ideas.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cue.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_hub_sheet.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';
import 'package:grow_daily_v2/features/habits/widgets/habit_ideas_page.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:grow_daily_v2/features/settings/notifiers/notification_settings_notifier.dart';

import 'support/add_habit_flow.dart';

const _manama = NotificationLocation(
  lat: 26.2285,
  lng: 50.5860,
  label: 'Manama, Bahrain',
);

void main() {
  late Directory tmp;
  late ProviderContainer container;

  /// Every built-in idea, read from the file the page reads.
  final ideas = parseHabitIdeas(File(kHabitIdeasAsset).readAsStringSync());
  HabitIdea idea(String id) => ideas.firstWhere((i) => i.id == id);

  /// The faith ideas these lean on.
  final charity = idea('daily_charity');
  final mulk = idea('mulk_before_sleep');
  final fasting = idea('fast_mon_thu');
  final onTime = idea('pray_on_time');

  /// Which ideas are featured is read from the file too: it is the admin's
  /// to change. The first featured idea to build, the first faith one that
  /// is not, and the first idea to build in another category, if any.
  final featured =
      ideas.firstWhere((i) => i.type == GoalType.build && i.featured);
  final unfeatured = ideas.firstWhere((i) =>
      i.type == GoalType.build &&
      i.category == HabitCategory.faith &&
      !i.featured);
  final elsewhere = ideas
      .where((i) =>
          i.type == GoalType.build && i.category != HabitCategory.faith)
      .firstOrNull;

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
    tmp = await Directory.systemTemp.createTemp('habit_ideas_page_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings', bytes: Uint8List(0));
    await Hive.openBox<dynamic>('box_daily_logs', bytes: Uint8List(0));
    await Hive.openBox<dynamic>('box_habits', bytes: Uint8List(0));
    // 430 wide, as reminder_step_test, for the English rows on step 3; and
    // tall, so the page's first cards are all on screen.
    const dpr = 3.0;
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(430 * dpr, 2400 * dpr);
    view.devicePixelRatio = dpr;

    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumAccessProvider.overrideWithValue(true),
      ],
    );
    await container.read(authStateProvider.future);
    container.read(customHabitsProvider);
    await container
        .read(notificationSettingsProvider.notifier)
        .update((s) => s.copyWith(location: _manama));
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

  /// Add Habit on a pushed route, so a save's Navigator.pop has somewhere
  /// to return to: the sheet on its own, or inside the hub ([hub]), which
  /// is what gives the ideas page its plans.
  Future<void> open(
    WidgetTester tester,
    Locale locale, {
    bool hub = false,
  }) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          locale: locale,
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
          builder: (_) => Scaffold(
            body: hub ? const AddHabitHub() : const AddHabitSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Past what a finished save leaves on screen: the burst, and for a quit
  /// habit or one with a reminder the mocked permission refusal's SnackBar.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  /// The one habit a test saved.
  IslamicHabitTemplate created() =>
      container.read(customHabitsProvider).single;

  Finder page() => find.byType(HabitIdeasPage);

  Finder onPage(Finder finder) =>
      find.descendant(of: page(), matching: finder);

  /// The page's search box (the name box is still behind the page).
  Finder searchBox() => onPage(find.byType(TextField));

  /// An idea's card on the page, by its id. [all] counts cards built off
  /// screen too.
  Finder card(String id, {bool all = false}) =>
      find.byKey(ValueKey<String>(id), skipOffstage: !all);

  /// The ids of every idea card the page has built, on screen or off.
  Set<String> builtCards(WidgetTester tester) => {
        for (final w in tester.widgetList(find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              ideas.any((i) => i.id == (w.key! as ValueKey<String>).value),
          skipOffstage: false,
        )))
          (w.key! as ValueKey<String>).value,
      };

  /// Scrolls the page down until [finder] is on screen.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: onPage(find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
  }

  /// Whether the control labelled [label] says it is the picked one, in
  /// its Semantics: the filter pills, and step 3's two cards.
  bool picked(WidgetTester tester, Finder label) =>
      tester
          .widget<Semantics>(
            find
                .ancestor(
                  of: label,
                  matching: find.byWidgetPredicate(
                    (w) => w is Semantics && (w.properties.button ?? false),
                  ),
                )
                .first,
          )
          .properties
          .selected ??
      false;

  /// A filter pill on the page, by its label.
  Finder pill(String label) => onPage(find.text(label));

  /// Taps a filter pill, scrolling the page back up to it first (scrolled
  /// far enough down, the list lets go of the filter row).
  Future<void> tapPill(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      pill(label),
      -300,
      scrollable: onPage(find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(pill(label));
    await tester.pumpAndSettle();
  }

  /// The weight a choice's label is drawn in: w800 lit, w600 not. The
  /// step-2 row and the day pills carry their state that way.
  FontWeight? weight(WidgetTester tester, String label) => tester
      .widget<Text>(
          find.descendant(of: choice(label), matching: find.byType(Text)))
      .style
      ?.fontWeight;

  String prayerLabel(String key, S s) =>
      HabitCue.preset(key).labelForLocale(s.isAr);

  /// Brings [idea]'s card on screen: where it already is under «الكل»,
  /// else through its category's pill.
  Future<void> reveal(WidgetTester tester, S s, HabitIdea idea) async {
    if (card(idea.id).evaluate().isNotEmpty) return;
    await tapPill(tester, idea.category.localizedName(s.isAr));
    await scrollTo(tester, card(idea.id));
  }

  /// Opens [idea] in full from its card on the page.
  Future<void> openDetail(WidgetTester tester, S s, HabitIdea idea) async {
    await reveal(tester, s, idea);
    await tester.tap(onPage(find.text(idea.name(s.isAr))));
    await tester.pumpAndSettle();
  }

  // ── The card on step 1 ─────────────────────────────────────────────────

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    /// The card with Doum holding his idea, under the given title.
    void expectCard(WidgetTester tester, {required bool withPlans}) {
      expect(find.text(withPlans ? s.ideasEntryTitle : s.ideasEntryTitleNoPlans),
          findsOneWidget);
      expect(find.text(withPlans ? s.ideasEntryBody : s.ideasEntryBodyNoPlans),
          findsOneWidget);
      expect(find.text(withPlans ? s.ideasEntryTitleNoPlans : s.ideasEntryTitle),
          findsNothing);
      final doum = find.descendant(
        of: ideasCard(s, withPlans: withPlans),
        matching: find.byType(Sprout),
      );
      expect(doum, findsOneWidget, reason: 'Doum is on the card');
      expect(tester.widget<Sprout>(doum).pose, SproutPose.idea);
    }

    testWidgets('[$tag] standalone, the card is «${s.ideasEntryTitleNoPlans}» '
        'for a habit to build or to quit', (tester) async {
      await open(tester, locale);
      expectCard(tester, withPlans: false);

      await tester.tap(find.text(s.goalTypeQuitOption));
      await tester.pumpAndSettle();
      expectCard(tester, withPlans: false);
    });

    testWidgets('[$tag] in the hub, «${s.ideasEntryTitle}» for a habit to '
        'build, «${s.ideasEntryTitleNoPlans}» for one to quit', (tester) async {
      await open(tester, locale, hub: true);
      expectCard(tester, withPlans: true);

      await tester.tap(find.text(s.goalTypeQuitOption));
      await tester.pumpAndSettle();
      expectCard(tester, withPlans: false);

      await tester.tap(find.text(s.goalTypeBuildOption));
      await tester.pumpAndSettle();
      expectCard(tester, withPlans: true);
    });

    // ── The page's sections ──────────────────────────────────────────────

    testWidgets('[$tag] in the hub, building: the plans first, then the '
        'single habits, and no plans while searching', (tester) async {
      await open(tester, locale, hub: true);
      await openIdeas(tester, s, withPlans: true);

      expect(page(), findsOneWidget);
      expect(onPage(find.text(s.ideasPageTitle)), findsOneWidget);
      expect(onPage(find.text(s.ideasPageIntro)), findsOneWidget);
      expect(tester.widget<TextField>(searchBox()).decoration?.hintText,
          s.ideasSearchHint);

      expect(onPage(find.text(s.ideasPlansTitle)), findsOneWidget);
      expect(onPage(find.text(s.ideasPlansNote)), findsOneWidget,
          reason: 'the section says a plan is a set of habits');
      final plan = shownPlans().first;
      expect(onPage(find.text(plan.name(s.isAr))), findsOneWidget);
      expect(onPage(find.text(plan.desc(s.isAr))), findsOneWidget);
      expect(
          onPage(find.text(s.ideasPlanHabitCount(plan.plan.habits.length))),
          findsWidgets,
          reason: 'each plan says how many habits it holds');
      expect(onPage(find.text(s.ideasHabitsTitle)), findsOneWidget);
      expect(onPage(find.text(s.ideasHabitsNote)), findsOneWidget);
      expect(
        tester.getTopLeft(onPage(find.text(s.ideasPlansTitle))).dy,
        lessThan(tester.getTopLeft(onPage(find.text(s.ideasHabitsTitle))).dy),
        reason: 'plans first, then the single habits',
      );

      await tester.enterText(searchBox(), charity.name(s.isAr));
      await tester.pumpAndSettle();
      expect(onPage(find.text(s.ideasPlansTitle)), findsNothing,
          reason: 'a search is for one habit, so the plans step aside');
      expect(onPage(find.text(plan.name(s.isAr))), findsNothing);
      expect(onPage(find.text(s.ideasHabitsTitle)), findsOneWidget);
    });

    testWidgets('[$tag] standalone, building: no plans', (tester) async {
      await open(tester, locale);
      await openIdeas(tester, s);

      expect(tester.widget<HabitIdeasPage>(page()).withPlans, isFalse);
      expect(onPage(find.text(s.ideasPlansTitle)), findsNothing,
          reason: 'Plans are a hub tab; standalone there is none to open');
      expect(onPage(find.text(shownPlans().first.name(s.isAr))), findsNothing);
      expect(onPage(find.text(s.ideasHabitsTitle)), findsOneWidget);
    });

    testWidgets('[$tag] in the hub, quitting: no plans, ideas to quit, and the '
        'popup adds one as a quit habit', (tester) async {
      await open(tester, locale, hub: true);
      await tester.tap(find.text(s.goalTypeQuitOption));
      await tester.pumpAndSettle();
      await openIdeas(tester, s);

      expect(onPage(find.text(s.ideasPageTitleQuit)), findsOneWidget);
      expect(onPage(find.text(s.ideasPlansTitle)), findsNothing,
          reason: 'a plan is a set of habits to build');
      expect(onPage(find.text(s.ideasHabitsTitleQuit)), findsOneWidget);
      expect(tester.widget<Sprout>(onPage(find.byType(Sprout))).pose,
          SproutPose.determined);
      for (final id in builtCards(tester)) {
        expect(idea(id).type, GoalType.quit,
            reason: '$id: only ideas to quit or cut down on this side');
      }
      expect(card(charity.id, all: true), findsNothing);
      await reveal(tester, s, onTime);
      expect(card(onTime.id), findsOneWidget);
      expect(
        find.descendant(
            of: card(onTime.id), matching: find.text(s.ideasQuitFully)),
        findsOneWidget,
        reason: 'a quit card says the style it suggests',
      );
      expect(
        find.descendant(
            of: card(onTime.id),
            matching: find.textContaining(s.ideasWhy)),
        findsOneWidget,
        reason: 'and why, in so many words',
      );

      await tester.tap(onPage(find.text(onTime.name(s.isAr))));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.ideasAddNow));
      await tester.pumpAndSettle();
      await settle(tester);

      final habit = created();
      expect(habit.name, onTime.name(s.isAr));
      expect(habit.goalType, GoalType.quit);
      expect(habit.reductionType, ReductionType.avoid,
          reason: 'the idea is to quit it fully');
      expect(habit.category, HabitCategory.faith);
      expect(habit.frequencyType, HabitFrequencyType.daily);
    });

    // ── The filter and the search ────────────────────────────────────────

    // «مختارة لك» was the admin's fixed star under a pill of its own, the
    // same for everyone, and Aziz had it taken off (2026-10-01: "if its not
    // smart enough lets remove it"). The star now puts an idea first.
    testWidgets('[$tag] the filter opens on «${s.ideasFilterAll}», starred '
        'ideas first, and a category narrows it', (tester) async {
      await open(tester, locale);
      await openIdeas(tester, s);

      expect(pill(s.isAr ? 'مختارة لك' : 'Picked for you'), findsNothing);
      expect(picked(tester, pill(s.ideasFilterAll)), isTrue,
          reason: 'every idea to build, from the start');
      final faith = HabitCategory.faith.localizedName(s.isAr);
      expect(pill(faith), findsOneWidget, reason: 'a pill per category');
      expect(card(featured.id), findsOneWidget,
          reason: 'a starred idea leads the list, on screen at once');
      for (final id in builtCards(tester)) {
        expect(idea(id).type, GoalType.build, reason: id);
      }
      expect(
        tester.getTopLeft(card(featured.id)).dy,
        lessThan(tester.getTopLeft(card(unfeatured.id, all: true)).dy),
        reason: 'starred before the rest',
      );

      await tapPill(tester, faith);
      expect(picked(tester, pill(faith)), isTrue);
      expect(picked(tester, pill(s.ideasFilterAll)), isFalse);
      for (final id in builtCards(tester)) {
        expect(idea(id).category, HabitCategory.faith,
            reason: '$id: one category at a time');
      }
      expect(card(charity.id, all: true), findsOneWidget);
      expect(card(unfeatured.id, all: true), findsOneWidget,
          reason: 'starred or not, every faith idea');
      if (elsewhere != null) {
        expect(card(elsewhere.id, all: true), findsNothing,
            reason: '${elsewhere.id} is in another category');
      }
    });

    testWidgets('[$tag] the search finds an idea by its name, hides the '
        'filter, and says when nothing matches', (tester) async {
      await open(tester, locale, hub: true);
      await openIdeas(tester, s, withPlans: true);

      // A word of the name, the way somebody types it.
      final word = s.isAr ? 'صدقة' : 'charity';
      expect(charity.name(s.isAr).toLowerCase(), contains(word));
      await tester.enterText(searchBox(), word);
      await tester.pumpAndSettle();

      expect(card(charity.id), findsOneWidget);
      expect(card(mulk.id, all: true), findsNothing);
      for (final id in builtCards(tester)) {
        final i = idea(id);
        expect(
          [i.nameAr, i.nameEn, i.shortAr, i.shortEn]
              .any((t) => t.toLowerCase().contains(word)),
          isTrue,
          reason: '$id matches «$word»',
        );
      }
      expect(pill(s.ideasFilterAll), findsNothing,
          reason: 'the filter steps aside while searching');
      expect(onPage(find.text(s.ideasPlansTitle)), findsNothing);

      await tester.enterText(searchBox(), 'zzqqxx');
      await tester.pumpAndSettle();
      expect(onPage(find.text(s.ideasNoResults)), findsOneWidget);
      expect(builtCards(tester), isEmpty);

      // The box's × puts it all back.
      await tester.tap(onPage(find.byTooltip(
          MaterialLocalizations.of(tester.element(page()))
              .deleteButtonTooltip)));
      await tester.pumpAndSettle();
      expect(picked(tester, pill(s.ideasFilterAll)), isTrue);
      expect(onPage(find.text(s.ideasPlansTitle)), findsOneWidget);
      expect(card(featured.id), findsOneWidget);
    });

    // ── Adding an idea ───────────────────────────────────────────────────

    // Aziz, 2026-10-01: "remove the + mark so user click on it, and then he
    // add, and when he add he can see that its added he can click back and
    // choose another one". In the hub the popup adds in place.
    testWidgets('[$tag] in the hub, «${s.ideasAddNow}» adds it there, says '
        'so, and goes back for another', (tester) async {
      await open(tester, locale, hub: true);
      await openIdeas(tester, s, withPlans: true);
      await reveal(tester, s, charity);
      expect(
        find.descendant(
            of: card(charity.id), matching: find.byIcon(Icons.add_rounded)),
        findsNothing,
        reason: 'no «+» on a card: the card opens the idea',
      );

      await openDetail(tester, s, charity);
      await tester.tap(find.text(s.ideasAddNow));
      await tester.pumpAndSettle();

      expect(find.text(s.ideasAddedDone), findsOneWidget,
          reason: 'the popup says it is added');
      expect(find.text(s.ideasAddNow), findsNothing);
      expect(find.text(s.ideasEditFirst), findsNothing,
          reason: 'nothing left to change before adding');
      expect(page(), findsOneWidget, reason: 'the page stays');
      final habit = created();
      expect(habit.name, charity.name(s.isAr));
      expect(habit.category, HabitCategory.faith);
      expect(habit.goalType, GoalType.build);
      expect(habit.frequencyType, HabitFrequencyType.daily);
      expect(habit.frequencyTarget, 1);
      expect(habit.cueAfter ?? '', isEmpty,
          reason: 'the idea suggests no reminder');

      await tester.tap(find.text(s.ideasPickAnother));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
            of: card(charity.id), matching: find.text(s.ideasAddedChip)),
        findsOneWidget,
        reason: 'back on the list the card says «${s.ideasAddedChip}»',
      );

      // Opened again, it says it is already there and adds nothing more.
      await openDetail(tester, s, charity);
      expect(find.text(s.ideasAlreadyHave), findsOneWidget);
      expect(find.text(s.ideasAddNow), findsNothing);
      await tester.tap(find.text(s.ideasPickAnother));
      await tester.pumpAndSettle();
      expect(container.read(customHabitsProvider), hasLength(1));

      // Closing the page with nothing typed closes Add Habit too.
      await closeIdeas(tester);
      await settle(tester);
      expect(page(), findsNothing);
      expect(find.byType(AddHabitHub), findsNothing,
          reason: 'the habits were added; the board is next');
    });

    testWidgets('[$tag] in the hub, «${s.ideasEditFirst}» saves nothing and '
        'goes to the form', (tester) async {
      await open(tester, locale, hub: true);
      await openIdeas(tester, s, withPlans: true);
      await openDetail(tester, s, mulk);
      await tester.tap(find.text(s.ideasEditFirst));
      await tester.pumpAndSettle();

      expect(page(), findsNothing);
      expect(find.text(s.howOftenQuestion), findsOneWidget);
      expect(container.read(customHabitsProvider), isEmpty,
          reason: 'changing it first adds nothing yet');

      await tester.tap(find.text(s.continueAction));
      await tester.pumpAndSettle();
      expect(find.text(s.reminderQuestion), findsOneWidget);
      expect(container.read(customHabitsProvider), isEmpty);
    });

    testWidgets('[$tag] a card is one button, and it opens the idea',
        (tester) async {
      await open(tester, locale);
      await openIdeas(tester, s);

      final data = tester.getSemantics(card(charity.id)).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      final name = charity.name(s.isAr);
      expect(find.bySemanticsLabel(s.isAr ? 'أضف $name' : 'Add $name'),
          findsNothing,
          reason: 'no separate «+» to reach any more');
    });

    testWidgets('[$tag] a card opens the idea in full, and «${s.ideasAddNow}» '
        'adds it', (tester) async {
      await open(tester, locale);
      await openIdeas(tester, s);
      await openDetail(tester, s, charity);

      expect(find.text(charity.benefit(s.isAr)), findsOneWidget,
          reason: 'the hadith behind the idea');
      expect(find.text(charity.source(s.isAr)!), findsOneWidget,
          reason: 'with its source');
      if (s.isAr) expect(charity.source(true), 'متفق عليه');
      expect(find.text(s.ideasEasyWays), findsOneWidget);
      for (final way in charity.ways(s.isAr)) {
        expect(find.text(way), findsOneWidget, reason: 'an easy way to start');
      }
      expect(find.text(s.ideasSuggested), findsOneWidget);
      expect(find.text(s.ideasEditFirst), findsOneWidget);

      await tester.tap(find.text(s.ideasAddNow));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(page(), findsNothing);
      expect(find.byType(AddHabitSheet), findsNothing);
      final habit = created();
      expect(habit.name, charity.name(s.isAr));
      expect(habit.category, HabitCategory.faith);
      expect(habit.frequencyType, HabitFrequencyType.daily);
    });

    testWidgets('[$tag] «${s.ideasEditFirst}» fills the form and stops on '
        '«كم مرة», «${s.oftenEveryDay}» lit, with a note', (tester) async {
      await open(tester, locale);
      await openIdeas(tester, s);
      await openDetail(tester, s, charity);
      await tester.tap(find.text(s.ideasEditFirst));
      await tester.pumpAndSettle();

      expect(page(), findsNothing);
      expect(find.text(s.howOftenQuestion), findsOneWidget,
          reason: 'on the second step, to change what was suggested');
      expect(weight(tester, s.oftenEveryDay), FontWeight.w800,
          reason: 'the idea\'s answer is lit');
      expect(weight(tester, s.oftenTimesAWeek), FontWeight.w600);
      expect(weight(tester, s.oftenSetDays), FontWeight.w600);
      expect(find.text(s.ideasFromIdeaNote), findsOneWidget,
          reason: 'and the step says it is a suggestion');
      expect(container.read(customHabitsProvider), isEmpty,
          reason: 'nothing is saved until the steps are done');
    });
  }

  // ── What an idea carries to the steps ──────────────────────────────────

  testWidgets('«${mulk.nameAr}» carries its Isha reminder to step 3',
      (tester) async {
    const ar = S(Locale('ar'));
    await open(tester, const Locale('ar'));
    await openIdeas(tester, ar);
    await openDetail(tester, ar, mulk);
    expect(find.text(ar.ideasWithPrayer(prayerLabel('isha', ar))),
        findsOneWidget,
        reason: 'the idea says the reminder it suggests');
    await tester.tap(find.text(ar.ideasEditFirst));
    await tester.pumpAndSettle();

    expect(weight(tester, ar.oftenEveryDay), FontWeight.w800);
    await tester.tap(find.text(ar.continueAction));
    await tester.pumpAndSettle();

    expect(find.text(ar.reminderQuestion), findsOneWidget,
        reason: 'sanity: on the third step');
    expect(picked(tester, find.text(ar.reminderWithPrayer)), isTrue,
        reason: 'the idea\'s reminder is with a prayer');
    expect(picked(tester, find.text(ar.reminderAtClock)), isFalse);
    expect(
      tester.widget<Text>(find.text(prayerLabel('isha', ar))).style?.fontWeight,
      FontWeight.w800,
      reason: 'and the prayer is Isha',
    );
    expect(
      tester.widget<Text>(find.text(prayerLabel('fajr', ar))).style?.fontWeight,
      FontWeight.w600,
    );

    await addHabit(tester, ar);
    await settle(tester);
    final habit = created();
    expect(habit.name, mulk.nameAr);
    expect(habit.cueAfter, 'isha', reason: 'saved with the Isha reminder');
  });

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    final s = S(locale);

    testWidgets('[$tag] «${fasting.name(s.isAr)}» comes with Monday and '
        'Thursday set', (tester) async {
      await open(tester, locale);
      await openIdeas(tester, s);
      // Two ways to an idea that is not under «مختارة لك»: in Arabic a word
      // of its name in the search box (not the whole name: find.text would
      // then match the box too), in English its category's pill.
      if (s.isAr) {
        const word = 'صيام';
        expect(fasting.nameAr, contains(word));
        await tester.enterText(searchBox(), word);
        await tester.pumpAndSettle();
      }
      await openDetail(tester, s, fasting);
      await tester.tap(find.text(s.ideasEditFirst));
      await tester.pumpAndSettle();

      expect(weight(tester, s.oftenSetDays), FontWeight.w800,
          reason: 'set days, lit');
      expect(weight(tester, s.oftenEveryDay), FontWeight.w600);
      expect(find.text(s.oftenDaysQuestion), findsOneWidget,
          reason: 'with the days under it');
      // The day pills' own labels: 2024-01-01 was a Monday.
      String day(int weekday) =>
          DateFormat.E(tag).format(DateTime(2024, 1, weekday));
      for (var d = DateTime.monday; d <= DateTime.sunday; d++) {
        final lit = d == DateTime.monday || d == DateTime.thursday;
        expect(weight(tester, day(d)), lit ? FontWeight.w800 : FontWeight.w600,
            reason: '${day(d)} ${lit ? 'is' : 'is not'} one of the days');
      }

      await tester.tap(find.text(s.continueAction));
      await tester.pumpAndSettle();
      await addHabit(tester, s);
      await settle(tester);
      final habit = created();
      expect(habit.frequencyType, HabitFrequencyType.weekly);
      expect(habit.scheduledWeekdays, [DateTime.monday, DateTime.thursday]);
      expect(habit.frequencyTarget, 2);
    });

    // ── A plan, in the hub ───────────────────────────────────────────────

    testWidgets('[$tag] a plan picked on the page opens on the Plans tab, '
        'expanded', (tester) async {
      await open(tester, locale, hub: true);
      await openIdeas(tester, s, withPlans: true);

      // The second plan, so "expanded" cannot be the first one by default.
      final plan = shownPlans()[1];
      final name = onPage(find.text(plan.name(s.isAr)));
      await tester.ensureVisible(name);
      await tester.pumpAndSettle();
      await tester.tap(name);
      await tester.pumpAndSettle();

      expect(page(), findsNothing);
      expect(find.text(s.addGoalTitle), findsOneWidget,
          reason: 'on the Plans tab, with the pills back as the way to the '
              'form');
      expect(find.text(s.plansTab), findsOneWidget);
      expect(find.text(s.planPickHabitsHint), findsOneWidget,
          reason: 'one plan is open');
      final planCard = find
          .ancestor(
            of: find.text(plan.name(s.isAr)),
            matching: find.byType(AnimatedContainer),
          )
          .first;
      expect(
        find.descendant(
            of: planCard, matching: find.text(s.planPickHabitsHint)),
        findsOneWidget,
        reason: 'and it is the plan that was picked',
      );
      for (final h in plan.plan.habits) {
        expect(
          find.descendant(
              of: planCard, matching: find.text(h.localName(s.isAr))),
          findsOneWidget,
          reason: 'its habits are listed, ready to start',
        );
      }
    });
  }
}
