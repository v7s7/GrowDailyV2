// The Grid day card's sprout: what it says and when it moves. See
// day_card_sprout.dart for the rules these pin.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/mascot/day_card_sprout.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';
import 'package:grow_daily_v2/features/mascot/sprout_signals.dart';

void main() {
  final ar = S(const Locale('ar'));

  late ProviderContainer container;
  setUp(() {
    container = ProviderContainer();
    DayCardSprout.greetedThisLaunch = true;
  });
  tearDown(() => container.dispose());

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
          theme: GameTheme.dark,
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
    bool? perfect,
    int hour = 10,
  }) =>
      DayCardSprout(
        greens: greens,
        owed: owed,
        ratio: owed == 0 ? 1 : greens / owed,
        perfectDay: perfect ?? (owed > 0 && greens >= owed),
        height: 90,
        clock: () => DateTime(2026, 9, 27, hour),
      );

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

  testWidgets('a square turning green: a hop and where the day stands',
      (tester) async {
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
    expect(find.text(ar.sproutProgress(2, 5)), findsOneWidget);
    expect(poseShown(tester), SproutPose.threeQuarterWave.asset);
  });

  testWidgets('every square green: «يوم مثالي!» and the happy pose',
      (tester) async {
    await tester.pumpWidget(app(card(greens: 4)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(app(card(greens: 5)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(ar.sproutPerfectDay), findsOneWidget);
    expect(poseShown(tester), SproutPose.happySparkles.asset);
  });

  testWidgets('the streak point (80%) says «يوم كامل!» with the pop-up, and '
      'a perfect day on the same tap says the bigger line', (tester) async {
    await tester.pumpWidget(app(card(greens: 3)));
    await tester.pump(const Duration(seconds: 1));

    container.read(sproutStreakPointProvider.notifier).state++;
    await tester.pumpWidget(app(card(greens: 4)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(ar.sproutFullDay), findsOneWidget);
    expect(find.text(ar.sproutProgress(4, 5)), findsNothing,
        reason: 'one moment, one line: the hop line must not overwrite it');

    await tester.pumpWidget(app(card(greens: 5)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(ar.sproutPerfectDay), findsOneWidget);
  });

  testWidgets('tapped: it laughs, then goes back to its mood', (tester) async {
    await tester.pumpWidget(app(card(greens: 2)));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byType(Sprout));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(ar.sproutTickle), findsOneWidget);
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
    expect(find.text(ar.sproutProgress(2, 5)), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
