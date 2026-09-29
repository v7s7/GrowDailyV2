// namesColumnFromStart against the board the Grid really draws: where the
// habit names end and the first square begins, measured on the real
// _GridTable, at every phone width, in both reading directions; and null
// exactly when the board scrolls sideways. Doum stands over the names when he
// waits above the bottom bar (SproutBottomPeek), so this arithmetic is what
// keeps him off the squares.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/grid/screens/grid_screen.dart';

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
  );

  /// The first row's squares, left to right (labelled, square, in the board).
  List<Rect> firstRow(WidgetTester tester) {
    final board = tester.getRect(table.first);
    final squares = <Rect>[];
    for (final element
        in find.bySemanticsLabel(RegExp('[,،]')).evaluate()) {
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

  final sideways = find.descendant(
    of: table.first,
    matching: find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    ),
  );

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final rtl = locale.languageCode == 'ar';
    for (final width in const [
      320.0,
      360.0,
      369.0,
      370.0,
      375.0,
      402.0,
      440.0,
      768.0,
    ]) {
      testWidgets('${locale.languageCode} at $width: the names end where the '
          'first square begins', (tester) async {
        phone(width, width > 600 ? 1024 : 874);
        await tester.pumpWidget(h.app(locale: locale));
        await h.settle(tester);

        final board = tester.getRect(table.first);
        final names = namesColumnFromStart(board.width, rtl: rtl);
        // Null exactly when the board scrolls sideways.
        expect(names == null, sideways.evaluate().isNotEmpty,
            reason: 'at $width');
        if (names == null) return;

        final row = firstRow(tester);
        expect(row, hasLength(7));
        final first = rtl ? row.last : row.first;
        final from = rtl ? board.right - first.right : first.left - board.left;
        expect(from, moreOrLessEquals(names.squaresFrom, epsilon: 0.01),
            reason: 'the first square at $width');
        // The column's middle, less its 8pt pad toward the squares.
        final column = names.squaresFrom - 12.5 - (rtl ? 0 : 5);
        expect(names.centre,
            moreOrLessEquals(12.5 + (column - 8) / 2, epsilon: 1e-9));
      });
    }
  }
}
