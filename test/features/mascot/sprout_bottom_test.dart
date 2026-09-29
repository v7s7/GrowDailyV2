// Doum at the foot of the screen (SproutBottomPeek, option A of the "Doum at
// the board's end" canvas): when the board's top edge scrolls near the top of
// the screen he ducks there and pops up above the bottom bar, over the habit
// names, and comes back when the edge is well in view. One mind throughout
// (DayCardSprout on the ledge), a second body down here. See sprout_bottom.dart.
//
// The page mirrors the app: HomeShell's Scaffold (with a bottom bar, the
// SnackBars and a PageView of tabs) around the Grid's own Scaffold, whose body
// is a bouncing CustomScrollView with the ledge and a board of rows whose
// names answer taps and holds, and the foot host in a Stack over it.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/grid/screens/grid_screen.dart'
    show namesColumnFromStart;
import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';
import 'package:grow_daily_v2/features/mascot/day_card_sprout.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';
import 'package:grow_daily_v2/features/mascot/sprout_ledge.dart';
import 'package:grow_daily_v2/features/mascot/sprout_praise.dart';
import 'package:grow_daily_v2/features/mascot/sprout_signals.dart';
import 'package:grow_daily_v2/shared/widgets/app_snackbar.dart';

void main() {
  const ar = S(Locale('ar'));

  /// A tap's line on screen: any row of the tap list («هههه», «اوبس»).
  Finder tickled() => find.byWidgetPredicate(
      (w) => w is Text && tickleLines(ar).contains(w.data));

  // 09:00, nothing done: the front pose, the one every size is measured by.
  DateTime morning() => DateTime(2026, 9, 28, 9);

  // Where the page puts things: 200pt of header, the 108pt card, then the
  // 44pt lane, so the line (the board's top edge) is 352pt down the content.
  const header = 200.0;
  const line = header + 108 + kLedgeLaneHeight;
  const barHeight = 94.0;
  const rowPitch = 61.0; // a 56pt row and a 5pt gap, as on the board

  late ProviderContainer container;
  late SproutStage stage;
  late ValueNotifier<bool> aside;
  late int nameTaps;
  late int nameHolds;
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
    stage = SproutStage();
    aside = ValueNotifier(false);
    nameTaps = 0;
    nameHolds = 0;
  });
  tearDown(() => container.dispose());

  void phone(WidgetTester tester, {double width = 402, double height = 874}) {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  /// A board of [rows] rows: a names column at the start that counts taps and
  /// holds (the real one opens a habit's actions), and room for squares.
  /// With [labels], each name has a tile-and-name box [label] tall in the
  /// middle of its row, marked for Doum to keep clear of, as on the Grid (22
  /// for a one-line name, 26.45 for two lines, taller with larger text).
  Widget board(int rows, {bool labels = false, double label = 22}) =>
      LayoutBuilder(
        builder: (context, box) {
          final rtl = Directionality.of(context) == TextDirection.rtl;
          final names = namesColumnFromStart(box.maxWidth, rtl: rtl);
          final column =
              names == null ? 68.0 : names.squaresFrom - 12.5 - (rtl ? 0 : 5);
          return Container(
            key: const Key('board'),
            color: Colors.black,
            padding: const EdgeInsets.all(12.5),
            child: Column(
              children: [
                for (var i = 0; i < rows; i++)
                  SizedBox(
                    height: rowPitch,
                    child: Row(
                      children: [
                        SizedBox(
                          width: column,
                          child: GestureDetector(
                            key: Key('name$i'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => nameTaps++,
                            onLongPress: () => nameHolds++,
                            child: labels
                                ? Center(
                                    child: SproutKeepClear(
                                      key: Key('label$i'),
                                      stage: stage,
                                      child: SizedBox(
                                        width: column - 8,
                                        height: label,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      );

  Widget page({
    required ScrollController scroll,
    int rows = 22,
    double tail = 120,
    bool reduceMotion = false,
    bool withLedge = true,
    Locale locale = const Locale('ar'),
    PageController? tabs,
    ThemeData? theme,
    int greens = 0,
    bool perfectDay = false,
    bool live = false,
    DateTime Function()? clock,
    bool hint = false,
    bool labels = false,
    double label = 22,
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
          theme: theme ?? GameTheme.dark,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reduceMotion),
              // HomeShell's Scaffold: the bar, the SnackBars, the tab pages.
              child: Scaffold(
                bottomNavigationBar:
                    const SizedBox(key: Key('bar'), height: barHeight),
                body: PageView(
                  controller: tabs,
                  children: [
                    // The Grid's own Scaffold.
                    Scaffold(
                      body: Stack(
                        children: [
                          CustomScrollView(
                            controller: scroll,
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            slivers: [
                              const SliverToBoxAdapter(
                                child: SizedBox(
                                  key: Key('header'),
                                  height: header,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                child: SizedBox(key: Key('card'), height: 108),
                              ),
                              SliverToBoxAdapter(
                                child: withLedge
                                    ? Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: SproutLedge(
                                          greens: greens,
                                          owed: 10,
                                          ratio: greens / 10,
                                          perfectDay: perfectDay,
                                          live: live,
                                          clock: clock ?? morning,
                                          stage: stage,
                                          namesFromStart: namesColumnFromStart,
                                        ),
                                      )
                                    : const SizedBox(height: kLedgeLaneHeight),
                              ),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: board(
                                    rows,
                                    labels: labels,
                                    label: label,
                                  ),
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: SizedBox(height: tail),
                              ),
                            ],
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: kSproutBottomHostHeight,
                            child: SproutBottomPeek(
                              stage: stage,
                              namesFromStart: namesColumnFromStart,
                              stepAside: aside,
                              hintShowing: hint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(key: Key('next tab')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Rect bar(WidgetTester tester) => tester.getRect(find.byKey(const Key('bar')));

  final bottomSprout = find.descendant(
    of: find.byType(SproutBottomPeek),
    matching: find.byType(Sprout),
  );
  final ledge = find.byType(SproutLedge, skipOffstage: false);
  final ledgeSprout = find.descendant(
    of: ledge,
    matching: find.byType(Sprout, skipOffstage: false),
    skipOffstage: false,
  );
  final mind = find.byType(DayCardSprout, skipOffstage: false);

  /// Whether the ledge's body is put away (not painted at all).
  bool tucked(WidgetTester tester) => tester
      .widget<Offstage>(find
          .ancestor(
            of: mind,
            matching: find.byType(Offstage, skipOffstage: false),
          )
          .first)
      .offstage;

  /// How much of the ledge's body shows above its line, 0 when put away.
  double upTop(WidgetTester tester) {
    if (tucked(tester)) return 0;
    final lane = tester.getRect(ledge);
    return (lane.bottom - tester.getRect(ledgeSprout).top)
        .clamp(0, 200)
        .toDouble();
  }

  /// How much of the foot's body shows above the bar, 0 when not built.
  double downHere(WidgetTester tester) => bottomSprout.evaluate().isEmpty
      ? 0
      : (bar(tester).top - tester.getRect(bottomSprout).top)
          .clamp(0, 200)
          .toDouble();

  /// Scrolls so the line sits [y] below the top of the page's scroll view.
  Future<void> lineAt(WidgetTester tester, ScrollController scroll, double y,
      {bool settle = true}) async {
    scroll.jumpTo(line - y);
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
  }

  double centreFromStart(WidgetTester tester, {double width = 402}) =>
      width - tester.getRect(bottomSprout).center.dx;

  // The front pose standing on a line: 52pt above it and its 1.44pt margin.
  const peek = 52 + 0.018 * 80;

  group('the hand-off', () {
    testWidgets('at the top he is on the board\'s edge and nothing is drawn '
        'at the foot', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      expect(bottomSprout, findsNothing);
      expect(tucked(tester), isFalse);
      expect(mind, findsOneWidget);
    });

    testWidgets('the line near the top: he ducks behind the board, is put '
        'away there, and pops up above the bar, 52pt of him, over the names',
        (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);

      expect(mind, findsOneWidget);
      expect(tucked(tester), isTrue);
      expect(stage.atBottom, isTrue);
      final b = bar(tester);
      final s = tester.getRect(bottomSprout);
      expect(b.top - s.top, moreOrLessEquals(peek, epsilon: 0.05));
      expect(s.bottom, moreOrLessEquals(b.top + 26.56, epsilon: 0.05));
      final names = namesColumnFromStart(370, rtl: true)!;
      expect(
        centreFromStart(tester),
        moreOrLessEquals(
          sproutBottomCentre(
            names: names,
            mood: SproutPose.frontWave,
            roundedBar: false,
          ),
          epsilon: 0.05,
        ),
      );
      // On a 402pt phone that is the middle of the names: 16 + 12.5 +
      // (72.45 - 8) / 2.
      expect(centreFromStart(tester), moreOrLessEquals(60.725, epsilon: 0.05));
    });

    testWidgets('nothing of him is drawn below the bar\'s edge',
        (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      final clip = tester.renderObject<RenderClipRect>(find.descendant(
        of: find.byType(SproutBottomPeek),
        matching: find.byType(ClipRect),
      ));
      final cut = clip.localToGlobal(
        Offset(0, clip.clipper!.getClip(clip.size).bottom),
      );
      expect(cut.dy, moreOrLessEquals(bar(tester).top, epsilon: 0.01));
    });

    testWidgets('the duck is seen first, the climb starts 90ms on: never two '
        'of him in view', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      scroll.jumpTo(line - 40);
      await tester.pump(); // the page moves
      await tester.pump(); // the decision, after that frame
      var both = false;
      var sawDuck = false;
      for (var t = 0; t < 60; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        final top = upTop(tester);
        final foot = downHere(tester);
        if (t == 4) {
          // 80ms in: the climb has not started.
          expect(foot, lessThan(1));
        }
        if (top > 1 && top < peek - 1) sawDuck = true;
        // More than 12pt of both at once would read as two of him.
        if (top > 12 && foot > 12) both = true;
      }
      expect(sawDuck, isTrue);
      expect(both, isFalse);
      await tester.pumpAndSettle();
      expect(downHere(tester), moreOrLessEquals(peek, epsilon: 0.05));
    });

    testWidgets('back up: he ducks at the foot and climbs onto the edge',
        (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      expect(bottomSprout, findsOneWidget);
      await lineAt(tester, scroll, 300);
      expect(bottomSprout, findsNothing);
      expect(tucked(tester), isFalse);
      expect(
        tester.getRect(ledgeSprout).bottom,
        moreOrLessEquals(tester.getRect(ledge).bottom + 26.56, epsilon: 0.05),
      );
    });

    testWidgets('turned back mid-duck: straight back up, no pause, and the '
        'foot never showed him', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 200);
      scroll.jumpTo(line - 40);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final dipped = upTop(tester);
      expect(dipped, lessThan(peek - 1));
      scroll.jumpTo(line - 200);
      await tester.pump();
      await tester.pump();
      var foot = 0.0;
      double? back;
      for (var t = 0; t < 40; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        foot = math.max(foot, downHere(tester));
        // Carried a little further down by the speed he had, then up: the
        // spring starts at once, it does not wait 90ms first.
        if (back == null && upTop(tester) > dipped) back = t * 16.0;
      }
      expect(back, isNotNull);
      expect(back, lessThan(180), reason: 'straight back up, no pause');
      expect(foot, lessThan(1));
      await tester.pumpAndSettle();
      expect(upTop(tester), moreOrLessEquals(peek, epsilon: 0.05));
    });

    testWidgets('down below 64, back above 116, and he stays put between',
        (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 100);
      expect(stage.atBottom, isFalse);
      await lineAt(tester, scroll, 64.5);
      expect(stage.atBottom, isFalse);
      await lineAt(tester, scroll, 63.5);
      expect(stage.atBottom, isTrue);
      await lineAt(tester, scroll, 100);
      expect(stage.atBottom, isTrue);
      await lineAt(tester, scroll, 115.5);
      expect(stage.atBottom, isTrue);
      await lineAt(tester, scroll, 116.5);
      expect(stage.atBottom, isFalse);
    });

    testWidgets('the same mind all along, through many trips', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      final before = tester.state(mind);
      for (var i = 0; i < 10; i++) {
        await lineAt(tester, scroll, 20, settle: false);
        await tester.pump(const Duration(milliseconds: 60));
        await lineAt(tester, scroll, 400, settle: false);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pumpAndSettle();
      expect(mind, findsOneWidget);
      expect(tester.state(mind), same(before));
      expect(bottomSprout, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bounce past the end is not a scroll', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      // At the very end the line rests about 90pt from the top: between the
      // two marks, from the edge's side.
      const rows = 9;
      const content = line + 25 + rows * rowPitch;
      const view = 874.0 - barHeight;
      const tail = view - (content - line) - 90;
      await tester.pumpWidget(page(scroll: scroll, rows: rows, tail: tail));
      await tester.pumpAndSettle();
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getRect(ledge).bottom, moreOrLessEquals(90, epsilon: 1));
      expect(stage.atBottom, isFalse);
      // A pull past the end drags the line under 64 for as long as it is
      // held; it is not where the page is.
      final g = await tester.startGesture(const Offset(200, 600));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.getRect(ledge).bottom, lessThan(64));
      await tester.pump();
      expect(stage.atBottom, isFalse);
      await g.up();
      await tester.pumpAndSettle();
      expect(stage.atBottom, isFalse);
      expect(bottomSprout, findsNothing);
    });

    testWidgets('built already scrolled, he is at the foot at once, no climb',
        (tester) async {
      phone(tester);
      final scroll = ScrollController(initialScrollOffset: line - 20);
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pump();
      await tester.pump();
      expect(stage.atBottom, isTrue);
      expect(stage.animate, isFalse);
      await tester.pump();
      final first = tester.getRect(bottomSprout);
      await tester.pumpAndSettle();
      expect(tester.getRect(bottomSprout), first);
      expect(bar(tester).top - first.top, moreOrLessEquals(peek, epsilon: 0.05));
      expect(tucked(tester), isTrue);
    });

    testWidgets('a new theme while scrolled (the scroll position is replaced): '
        'he still follows the page', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 300);
      await tester.pumpWidget(page(scroll: scroll, theme: GameTheme.light));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 30);
      expect(stage.atBottom, isTrue);
      expect(bottomSprout, findsOneWidget);
      await lineAt(tester, scroll, 300);
      expect(stage.atBottom, isFalse);
    });
  });

  group('down at the foot', () {
    Finder said() => find.descendant(
          of: find.byType(SproutBottomPeek),
          matching: tickled(),
        );

    testWidgets('a tap on him is his: he laughs beside him, the name under '
        'him is not tapped', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      final s = tester.getRect(bottomSprout);
      await tester.tapAt(Offset(s.center.dx, bar(tester).top - 24));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(said(), findsOneWidget);
      expect(nameTaps, 0);
      final bubble = tester.getRect(find.ancestor(
        of: said(),
        matching: find.byType(SproutBubble),
      ));
      // Toward the squares (left, in Arabic), just above his line, on screen.
      expect(bubble.right, lessThanOrEqualTo(s.center.dx));
      expect(bubble.left, greaterThanOrEqualTo(0));
      expect(bubble.bottom, moreOrLessEquals(bar(tester).top - 2, epsilon: 0.5));
      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(said(), findsNothing);
    });

    testWidgets('a hold on him is his too: the name under him never opens',
        (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      final s = tester.getRect(bottomSprout);
      final at = Offset(s.center.dx, bar(tester).top - 24);
      // There is a name under him to be held.
      final names = find.byWidgetPredicate(
        (w) => w is GestureDetector && '${w.key}'.contains('name'),
      );
      expect(
        names.evaluate().any((e) {
          final box = e.renderObject! as RenderBox;
          return (box.localToGlobal(Offset.zero) & box.size).contains(at);
        }),
        isTrue,
      );
      await tester.longPressAt(at);
      await tester.pump(const Duration(milliseconds: 250));
      expect(nameHolds, 0);
      expect(nameTaps, 0);
      expect(said(), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('a drag up that starts on him still scrolls the page',
        (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      final before = scroll.offset;
      final s = tester.getRect(bottomSprout);
      await tester.dragFrom(
        Offset(s.center.dx, bar(tester).top - 24),
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(before + 100));
      expect(tickled(), findsNothing);
    });

    testWidgets('a sideways drag on him gives a little and springs back; the '
        'tab stays', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      final tabs = PageController();
      await tester.pumpWidget(page(scroll: scroll, tabs: tabs));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      final rest = tester.getRect(bottomSprout);
      final g = await tester.startGesture(
        Offset(rest.center.dx, bar(tester).top - 24),
      );
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(25, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final pulled = tester.getRect(bottomSprout).center.dx - rest.center.dx;
      expect(pulled, greaterThan(2));
      expect(pulled, lessThanOrEqualTo(10));
      await g.up();
      await tester.pumpAndSettle();
      expect(tabs.page, 0);
      expect(tester.getRect(bottomSprout), rest);
      // The same drag anywhere else on the page does turn the tab (in
      // Arabic the next tab is to the left, so the page is pulled right).
      await tester.dragFrom(const Offset(200, 500), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(tabs.page, 1);
    });

    testWidgets('a tap that stops a gliding page is not a tickle',
        (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      await tester.flingFrom(
        const Offset(200, 500),
        const Offset(0, -80),
        1500,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(stage.scrolling.value, isTrue);
      final s = tester.getRect(bottomSprout);
      await tester.tapAt(Offset(s.center.dx, bar(tester).top - 24));
      await tester.pump(const Duration(milliseconds: 250));
      expect(tickled(), findsNothing);
      await tester.pumpAndSettle();
      expect(stage.scrolling.value, isFalse);
    });

    testWidgets('his moves play down here, a frame on; the body up top makes '
        'none', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      expect(tester.widget<Sprout>(ledgeSprout).controller, isNull);
      // Its own, which plays the mind's moves when there is room (nothing
      // is marked on this page, so there always is).
      expect(tester.widget<Sprout>(bottomSprout).controller, isNotNull);
      final rest = tester.getRect(bottomSprout).top;
      stage.echo.moves.hop();
      await tester.pump();
      var highest = rest;
      for (var t = 0; t < 30; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        for (final e in find
            .descendant(of: bottomSprout, matching: find.byType(Transform))
            .evaluate()) {
          final dy = (e.widget as Transform).transform.getTranslation().y;
          if (rest + dy < highest) highest = rest + dy;
        }
      }
      // The hop is drawn for a 150pt sprout: 25 units of 80/150.
      expect(rest - highest, greaterThan(10));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    });
  });

  group('pop-ups', () {
    Rect surface(WidgetTester tester) => tester.getRect(find
        .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
        .first);

    /// The bar's visible top edge: the lower of its growing clip's top and
    /// its surface's.
    double visibleTop(WidgetTester tester) {
      final clip = tester.getRect(find
          .descendant(of: find.byType(SnackBar), matching: find.byType(ClipRect))
          .first);
      return math.max(surface(tester).top, clip.top);
    }

    double standLine(WidgetTester tester) =>
        tester.getRect(bottomSprout).bottom - 26.56;

    ScaffoldMessengerState messenger(WidgetTester tester) =>
        ScaffoldMessenger.of(tester.element(find.byKey(const Key('board'))));

    /// Every frame for [frames]: he never stands higher than the bar's
    /// visible edge (so the bar, drawn over him, always hides his feet and
    /// his cut never hangs over nothing), one frame behind allowed for.
    Future<void> neverAbove(WidgetTester tester, int frames) async {
      var lastEdge = double.infinity;
      for (var t = 0; t < frames; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find.byType(SnackBar).evaluate().isEmpty) {
          lastEdge = double.infinity;
          continue;
        }
        final stand = standLine(tester);
        final edge = visibleTop(tester);
        if (stand < bar(tester).top - 0.5) {
          expect(stand, greaterThanOrEqualTo(math.min(edge, lastEdge) - 0.5),
              reason: 'frame $t: stands at $stand over an edge at $edge');
        }
        lastEdge = edge;
      }
    }

    testWidgets('he rises with one and steps down as it goes, never over '
        'nothing', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      messenger(tester).showOne(const SnackBar(
        content: Text('يومك انحسب في سلسلتك.'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: Duration(seconds: 3),
      ));
      await tester.pump();
      await neverAbove(tester, 24);
      await tester.pump();
      // Up: on its surface, cut at its edge, nothing of him in the 16pt
      // between it and the bar.
      expect(standLine(tester),
          moreOrLessEquals(surface(tester).top, epsilon: 0.5));
      final clip = tester.renderObject<RenderClipRect>(find.descendant(
        of: find.byType(SproutBottomPeek),
        matching: find.byType(ClipRect),
      ));
      final cut = clip.localToGlobal(
        Offset(0, clip.clipper!.getClip(clip.size).bottom),
      );
      expect(cut.dy, moreOrLessEquals(surface(tester).top, epsilon: 0.5));
      // Going: back on the bar by the time it is gone.
      messenger(tester).hideCurrentSnackBar();
      await tester.pump();
      await neverAbove(tester, 18);
      await tester.pump();
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
      expect(standLine(tester),
          moreOrLessEquals(bar(tester).top, epsilon: 0.05));
    });

    testWidgets('one replacing another: down with the old, up with the new, '
        'never over nothing', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      messenger(tester).showOne(const SnackBar(
        content: Text('first'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ));
      await tester.pumpAndSettle();
      messenger(tester).showOne(const SnackBar(
        content: Text('second\nof two lines'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ));
      await tester.pump();
      await neverAbove(tester, 50);
      await tester.pumpAndSettle();
      expect(find.text('second\nof two lines'), findsOneWidget);
      expect(standLine(tester),
          moreOrLessEquals(surface(tester).top, epsilon: 0.5));
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('swiped away: he goes down with it', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      messenger(tester).showOne(const SnackBar(
        content: Text('swipe me'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ));
      await tester.pumpAndSettle();
      final up = standLine(tester);
      final g =
          await tester.startGesture(tester.getCenter(find.text('swipe me')));
      for (var i = 0; i < 3; i++) {
        await g.moveBy(const Offset(0, 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump();
      expect(standLine(tester), greaterThan(up + 10));
      await g.moveBy(const Offset(0, 80));
      await g.up();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(standLine(tester),
          moreOrLessEquals(bar(tester).top, epsilon: 0.05));
    });
  });

  group('stepping aside', () {
    testWidgets('hidden: gone from the foot too, and nothing throws',
        (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      expect(bottomSprout, findsOneWidget);
      unawaited(container.read(gridSproutShownProvider.notifier).set(false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(bottomSprout, findsNothing);
      await lineAt(tester, scroll, 300);
      await lineAt(tester, scroll, 30);
      expect(bottomSprout, findsNothing);
      unawaited(container.read(gridSproutShownProvider.notifier).set(true));
      await tester.pumpAndSettle();
    });

    testWidgets('a voice note in the player: he goes back up to the edge, '
        'and comes down again after', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      aside.value = true;
      await tester.pumpAndSettle();
      expect(bottomSprout, findsNothing);
      expect(stage.atBottom, isFalse);
      expect(tucked(tester), isFalse);
      aside.value = false;
      await tester.pumpAndSettle();
      expect(stage.atBottom, isTrue);
      expect(bottomSprout, findsOneWidget);
    });

    testWidgets('the keyboard up (a sheet over the page): gone at once, back '
        'at once', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      final rest = tester.getRect(bottomSprout);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(bottomSprout, findsNothing);
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(bottomSprout), rest);
    });

    testWidgets('a board too narrow to keep its names in place: he stays on '
        'the edge', (tester) async {
      phone(tester, width: 360);
      expect(namesColumnFromStart(328, rtl: true), isNull);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 20);
      expect(stage.atBottom, isFalse);
      expect(bottomSprout, findsNothing);
    });

    testWidgets('Reduce Motion: he fades in at his place, no climb',
        (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll, reduceMotion: true));
      await tester.pumpAndSettle();
      scroll.jumpTo(line - 40);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final first = tester.getRect(bottomSprout);
      final fades = <double>[];
      for (var t = 0; t < 14; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getRect(bottomSprout), first);
        fades.add(tester
            .widget<Opacity>(find
                .ancestor(of: bottomSprout, matching: find.byType(Opacity))
                .first)
            .opacity);
      }
      expect(fades.first, lessThan(0.5));
      expect(fades.last, 1);
      expect(bar(tester).top - first.top, moreOrLessEquals(peek, epsilon: 0.05));
      await tester.pumpAndSettle();
    });

    testWidgets('the ledge going away takes him from the foot, cleanly',
        (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      expect(bottomSprout, findsOneWidget);
      await tester.pumpWidget(page(scroll: scroll, withLedge: false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(stage.atBottom, isFalse);
      expect(bottomSprout, findsNothing);
      expect(stage.speech.value, isNull);
    });
  });

  group('where he stands', () {
    testWidgets('English: over the names on the left', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll, locale: const Locale('en')));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      final names = namesColumnFromStart(370, rtl: false)!;
      expect(
        tester.getRect(bottomSprout).center.dx,
        moreOrLessEquals(
          sproutBottomCentre(
            names: names,
            mood: SproutPose.frontWave,
            roundedBar: false,
          ),
          epsilon: 0.05,
        ),
      );
    });

    testWidgets('iPhone: kept off the rounded bar\'s corner', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      final names = namesColumnFromStart(370, rtl: true)!;
      expect(
        centreFromStart(tester),
        moreOrLessEquals(
          sproutBottomCentre(
            names: names,
            mood: SproutPose.frontWave,
            roundedBar: true,
          ),
          epsilon: 0.05,
        ),
      );
      expect(centreFromStart(tester), greaterThan(16 + names.centre));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    test('the names column: its centre and the first square, both ways', () {
      final rtl = namesColumnFromStart(370, rtl: true)!;
      expect(rtl.centre,
          moreOrLessEquals(12.5 + (72.45 - 8) / 2, epsilon: 1e-9));
      expect(rtl.squaresFrom, moreOrLessEquals(12.5 + 72.45, epsilon: 1e-9));
      final ltr = namesColumnFromStart(370, rtl: false)!;
      expect(
          ltr.squaresFrom, moreOrLessEquals(12.5 + 72.45 + 5, epsilon: 1e-9));
      expect(namesColumnFromStart(343, rtl: true)!.centre, 12.5 + 30);
      expect(namesColumnFromStart(768 - 32, rtl: true)!.centre, 12.5 + 44);
      expect(namesColumnFromStart(328, rtl: true), isNull);
    });

    test('no mood, laughing or not, reaches the first square; on the iPhone '
        'bar his cut clears the corner wherever the names leave room', () {
      // Facing into the page, the drawing's right side (as the files have
      // it) is toward the squares and its left toward the corner, in both
      // languages (_kReach): with a laugh on top, and at rest in the pose.
      const toSquares = {
        SproutPose.frontWave: 33.0,
        SproutPose.threeQuarterWave: 33.0,
        SproutPose.happySparkles: 35.0,
      };
      const atRest = {
        SproutPose.frontWave: 29.4,
        SproutPose.threeQuarterWave: 24.8,
        SproutPose.happySparkles: 33.3,
      };
      // How far the pill's 28pt corner, 16pt in from the edge, curves below
      // its flat top at [x] from the edge.
      double dip(double x) {
        if (x >= 44) return 0;
        final d = math.min(44 - x, 28.0);
        return 28 - math.sqrt(28 * 28 - d * d);
      }

      for (final phoneWidth in [
        375.0,
        390.0,
        393.0,
        402.0,
        430.0,
        440.0,
        768.0,
      ]) {
        for (final rtl in [true, false]) {
          // Where the names are differs by direction (the first square's
          // gap), which is why both are checked.
          final n = namesColumnFromStart(phoneWidth - 32, rtl: rtl)!;
          for (final mood in toSquares.keys) {
            for (final rounded in [true, false]) {
              final c = sproutBottomCentre(
                names: n,
                mood: mood,
                roundedBar: rounded,
              );
              expect(c + toSquares[mood]!,
                  lessThanOrEqualTo(16 + n.squaresFrom - 2 + 1e-9),
                  reason: '$mood at $phoneWidth rtl=$rtl');
              if (!rounded) continue;
              // At rest in his mood's pose, the gap under his outer edge,
              // as measured when this was built (a guard, not a wish). The
              // names are too narrow for all of him on the flat of the bar
              // (68 to 80pt, the bar flat from 44pt in), and the squares win:
              // while ticking (three-quarter) it is under a point
              // everywhere; with nothing done yet, up to 2.7pt on a 375pt
              // phone in Arabic; on a perfect day, arms up, up to 6.4pt
              // there, 3.4pt on a 402pt one. From 430pt it is gone.
              const measured = {
                SproutPose.frontWave: [2.7, 1.9, 1.7, 1.1, 0.2],
                SproutPose.threeQuarterWave: [1.0, 0.6, 0.5, 0.2, 0.1],
                SproutPose.happySparkles: [6.5, 5.0, 4.6, 3.5, 1.1],
              };
              final band = phoneWidth < 390
                  ? 0
                  : phoneWidth < 393
                      ? 1
                      : phoneWidth < 402
                          ? 2
                          : phoneWidth < 430
                              ? 3
                              : 4;
              final gap = dip(c - atRest[mood]!);
              expect(gap, lessThan(measured[mood]![band]),
                  reason: '$mood at $phoneWidth rtl=$rtl: gap $gap');
            }
          }
        }
      }
    });
  });

  group('one Doum, everything he does', () {
    Finder footBubble() => find.descendant(
          of: find.byType(SproutBottomPeek),
          matching: find.byType(SproutBubble),
        );
    Finder ledgeBubble() => find.descendant(
          of: ledge,
          matching: find.byType(SproutBubble, skipOffstage: false),
          skipOffstage: false,
        );

    /// The highest the foot's body got above where it rests, over [frames].
    Future<double> hopHeight(WidgetTester tester, int frames) async {
      final rest = tester.getRect(bottomSprout).top;
      var highest = rest;
      for (var t = 0; t < frames; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        for (final e in find
            .descendant(of: bottomSprout, matching: find.byType(Transform))
            .evaluate()) {
          final dy = (e.widget as Transform).transform.getTranslation().y;
          if (rest + dy < highest) highest = rest + dy;
        }
      }
      return rest - highest;
    }

    testWidgets('a square done while he waits down there: the mind hops and '
        'praises, and the foot does both, in the pose the mind is in',
        (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll, live: true));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      await tester.pumpWidget(page(scroll: scroll, live: true, greens: 1));
      await tester.pump();
      expect(await hopHeight(tester, 30), greaterThan(10));
      expect(tester.takeException(), isNull);
      expect(footBubble(), findsOneWidget);
      expect(ledgeBubble(), findsNothing);
      expect(tester.widget<Sprout>(bottomSprout).pose,
          SproutPose.threeQuarterWave);
      expect(stage.echo.mood, SproutPose.threeQuarterWave);
      // The body up top made no move of its own.
      expect(tester.widget<Sprout>(ledgeSprout).controller, isNull);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('tapped down there, he laughs down there, face and all',
        (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      final s = tester.getRect(bottomSprout);
      await tester.tapAt(Offset(s.center.dx, bar(tester).top - 24));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<Sprout>(bottomSprout).pose, SproutPose.laugh);
      // Where he stands goes by his mood, not a laugh: he does not move.
      expect(tester.getRect(bottomSprout).center.dx,
          moreOrLessEquals(s.center.dx, epsilon: 0.01));
      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(tester.widget<Sprout>(bottomSprout).pose, SproutPose.frontWave);
    });

    testWidgets('in Arabic he faces into the page (mirrored); in English, as '
        'drawn', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      expect(tester.widget<Sprout>(bottomSprout).mirror, isTrue);
      await lineAt(tester, scroll, 300);
      await tester.pumpWidget(page(scroll: scroll, locale: const Locale('en')));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      expect(tester.widget<Sprout>(bottomSprout).mirror, isFalse);
    });

    testWidgets('a line said on the edge does not follow him down, and one '
        'said down there does not follow him up', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 300);
      await tester.tapAt(tester.getCenter(ledgeSprout) + const Offset(0, -12));
      await tester.pump();
      await tester.pump();
      expect(tickleLines(ar), contains(stage.speech.value));
      await lineAt(tester, scroll, 40, settle: false);
      for (var t = 0; t < 30; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(footBubble(), findsNothing);
      }
      expect(stage.speech.value, isNull);
      final s = tester.getRect(bottomSprout);
      await tester.tapAt(Offset(s.center.dx, bar(tester).top - 24));
      await tester.pump();
      await tester.pump();
      expect(tickleLines(ar), contains(stage.speech.value));
      await lineAt(tester, scroll, 300);
      expect(stage.speech.value, isNull);
      expect(ledgeBubble(), findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('asleep (02:00, nothing done), he sleeps on his edge and does '
        'not come down', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(
        page(scroll: scroll, clock: () => DateTime(2026, 9, 29, 2)),
      );
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 20);
      expect(stage.atBottom, isFalse);
      expect(bottomSprout, findsNothing);
    });

    testWidgets('woken down there by the first square of the small hours, he '
        'comes down with its praise', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      DateTime night() => DateTime(2026, 9, 29, 2);
      await tester.pumpWidget(page(scroll: scroll, live: true, clock: night));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 20);
      expect(stage.atBottom, isFalse);
      await tester.pumpWidget(
        page(scroll: scroll, live: true, clock: night, greens: 1),
      );
      await tester.pump();
      await tester.pump();
      expect(stage.atBottom, isTrue);
      expect(stage.speech.value, isNotNull);
      // Shown once he is up (a spring's clock starts on its first frame).
      for (var t = 0; t < 30; t++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(footBubble(), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('the day made perfect after bedtime, down there: he says it '
        'down there, then goes up to sleep on his edge', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      DateTime late() => DateTime(2026, 9, 29, 21, 30);
      await tester.pumpWidget(
        page(scroll: scroll, live: true, clock: late, greens: 9),
      );
      await tester.pumpAndSettle(const Duration(seconds: 4));
      await lineAt(tester, scroll, 20);
      expect(stage.atBottom, isTrue);
      await tester.pumpWidget(page(
        scroll: scroll,
        live: true,
        clock: late,
        greens: 10,
        perfectDay: true,
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(stage.atBottom, isTrue, reason: 'stays for his words');
      expect(
        find.descendant(
          of: footBubble(),
          matching: find.text('${ar.sproutPerfectDay}\n'
              '${ar.sproutPerfectDayBlessing}'),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(stage.atBottom, isFalse, reason: 'then asleep on his edge');
      expect(bottomSprout, findsNothing);
    });

    testWidgets('the bar\'s one-time hint: he goes back up, and comes down '
        'after', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      await tester.pumpWidget(page(scroll: scroll, hint: true));
      await tester.pumpAndSettle();
      expect(stage.atBottom, isFalse);
      expect(bottomSprout, findsNothing);
      expect(tucked(tester), isFalse);
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      expect(stage.atBottom, isTrue);
      expect(bottomSprout, findsOneWidget);
    });
  });

  group('the way back, frame by frame', () {
    testWidgets('scrolled up: the foot ducks first, the edge climbs 90ms on, '
        'never two of him', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      scroll.jumpTo(line - 300);
      await tester.pump();
      await tester.pump();
      var both = false;
      var sawDuck = false;
      for (var t = 0; t < 60; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        final top = upTop(tester);
        final foot = downHere(tester);
        if (t < 4) expect(top, lessThan(1), reason: 'frame $t');
        if (foot > 1 && foot < peek - 1) sawDuck = true;
        if (top > 12 && foot > 12) both = true;
      }
      expect(sawDuck, isTrue);
      expect(both, isFalse);
      await tester.pumpAndSettle();
      expect(upTop(tester), moreOrLessEquals(peek, epsilon: 0.05));
    });

    testWidgets('turned back mid-duck at the foot: straight back up there, '
        'no blink', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      scroll.jumpTo(line - 200);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final dipped = downHere(tester);
      expect(dipped, greaterThan(1));
      expect(dipped, lessThan(peek - 1));
      scroll.jumpTo(line - 40);
      await tester.pump();
      await tester.pump();
      var lowest = dipped;
      for (var t = 0; t < 40; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        lowest = math.min(lowest, downHere(tester));
      }
      expect(lowest, greaterThan(0), reason: 'never gone in between');
      await tester.pumpAndSettle();
      expect(downHere(tester), moreOrLessEquals(peek, epsilon: 0.05));
    });

    testWidgets('Reduce Motion, both ways: a fade in place, never both of him',
        (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll, reduceMotion: true));
      await tester.pumpAndSettle();
      scroll.jumpTo(line - 40);
      await tester.pump();
      await tester.pump();
      expect(tucked(tester), isTrue, reason: 'gone up top at once');
      await tester.pumpAndSettle();
      scroll.jumpTo(line - 300);
      await tester.pump();
      await tester.pump();
      for (var t = 0; t < 16; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        final foot = bottomSprout.evaluate().isEmpty
            ? 0.0
            : tester
                .widget<Opacity>(find
                    .ancestor(of: bottomSprout, matching: find.byType(Opacity))
                    .first)
                .opacity;
        if (foot > 0) {
          expect(upTop(tester), 0, reason: 'frame $t: both at once');
        } else {
          // Up top at once, whole, no climb.
          expect(upTop(tester), anyOf(0, moreOrLessEquals(peek, epsilon: 0.05)));
        }
      }
      await tester.pumpAndSettle();
      expect(upTop(tester), moreOrLessEquals(peek, epsilon: 0.05));
    });
  });

  group('pop-ups, frame by frame', () {
    double standLine(WidgetTester tester) =>
        tester.getRect(bottomSprout).bottom - 26.56;

    testWidgets('he rises with the bar and steps down with it: no jumps',
        (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      final messenger =
          ScaffoldMessenger.of(tester.element(find.byKey(const Key('board'))));
      messenger.showOne(const SnackBar(
        content: Text('يومك انحسب في سلسلتك.'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: Duration(seconds: 3),
      ));
      await tester.pump();
      final barTop = bar(tester).top;
      var last = standLine(tester);
      var between = 0;
      // The bar's own edge grows by up to about 16pt a frame at 60Hz; he
      // rises no faster than it does.
      for (var t = 0; t < 24; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        final now = standLine(tester);
        expect((now - last).abs(), lessThan(18), reason: 'frame $t jumped');
        if (now < barTop - 1 && now > barTop - 63) between++;
        last = now;
      }
      expect(between, greaterThanOrEqualTo(3), reason: 'rises, not snaps');
      messenger.hideCurrentSnackBar();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(standLine(tester), lessThan(barTop - 30),
          reason: 'still on the bar as it starts to fade');
      for (var t = 0; t < 20; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        final now = standLine(tester);
        expect((now - last).abs(), lessThan(18), reason: 'frame $t dropped');
        last = now;
      }
      await tester.pumpAndSettle();
      expect(standLine(tester), moreOrLessEquals(barTop, epsilon: 0.05));
    });

    testWidgets('swiped down: his cut never hangs above the bar\'s surface',
        (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      ScaffoldMessenger.of(tester.element(find.byKey(const Key('board'))))
          .showOne(const SnackBar(
        content: Text('swipe me'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ));
      await tester.pumpAndSettle();
      final g =
          await tester.startGesture(tester.getCenter(find.text('swipe me')));
      // The frame the drag takes hold, the surface jumps by however far the
      // finger went before it did; nothing can see that coming. From then
      // on he steps ahead of it.
      for (var i = 0; i < 8; i++) {
        await g.moveBy(const Offset(0, 6));
        await tester.pump(const Duration(milliseconds: 16));
        final surface = tester.getRect(find
            .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
            .first);
        if (i < 2) continue;
        expect(standLine(tester), greaterThanOrEqualTo(surface.top - 0.5),
            reason: 'step $i');
      }
      await g.moveBy(const Offset(0, 80));
      await g.up();
      await tester.pumpAndSettle();
    });
  });

  test('kSproutBottomHostHeight holds the peek, a jump, the highest ride and '
      'a bubble', () {
    expect(kSproutBottomHostHeight, greaterThanOrEqualTo(180 + 52 + 27 + 50));
    expect(debugDefaultTargetPlatformOverride, isNull);
  });

  group('making way for the names', () {
    // Each row's tile-and-name box sits in the middle of a 61pt pitch, like
    // the Grid's names. Doum stands all up (sunk 0), with just his leaves
    // over the bar (39) or out of sight behind it (58).
    const leavesSink = 39.0;
    const awaySink = 58.0;
    const heights = [0.0, leavesSink, awaySink];

    double sunk(WidgetTester tester) =>
        tester.getRect(bottomSprout).bottom - (bar(tester).top + 26.56);

    Future<void> still(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    /// The labels that can be read over [edge] (the bar's top unless given):
    /// on screen above it, or showing 6pt or more over it.
    List<Rect> readable(WidgetTester tester, {double? edge}) {
      final at = edge ?? bar(tester).top;
      return [
        for (final e in find.byType(SproutKeepClear).evaluate())
          if (e.renderObject case final RenderBox box
              when box.attached && box.hasSize)
            box.localToGlobal(Offset.zero) & box.size,
      ].where((r) => r.top < at && (r.bottom <= at || at - r.top >= 6))
          .toList();
    }

    /// Where the top of his drawing is painted: his box, moved by his hop.
    double paintedTop(WidgetTester tester) {
      final box = tester.getRect(bottomSprout);
      var top = box.top;
      for (final e in find
          .descendant(of: bottomSprout, matching: find.byType(Transform))
          .evaluate()) {
        final m = (e.widget as Transform).transform;
        final lifted =
            box.top + m.getTranslation().y - (m.storage[5] - 1) * box.height;
        if (lifted < top) top = lifted;
      }
      return top;
    }

    /// Nothing of him over a label that can be read over [edge].
    void clearOfNames(WidgetTester tester, String when,
        {double? top, double? edge}) {
      final body = tester.getRect(bottomSprout);
      final line = edge ?? bar(tester).top;
      final from = top ?? body.top;
      if (from >= line) return;
      final art =
          Rect.fromLTRB(body.center.dx - 33, from, body.center.dx + 33, line);
      for (final r in readable(tester, edge: line)) {
        expect(art.overlaps(r), isFalse, reason: '$when: $art over $r');
      }
    }

    /// Moves the page on, a few points at a time, until he stands at
    /// [target]; false if he never does.
    Future<bool> findSpot(
      WidgetTester tester,
      ScrollController scroll,
      double target,
    ) async {
      for (var px = scroll.offset;
          px <= scroll.position.maxScrollExtent;
          px += 3) {
        scroll.jumpTo(px);
        await still(tester);
        if ((sunk(tester) - target).abs() < 0.2) return true;
      }
      return false;
    }

    Future<ScrollController> open(
      WidgetTester tester, {
      bool reduceMotion = false,
      Locale locale = const Locale('ar'),
      double label = 22,
    }) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(
        scroll: scroll,
        labels: true,
        label: label,
        reduceMotion: reduceMotion,
        locale: locale,
      ));
      await tester.pumpAndSettle();
      await lineAt(tester, scroll, 40);
      await still(tester);
      expect(stage.atBottom, isTrue);
      return scroll;
    }

    /// Stops a moving page for good, the way a finger lets go: the page's
    /// scroll turns off, and he has not looked at the room yet.
    void pageStops() {
      stage.scrolling.value = true;
      stage.scrolling.value = false;
    }

    for (final (code, label) in const [
      ('ar', 22.0),
      ('en', 22.0),
      ('ar', 26.45),
      ('ar', 53.0),
    ]) {
      testWidgets('$code, names $label tall: wherever the page stops, he '
          'hides no name, at one of his three heights', (tester) async {
        final scroll =
            await open(tester, locale: Locale(code), label: label);
        final seen = <double>{};
        for (var px = scroll.offset;
            px <= scroll.position.maxScrollExtent;
            px += 4) {
          scroll.jumpTo(px);
          await still(tester);
          final down = sunk(tester);
          final level = heights.firstWhere(
            (l) => (down - l).abs() < 0.2,
            orElse: () => -1,
          );
          expect(level, isNot(-1), reason: 'at $px he is $down down');
          seen.add(level);
          clearOfNames(tester, 'at $px');
        }
        expect(seen, contains(0.0));
        expect(seen, contains(awaySink));
        // The page's end: all of him.
        expect(sunk(tester), moreOrLessEquals(0, epsilon: 0.1));
      });
    }

    testWidgets('while a finger moves the page he holds his height, rows '
        'passing behind him; let go, and he makes way', (tester) async {
      final scroll = await open(tester);
      // The page's end, all of him up; then the finger brings rows back
      // down behind him.
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await still(tester);
      expect(sunk(tester), moreOrLessEquals(0, epsilon: 0.01));
      final start = scroll.offset;
      final g = await tester.startGesture(const Offset(250, 400));
      var behind = false;
      for (var i = 0; i < 30; i++) {
        await g.moveBy(const Offset(0, 6));
        await tester.pump(const Duration(milliseconds: 16));
        expect(sunk(tester), moreOrLessEquals(0, epsilon: 0.01),
            reason: 'step $i');
        final body = tester.getRect(bottomSprout);
        behind |= readable(tester).any((r) =>
            r.bottom > body.top && r.left < body.right && r.right > body.left);
      }
      expect(scroll.offset, lessThan(start - 100));
      expect(behind, isTrue, reason: 'a name went behind him');
      // A finger held still on the page is still moving it, as far as the
      // page is concerned: he waits for it to let go.
      await tester.pump(const Duration(seconds: 1));
      expect(sunk(tester), moreOrLessEquals(0, epsilon: 0.01));
      await g.up();
      await still(tester);
      clearOfNames(tester, 'let go');
    });

    testWidgets('a finger that lifts to flick again does not move him; '
        'once the page rests, he makes way', (tester) async {
      final scroll = await open(tester);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await still(tester);
      Future<void> drag() async {
        final g = await tester.startGesture(const Offset(250, 400));
        for (var i = 0; i < 12; i++) {
          await g.moveBy(const Offset(0, 5));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g.up();
      }

      // Scrolled until names are behind him, then two quick drags.
      var tries = 0;
      do {
        await drag();
        await tester.pump(const Duration(milliseconds: 100));
        expect(sunk(tester), moreOrLessEquals(0, epsilon: 0.01),
            reason: '100ms after a finger lifts, he has not moved');
        tries++;
      } while (tries < 8 &&
          readable(tester).every((r) => r.bottom < bar(tester).top - 60));
      await drag();
      await tester.pump(const Duration(milliseconds: 80));
      expect(sunk(tester), moreOrLessEquals(0, epsilon: 0.01));
      await still(tester);
      clearOfNames(tester, 'rested');
      expect(sunk(tester), greaterThan(1), reason: 'he made way');
    });

    testWidgets('a hop with nothing said, while he makes way, is let go: '
        'nothing of him rises over a name', (tester) async {
      final scroll = await open(tester);
      for (final height in [awaySink, leavesSink]) {
        expect(await findSpot(tester, scroll, height), isTrue);
        stage.echo.moves.hop();
        for (var t = 0; t < 45; t++) {
          await tester.pump(const Duration(milliseconds: 16));
          clearOfNames(tester, 'at $height, frame $t',
              top: paintedTop(tester));
        }
        await still(tester);
        expect(sunk(tester), moreOrLessEquals(height, epsilon: 0.1));
        scroll.jumpTo(line - 40);
        await still(tester);
      }
    });

    testWidgets('all up with room over his head, his hop still plays; the '
        'big jump too where it clears the names', (tester) async {
      final scroll = await open(tester);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await still(tester);
      expect(sunk(tester), moreOrLessEquals(0, epsilon: 0.01));
      final rest = paintedTop(tester);
      stage.echo.moves.hop();
      var highest = rest;
      for (var t = 0; t < 45; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        highest = math.min(highest, paintedTop(tester));
        clearOfNames(tester, 'hop frame $t', top: paintedTop(tester));
      }
      expect(rest - highest, greaterThan(10));
      await still(tester);
      stage.echo.moves.celebrate();
      for (var t = 0; t < 75; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        clearOfNames(tester, 'jump frame $t', top: paintedTop(tester));
      }
      await still(tester);
    });

    testWidgets('a tap on his leaves: he pops up laughing and stays up for '
        'his words, then makes way again; the name under him is not '
        'opened', (tester) async {
      final scroll = await open(tester);
      expect(await findSpot(tester, scroll, leavesSink), isTrue);
      final body = tester.getRect(bottomSprout);
      await tester.tapAt(Offset(body.center.dx, bar(tester).top - 5));
      final words = find.descendant(
        of: find.byType(SproutBottomPeek),
        matching: find.byType(SproutBubble),
      );
      // Up, laughing.
      for (var t = 0; t < 30; t++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(sunk(tester).abs(), lessThan(3));
      expect(tester.widget<Sprout>(bottomSprout).pose, SproutPose.laugh);
      // Still up while his words show, the laugh over (2.5s in).
      for (var t = 0; t < 128; t++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(sunk(tester), moreOrLessEquals(0, epsilon: 0.1));
      expect(words, findsOneWidget);
      // His words last 3s, and 350ms after them he makes way.
      for (var t = 0; t < 70; t++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(sunk(tester), moreOrLessEquals(leavesSink, epsilon: 0.1));
      await tester.pumpAndSettle();
      expect(sunk(tester), moreOrLessEquals(leavesSink, epsilon: 0.1));
      expect(nameTaps, 0);
      expect(nameHolds, 0);
    });

    for (final height in heights) {
      testWidgets('a pop-up carries him from $height down: every frame, no '
          'name that stays in view over it is hidden', (tester) async {
        final scroll = await open(tester);
        if (height == 0) {
          scroll.jumpTo(scroll.position.maxScrollExtent - 40);
          await still(tester);
        }
        if ((sunk(tester) - height).abs() > 0.2) {
          expect(await findSpot(tester, scroll, height), isTrue);
        }
        final messenger = ScaffoldMessenger.of(
            tester.element(find.byKey(const Key('board'))));
        messenger.showSnackBar(const SnackBar(content: Text('x')));
        await tester.pump();
        // Where the pop-up will stand: laid out full size from its start.
        final surface = find.descendant(
            of: find.byType(SnackBar), matching: find.byType(Material));
        await tester.pump();
        final top = tester.getRect(surface.first).top;
        for (var t = 0; t < 40; t++) {
          await tester.pump(const Duration(milliseconds: 16));
          clearOfNames(tester, 'rising, frame $t', edge: top);
        }
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        if (find.byType(SnackBar).evaluate().isNotEmpty) {
          clearOfNames(tester, 'up', edge: top);
        }
        messenger.hideCurrentSnackBar();
        for (var t = 0; t < 40; t++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (find.byType(SnackBar).evaluate().isEmpty) {
            clearOfNames(tester, 'going, frame $t');
          }
        }
        await still(tester);
        clearOfNames(tester, 'after');
      });
    }

    Finder snackSurface() => find.descendant(
        of: find.byType(SnackBar), matching: find.byType(Material));

    /// The line he stands on (his cut): the bar's edge, or a pop-up's.
    double standOn(WidgetTester tester) {
      final clip = tester.renderObject<RenderClipRect>(find.descendant(
        of: find.byType(SproutBottomPeek),
        matching: find.byType(ClipRect),
      ));
      return clip
          .localToGlobal(Offset(0, clip.clipper!.getClip(clip.size).bottom))
          .dy;
    }

    /// A still page where all of him fits over the bar, but a name sits
    /// 70 to 110pt up: just over where a pop-up will lift him, so on it he
    /// has to sink.
    Future<void> rideSpot(WidgetTester tester, ScrollController scroll) async {
      for (var px = scroll.position.maxScrollExtent; px > 0; px -= 3) {
        scroll.jumpTo(px);
        await still(tester);
        if (sunk(tester).abs() > 0.2) continue;
        final edge = bar(tester).top;
        final above = readable(tester).where((r) => r.bottom <= edge);
        if (above.isEmpty) continue;
        final gap = edge - above.map((r) => r.bottom).reduce(math.max);
        if (gap > 70 && gap < 110) return;
      }
      fail('no such spot on this page');
    }

    testWidgets('a ride cut short by the page moving: once it rests he goes '
        'the rest of the way, never left part-way in front of a name',
        (tester) async {
      final scroll = await open(tester);
      for (final height in [0.0, leavesSink]) {
        if (height == 0) {
          scroll.jumpTo(scroll.position.maxScrollExtent - 40);
          await still(tester);
        }
        if ((sunk(tester) - height).abs() > 0.2) {
          expect(await findSpot(tester, scroll, height), isTrue);
        }
        final messenger = ScaffoldMessenger.of(
            tester.element(find.byKey(const Key('board'))));
        messenger.showSnackBar(const SnackBar(content: Text('x')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        // A finger lands on the page mid-ride.
        stage.scrolling.value = true;
        for (var t = 0; t < 20; t++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        stage.scrolling.value = false;
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        final top = tester.getRect(snackSurface().first).top;
        clearOfNames(tester, 'from $height, rested on the pop-up', edge: top);
        messenger.hideCurrentSnackBar();
        await tester.pump(const Duration(milliseconds: 16));
        stage.scrolling.value = true;
        for (var t = 0; t < 30; t++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        stage.scrolling.value = false;
        await still(tester);
        clearOfNames(tester, 'from $height, rested after it');
        scroll.jumpTo(line - 40);
        await still(tester);
      }
    });

    testWidgets('he starts making way in the middle of a ride: a smooth '
        'duck, no jump', (tester) async {
      final scroll = await open(tester);
      await rideSpot(tester, scroll);
      final messenger = ScaffoldMessenger.of(
          tester.element(find.byKey(const Key('board'))));
      // The page is moving as the pop-up comes, and rests part-way through.
      stage.scrolling.value = true;
      await tester.pump();
      messenger.showSnackBar(const SnackBar(content: Text('x')));
      await tester.pump();
      stage.scrolling.value = false;
      // His sink against the pop-up's line: the ride itself is not his.
      double own() => tester.getRect(bottomSprout).bottom -
          (standOn(tester) + 26.56);
      var last = own();
      var most = last;
      for (var t = 0; t < 40; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        final now = own();
        expect(now - last, lessThan(14), reason: 'frame $t dropped');
        last = now;
        most = math.max(most, now);
      }
      expect(most, greaterThan(20), reason: 'he did sink on the pop-up');
      await tester.pumpAndSettle();
      clearOfNames(tester, 'up',
          edge: tester.getRect(snackSurface().first).top);
      messenger.hideCurrentSnackBar();
      await still(tester);
    });

    testWidgets('back from stepping aside while a pop-up is up: he stands at '
        'the height the room over the pop-up allows, from his first frame',
        (tester) async {
      final scroll = await open(tester);
      await rideSpot(tester, scroll);
      final messenger = ScaffoldMessenger.of(
          tester.element(find.byKey(const Key('board'))));
      messenger.showSnackBar(const SnackBar(
        content: Text('x'),
        duration: Duration(seconds: 20),
      ));
      await tester.pump();
      await tester.pumpAndSettle();
      final top = tester.getRect(snackSurface().first).top;
      aside.value = true;
      await tester.pumpAndSettle();
      expect(stage.atBottom, isFalse);
      aside.value = false;
      for (var t = 0; t < 60; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (bottomSprout.evaluate().isEmpty) continue;
        clearOfNames(tester, 'frame $t', edge: top);
      }
      expect(stage.atBottom, isTrue);
      messenger.hideCurrentSnackBar();
      await still(tester);
    });

    testWidgets('while he is out of sight a pop-up carries him hidden, and '
        'he is still out of sight after it', (tester) async {
      final scroll = await open(tester);
      expect(await findSpot(tester, scroll, awaySink), isTrue);
      ScaffoldMessenger.of(tester.element(find.byKey(const Key('board'))))
          .showSnackBar(const SnackBar(content: Text('x')));
      for (var t = 0; t < 40; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        final snack = find.descendant(
            of: find.byType(SnackBar), matching: find.byType(Material));
        if (snack.evaluate().isEmpty) continue;
        final surface = tester.getRect(snack.first);
        expect(tester.getRect(bottomSprout).top,
            greaterThanOrEqualTo(math.min(surface.top, bar(tester).top) - 0.5),
            reason: 'frame $t: nothing of him above the pop-up');
      }
      ScaffoldMessenger.of(tester.element(find.byKey(const Key('board'))))
          .hideCurrentSnackBar();
      await still(tester);
      expect(sunk(tester), moreOrLessEquals(awaySink, epsilon: 0.1));
    });

    testWidgets('Reduce Motion: a new height is taken at once', (tester) async {
      final scroll = await open(tester, reduceMotion: true);
      expect(await findSpot(tester, scroll, leavesSink), isTrue);
      // On, to where he needs another height.
      var px = scroll.offset;
      double? before;
      while (px < scroll.position.maxScrollExtent) {
        px += 3;
        before = sunk(tester);
        scroll.jumpTo(px);
        await tester.pump();
        await tester.pump();
        if ((sunk(tester) - before).abs() > 0.2) break;
      }
      final now = sunk(tester);
      expect(now, isNot(moreOrLessEquals(before!, epsilon: 0.2)));
      expect(heights.any((l) => (now - l).abs() < 0.01), isTrue,
          reason: 'no frame in between: $now');
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a screen reader finds him while any of him shows, and not '
        'while he is out of sight', (tester) async {
      final semantics = tester.ensureSemantics();
      final scroll = await open(tester);
      final name = ar.sproutName;
      expect(await findSpot(tester, scroll, leavesSink), isTrue);
      expect(find.bySemanticsLabel(name), findsOneWidget);
      scroll.jumpTo(line - 40);
      await still(tester);
      expect(await findSpot(tester, scroll, awaySink), isTrue);
      expect(find.bySemanticsLabel(name), findsNothing);
      semantics.dispose();
    });

    testWidgets('back from stepping aside, he comes straight to the height '
        'the room allows, never all up first', (tester) async {
      final scroll = await open(tester);
      expect(await findSpot(tester, scroll, awaySink), isTrue);
      aside.value = true;
      await tester.pumpAndSettle();
      expect(stage.atBottom, isFalse);
      aside.value = false;
      for (var t = 0; t < 60; t++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (bottomSprout.evaluate().isEmpty) continue;
        expect(sunk(tester), greaterThan(awaySink - 0.5),
            reason: 'frame $t');
      }
      await still(tester);
      expect(stage.atBottom, isTrue);
      expect(sunk(tester), moreOrLessEquals(awaySink, epsilon: 0.1));
    });

    testWidgets('gone while he waits for the page to rest: nothing is left '
        'running', (tester) async {
      final scroll = await open(tester);
      expect(await findSpot(tester, scroll, 0), isTrue);
      scroll.jumpTo(line - 40);
      await tester.pump();
      pageStops();
      await tester.pump(const Duration(milliseconds: 50));
      // Still waiting: the page has not been at rest for long enough.
      expect(sunk(tester), moreOrLessEquals(0, epsilon: 0.1));
      await tester.pumpWidget(const SizedBox());
      // No more time passes: a timer he left behind fails this test.
    });

    testWidgets('down from the board\'s edge under a finger: all of him '
        'arrives, then he makes way once the page is let go', (tester) async {
      phone(tester);
      final scroll = ScrollController();
      await tester.pumpWidget(page(scroll: scroll, labels: true));
      await tester.pumpAndSettle();
      final g = await tester.startGesture(const Offset(250, 600));
      var climbing = false;
      for (var i = 0; i < 90; i++) {
        await g.moveBy(const Offset(0, -5));
        await tester.pump(const Duration(milliseconds: 16));
        if (bottomSprout.evaluate().isEmpty) continue;
        final down = sunk(tester);
        if (!climbing && down < 8) climbing = true;
        if (climbing) {
          // All up, give or take his landing bounce: never down to his
          // leaves while the finger moves.
          expect(down.abs(), lessThan(8), reason: 'step $i');
        }
      }
      expect(climbing, isTrue);
      // The finger stays down: he settles all up.
      for (var t = 0; t < 40; t++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(sunk(tester), moreOrLessEquals(0, epsilon: 0.1));
      await g.up();
      await still(tester);
      clearOfNames(tester, 'let go');
    });
  });
}
