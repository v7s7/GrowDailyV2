// The sprout on the real Grid: on the board's top edge, over today's square,
// on every phone width, in both reading directions (Aziz, 2026-09-28:
// "attach to the line, on all phones"). sprout_ledge_test.dart covers the
// gestures on the ledge alone; this one measures the ledge against the real
// board _GridTable draws, so the two can never drift apart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/screens/grid_screen.dart'
    show todayColumnFromStart;
import 'package:grow_daily_v2/features/mascot/sprout.dart';
import 'package:grow_daily_v2/features/mascot/sprout_ledge.dart';

import '../../helpers/landing_harness.dart';

void main() {
  late LandingHarness h;

  setUp(() async {
    h = LandingHarness();
    await h.prepare(activeCatalogIds: const [
      'inbox_zero',
      'quran_daily_page',
      'sleep_schedule',
    ]);
  });
  tearDown(() => h.dispose());

  void phone(double width, [double height = 874]) {
    const dpr = 3.0;
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = Size(width * dpr, height * dpr);
    view.devicePixelRatio = dpr;
  }

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  final table = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_GridTable',
  );

  /// Every square of the board's first row, left to right. Squares are the
  /// labelled cells (see grid_square_alignment_test) that sit inside the
  /// board and are square.
  List<Rect> firstRow(WidgetTester tester) {
    final board = tester.getRect(table.first);
    final squares = <Rect>[];
    // «،» in Arabic, "," in English.
    for (final element in find.bySemanticsLabel(RegExp('[,\u060C]')).evaluate()) {
      final box = element.renderObject as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final r = box.localToGlobal(Offset.zero) & box.size;
      if ((r.width - r.height).abs() > 0.5 || r.width < 28) continue;
      if (!board.contains(r.center)) continue;
      squares.add(r);
    }
    final top = squares.map((r) => r.top).reduce((a, b) => a < b ? a : b);
    return squares.where((r) => (r.top - top).abs() < 0.5).toList()
      ..sort((a, b) => a.left.compareTo(b.left));
  }

  final scrolls = find.descendant(
    of: table.first,
    matching: find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    ),
  );

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final rtl = locale.languageCode == 'ar';
    for (final width in const [
      320.0, // iPhone SE (1st), small Androids
      360.0, // the most common Android width
      375.0, // iPhone SE / mini
      390.0,
      402.0, // iPhone 17 Pro
      430.0,
      440.0, // Pro Max
      768.0, // a tablet
    ]) {
      testWidgets('${locale.languageCode} at $width: on the line, over today',
          (tester) async {
        phone(width, width > 600 ? 1024 : 874);
        await tester.pumpWidget(h.app(locale: locale));
        await h.settle(tester);

        final ledge = tester.getRect(find.byType(SproutLedge));
        final board = tester.getRect(table.first);
        final sprout = tester.getRect(find.descendant(
          of: find.byType(SproutLedge),
          matching: find.byType(Sprout),
        ));

        // The line: the lane ends exactly where the board begins, and the
        // sprout stands behind it, face above, feet below.
        expect(board.top, moreOrLessEquals(ledge.bottom, epsilon: 0.01),
            reason: 'a gap between the lane and the board at $width');
        expect(ledge.height, kLedgeLaneHeight);
        expect(sprout.top, lessThan(ledge.top));
        expect(sprout.bottom, greaterThan(board.top));

        final half =
            Sprout.sizeOf(SproutPose.frontWave, kLedgeSproutHeight).width / 2;

        if (scrolls.evaluate().isNotEmpty) {
          // Squares under 30pt: the board scrolls sideways, today's column
          // has no fixed place, and the sprout stands at the end of the line.
          final fromStart =
              rtl ? ledge.right - sprout.center.dx : sprout.center.dx - ledge.left;
          expect(fromStart,
              moreOrLessEquals(ledge.width - half - 8, epsilon: 0.5));
          return;
        }

        final row = firstRow(tester);
        expect(row, hasLength(7), reason: 'a full week in the first row');

        // Where the sprout rests when [square] is today's: over its middle,
        // except that his centre keeps half his width from each end of the
        // line so he never hangs past the board (SproutLedge._restX). In a
        // left-to-right row the last square, Friday, has only the board's
        // padding after it, so on some widths he stands a point or so short
        // of its middle (1.3pt at 430).
        double restOver(Rect square) => square.center.dx
            .clamp(ledge.left + half, ledge.right - half)
            .toDouble();

        // Every day of the week, not only today, so a run on any weekday
        // reaches the ends of the line too: this test was first run on a
        // Friday four days after it was written. The app's arithmetic finds
        // each square of the real board, and the edge never takes the
        // sprout off the square he stands for.
        final now = DateTime.now();
        final weekStart = now.startOfDisplayWeek;
        for (var i = 0; i < 7; i++) {
          final day =
              DateTime(weekStart.year, weekStart.month, weekStart.day + i);
          final square = rtl ? row[6 - i] : row[i];
          final fromStart =
              todayColumnFromStart(ledge.width, rtl: rtl, now: day)!;
          expect(
            rtl ? ledge.right - fromStart : ledge.left + fromStart,
            moreOrLessEquals(square.center.dx, epsilon: 0.5),
            reason: 'day $i of the week is not where the board draws it '
                'at $width',
          );
          expect(
            restOver(square),
            inExclusiveRange(square.left, square.right),
            reason: 'on day $i the edge pushes the sprout off its square '
                'at $width',
          );
        }

        final index = (DateTime(now.year, now.month, now.day)
                        .difference(weekStart)
                        .inHours /
                    24)
                .round();
        final today = rtl ? row[6 - index] : row[index];
        expect(sprout.center.dx,
            moreOrLessEquals(restOver(today), epsilon: 0.5),
            reason: "the sprout is not over today's square at $width");
      });
    }
  }
}
