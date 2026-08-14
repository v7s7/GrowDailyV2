// The Grid is a grid, and a grid that isn't square is broken on sight.
//
// Reported from a device: "if you add some habits, randoms, you will see some
// of them are not aligned with the others — it's not a straight line of
// squares." The table already carries two separate defences against exactly
// this (the fixed `rowHeight` in _GridTable._buildTable, and _SquareCell's
// uniform border width — read both doc comments before changing anything
// here), so a regression would be a *third* cause, and reading the source is
// evidently not enough to catch it. These measure the rendered geometry
// instead.
//
// The invariants, stated as a user would: every square in one habit's row
// sits at the same height, every square under one weekday sits at the same
// horizontal position, and every square is the same size as every other. Name
// length is the variable under test, because that is what differs between
// "random" habits — a name that wraps to two lines makes its row's label
// taller than a one-line neighbour's, and that is the shape of bug the
// rowHeight lock exists to prevent.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/landing_harness.dart';

void main() {
  late LandingHarness h;

  // A FRESH harness per test, and prepare() from setUp rather than from inside
  // testWidgets. Two separate constraints, both load-bearing: prepare() opens
  // Hive boxes for real and the widget-test body runs in a fake-async zone
  // where real IO can never complete (see LandingHarness's own doc comment),
  // and its `tmp`/`container` fields are `late final`, so re-preparing one
  // instance throws LateInitializationError on the second test.
  setUp(() async {
    h = LandingHarness();
    await h.prepare(activeCatalogIds: const [
      'inbox_zero',
      'sunnah_fasting',
      'quran_daily_page',
      'sleep_schedule',
      'cold_shower',
    ]);
  });
  tearDown(() => h.dispose());

  // Shared by all three tests so a catalog rename breaks one line, not three.
  const names = [
    'Inbox Zero',
    'Monday & Thursday Fast',
    'Quran Daily Page',
    'Sleep Before Midnight',
    'Cold Shower',
  ];

  /// Every rendered square, grouped by the habit row it belongs to.
  ///
  /// Squares are found through the semantic label _SquareCell is given, which
  /// always begins with the habit's own localized name (see the
  /// `semanticLabel:` argument in _GridTable._habitRow). That is the only
  /// stable public handle on a private widget, and it has the pleasant side
  /// effect that this test also fails if the labels regress to unlabelled.
  Map<String, List<Rect>> squaresByHabit(WidgetTester tester,
      List<String> habitNames) {
    final out = <String, List<Rect>>{};
    for (final name in habitNames) {
      final finder = find.bySemanticsLabel(RegExp('^${RegExp.escape(name)},'));
      final rects = <Rect>[];
      for (final element in finder.evaluate()) {
        final box = element.renderObject as RenderBox?;
        if (box == null || !box.hasSize) continue;
        final topLeft = box.localToGlobal(Offset.zero);
        rects.add(topLeft & box.size);
      }
      // Left-to-right, so index i is the same weekday column in every row.
      rects.sort((a, b) => a.left.compareTo(b.left));
      out[name] = rects;
    }
    return out;
  }

  testWidgets('squares in a row share one baseline, even when a name wraps',
      (tester) async {
    await h.pumpApp(tester);

    final byHabit = squaresByHabit(tester, names);

    // Guard the guard: if the finder stops matching, every assertion below
    // passes vacuously and the test becomes decorative.
    final found = byHabit.entries.where((e) => e.value.isNotEmpty).toList();
    expect(found, isNotEmpty,
        reason: 'no squares matched — the semantic label format changed, and '
            'this test is no longer measuring anything');

    for (final entry in found) {
      final rects = entry.value;
      final tops = rects.map((r) => r.top.roundToDouble()).toSet();
      expect(tops, hasLength(1),
          reason: '"${entry.key}" has squares at different heights within its '
              'own row: $tops');
      final heights = rects.map((r) => r.height.roundToDouble()).toSet();
      final widths = rects.map((r) => r.width.roundToDouble()).toSet();
      expect(heights, hasLength(1),
          reason: '"${entry.key}" has squares of differing heights: $heights');
      expect(widths, hasLength(1),
          reason: '"${entry.key}" has squares of differing widths: $widths');
    }
  });

  testWidgets('each weekday column is a straight vertical line', (tester) async {
    await h.pumpApp(tester);

    final byHabit = squaresByHabit(tester, names);
    final rows = byHabit.values.where((r) => r.isNotEmpty).toList();
    expect(rows, isNotEmpty, reason: 'no squares matched — finder is stale');

    // Every row must have the same number of columns before comparing them
    // pairwise; a short row would silently skip columns otherwise.
    final columnCounts = rows.map((r) => r.length).toSet();
    expect(columnCounts, hasLength(1),
        reason: 'habit rows rendered different numbers of squares: '
            '$columnCounts');

    final columns = rows.first.length;
    for (var col = 0; col < columns; col++) {
      final lefts = rows.map((r) => r[col].left.roundToDouble()).toSet();
      expect(lefts, hasLength(1),
          reason: 'column $col is not vertically aligned across habit rows: '
              '$lefts');
    }
  });

  // The three tests above run at flutter_test's default 800x600 surface,
  // which is wider than any phone — wide enough that _GridTable's LayoutBuilder
  // takes its non-scrolling branch (cell lands above the 34pt floor, the table
  // fits, nothing is clipped). That is NOT the regime a user is in. On a real
  // 402pt iPhone the same arithmetic gives cell ≈ 30.3, trips the `cell < 34`
  // branch, pins cells at 34 and wraps the whole table in a horizontal
  // SingleChildScrollView that overflows by ~26pt. Alignment has to survive
  // that branch too, and it is the branch the device report came from.
  group('at real phone width, where the table scrolls horizontally', () {
    setUp(() {
      // iPhone 17 Pro logical size, the device the report came from.
      const dpr = 3.0;
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher
          .implicitView!;
      view.physicalSize = const Size(402 * dpr, 874 * dpr);
      view.devicePixelRatio = dpr;
    });

    tearDown(() {
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher
          .implicitView!;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    testWidgets('rows still share a baseline in the scrolling branch',
        (tester) async {
      await h.pumpApp(tester);
      final byHabit = squaresByHabit(tester, names);
      final found = byHabit.entries.where((e) => e.value.isNotEmpty).toList();
      expect(found, isNotEmpty, reason: 'no squares matched — finder is stale');
      for (final entry in found) {
        final tops = entry.value.map((r) => r.top.roundToDouble()).toSet();
        expect(tops, hasLength(1),
            reason: '"${entry.key}" squares sit at different heights: $tops');
      }
    });

    testWidgets('columns are still straight in the scrolling branch',
        (tester) async {
      await h.pumpApp(tester);
      final rows = squaresByHabit(tester, names)
          .values
          .where((r) => r.isNotEmpty)
          .toList();
      expect(rows, isNotEmpty, reason: 'no squares matched — finder is stale');
      expect(rows.map((r) => r.length).toSet(), hasLength(1),
          reason: 'rows rendered different square counts');
      for (var col = 0; col < rows.first.length; col++) {
        final lefts = rows.map((r) => r[col].left.roundToDouble()).toSet();
        expect(lefts, hasLength(1),
            reason: 'column $col is not vertically aligned: $lefts');
      }
    });

    testWidgets('all seven days of the week are on screen', (tester) async {
      // The bug this locks down: on a 402pt iPhone the habit-name column was a
      // flat 96pt, which left ~30.3pt per square, under the old 34pt floor —
      // so the table quietly became horizontally scrollable and the seventh
      // day sat off the right edge with no fade, scrollbar or any other hint
      // it existed. A week view that hides a day of the week is the app's main
      // screen lying about the week.
      await h.pumpApp(tester);
      final rows = squaresByHabit(tester, names)
          .values
          .where((r) => r.isNotEmpty)
          .toList();
      expect(rows, isNotEmpty, reason: 'no squares matched — finder is stale');
      for (final row in rows) {
        expect(row, hasLength(7),
            reason: 'a habit row rendered ${row.length} squares, not 7');
      }

      // Asserted as "the table is not inside a horizontal scroller", NOT as
      // "every square's rect is within 402pt". The rect version was written
      // first and was useless: localToGlobal reports a widget's layout
      // position and knows nothing about an ancestor ScrollView clipping it,
      // so the off-screen seventh day still reported a right edge inside the
      // screen and the test passed with the bug fully present. Whether
      // _GridTable took its scrolling branch is the actual thing that decides
      // if a day is hidden, so that is what gets asserted.
      final horizontalScrollers = find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      expect(horizontalScrollers, findsNothing,
          reason: 'the week grid fell back to horizontal scrolling, which '
              'hides the seventh day behind an edge with no scrollbar, fade '
              'or any other hint that it is there');
    });

    testWidgets('squares are all one size in the scrolling branch',
        (tester) async {
      await h.pumpApp(tester);
      final sizes = squaresByHabit(tester, names)
          .values
          .expand((r) => r)
          .map((r) => '${r.width.roundToDouble()}x${r.height.roundToDouble()}')
          .toSet();
      expect(sizes, isNotEmpty, reason: 'no squares matched — finder is stale');
      expect(sizes, hasLength(1),
          reason: 'the board contains more than one square size: $sizes');
    });
  });

  testWidgets('every square on the board is identically sized', (tester) async {
    await h.pumpApp(tester);

    final all = squaresByHabit(tester, names)
        .values
        .expand((r) => r)
        .toList();
    expect(all, isNotEmpty, reason: 'no squares matched — finder is stale');

    final sizes = all
        .map((r) => '${r.width.roundToDouble()}x${r.height.roundToDouble()}')
        .toSet();
    expect(sizes, hasLength(1),
        reason: 'the board contains squares of more than one size: $sizes — '
            'see _SquareCell\'s border-width comment for why this matters');
  });
}
