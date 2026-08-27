// A yellow square means "counts as half a day". It used to draw a clock.
//
// `Icons.timelapse_rounded` is a clock face, and the one thing the جزئي state
// does NOT mean is that time is passing — the app's own sentence under the
// long-press palette says "يُحتسب نصف يوم." / "Counts as half a day." The
// words were right and the picture disagreed with them.
//
// The square is now drawn filled to a hard line at half its height, which is
// the metaphor the board already uses when a counted habit fills upward. That
// is geometry, not a glyph, and geometry is invisible to every existing test
// here: nothing under test/ referenced the icon, the accent or the fill
// before this file, so a future author could quietly put the clock back — or
// "clean up" partial's icon to null and make a marked square render the same
// hollow circle as an empty one — and every suite would stay green.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';

import '../../helpers/landing_harness.dart';

void main() {
  group('the partial state is drawn as half full, not as a timer', () {
    test('no clock face is left anywhere in the app', () {
      // A source-level lock rather than a widget one, because the two sites
      // that drew this glyph were in different features and only one of them
      // read it off SquareState — the room card hardcoded its own copy in a
      // nested ternary. A grep is the only assertion that covers both, and
      // any third site somebody adds later.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          // Comments are exempt: square_state.dart's own doc comment names
          // the glyph it replaced, and that sentence is the reason anybody
          // reading it later will not put the clock back.
          final line = lines[i].trimLeft();
          if (line.startsWith('//')) continue;
          if (line.contains('Icons.timelapse')) {
            offenders.add('${entity.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'a clock face is back. The partial state means half a day, '
              'not elapsed time — draw it with SquareState.levelFactor on a '
              'square, or with HalfFullMark where only a glyph fits.');
    });

    test('partial keeps a non-null icon so no site falls back to empty', () {
      // Four call sites write `state.icon ?? Icons.circle_outlined`, and
      // `none` already returns null. Making partial null too would render a
      // marked square as the exact same hollow circle as an untouched one:
      // a state marker becoming indistinguishable from "nothing happened".
      expect(SquareState.partial.icon, isNotNull,
          reason: 'partial.icon is the fallback for any site that forgets '
              'glyph(); null there means it renders as the empty state');
      expect(SquareState.partial.icon, isNot(SquareState.none.icon));
    });

    test('only partial has a level, and the level is exactly a half', () {
      expect(SquareState.partial.levelFactor, 0.5);
      for (final state in SquareState.values) {
        if (state == SquareState.partial) continue;
        expect(state.levelFactor, isNull,
            reason: '$state is drawn flat; a level would make the board say '
                'something about it that is not true');
      }
    });

    test('dark is a second wash of the same token, on purpose', () {
      // Not a redundant assertion — it locks the choice. The risen half is
      // painted OVER the square's own fill, so handing it the identical
      // colour composites 0.30 over 0.30 to 0.51 and measures 1.75:1 against
      // the unrisen half. That is a clear step with no new colour to keep in
      // sync across the eleven theme presets, and someone "fixing" this to a
      // bespoke shade would be adding a twelfth thing to maintain.
      expect(SquareState.partial.levelFill(true),
          SquareState.partial.fill(true));
    });

    test('light steps down in value rather than piling on more yellow', () {
      // Light cannot do what dark does. #F7C948 has no headroom above a cream
      // card: a second wash moves almost only the blue channel, so the two
      // halves come out about 1.07:1 apart and the square reads as flat.
      expect(SquareState.partial.levelFill(false),
          isNot(SquareState.partial.fill(false)),
          reason: 'the light risen half is another wash of the accent, which '
              'is a saturation step the eye does not see as a level');
      expect(SquareState.partial.levelLine(true),
          isNot(SquareState.partial.levelLine(false)),
          reason: 'light mode needs its own darker ink; the full-strength '
              'accent measures about 1.1:1 on the light fill, i.e. gone');
      expect(SquareState.partial.levelLine(false),
          isNot(SquareState.partial.accent));
    });

    testWidgets('the half-full mark occupies the same box as an icon would',
        (tester) async {
      // HalfFullMark is a drop-in for `Icon(state.icon, size: n)` at every
      // small-tile site. If its box differs, list rows shift.
      await tester.pumpWidget(const MaterialApp(
        home: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HalfFullMark(size: 18, color: Color(0xFFF7C948)),
              Icon(Icons.check_rounded, size: 18),
            ],
          ),
        ),
      ));
      final mark = tester.getSize(find.byType(HalfFullMark));
      final icon = tester.getSize(find.byType(Icon));
      expect(mark, icon);
      expect(mark, const Size(18, 18));
    });
  });

  group('on the board', () {
    late LandingHarness h;

    setUp(() async {
      h = LandingHarness();
      await h.prepare(activeCatalogIds: const ['inbox_zero']);
    });
    tearDown(() => h.dispose());

    /// Every non-uniform top-only border in the tree — the waterline is the
    /// only thing in the Grid drawn that way, so this is a specific handle on
    /// it without reaching into a private widget.
    ///
    /// Seeded BEFORE the app is pumped on purpose: the fill lives in an
    /// AnimatedContainer, and setting the state afterwards would leave the
    /// decoration mid-lerp on the frame this reads.
    Iterable<BoxDecoration> topOnlyBorders(WidgetTester tester) => tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .where((b) {
          final border = b.border;
          return border is Border &&
              border.top.width == 1 &&
              border.bottom == BorderSide.none &&
              border.left == BorderSide.none;
        });

    testWidgets('a partial square draws a waterline and no glyph',
        (tester) async {
      h.container.read(weeklyGridProvider.notifier).setSquareStateOnly(
          'inbox_zero', DateTime.now().effectiveDay, SquareState.partial);
      await h.pumpApp(tester);

      final lines = topOnlyBorders(tester).toList();
      // Exactly one, for exactly one seeded square. `isNotEmpty` alone would
      // also pass on a stray border some unrelated card happens to draw, and
      // the count is what ties the mark to the square that earned it.
      expect(lines, hasLength(1),
          reason: 'one square was marked جزئي, so the board should carry one '
              'waterline. None means the mark is gone — and in light mode the '
              'two halves sit about 1.1:1 apart, so the line is not a detail, '
              'it is the whole design there.');
      expect(
        lines.single.border!.top.color,
        anyOf(SquareState.partial.levelLine(true),
            SquareState.partial.levelLine(false)),
      );

      expect(find.byIcon(SquareState.partial.icon!), findsNothing,
          reason: 'the square is drawing both the fill and a centred glyph; '
              'they sit on top of each other');
    });
  });
}
