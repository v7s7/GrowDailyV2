// The sprout on the board's edge (SproutLedge): it stands on the line,
// slides along it, and hides behind it after a question. See
// sprout_ledge.dart for the rules these pin.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/mascot/day_card_sprout.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';
import 'package:grow_daily_v2/features/mascot/sprout_ledge.dart';
import 'package:grow_daily_v2/features/mascot/sprout_praise.dart';
import 'package:grow_daily_v2/features/mascot/sprout_signals.dart';

void main() {
  // Every word the ledge shows, read from S rather than copied: the sprout's
  // name and the pop-up's wording follow Aziz's pick (see sproutName).
  const ar = S(Locale('ar'));

  /// A tap's line on screen: any row of the tap list («هههه», «اوبس»).
  Finder tickled() => find.byWidgetPredicate(
      (w) => w is Text && tickleLines(ar).contains(w.data));

  // Half the front pose's width at the ledge's height: the closest the
  // sprout's centre comes to either end of the line.
  final half = Sprout.sizeOf(SproutPose.frontWave, kLedgeSproutHeight).width / 2;

  // 09:00: nothing done is the front pose («صباح الخير»), whose box is the
  // reference the ledge is measured in.
  DateTime morning() => DateTime(2026, 9, 28, 9);

  late ProviderContainer container;
  setUp(() {
    PraisePicker.persist = false;
    DayCardSprout.greetedThisLaunch = true;
    container = ProviderContainer(
      overrides: [
        sproutAddressProvider.overrideWithValue(PraiseForm.man),
        sproutPraisePickerProvider.overrideWithValue(PraisePicker()),
        allHabitsEverProvider.overrideWithValue(const []),
      ],
    );
  });
  tearDown(() => container.dispose());

  /// A day card, the ledge, and a board under it, in a scrolling page like
  /// the Grid's, [width] wide.
  Widget page({
    double width = 370,
    double? Function(double)? today,
    bool drawLine = false,
    bool reduceMotion = false,
    ScrollController? scroll,
    Locale locale = const Locale('ar'),
    DeviceGestureSettings? gestures,
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
          theme: GameTheme.dark,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: reduceMotion,
                gestureSettings: gestures,
              ),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    child: SingleChildScrollView(
                      controller: scroll,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(key: Key('card'), height: 108),
                          SproutLedge(
                            greens: 0,
                            owed: 10,
                            ratio: 0,
                            perfectDay: false,
                            live: false,
                            todayFromStart: today,
                            drawLine: drawLine,
                            clock: morning,
                          ),
                          const ColoredBox(
                            key: Key('board'),
                            color: Colors.black,
                            child: SizedBox(height: 1200),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Rect lane(WidgetTester tester) => tester.getRect(find.byType(SproutLedge));
  Rect sprout(WidgetTester tester) => tester.getRect(find.byType(Sprout));

  /// A point on the sprout's face: inside the lane, above the line.
  Offset face(WidgetTester tester) =>
      Offset(sprout(tester).center.dx, lane(tester).top + 22);

  /// How far the first step of [drag] goes: past the 12pt pick-up, so the
  /// sprout is picked up there and moves by everything after it.
  const pickUp = 14.0;

  /// A drag: one [pickUp] step, the rest in ten even steps, then a still
  /// moment before letting go, so it ends with no fling.
  Future<void> drag(WidgetTester tester, Offset from, Offset by) async {
    final first = by / by.distance * pickUp;
    final g = await tester.startGesture(from);
    await g.moveBy(first);
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 10; i++) {
      await g.moveBy((by - first) / 10);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
  }

  group('on the line', () {
    testWidgets('stands behind the board edge: leaves 8pt up, face above it',
        (tester) async {
      await tester.pumpWidget(page(today: (w) => 120));
      await tester.pumpAndSettle();

      final l = lane(tester);
      final s = sprout(tester);
      expect(l.height, kLedgeLaneHeight);
      // The board starts where the lane ends.
      expect(tester.getRect(find.byKey(const Key('board'))).top, l.bottom);
      // The front pose's box: 1.44pt of transparent margin, then the leaves
      // 8pt above the lane, the feet 26.56pt below the line.
      expect(s.top, moreOrLessEquals(l.top - kLedgePeek - 0.018 * 80,
          epsilon: 0.01));
      expect(s.bottom, moreOrLessEquals(l.bottom + 26.56, epsilon: 0.01));
    });

    testWidgets('nothing of it shows below the line', (tester) async {
      await tester.pumpWidget(page(today: (w) => 120));
      await tester.pumpAndSettle();
      final clip = tester.renderObject<RenderClipRect>(find.descendant(
        of: find.byType(SproutLedge),
        matching: find.byType(ClipRect),
      ));
      expect(clip.clipper!.getClip(clip.size).bottom, kLedgeLaneHeight);
    });

    testWidgets('starts over today\'s column, measured from the start edge',
        (tester) async {
      await tester.pumpWidget(page(today: (w) => 120));
      await tester.pumpAndSettle();
      // Arabic: the start edge is the right one.
      expect(lane(tester).right - sprout(tester).center.dx,
          moreOrLessEquals(120, epsilon: 0.01));

      await tester.pumpWidget(page(today: (w) => 120, locale: const Locale('en')));
      await tester.pumpAndSettle();
      expect(sprout(tester).center.dx - lane(tester).left,
          moreOrLessEquals(120, epsilon: 0.01));
    });

    testWidgets('with no column to stand on, it stands at the end',
        (tester) async {
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(sprout(tester).center.dx - lane(tester).left,
          moreOrLessEquals(half + 8, epsilon: 0.01));
    });

    testWidgets('a saved spot lands on the same share of any phone',
        (tester) async {
      await container.read(gridSproutSpotProvider.notifier).set(0.25);
      for (final width in [343.0, 370.0, 408.0]) {
        await tester.pumpWidget(page(width: width, today: (w) => 120));
        await tester.pumpAndSettle();
        final fromStart = lane(tester).right - sprout(tester).center.dx;
        expect(fromStart,
            moreOrLessEquals(half + 0.25 * (width - 2 * half), epsilon: 0.01),
            reason: 'at $width wide');
      }
    });

    testWidgets('the board splitting keeps the same sprout, no new entrance',
        (tester) async {
      await tester.pumpWidget(page(today: (w) => 120));
      await tester.pumpAndSettle();
      final before = tester.state(find.byType(Sprout));
      // A habit paused today splits the board into sections.
      await tester.pumpWidget(page(today: (w) => 120, drawLine: true));
      expect(tester.state(find.byType(Sprout)), same(before));
      // And the lane grows its 6pt under the line gradually, not in one jump.
      await tester.pump(const Duration(milliseconds: 100));
      final mid = lane(tester).height;
      expect(mid, greaterThan(kLedgeLaneHeight));
      expect(mid, lessThan(kLedgeLaneHeight + 6));
      await tester.pumpAndSettle();
      expect(lane(tester).height, kLedgeLaneHeight + 6);
    });

    testWidgets('a split board gets a line drawn for it to stand behind',
        (tester) async {
      await tester.pumpWidget(page(today: (w) => 120, drawLine: true));
      await tester.pumpAndSettle();
      expect(lane(tester).height, kLedgeLaneHeight + 6);
      final line = find.descendant(
        of: find.byType(SproutLedge),
        matching: find.byType(ColoredBox),
      );
      expect(line, findsOneWidget);
      expect(tester.getRect(line).center.dy,
          moreOrLessEquals(lane(tester).top + kLedgeLaneHeight, epsilon: 0.01));
    });
  });

  group('sliding', () {
    testWidgets('follows the finger and saves the spot', (tester) async {
      await tester.pumpWidget(page(today: (w) => 120));
      await tester.pumpAndSettle();
      final before = sprout(tester).center.dx;

      await drag(tester, face(tester), const Offset(-80, 0));
      await tester.pumpAndSettle();

      // The first step picks it up; everything after moves it.
      final after = sprout(tester).center.dx;
      expect(after, moreOrLessEquals(before - (80 - pickUp), epsilon: 0.5));
      final l = lane(tester);
      final expected = ((l.right - after) - half) / (l.width - 2 * half);
      expect(container.read(gridSproutSpotProvider),
          moreOrLessEquals(expected, epsilon: 0.002));
    });

    testWidgets('pulls against a rubber band past the end, then comes home',
        (tester) async {
      await tester.pumpWidget(page(today: (w) => 120));
      await tester.pumpAndSettle();
      final g = await tester.startGesture(face(tester));
      for (var i = 0; i < 20; i++) {
        await g.moveBy(const Offset(-40, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final l = lane(tester);
      // Held far past the left end: over it, but never more than 24pt.
      final held = sprout(tester).center.dx - l.left;
      expect(held, lessThan(half));
      expect(held, greaterThan(half - 24));
      await tester.pump(const Duration(milliseconds: 300));
      await g.up();
      await tester.pumpAndSettle();
      expect(sprout(tester).center.dx - l.left,
          moreOrLessEquals(half, epsilon: 0.01));
      expect(container.read(gridSproutSpotProvider), 1.0);
    });

    testWidgets('a slide never sinks it', (tester) async {
      await tester.pumpWidget(page(today: (w) => 120));
      await tester.pumpAndSettle();
      final top = sprout(tester).top;
      // Mostly sideways, a little down.
      await drag(tester, face(tester), const Offset(-100, 40));
      await tester.pump(const Duration(milliseconds: 50));
      expect(sprout(tester).top, top);
      await tester.pumpAndSettle();
      expect(find.text(ar.gridSproutHideTitle), findsNothing);
    });
  });

  group('pulling down', () {
    testWidgets('a short pull springs back and asks nothing', (tester) async {
      await tester.pumpWidget(page(today: (w) => 120));
      await tester.pumpAndSettle();
      final rest = sprout(tester);
      await drag(tester, face(tester), const Offset(0, 20));
      await tester.pumpAndSettle();
      expect(find.text(ar.gridSproutHideTitle), findsNothing);
      expect(sprout(tester), rest);
    });

    testWidgets('a pull never slides it', (tester) async {
      await tester.pumpWidget(page(today: (w) => 120));
      await tester.pumpAndSettle();
      final x = sprout(tester).center.dx;
      await drag(tester, face(tester), const Offset(12, 20));
      await tester.pumpAndSettle();
      expect(sprout(tester).center.dx, x);
    });

    testWidgets('past half way it ducks and asks; keeping him brings him back',
        (tester) async {
      await tester.pumpWidget(page(today: (w) => 120));
      await tester.pumpAndSettle();
      final rest = sprout(tester);

      await drag(tester, face(tester), const Offset(0, 50));
      await tester.pumpAndSettle();
      expect(find.text(ar.gridSproutHideTitle), findsOneWidget);
      expect(find.text(ar.gridSproutHideBody),
          findsOneWidget);
      // Out of sight while it asks: the leaves are below the line too.
      final ducked = tester
          .getRect(find.descendant(
            of: find.byType(SproutLedge),
            matching: find.byType(Sprout),
          ))
          .top;
      expect(ducked, greaterThan(lane(tester).bottom));

      await tester.tap(find.text(ar.gridSproutHideNo));
      await tester.pumpAndSettle();
      expect(find.text(ar.gridSproutHideTitle), findsNothing);
      expect(container.read(gridSproutShownProvider), isTrue);
      expect(sprout(tester), rest);
    });

    testWidgets('hiding him closes the lane; Settings brings him back',
        (tester) async {
      await tester.pumpWidget(page(today: (w) => 120));
      await tester.pumpAndSettle();
      final rest = sprout(tester);

      await drag(tester, face(tester), const Offset(0, 50));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ar.gridSproutHideYes));
      await tester.pumpAndSettle();

      expect(container.read(gridSproutShownProvider), isFalse);
      expect(lane(tester).height, kLedgeClosedHeight);
      expect(find.byType(Sprout), findsNothing);
      expect(tester.getRect(find.byKey(const Key('board'))).top,
          lane(tester).bottom);

      // The Settings switch.
      await container.read(gridSproutShownProvider.notifier).set(true);
      await tester.pumpAndSettle();
      expect(lane(tester).height, kLedgeLaneHeight);
      expect(sprout(tester), rest);
    });

    testWidgets('a quick flick down asks too', (tester) async {
      await tester.pumpWidget(page(today: (w) => 120));
      await tester.pumpAndSettle();
      // 7pt every 4ms (1750pt/s): picked up on the first, 21pt down by the
      // last, short of half way (26pt) but plainly a flick. Timestamps,
      // because a test pointer's events are otherwise all at time zero and
      // have no speed at all.
      final g = await tester.startGesture(face(tester));
      for (var i = 1; i <= 4; i++) {
        await g.moveBy(const Offset(0, 7),
            timeStamp: Duration(milliseconds: 4 * i));
      }
      await g.up(timeStamp: const Duration(milliseconds: 17));
      await tester.pumpAndSettle();
      expect(find.text(ar.gridSproutHideTitle), findsOneWidget);
      await tester.tap(find.text(ar.gridSproutHideNo));
      await tester.pumpAndSettle();
    });
  });

  group('the rest of the page', () {
    testWidgets('a tap still makes it laugh, and the bubble sits beside it',
        (tester) async {
      // 250 from the right edge: room on the reading side for the bubble.
      await tester.pumpWidget(page(today: (w) => 250));
      await tester.pumpAndSettle();
      await tester.tapAt(face(tester));
      await tester.pump(const Duration(milliseconds: 300));
      final bubble = find.byType(SproutBubble);
      expect(bubble, findsOneWidget);
      expect(tickled(), findsOneWidget);
      final b = tester.getRect(bubble);
      final s = sprout(tester);
      // On the reading side (right, in Arabic), bottom just above the line.
      expect(b.left, greaterThan(s.center.dx));
      expect(b.bottom, moreOrLessEquals(lane(tester).bottom - 2, epsilon: 0.5));
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('with no room on the reading side it speaks on the other',
        (tester) async {
      // 120 from the right edge leaves 87pt there, under a bubble's width.
      await tester.pumpWidget(page(today: (w) => 120));
      await tester.pumpAndSettle();
      await tester.tapAt(face(tester));
      await tester.pump(const Duration(milliseconds: 300));
      final b = tester.getRect(find.byType(SproutBubble));
      expect(b.right, lessThan(sprout(tester).center.dx));
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('near the start edge the bubble goes to the other side',
        (tester) async {
      await container.read(gridSproutSpotProvider.notifier).set(0);
      await tester.pumpWidget(page(today: (w) => 120));
      await tester.pumpAndSettle();
      await tester.tapAt(face(tester));
      await tester.pump(const Duration(milliseconds: 300));
      final b = tester.getRect(find.byType(SproutBubble));
      expect(b.right, lessThan(sprout(tester).center.dx));
      expect(b.left, greaterThanOrEqualTo(lane(tester).left - 12));
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    // Aziz, 2026-09-28: "make sure that user can easily click on the pet,
    // not by mistake slide the screen".
    testWidgets('a tap that wobbles 10pt is still a tap: it laughs, stays put',
        (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(page(today: (w) => 250, scroll: scroll));
      await tester.pumpAndSettle();
      final rest = sprout(tester);
      // 10pt out and back, then down and back: 36pt of path, never more
      // than 10pt from where it landed.
      final g = await tester.startGesture(face(tester));
      for (final step in const [
        Offset(10, 0),
        Offset(-10, 0),
        Offset(0, 8),
        Offset(0, -8),
      ]) {
        await g.moveBy(step);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tickled(), findsOneWidget);
      // Not slid: the same place along the line (mid-hop, it is higher for a
      // moment, which is the laugh), and nothing saved.
      expect(sprout(tester).center.dx, rest.center.dx);
      expect(scroll.offset, 0);
      expect(container.read(gridSproutSpotProvider), isNull);
      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(sprout(tester), rest);
    });

    testWidgets('a tap on its side, not its face, laughs too', (tester) async {
      await tester.pumpWidget(page(today: (w) => 250));
      await tester.pumpAndSettle();
      final s = sprout(tester);
      await tester.tapAt(Offset(s.left + 8, lane(tester).top + 30));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tickled(), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    // Android reports its own touch slop, 8dp on most phones, and the page
    // scrolls from 8 there, not 18.
    testWidgets('with Android\'s 8pt slop a drag on it still never scrolls',
        (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(page(
        today: (w) => 120,
        scroll: scroll,
        gestures: const DeviceGestureSettings(touchSlop: 8),
      ));
      await tester.pumpAndSettle();
      // 9pt steps: the first is already past the page's 8, so the page
      // takes the finger unless the sprout picked it up by then; at a flat
      // 12pt, as iOS allows, it would not have.
      final g = await tester.startGesture(face(tester));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(0, -9));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await g.up();
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);

      final board = tester.getRect(find.byKey(const Key('board')));
      await drag(
        tester,
        board.topCenter + const Offset(0, 100),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
    });

    testWidgets('with Android\'s slop a 5pt wobble is still a tap',
        (tester) async {
      await tester.pumpWidget(page(
        today: (w) => 250,
        gestures: const DeviceGestureSettings(touchSlop: 8),
      ));
      await tester.pumpAndSettle();
      final rest = sprout(tester);
      final g = await tester.startGesture(face(tester));
      await g.moveBy(const Offset(5, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveBy(const Offset(-5, 3));
      await tester.pump(const Duration(milliseconds: 16));
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tickled(), findsOneWidget);
      expect(sprout(tester).center.dx, rest.center.dx);
      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(sprout(tester), rest);
    });

    testWidgets('a finger that starts on the sprout never scrolls the page',
        (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(page(today: (w) => 120, scroll: scroll));
      await tester.pumpAndSettle();

      await drag(tester, face(tester), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);

      // The same drag on the board scrolls as always.
      final board = tester.getRect(find.byKey(const Key('board')));
      await drag(
        tester,
        board.topCenter + const Offset(0, 100),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
    });

    testWidgets('Reduce Motion: every settle is short and nothing breaks',
        (tester) async {
      await tester.pumpWidget(page(today: (w) => 120, reduceMotion: true));
      await tester.pumpAndSettle();
      final before = sprout(tester).center.dx;
      await drag(tester, face(tester), const Offset(-80, 0));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        sprout(tester).center.dx,
        moreOrLessEquals(before - (80 - pickUp), epsilon: 0.5),
      );
      await drag(tester, face(tester), const Offset(0, 50));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ar.gridSproutHideNo));
      await tester.pumpAndSettle();
    });
  });
}
