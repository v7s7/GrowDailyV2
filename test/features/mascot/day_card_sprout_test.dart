// The Grid day card's sprout: what it says and when it moves. See
// day_card_sprout.dart for the rules these pin.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/l10n/wording_edits.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/mascot/day_card_sprout.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';
import 'package:grow_daily_v2/features/mascot/sprout_praise.dart';
import 'package:grow_daily_v2/features/mascot/sprout_signals.dart';

void main() {
  final ar = S(const Locale('ar'));

  IslamicHabitTemplate habit(String id, HabitCategory category) =>
      IslamicHabitTemplate(
        id: id,
        name: id,
        description: '',
        category: category,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        scheduledWeekdays: const [],
        hasTimer: false,
        xpReward: 10,
        goldReward: 5,
        createdAt: DateTime(2026, 9),
      );

  late ProviderContainer container;
  // Who the sprout speaks to comes from the character the account wears,
  // which needs a signed-in app; these tests say it outright. Each gets a
  // picker of its own, so what one test said is not remembered by the next.
  ProviderContainer speakingTo(PraiseForm form) => ProviderContainer(
        overrides: [
          sproutAddressProvider.overrideWithValue(form),
          sproutPraisePickerProvider.overrideWithValue(PraisePicker()),
          allHabitsEverProvider.overrideWithValue([
            habit('fajr', HabitCategory.faith),
            habit('gym', HabitCategory.fitness),
          ]),
        ],
      );
  // The wall clock the cards read, unless a test pins the hour: moved on by a
  // test that needs time to pass (the talking limit).
  var clockAt = DateTime(2026, 9, 27, 10);
  setUp(() {
    PraisePicker.persist = false;
    container = speakingTo(PraiseForm.man);
    DayCardSprout.greetedThisLaunch = true;
    clockAt = DateTime(2026, 9, 27, 10);
  });
  tearDown(() => container.dispose());

  // Built once (on first use, once the binding exists), so a second
  // pumpWidget hands MaterialApp the SAME theme. A fresh GameTheme.dark is
  // never == the last one (its WidgetStateProperty closures differ), so
  // AnimatedTheme lerps between the two; on Doum's
  // colours, the default since 2026-09-30, that lerp rounds a hair off the
  // cream and restarts Material's 200 ms text-style fade, which reads as a
  // running animation to the Reduce Motion check below.
  ThemeData? theme;

  Widget app(
    DayCardSprout sprout, {
    bool reduceMotion = false,
  }) =>
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
          theme: theme ??= GameTheme.dark,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reduceMotion),
              child: Scaffold(
                body: Center(child: SizedBox(height: 300, child: sprout)),
              ),
            ),
          ),
        ),
      );

  DayCardSprout card({
    required int greens,
    int owed = 5,
    double? ratio,
    bool? perfect,
    int? hour,
    Key? key,
  }) =>
      DayCardSprout(
        key: key,
        greens: greens,
        owed: owed,
        ratio: ratio ?? (owed == 0 ? 1 : greens / owed),
        perfectDay: perfect ?? (owed > 0 && greens >= owed),
        height: 90,
        clock: hour == null ? () => clockAt : () => DateTime(2026, 9, 27, hour),
      );

  /// How far the sprout is lifted off its feet right now, 0 at rest: the hop
  /// and the big jump move it up.
  double lift(WidgetTester tester) => tester
      .widgetList<Transform>(
        find.descendant(of: find.byType(Sprout), matching: find.byType(Transform)),
      )
      .map((t) => -t.transform.getTranslation().y)
      .fold(0.0, (a, b) => a > b ? a : b);

  /// The asset the sprout is drawing right now: the incoming child of its
  /// AnimatedSwitcher, i.e. the last Image in the tree.
  String poseShown(WidgetTester tester) {
    final image = tester.widgetList<Image>(find.byType(Image)).last;
    final provider = image.image as ResizeImage;
    return (provider.imageProvider as AssetImage).assetName;
  }

  testWidgets('greets once per app launch, then the bubble goes',
      (tester) async {
    DayCardSprout.greetedThisLaunch = false;
    await tester.pumpWidget(app(card(greens: 0, hour: 8)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(ar.sproutMorning), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(ar.sproutMorning), findsNothing,
        reason: 'the bubble is a moment, not a fixture on the card');

    // A rebuild of the tab (a new widget) does not greet again.
    await tester.pumpWidget(app(card(greens: 0, hour: 8)));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(card(greens: 0, hour: 8)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(ar.sproutMorning), findsNothing);
  });

  testWidgets('the hello waits for today\'s numbers: a slow launch never '
      'greets a 3 of 5 day as if nothing were done', (tester) async {
    DayCardSprout.greetedThisLaunch = false;
    DayCardSprout loading() => DayCardSprout(
          greens: 0,
          owed: 5,
          ratio: 0,
          perfectDay: false,
          live: false,
          height: 90,
          clock: () => DateTime(2026, 9, 27, 8),
        );
    await tester.pumpWidget(app(loading()));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(SproutBubble), findsNothing);

    await tester.pumpWidget(app(card(greens: 3, hour: 8)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(ar.sproutProgress(3, 5)), findsOneWidget);
    expect(find.text(ar.sproutMorning), findsNothing);
  });

  /// The line in the sprout's bubble right now.
  /// While one line replaces another, the AnimatedSwitcher holds both until
  /// the next frame; the incoming one is the last.
  String said(WidgetTester tester) =>
      tester.widgetList<SproutBubble>(find.byType(SproutBubble)).last.text;

  List<String> lines(PraiseGroup group, [PraiseForm form = PraiseForm.man]) =>
      praiseLines(ar, group, form: form);

  testWidgets('a square turning green: a hop and praise (the general lines, '
      'when nothing says which habit it was)', (tester) async {
    await tester.pumpWidget(app(card(greens: 1)));
    // Frame by frame through the entrance and its breaths. pumpAndSettle
    // times out on anything that loops forever, so returning at all is the
    // check that it stands still afterwards: nothing on the home screen
    // moves for no reason.
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(app(card(greens: 2)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue, reason: 'the hop');
    await tester.pump(const Duration(milliseconds: 300));
    expect(lines(PraiseGroup.general), contains(said(tester)));
    expect(poseShown(tester), SproutPose.threeQuarterWave.asset);
  });

  testWidgets('praise fits the habit: a prayer hears faith praise, a workout '
      'sport praise', (tester) async {
    await tester.pumpWidget(app(card(greens: 1)));
    await tester.pump(const Duration(seconds: 1));

    container.read(sproutDoneProvider.notifier).state =
        SproutDone('fajr', DateTime.now());
    await tester.pumpWidget(app(card(greens: 2)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(lines(PraiseGroup.faith), contains(said(tester)));

    await tester.pump(const Duration(seconds: 4));
    clockAt = clockAt.add(kSproutPraiseEvery);
    container.read(sproutDoneProvider.notifier).state =
        SproutDone('gym', DateTime.now());
    await tester.pumpWidget(app(card(greens: 3)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      [...lines(PraiseGroup.sport), ...lines(PraiseGroup.health)],
      contains(said(tester)),
    );
  });

  testWidgets('a woman hears the F lists: «عليج», «فيج»', (tester) async {
    container.dispose();
    container = speakingTo(PraiseForm.woman);
    await tester.pumpWidget(app(card(greens: 1)));
    await tester.pump(const Duration(seconds: 1));
    final seen = <String>[];
    for (var greens = 2; greens <= 4; greens++) {
      await tester.pumpWidget(app(card(greens: greens)));
      await tester.pump(const Duration(milliseconds: 400));
      seen.add(said(tester));
      await tester.pump(const Duration(seconds: 4));
      clockAt = clockAt.add(kSproutPraiseEvery);
    }
    for (final line in seen) {
      expect(lines(PraiseGroup.general, PraiseForm.woman), contains(line));
    }
    expect(seen.toSet(), hasLength(3), reason: 'no line twice');

    await tester.pumpWidget(app(card(greens: 5)));
    await tester.pump(const Duration(milliseconds: 400));
    final perfect = said(tester).split('\n');
    expect(perfect.first, ar.sproutPerfectDay);
    expect(perfect.last, ar.sproutPerfectDayBlessing);
  });

  testWidgets('a reader the app cannot place (the starting character) hears '
      'only lines that fit anyone, and «خلصنا» for the numbers',
      (tester) async {
    container.dispose();
    container = speakingTo(PraiseForm.unknown);
    DayCardSprout.greetedThisLaunch = false;
    await tester.pumpWidget(app(card(greens: 3)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(said(tester), ar.sproutProgressWe(3, 5));
    await tester.pump(const Duration(seconds: 4));

    for (var greens = 4; greens <= 4; greens++) {
      await tester.pumpWidget(app(card(greens: greens)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(lines(PraiseGroup.general, PraiseForm.unknown),
          contains(said(tester)));
    }
  });

  testWidgets('a تخطّي lifts the ring with nothing done: no praise (and so no '
      'hop, the two come together); the next real square is praised',
      (tester) async {
    await tester.pumpWidget(app(card(greens: 3, owed: 5)));
    await tester.pumpAndSettle();
    // 3 of 5 becomes 3 of 4: the ring rises from 60% to 75%.
    await tester.pumpWidget(app(card(greens: 3, owed: 4)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SproutBubble), findsNothing,
        reason: 'praising a skip would be a mistake');

    await tester.pumpWidget(app(card(greens: 4, owed: 4, perfect: false)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(lines(PraiseGroup.general), contains(said(tester)),
        reason: 'a square done is still praised');
  });

  testWidgets('the numbers can never swap places: «خلصت 5 من 10» lays out '
      'right to left in the order it is written', (tester) async {
    final text = ar.sproutProgress(5, 10);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.dark,
      home: Scaffold(body: Center(child: SproutBubble(text: text))),
    ));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
    double leftOf(String token) {
      final at = text.indexOf(token);
      return paragraph
          .getBoxesForSelection(
              TextSelection(baseOffset: at, extentOffset: at + token.length))
          .first
          .left;
    }

    // Read from the right: «خلصت», then 5, then «من», then 10.
    expect(leftOf('خلصت'), greaterThan(leftOf('5')));
    expect(leftOf('5'), greaterThan(leftOf('من')));
    expect(leftOf('من'), greaterThan(leftOf('10')));
  });

  testWidgets('every habit the day asked for done: «يوم مثالي!» and the '
      'happy pose', (tester) async {
    await tester.pumpWidget(app(card(greens: 4)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(app(card(greens: 5)));
    await tester.pump(const Duration(milliseconds: 400));
    final bubble = said(tester).split('\n');
    expect(bubble.first, ar.sproutPerfectDay,
        reason: 'told it is a perfect day');
    expect(bubble.last, ar.sproutPerfectDayBlessing,
        reason: '«ما شاء الله تبارك الله» under it, every time');
    expect(poseShown(tester), SproutPose.happySparkles.asset);
  });

  testWidgets('the streak point (80%) says «سلسلتك زادت!» with the pop-up, '
      'never a full or perfect day, and every habit done on the same tap '
      'says «يوم مثالي!», the bigger line', (tester) async {
    await tester.pumpWidget(app(card(greens: 3)));
    await tester.pump(const Duration(seconds: 1));

    container.read(sproutStreakPointProvider.notifier).state++;
    await tester.pumpWidget(app(card(greens: 4)));
    await tester.pump(const Duration(milliseconds: 400));
    final streak = said(tester).split('\n');
    expect(streak.first, ar.sproutStreakPoint,
        reason: 'one moment, one line: the hop must not overwrite it');
    expect(lines(PraiseGroup.general), contains(streak.last));
    expect(find.textContaining(ar.sproutPerfectDay), findsNothing,
        reason: '80% is a streak pass; a perfect day is every habit');

    await tester.pumpWidget(app(card(greens: 5)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining(ar.sproutPerfectDay), findsOneWidget);
  });

  testWidgets('the talking limit: every square done hops, but praise speaks '
      'at most once per kSproutPraiseEvery, and the perfect day always '
      'speaks', (tester) async {
    final start = clockAt;
    final heard = <String>[];
    DayCardSprout hosted(int greens) => DayCardSprout(
          greens: greens,
          owed: 7,
          ratio: greens / 7,
          perfectDay: greens >= 7,
          height: 90,
          clock: () => clockAt,
          drawsBubble: false,
          onBubble: (line) {
            if (line != null) heard.add(line);
          },
        );
    await tester.pumpWidget(app(hosted(1)));
    await tester.pump(const Duration(seconds: 1));

    // Aziz's example: squares at 0, 4, 8, 16 and 23 seconds.
    Future<void> square(int greens, int second) async {
      clockAt = start.add(Duration(seconds: second));
      await tester.pumpWidget(app(hosted(greens)));
      await tester.pump(const Duration(milliseconds: 360));
      expect(lift(tester), greaterThan(5),
          reason: 'the square at ${second}s gets its hop');
      await tester.pump(const Duration(seconds: 1));
    }

    await square(2, 0);
    expect(heard, hasLength(1), reason: 'the first square speaks');
    await square(3, 4);
    await square(4, 8);
    await square(5, 16);
    expect(heard, hasLength(1), reason: 'inside 20 seconds: the hop alone');
    await square(6, 23);
    expect(heard, hasLength(2), reason: 'past 20 seconds it speaks again');
    expect(lines(PraiseGroup.general), containsAll(heard));

    // Two seconds later every habit is done: the big moment ignores the
    // limit.
    clockAt = start.add(const Duration(seconds: 25));
    await tester.pumpWidget(app(hosted(7)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(heard, hasLength(3));
    expect(heard.last,
        '${ar.sproutPerfectDay}\n${ar.sproutPerfectDayBlessing}');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('the admin\'s «دوم» page sets how often Doum talks and how '
      'long a bubble stays, and a save lands without a restart',
      (tester) async {
    addTearDown(() => WordingEditsStore.debugPublish(WordingEdits.empty));
    WordingEditsStore.debugPublish(const WordingEdits(
      pet: PetEdits(numbers: {'praiseEverySeconds': 5, 'bubbleSeconds': 6}),
    ));
    final start = clockAt;
    final events = <String?>[];
    DayCardSprout hosted(int greens) => DayCardSprout(
          greens: greens,
          owed: 7,
          ratio: greens / 7,
          perfectDay: false,
          height: 90,
          clock: () => clockAt,
          drawsBubble: false,
          onBubble: events.add,
        );
    await tester.pumpWidget(app(hosted(1)));
    await tester.pump(const Duration(seconds: 1));

    await tester.pumpWidget(app(hosted(2)));
    await tester.pump(const Duration(seconds: 5));
    expect(events, hasLength(1), reason: 'still up after 5 seconds');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(events.last, isNull, reason: 'gone after the edited 6');

    // 6 seconds after the first line: past the edited limit of 5.
    clockAt = start.add(const Duration(seconds: 6));
    await tester.pumpWidget(app(hosted(3)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(events.whereType<String>(), hasLength(2));
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('a «جزئي» that crosses the streak point is praised first, and '
      'the celebration keeps that same praise under «سلسلتك زادت»: the '
      'sprout never seems to change its mind', (tester) async {
    await tester.pumpWidget(app(card(greens: 3, ratio: 0.6)));
    await tester.pump(const Duration(seconds: 1));

    // Half a square more: painted, and praised, before the streak is counted.
    await tester.pumpWidget(app(card(greens: 3, ratio: 0.7)));
    await tester.pump(const Duration(milliseconds: 300));
    final praise = said(tester);
    expect(lines(PraiseGroup.general), contains(praise));

    // The same moment on the widget's clock (it has not moved).
    container.read(sproutStreakPointProvider.notifier).state++;
    await tester.pump(const Duration(milliseconds: 300));
    expect(said(tester), '${ar.sproutStreakPoint}\n$praise');

    // A streak point with no praise just before it says one of its own.
    await tester.pump(const Duration(seconds: 4));
    clockAt = clockAt.add(kSproutPraiseEvery);
    container.read(sproutStreakPointProvider.notifier).state++;
    await tester.pump(const Duration(milliseconds: 300));
    final again = said(tester).split('\n');
    expect(again.first, ar.sproutStreakPoint);
    expect(again.last, isNot(praise), reason: 'no line twice');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('the hello and a laugh do not count against the talking limit: '
      'the first square after them is still praised', (tester) async {
    DayCardSprout.greetedThisLaunch = false;
    await tester.pumpWidget(app(card(greens: 1)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(said(tester), ar.sproutFirstDone);

    await tester.tap(find.byType(Sprout));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tickleLines(ar), contains(said(tester)));
    await tester.pump(const Duration(seconds: 2));

    await tester.pumpWidget(app(card(greens: 2)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(lines(PraiseGroup.general), contains(said(tester)));
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a host that draws the bubble itself: no bubble here, and '
      'onBubble told the words, then null when they go', (tester) async {
    final heard = <String?>[];
    DayCardSprout hosted(int greens) => DayCardSprout(
          greens: greens,
          owed: 5,
          ratio: greens / 5,
          perfectDay: false,
          height: 90,
          clock: () => DateTime(2026, 9, 27, 10),
          drawsBubble: false,
          onBubble: heard.add,
        );
    await tester.pumpWidget(app(hosted(1)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(app(hosted(2)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SproutBubble), findsNothing);
    expect(heard, hasLength(1));
    expect(lines(PraiseGroup.general), contains(heard.single));
    await tester.pump(const Duration(seconds: 3));
    expect(heard, [heard.first, null]);
  });

  testWidgets('the bubble\'s tail can sit at either bottom corner',
      (tester) async {
    BorderRadiusDirectional cornersOf(bool tailAtStart) {
      final box = tester.widget<DecoratedBox>(find.descendant(
        of: find.byType(SproutBubble),
        matching: find.byType(DecoratedBox),
      ));
      return (box.decoration as BoxDecoration).borderRadius!
          as BorderRadiusDirectional;
    }

    for (final tailAtStart in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        theme: GameTheme.dark,
        home: Scaffold(
          body: Center(
            child: SproutBubble(text: 'x', tailAtStart: tailAtStart),
          ),
        ),
      ));
      final r = cornersOf(tailAtStart);
      expect(r.bottomStart.x, tailAtStart ? 4 : 14);
      expect(r.bottomEnd.x, tailAtStart ? 14 : 4);
    }
  });

  testWidgets('tapped: it laughs, then goes back to its mood', (tester) async {
    await tester.pumpWidget(app(card(greens: 2)));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byType(Sprout));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tickleLines(ar), contains(said(tester)));
    expect(poseShown(tester), SproutPose.laugh.asset);

    await tester.pump(const Duration(milliseconds: 1600));
    expect(poseShown(tester), SproutPose.threeQuarterWave.asset);
  });

  testWidgets('numbers that are not live (the week loading at launch, or '
      'another week on screen) never make it react', (tester) async {
    DayCardSprout still(int greens, {required bool live}) => DayCardSprout(
          greens: greens,
          owed: 5,
          ratio: greens / 5,
          perfectDay: greens >= 5,
          live: live,
          height: 90,
          clock: () => DateTime(2026, 9, 27, 10),
        );
    await tester.pumpWidget(app(still(0, live: false)));
    await tester.pumpAndSettle();

    // The load lands: 0 becomes 5 of 5 in one rebuild. Not a celebration.
    await tester.pumpWidget(app(still(5, live: true)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SproutBubble), findsNothing,
        reason: 'no line at all: nothing was done');
    await tester.pumpAndSettle();
    expect(poseShown(tester), SproutPose.happySparkles.asset,
        reason: 'the pose still follows the day');
  });

  testWidgets('a day finished while the card was out of sight (a long '
      'return\'s launch curtain) says «يوم مثالي!» once it is back, and '
      'the week landing at launch still never does', (tester) async {
    DayCardSprout still(int greens, {required bool live}) => DayCardSprout(
          greens: greens,
          owed: 5,
          ratio: greens / 5,
          perfectDay: greens >= 5,
          live: live,
          height: 90,
          clock: () => DateTime(2026, 9, 27, 10),
        );
    await tester.pumpWidget(app(still(4, live: true)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(still(4, live: false)));
    await tester.pumpWidget(app(still(5, live: false)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining(ar.sproutPerfectDay), findsNothing,
        reason: 'nothing said behind the curtain');
    await tester.pumpWidget(app(still(5, live: true)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining(ar.sproutPerfectDay), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('a finished day at night: asleep', (tester) async {
    await tester.pumpWidget(app(card(greens: 5, hour: 22)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(poseShown(tester), SproutPose.sleeping.asset);
  });

  testWidgets('Reduce Motion: no movement at all, only the pose and words',
      (tester) async {
    await tester.pumpWidget(app(card(greens: 1), reduceMotion: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse,
        reason: 'no entrance pop and no breaths');

    await tester.pumpWidget(app(card(greens: 2), reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 16));
    // The bubble still cross-fades in; no hop runs under it.
    await tester.pump(const Duration(milliseconds: 400));
    expect(lines(PraiseGroup.general), contains(said(tester)));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
