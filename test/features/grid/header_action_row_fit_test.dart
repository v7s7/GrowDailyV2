// The Grid header must fit on a narrow phone and at a raised font scale.
//
// The header used to carry the screen's big title in an Expanded, which
// quietly absorbed every pixel of slack the action controls did not use.
// Removing the title (the board is the identity; the header is a pure
// action strip now) left a row of fixed-width children — a labelled
// add-habit chip beside four tight 44pt icon frames — and nothing able to
// shrink. It overflowed by 20px at a 320pt viewport (an iPhone on Zoomed
// display, a small Android) and by 6px at 360pt once the system font
// reached 1.4x. On the 402pt simulator it looked perfect, which is exactly
// why this is measured rather than eyeballed.
//
// Measured as GEOMETRY, not by intercepting Flutter's overflow error. Two
// reasons: the stripe is a debug-only diagnostic, while a clipped control
// is what a real user actually loses, and installing a FlutterError.onError
// collector around the harness swallows its own pumpAndSettle diagnostics
// and turned a failure into a ten-minute hang.
//
// The invariant, stated as a user would: every control in the header is
// fully on screen and still tappable, on the narrowest phone the app
// supports and with the system font turned up.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/landing_harness.dart';

void main() {
  late LandingHarness h;

  setUp(() async {
    h = LandingHarness();
    // Habits present, so the header renders BOTH the add chip
    // (showAddAction: habits.isNotEmpty) and the overflow menu
    // (onStartSelection, non-null only when there is something to select) —
    // the widest state the row ever has.
    // morning_athkar is in here on purpose: the tasbih glyph only renders
    // for a board with an athkar-category habit, and this test exists to
    // measure the row at its WIDEST. Drop it and the test would quietly
    // start measuring a narrower header than users can actually have.
    await h.prepare(activeCatalogIds: const [
      'inbox_zero',
      'quran_daily_page',
      'cold_shower',
      'morning_athkar',
    ]);
  });
  tearDown(() => h.dispose());

  Future<void> pumpAt(
    WidgetTester tester, {
    required double width,
    double textScale = 1.0,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await h.pumpApp(tester);
  }

  /// Every header control's on-screen rectangle, by the handle a user would
  /// name it: its tooltip. The add chip has no tooltip (it is labelled), so
  /// it is found by its own text.
  ///
  /// Tooltips are the stable public handle on these private widgets, and
  /// using them means this test also fails if a control loses the tooltip a
  /// screen reader depends on.
  Map<String, Rect> headerControls(WidgetTester tester) {
    Rect rectOf(Finder f) {
      final box = tester.renderObject<RenderBox>(f);
      return box.localToGlobal(Offset.zero) & box.size;
    }

    return {
      'add chip': rectOf(find.text('ADD HABIT')),
      // The Progress Map glyph was removed on 2026-09-03: the worded row in
      // _SummaryCard, on this same screen, opens the same place, and two
      // doors into one room is what paid for the bigger add chip.
      'night review': rectOf(find.byTooltip('Night Review').first),
      'tasbih': rectOf(find.byTooltip('Tasbih').first),
      'list actions': rectOf(find.byTooltip('List actions').first),
    };
  }

  void expectAllOnScreen(Map<String, Rect> controls, double width) {
    // Guard the guard: if a finder stops matching, headerControls throws —
    // but an empty map would make every assertion below pass vacuously.
    expect(controls, hasLength(4),
        reason: 'a header control went missing; if one was renamed, update '
            'the finder rather than deleting the assertion');
    controls.forEach((name, rect) {
      expect(rect.left, greaterThanOrEqualTo(0),
          reason: '"$name" is painted past the leading edge: $rect');
      expect(rect.right, lessThanOrEqualTo(width),
          reason: '"$name" is painted past the trailing edge and would be '
              'clipped on a ${width.toInt()}pt screen: $rect');
    });
  }

  testWidgets('every header control fits a 320pt viewport', (tester) async {
    await pumpAt(tester, width: 320);
    expectAllOnScreen(headerControls(tester), 320);
  });

  testWidgets('every header control fits 360pt at 1.4x system font',
      (tester) async {
    // Raising the system font is a standard accessibility step, not an
    // exotic configuration.
    await pumpAt(tester, width: 360, textScale: 1.4);
    expectAllOnScreen(headerControls(tester), 360);
  });

  testWidgets('the add chip is the part that gives way, not the icons',
      (tester) async {
    // WHICH control shrinks is the design decision, so it is pinned
    // separately: the three icon frames stay a full 44pt at every width
    // (they are already the smallest comfortable target), and the chip's
    // label ellipsizes instead. Reversing that — shrinking the icons to fit
    // a full label — would be the wrong trade and would pass a
    // does-it-overflow test just as happily.
    await pumpAt(tester, width: 320);
    final controls = headerControls(tester);
    for (final name in const [
      'night review',
      'tasbih',
      'list actions',
    ]) {
      expect(controls[name]!.width, 44,
          reason: '"$name" was shrunk to fit; the chip label should '
              'ellipsize instead');
    }
  });
}
