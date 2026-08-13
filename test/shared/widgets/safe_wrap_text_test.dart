// Deterministic tests for SafeWrapText's tapToRevealWhenTruncated feature -
// added so a habit/task name too long for its column (see
// grid_screen_table.dart's habit row) can still be read in full on tap,
// without the row itself growing and knocking the grid's squares out of
// alignment (see that file's own doc comment on why row height is fixed).
//
// These pump real widgets rather than calling the overflow-detection
// helpers directly, since the whole point is confirming the *widget*
// wraps itself in a Tooltip exactly when (and only when) real layout
// overflow actually happens - a plain logic test of wordExceedsWidth/
// textOverflowsAt in isolation wouldn't catch a mismatch between what
// those helpers report and what SafeWrapText.build actually does with it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/shared/widgets/safe_wrap_text.dart';

void main() {
  // A deliberately long, single-line-worthy sentence with plenty of short
  // words - guaranteed to overflow two lines at a narrow width without
  // relying on any single word being individually too wide (that's a
  // separate case, covered below).
  const longText =
      'This is a genuinely long habit name that will not fit on two lines';
  const shortText = 'Fajr';

  Future<void> pump(
    WidgetTester tester, {
    required String text,
    required double width,
    bool tapToReveal = false,
    int maxLines = 2,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: SafeWrapText(
                text,
                maxLines: maxLines,
                tapToRevealWhenTruncated: tapToReveal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('SafeWrapText.tapToRevealWhenTruncated', () {
    testWidgets('short text that fits is never wrapped in a Tooltip, '
        'even when the flag is on', (tester) async {
      await pump(tester, text: shortText, width: 300, tapToReveal: true);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets(
        'long text that overflows is NOT wrapped in a Tooltip by default '
        '(flag off) - existing callers keep their exact old behavior',
        (tester) async {
      await pump(tester, text: longText, width: 60, tapToReveal: false);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets(
        'long text that overflows IS wrapped in a Tooltip carrying the '
        'full text, when the flag is on', (tester) async {
      await pump(tester, text: longText, width: 60, tapToReveal: true);
      final tooltipFinder = find.byType(Tooltip);
      expect(tooltipFinder, findsOneWidget);
      final tooltip = tester.widget<Tooltip>(tooltipFinder);
      expect(tooltip.message, longText);
      expect(tooltip.triggerMode, TooltipTriggerMode.tap);
    });

    testWidgets('tapping the truncated text actually reveals the full '
        'message on screen', (tester) async {
      await pump(tester, text: longText, width: 60, tapToReveal: true);
      // The row's own Text widget already carries the full string as its
      // `data` even while visually truncated - the ellipsis is a paint-
      // time effect only, not a change to the widget itself - so
      // find.text(longText) would match even before anything is tapped.
      // The real proof an overlay actually appeared is a *new* match
      // showing up after the tap, not just the string being findable at
      // all.
      final before = find.text(longText).evaluate().length;
      await tester.tap(find.byType(Tooltip));
      // Tooltip's overlay fades in - give it a frame.
      await tester.pump(const Duration(milliseconds: 50));
      final after = find.text(longText).evaluate().length;
      expect(after, greaterThan(before));
    });

    testWidgets(
        'a single word too wide for even one line still gets a Tooltip '
        '(the wordExceedsWidth fallback path), not just the "too many '
        'words" path', (tester) async {
      const oneGiantWord =
          'Supercalifragilisticexpialidocioussupercalifragilistic';
      await pump(tester, text: oneGiantWord, width: 60, tapToReveal: true);
      final tooltipFinder = find.byType(Tooltip);
      expect(tooltipFinder, findsOneWidget);
      expect(tester.widget<Tooltip>(tooltipFinder).message, oneGiantWord);
    });
  });
}
