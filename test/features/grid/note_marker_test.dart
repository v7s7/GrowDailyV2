// The mark that says "you wrote here".
//
// A note used to be announced by a 9pt `sticky_note_2_rounded` in the
// BOTTOM-right of a square whose floor size is 30pt: a paper-and-lines glyph
// rendered into about 12 square points, overlapping the centred state glyph's
// box, and falling back to `textTert` (the lowest ink in the palette) on the
// empty square where most notes actually land. It was also absent from the
// square's semantic label entirely, so a screen-reader user had no note
// affordance at all, and it was drawn at 0.35 opacity on any day the habit
// had stopped asking for, which is exactly when someone is browsing back
// through old writing.
//
// Nothing under test/ referenced hasNote, the icon, or the ink before this
// file, so every one of those could have been quietly reverted with the suite
// staying green.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/grid/widgets/note_corner.dart';

import '../../helpers/landing_harness.dart';

void main() {
  group('NoteCornerPainter', () {
    test('repaints only when the ink changes', () {
      const a = NoteCornerPainter(Color(0xFFAABBCC));
      const b = NoteCornerPainter(Color(0xFFAABBCC));
      const c = NoteCornerPainter(Color(0xFF112233));
      expect(a.shouldRepaint(b), isFalse);
      expect(a.shouldRepaint(c), isTrue);
    });

    testWidgets('it occupies exactly the box it is given', (tester) async {
      // It is painted into a corner of a square whose geometry is pinned by
      // grid_square_alignment_test. A mark that claimed layout width would
      // move every square on the board.
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: NoteCorner(size: 9, ink: Color(0xFFFFFFFF))),
      ));
      expect(tester.getSize(find.byType(NoteCorner)), const Size(9, 9));
    });
  });

  group('on the board', () {
    late LandingHarness h;

    setUp(() async {
      h = LandingHarness();
      await h.prepare(activeCatalogIds: const ['inbox_zero']);
      // Hive boxes are process-wide and LandingHarness.dispose deliberately
      // does not close them, so a note written by one test is still sitting
      // in the box when the next one loads its week.
      (await LocalStoreService.dailyBox()).clear();
    });
    tearDown(() => h.dispose());

    /// Seeds AFTER the first pump, on purpose.
    ///
    /// _loadWeek starts the moment the notifier is created and replaces the
    /// whole state when it resolves, so anything seeded before the app is
    /// pumped is racing that load rather than setting up the test.
    Future<void> seed(
      WidgetTester tester,
      void Function(WeeklyGridNotifier grid) mutate,
    ) async {
      mutate(h.container.read(weeklyGridProvider.notifier));
      await h.settle(tester);
    }

    /// Every note mark currently painted anywhere in the tree.
    Iterable<NoteCornerPainter> marks(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<NoteCornerPainter>();

    testWidgets('a square with no note carries no mark', (tester) async {
      // The zero case first: without it, every assertion below could pass
      // vacuously against a finder that no longer matches anything.
      await h.pumpApp(tester);
      expect(marks(tester), isEmpty);
    });

    testWidgets('a written day is marked, and only that day', (tester) async {
      // Seeded BEFORE pumping: the square lives in an AnimatedContainer, and
      // setting state afterwards would read a frame mid-lerp.
      final today = DateTime.now().effectiveDay;
      await h.pumpApp(tester);
      await seed(tester,
          (g) => g.setNote('inbox_zero', today, 'cleared the inbox, felt light'));

      expect(marks(tester), hasLength(1),
          reason: 'one day was written on, so the board should carry exactly '
              'one note mark');
    });

    testWidgets('the old sticky-note glyph is gone', (tester) async {
      final today = DateTime.now().effectiveDay;
      await h.pumpApp(tester);
      await seed(tester, (g) => g.setNote('inbox_zero', today, 'a note'));

      expect(find.byIcon(Icons.sticky_note_2_rounded), findsNothing,
          reason: 'the square is drawing both the folded corner and the glyph '
              'it replaced, which is two marks for one fact');
    });

    testWidgets('whitespace is not writing and earns no mark', (tester) async {
      final today = DateTime.now().effectiveDay;
      await h.pumpApp(tester);
      await seed(tester, (g) => g.setNote('inbox_zero', today, '    '));

      expect(marks(tester), isEmpty,
          reason: 'setNote trims, so this stores nothing; a mark here would '
              'send the user to an editor holding an empty field');
    });

    testWidgets('a cleared note takes its mark with it', (tester) async {
      final today = DateTime.now().effectiveDay;
      await h.pumpApp(tester);
      await seed(tester, (g) {
        g.setNote('inbox_zero', today, 'something');
        g.setNote('inbox_zero', today, '');
      });

      expect(marks(tester), isEmpty);
    });

    testWidgets('an unmarked square uses textSec, not the palette floor',
        (tester) async {
      // The branch most notes land in. textTert measures 3.17:1 on the dark
      // empty fill and 1.98:1 in light; textSec is 7.24:1 and 3.88:1. This
      // pins the step up rather than the exact colour, so a theme preset
      // swap cannot fail it.
      final today = DateTime.now().effectiveDay;
      await h.pumpApp(tester);
      await seed(tester,
          (g) => g.setNote('inbox_zero', today, 'a note on an empty square'));

      final context = tester.element(find.byType(NoteCorner).first);
      expect(marks(tester).single.ink, context.gp.textSec);
      expect(marks(tester).single.ink, isNot(context.gp.textTert));
    });

    testWidgets('a marked square takes that state\'s own accent',
        (tester) async {
      final today = DateTime.now().effectiveDay;
      await h.pumpApp(tester);
      await seed(tester, (g) {
        g.setSquareStateOnly('inbox_zero', today, SquareState.skipped);
        g.setNote('inbox_zero', today, 'travelling');
      });

      // `accent` takes the brightness now: the vivid versions are tuned for
      // the dark theme and drop under AA on the light one. Read it off a
      // real context, the same way the sibling test above reads textSec.
      final context = tester.element(find.byType(NoteCorner).first);
      expect(marks(tester).single.ink,
          SquareState.skipped.accent(context.gp.dark));
    });

    testWidgets('a written day is never dimmed', (tester) async {
      // A day the habit stopped asking for is drawn at 0.35, which is exactly
      // when someone is browsing back through old writing. Notes are
      // information for the same reason a covered day is.
      final today = DateTime.now().effectiveDay;
      await h.pumpApp(tester);
      await seed(tester, (g) => g.setNote('inbox_zero', today, 'a note'));

      final dimmed = tester
          .widgetList<Opacity>(find.ancestor(
            of: find.byType(NoteCorner),
            matching: find.byType(Opacity),
          ))
          .where((o) => o.opacity < 1);
      expect(dimmed, isEmpty,
          reason: 'the note mark is sitting inside a dimmed square');
    });

    testWidgets('a screen reader is told the day carries writing',
        (tester) async {
      // container: true on the cell stops the painted mark announcing itself,
      // so the label is the only channel there is.
      final today = DateTime.now().effectiveDay;
      await h.pumpApp(tester);
      await seed(tester, (g) => g.setNote('inbox_zero', today, 'a note'));

      final spoken = const S(Locale('en')).gridNoteSemantics;
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .any((w) => w.properties.label?.contains(spoken) ?? false),
        isTrue,
        reason: 'no square announces "$spoken", so the mark is invisible to '
            'anyone who cannot see it',
      );
    });
  });
}
