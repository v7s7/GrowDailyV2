// Doum on the real Grid, inside HomeShell with its real bottom bar, on a
// board long enough to scroll: scrolled down to the last rows he waits above
// the bar, over the habit names and never over a square, reacts there to a
// square done down there, rides a pop-up, and is back on the board's edge
// when the page is back up. Once the page is still he never hides a habit's
// name or its tile, in Arabic or in English, at any point of the page, and
// is no lower than that needs. sprout_bottom_test.dart pins the rules on a
// page of its own; this pins them against what the Grid really draws.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/l10n/wording_edits.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/providers/get_started_checklist_provider.dart';
import 'package:grow_daily_v2/features/dashboard/widgets/reaction_overlays.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/grid/screens/grid_screen.dart';
import 'package:grow_daily_v2/features/mascot/day_card_sprout.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';
import 'package:grow_daily_v2/features/mascot/sprout_ledge.dart';
import 'package:grow_daily_v2/shared/widgets/category_icon.dart';
import 'package:grow_daily_v2/shared/widgets/game_nav_bar.dart';
import 'package:grow_daily_v2/shared/widgets/home_shell.dart';

import '../../helpers/landing_harness.dart';

/// 14:00 of the real day, the minutes still running.
DateTime _afternoonToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 14, now.minute, now.second);
}

void main() {
  late LandingHarness h;

  // Twelve daily habits, one a day each, none a quit or a quota (either
  // would split the board or rest a square): enough rows to scroll a phone.
  const ids = [
    'quran_daily_page',
    'quran_memorization',
    'morning_athkar',
    'evening_athkar',
    'daily_sadaqah',
    'sleep_schedule',
    'deep_work_block',
    'inbox_zero',
    'daily_planning',
    'no_phone_morning',
    'cold_shower',
    'wake_early',
  ];

  setUp(() async {
    h = LandingHarness();
    await h.prepare(
      activeCatalogIds: ids,
      extraOverrides: [
        getStartedDismissedProvider.overrideWith((ref) => true),
        // Awake at any hour the suite runs (asleep, he keeps to the board's
        // edge, which sprout_bottom_test pins on its own): the ledge reads
        // his mood's hour from this clock, held at 14:00 of the real day so
        // today stays today. The edits below alone left him asleep from
        // 23:00, the latest bedtime they allow, and a perfect day then took
        // him off the foot of the page.
        dayClockSourceProvider.overrideWithValue(_afternoonToday),
      ],
    );
    DayCardSprout.greetedThisLaunch = true;
    WordingEditsStore.debugPublish(const WordingEdits(
      pet: PetEdits(numbers: {'wakeHour': 0, 'bedtimeHour': 23}),
    ));
    addTearDown(() => WordingEditsStore.debugPublish(WordingEdits.empty));
  });
  tearDown(() => h.dispose());

  void phone(double width, [double height = 874]) {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = Size(width * 3, height * 3);
    view.devicePixelRatio = 3;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  }

  final table = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_GridTable',
    skipOffstage: false,
  );
  final bottomSprout = find.descendant(
    of: find.byType(SproutBottomPeek),
    matching: find.byType(Sprout),
  );
  final ledgeSprout = find.descendant(
    of: find.byType(SproutLedge, skipOffstage: false),
    matching: find.byType(Sprout, skipOffstage: false),
    skipOffstage: false,
  );

  // The drawing's half width toward the squares, per pose (_halfArt).
  const halfArt = {
    SproutPose.frontWave: 31.6,
    SproutPose.threeQuarterWave: 29.8,
    SproutPose.laugh: 33.0,
    SproutPose.happySparkles: 35.1,
  };

  // How far he sinks to make way: to his leaves, and to just their tips
  // (never less of him: the bar is never left empty).
  const leavesSink = 39.0;
  const tipsSink = 45.0;

  ScrollPosition page(WidgetTester tester) => tester
      .state<ScrollableState>(find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first)
      .position;

  double barTop(WidgetTester tester) =>
      tester.getRect(find.byType(GameNavBar)).top;

  SproutStage stage(WidgetTester tester) =>
      tester.widget<SproutBottomPeek>(find.byType(SproutBottomPeek)).stage;

  /// How far below where he stands all up he is: 0 all up, then his leaves'
  /// sink, then out of sight. By his feet, the same for every pose.
  double sunk(WidgetTester tester) =>
      tester.getRect(bottomSprout).bottom - (barTop(tester) + 26.56);

  /// Lets the page be still long enough for him to stand as tall as he may
  /// (he stands up 450ms after the page is still).
  Future<void> still(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 600));
    await h.settle(tester);
  }

  /// Every habit's tile-and-name box on screen that can be read: above the
  /// bar, or showing 6pt or more over it (a badge's reach included).
  List<Rect> readable(WidgetTester tester) {
    final bar = barTop(tester);
    final out = <Rect>[];
    for (final e in find.byType(SproutKeepClear).evaluate()) {
      final box = e.renderObject! as RenderBox;
      if (!box.attached || !box.hasSize) continue;
      final above = (e.widget as SproutKeepClear).reachAbove;
      final r = Rect.fromLTRB(
        box.localToGlobal(Offset.zero).dx,
        box.localToGlobal(Offset.zero).dy - above,
        box.localToGlobal(box.size.bottomRight(Offset.zero)).dx,
        box.localToGlobal(box.size.bottomRight(Offset.zero)).dy,
      );
      if (r.top >= bar) continue;
      if (r.bottom > bar && bar - r.top < 6) continue;
      out.add(r);
    }
    return out;
  }

  /// What a person reads, found on its own: each habit's tile (the 22pt
  /// square around its category icon) once 6pt of it shows over the bar,
  /// and each line of each name once half of that line does.
  List<Rect> ink(WidgetTester tester) {
    final bar = barTop(tester);
    final out = <Rect>[];
    final names = find.byType(SproutKeepClear);
    for (final e in find
        .descendant(of: names, matching: find.byType(CategoryIcon))
        .evaluate()) {
      final box = e.renderObject! as RenderBox;
      final icon = box.localToGlobal(Offset.zero) & box.size;
      final tile = Rect.fromCenter(center: icon.center, width: 22, height: 22);
      if (tile.top < bar && bar - tile.top >= 6) out.add(tile);
    }
    for (final e in find
        .descendant(of: names, matching: find.byType(RichText))
        .evaluate()) {
      final text = e.renderObject! as RenderParagraph;
      final origin = text.localToGlobal(Offset.zero);
      for (final line in text.getBoxesForSelection(TextSelection(
        baseOffset: 0,
        extentOffset: text.text.toPlainText().length,
      ))) {
        final r = line.toRect().shift(origin);
        if (r.top < bar && bar - r.top >= r.height / 2) out.add(r);
      }
    }
    return out;
  }

  /// Scrolls the page so the board's top edge sits [y] below the top of the
  /// Grid's scroll view.
  Future<void> lineAt(WidgetTester tester, double y) async {
    final view = tester.getRect(find.byType(CustomScrollView)).top;
    final line =
        tester.getRect(find.byType(SproutLedge, skipOffstage: false)).bottom;
    final pos = page(tester);
    pos.jumpTo((pos.pixels + (line - view) - y)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent)
        .toDouble());
    await tester.pump();
    await h.settle(tester);
  }

  /// Every square on screen (labelled cells that are square and inside a
  /// board), as grid_square_alignment_test finds them.
  List<Rect> squares(WidgetTester tester) {
    final boards = table.evaluate().map((e) {
      final box = e.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    }).toList();
    final out = <Rect>[];
    for (final element
        in find.bySemanticsLabel(RegExp('[,،]')).evaluate()) {
      final box = element.renderObject as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) continue;
      final r = box.localToGlobal(Offset.zero) & box.size;
      if ((r.width - r.height).abs() > 0.5 || r.width < 28) continue;
      if (!boards.any((b) => b.contains(r.center))) continue;
      out.add(r);
    }
    return out;
  }

  Future<void> open(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(h.app(
      home: const HomeShell(),
      locale: locale,
    ));
    await h.settle(tester);
  }

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final rtl = locale.languageCode == 'ar';
    testWidgets('${locale.languageCode}: down at the last rows he waits above '
        'the bar over the names, never over a square, then goes home',
        (tester) async {
      phone(402);
      await open(tester, locale);
      final pos = page(tester);
      expect(pos.maxScrollExtent, greaterThan(300),
          reason: 'the board must be long enough to scroll away from');
      expect(stage(tester).atBottom, isFalse);
      expect(bottomSprout, findsNothing);

      await lineAt(tester, 30);
      expect(stage(tester).atBottom, isTrue);
      expect(find.byType(DayCardSprout, skipOffstage: false), findsOneWidget);
      expect(bottomSprout, findsOneWidget);

      // The last rows: the board ends above him, so all of him is up.
      pos.jumpTo(pos.maxScrollExtent);
      await still(tester);
      final bar = barTop(tester);
      final body = tester.getRect(bottomSprout);
      final pose = tester.widget<Sprout>(bottomSprout).pose;
      expect(pose, SproutPose.frontWave);
      // Standing behind the bar's edge: feet 26.56pt under it.
      expect(body.bottom, moreOrLessEquals(bar + 26.56, epsilon: 0.1));
      expect(body.top, lessThan(bar));

      // Over the names column of the board actually drawn.
      final board = tester.getRect(table.first);
      final names = namesColumnFromStart(board.width, rtl: rtl)!;
      final centre = rtl
          ? board.right - names.centre
          : board.left + names.centre;
      expect(body.center.dx, moreOrLessEquals(centre, epsilon: 0.1));
      // Nothing of his drawing over any square on screen.
      final half = halfArt[pose]!;
      final art = Rect.fromLTRB(
        body.center.dx - half,
        body.top,
        body.center.dx + half,
        bar,
      );
      final onScreen = squares(tester);
      expect(onScreen, isNotEmpty);
      for (final sq in onScreen) {
        expect(sq.overlaps(art), isFalse,
            reason: 'Doum ($art) over a square ($sq)');
      }

      // Back up: home on the edge, nothing at the foot.
      pos.jumpTo(0);
      await tester.pump();
      await h.settle(tester);
      expect(stage(tester).atBottom, isFalse);
      expect(bottomSprout, findsNothing);
      final ledge = tester.getRect(find.byType(SproutLedge));
      expect(tester.getRect(ledgeSprout).top, lessThan(ledge.top));
    });
  }

  testWidgets('a square done while he makes way: he pops up to say it, '
      'then makes way again', (tester) async {
    phone(402);
    await open(tester, const Locale('ar'));
    await lineAt(tester, 30);
    expect(stage(tester).atBottom, isTrue);
    // A still page with a habit's name right behind him: he is down.
    final pos = page(tester);
    var px = pos.pixels;
    while (sunk(tester) < 1 && px < pos.maxScrollExtent) {
      px = (px + 6).clamp(0, pos.maxScrollExtent).toDouble();
      pos.jumpTo(px);
      await still(tester);
    }
    expect(stage(tester).atBottom, isTrue);
    final low = sunk(tester);
    expect(low, greaterThan(1), reason: 'somewhere he makes way');

    final grid = h.container.read(weeklyGridProvider.notifier);
    final today = h.container
        .read(weeklyGridProvider)
        .days
        .firstWhere((d) => d.isSameDayAs(DateTime.now().effectiveDay));
    grid.setSquareStateOnly(ids.last, today, SquareState.complete);
    await tester.pump();
    final said = find.descendant(
      of: find.byType(SproutBottomPeek),
      matching: find.byType(SproutBubble),
    );
    // Up first, then the words.
    for (var t = 0; t < 60 && said.evaluate().isEmpty; t++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(said, findsOneWidget,
        reason: 'his praise is drawn at the foot, beside him');
    await tester.pump(const Duration(milliseconds: 600));
    expect(sunk(tester), moreOrLessEquals(0, epsilon: 0.5),
        reason: 'all of him up to talk');
    final bubble = tester.getRect(said);
    expect(bubble.bottom, moreOrLessEquals(barTop(tester) - 2, epsilon: 0.5));
    // And not up on the edge, off screen.
    expect(
      find.descendant(
        of: find.byType(SproutLedge, skipOffstage: false),
        matching: find.byType(SproutBubble, skipOffstage: false),
        skipOffstage: false,
      ),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 7));
    await still(tester);
    expect(said, findsNothing);
    // The line said, he makes way again: as low as before, the rows being
    // where they were.
    expect(sunk(tester), moreOrLessEquals(low, epsilon: 0.5));
  });

  testWidgets('the streak pop-up: he rides up on it, and down after',
      (tester) async {
    phone(402);
    await open(tester, const Locale('ar'));
    await lineAt(tester, 30);
    final pos = page(tester);
    pos.jumpTo(pos.maxScrollExtent);
    await still(tester);
    expect(sunk(tester), moreOrLessEquals(0, epsilon: 0.1));
    final bar = barTop(tester);
    showPerfectDaySnackBar(tester.element(find.byType(GridScreen)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump();
    final surface = tester.getRect(find
        .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
        .first);
    expect(tester.getRect(bottomSprout).bottom - 26.56,
        moreOrLessEquals(surface.top, epsilon: 0.5));
    await tester.pump(const Duration(seconds: 4));
    await h.settle(tester);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.getRect(bottomSprout).bottom - 26.56,
        moreOrLessEquals(bar, epsilon: 0.1));
  });

  testWidgets('selecting several habits keeps the same Doum, and he still '
      'follows the page down', (tester) async {
    phone(402);
    await open(tester, const Locale('ar'));
    final mind = find.byType(DayCardSprout, skipOffstage: false);
    final before = tester.state(mind);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await h.settle(tester);
    await tester.tap(find.text('تحديد متعدد'));
    await h.settle(tester);
    expect(
      find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_SelectionBar'),
      findsOneWidget,
      reason: 'selection mode is on',
    );
    // The bar above the board did not rebuild him from scratch: a new mind
    // would forget what he said and greet again.
    expect(identical(tester.state(mind), before), isTrue);

    await lineAt(tester, 30);
    expect(stage(tester).atBottom, isTrue);
    expect(bottomSprout, findsOneWidget);
    expect(identical(tester.state(mind), before), isTrue);

    page(tester).jumpTo(0);
    await tester.pump();
    await h.settle(tester);
    expect(stage(tester).atBottom, isFalse);
    expect(identical(tester.state(mind), before), isTrue);
  });

  /// Every stop of the page from where he comes down to its end, 5pt
  /// apart: he is at the height the rule gives for the page as drawn, and
  /// nothing he covers can be read. Returns how often each height came up.
  Future<Map<String, int>> sweep(WidgetTester tester) async {
    final pos = page(tester);
    await lineAt(tester, 30);
    expect(stage(tester).atBottom, isTrue);
    final counts = <String, int>{};
    for (var px = pos.pixels; px <= pos.maxScrollExtent + 0.01; px += 5) {
      pos.jumpTo(math.min(px, pos.maxScrollExtent));
      await still(tester);
      expect(stage(tester).atBottom, isTrue);
      final bar = barTop(tester);
      final body = tester.getRect(bottomSprout);
      final pose = tester.widget<Sprout>(bottomSprout).pose;
      final half = math.max(halfArt[pose]!, halfArt[SproutPose.laugh]!);
      final left = body.center.dx - half;
      final right = body.center.dx + half;
      // What the rule allows, from the page as drawn.
      var room = double.infinity;
      var across = false;
      for (final r in readable(tester)) {
        if (r.right <= left || r.left >= right) continue;
        if (r.bottom > bar) {
          across = true;
        } else {
          room = math.min(room, bar - r.bottom - 3);
        }
      }
      // How far over the bar his pose's box reaches, all up.
      final tall = body.height - 26.56;
      final expected = across
          ? 'tips'
          : room >= tall
              ? 'up'
              : room >= tall - leavesSink
                  ? 'leaves'
                  : 'tips';
      final down = sunk(tester);
      final String level;
      if (down.abs() < 0.2) {
        level = 'up';
      } else if ((down - leavesSink).abs() < 0.2) {
        level = 'leaves';
      } else if ((down - tipsSink).abs() < 0.2) {
        level = 'tips';
      } else {
        level = 'between: $down';
      }
      expect(level, expected, reason: 'at $px');
      counts[level] = (counts[level] ?? 0) + 1;
      // And, drawn: nothing of him over a tile or a line of a name that can
      // be read, found apart from what he measures; at his leaf tips, those
      // tips are all that stands over the bar.
      if (level == 'tips') {
        expect(bar - body.top, lessThanOrEqualTo(tall - tipsSink + 0.05),
            reason: 'at $px, more than his tips');
        expect(bar - body.top, greaterThan(4), reason: 'at $px, his tips');
      } else if (body.top < bar) {
        final art = Rect.fromLTRB(left, body.top, right, bar);
        for (final r in ink(tester)) {
          expect(art.overlaps(r), isFalse,
              reason: 'at $px, Doum $art over $r');
        }
      }
    }
    // The page's end is always his: all of him there.
    expect(sunk(tester), moreOrLessEquals(0, epsilon: 0.1));
    return counts;
  }

  for (final locale in const [Locale('ar'), Locale('en')]) {
    for (final width in const [375.0, 402.0, 440.0]) {
      testWidgets('${locale.languageCode} at $width: wherever the page stops, '
          'no name or tile is behind him, and he is no lower than that needs',
          (tester) async {
        phone(width);
        await open(tester, locale);
        final counts = await sweep(tester);
        // Every height happens on a board this long.
        expect(counts.keys, containsAll(<String>['up', 'leaves', 'tips']));
      });
    }
  }

  for (final locale in const [Locale('ar'), Locale('en')]) {
    testWidgets('${locale.languageCode}, on an iPhone, the day complete (his '
        'widest, tallest pose): the same', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        phone(402);
        await open(tester, locale);
        final grid = h.container.read(weeklyGridProvider.notifier);
        final today = h.container
            .read(weeklyGridProvider)
            .days
            .firstWhere((d) => d.isSameDayAs(DateTime.now().effectiveDay));
        for (final id in ids) {
          grid.setSquareStateOnly(id, today, SquareState.complete);
        }
        await tester.pump();
        await tester.pump(const Duration(seconds: 8));
        await h.settle(tester);
        await lineAt(tester, 30);
        await tester.pump(const Duration(seconds: 8));
        await h.settle(tester);
        expect(tester.widget<Sprout>(bottomSprout).pose,
            SproutPose.happySparkles);
        await sweep(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('360pt: the board scrolls sideways, so he stays on the edge',
      (tester) async {
    phone(360);
    await open(tester, const Locale('ar'));
    await lineAt(tester, 20);
    expect(stage(tester).atBottom, isFalse);
    expect(bottomSprout, findsNothing);
  });
}
