// Milestone chips as full, even rows (lib/shared/widgets/milestone_tally_chip
// .dart), on every Life Timeline year and the monthly report header.
//
// Aziz, 2026-09-21, on the Life Timeline: "the chips ... make it fit and
// clean size and not random sizes". A Wrap sized each chip to its own words
// and dropped a fourth onto a line of its own; the two-column grid before
// that left a ragged half-empty row on an odd count.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/shared/widgets/milestone_tally_chip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The real labels, the longest ones included.
  const labels = [
    'يوم مثالي',
    'ارتقاء مستوى',
    'إنجاز سلسلة',
    'إنجاز مفتوح',
    'أسبوع مثالي',
  ];
  List<MilestoneTallyChip> chips(int n) => [
        for (var i = 0; i < n; i++)
          MilestoneTallyChip(
            icon: Icons.star_rounded,
            color: GameColors.gold,
            count: i + 1,
            label: labels[i],
          ),
      ];

  Future<void> host(WidgetTester tester, int n, {double width = 342}) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.dark,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: MilestoneTallyRows(chips: chips(n)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  List<Rect> chipRects(WidgetTester tester) => [
        for (final e in find.byType(MilestoneTallyChip).evaluate())
          tester.getRect(find.byWidget(e.widget)),
      ];

  Map<double, List<Rect>> byRow(List<Rect> rects) {
    final rows = <double, List<Rect>>{};
    for (final r in rects) {
      rows.putIfAbsent(r.top.roundToDouble(), () => []).add(r);
    }
    return rows;
  }

  testWidgets('three chips: one row, one width', (tester) async {
    await host(tester, 3);
    final rows = byRow(chipRects(tester));
    expect(rows.length, 1);
    final widths = rows.values.single.map((r) => r.width.round()).toSet();
    expect(widths, hasLength(1), reason: 'every chip the same width');
    expect(tester.takeException(), isNull);
  });

  testWidgets('four chips: two rows of two, every chip the same width',
      (tester) async {
    // The screenshot that asked for this: three on one line in three
    // widths, and the fourth alone below.
    await host(tester, 4);
    final rects = chipRects(tester);
    final rows = byRow(rects);
    expect(rows.values.map((r) => r.length).toList(), [2, 2]);
    expect(rects.map((r) => r.width.round()).toSet(), hasLength(1));
  });

  testWidgets('five chips: three and two, no row left half empty',
      (tester) async {
    await host(tester, 5);
    final rows = byRow(chipRects(tester));
    expect(rows.values.map((r) => r.length).toList(), [3, 2]);
    for (final row in rows.values) {
      final left = row.map((r) => r.left).reduce((a, b) => a < b ? a : b);
      final right = row.map((r) => r.right).reduce((a, b) => a > b ? a : b);
      expect(right - left, closeTo(342, 1),
          reason: 'each row spans the full width');
      expect(row.map((r) => r.width.round()).toSet(), hasLength(1));
    }
  });

  testWidgets('a lone chip keeps its own size', (tester) async {
    await host(tester, 1);
    final rect = chipRects(tester).single;
    expect(rect.width, lessThan(342 / 2),
        reason: 'stretched across the card it would read as a button');
  });

  testWidgets('the longest labels fit a narrow phone without overflow',
      (tester) async {
    await host(tester, 3, width: 300);
    expect(tester.takeException(), isNull);
  });
}
