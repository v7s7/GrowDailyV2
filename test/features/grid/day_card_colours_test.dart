// The Grid's day card in the colours Aziz picked on 2026-09-28 (style A,
// "better, cleaner"): the card is dressed exactly like the board under it,
// and the ring is the only colour on it. This locks down what makes that
// hold on every theme: the board's own fill and edge, a ring whose empty part
// is an empty square's grey, the grid colour (never the accent) for the arc
// and a perfect day's glow, words that read on the card, and a perfect day
// that lights the edge without moving the board or the sprout standing on it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/core/theme/theme_preset.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/grid/notifiers/weekly_grid_notifier.dart';
import 'package:grow_daily_v2/features/grid/screens/grid_screen.dart';
import 'package:grow_daily_v2/features/mascot/sprout_ledge.dart';

import '../../helpers/landing_harness.dart';

/// WCAG AA: 4.5:1 for text this small, 3:1 for a line. A hair of slack,
/// because the inks are solved by bisection onto the threshold itself.
const double kText = 4.5;
const double kLine = 3.0;
const double kSlack = 0.005;

void main() {
  late LandingHarness h;

  const daily = 'inbox_zero'; // daily, every weekday
  const quota = 'gym_consistency'; // 3x a week, any days

  setUp(() async {
    h = LandingHarness();
    await h.prepare(activeCatalogIds: const [daily, quota]);
  });
  tearDown(() {
    h.dispose();
    // applyPreset writes global statics; put the default back so a theme
    // set here cannot leak into the next test.
    GameColors.applyPreset(ThemePresets.byId(ThemePresets.defaultId));
  });

  Future<void> pumpGrid(WidgetTester tester, {required bool dark}) async {
    await tester.pumpWidget(h.app(
      home: Theme(
        data: dark ? GameTheme.dark : GameTheme.light,
        child: const GridScreen(),
      ),
    ));
    await h.settle(tester);
  }

  /// The day card: the rounded box around today's big number (34pt is
  /// unique to it).
  final dayCard = find.ancestor(
    of: find.byWidgetPredicate(
        (w) => w is Text && w.style?.fontSize == 34),
    matching: find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration! as BoxDecoration).borderRadius ==
            BorderRadius.circular(GameSpacing.cardRadius)),
  );

  /// The board's own box, the first Container _GridTable builds.
  final boardBox = find
      .descendant(
        of: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_GridTable'),
        matching: find.byType(Container),
      )
      .first;

  final ring = find.descendant(
      of: dayCard, matching: find.byType(CircularProgressIndicator));

  Finder cardText(double size) => find.descendant(
      of: dayCard,
      matching: find.byWidgetPredicate(
          (w) => w is Text && w.style?.fontSize == size));

  BoxDecoration decorationOf(WidgetTester tester, Finder f) =>
      tester.widget<Container>(f).decoration! as BoxDecoration;

  /// The grid colour as a line (3:1), from the palette the Grid itself reads.
  Color edgeOf(WidgetTester tester) =>
      tester.element(find.byType(GridScreen)).gp.emeraldEdge;

  for (final dark in const [true, false]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('$mode: the card wears the board\'s own fill and edge',
        (tester) async {
      await pumpGrid(tester, dark: dark);
      expect(dayCard, findsOneWidget);

      final card = decorationOf(tester, dayCard);
      final board = decorationOf(tester, boardBox);
      expect(card.gradient, isNull,
          reason: 'the wash went muddy in the middle; the card is flat now');
      expect(card.color, board.color);
      final cardEdge = (card.border! as Border).top;
      final boardEdge = (board.border! as Border).top;
      expect(cardEdge.color, boardEdge.color);
      expect(cardEdge.width, boardEdge.width);
      expect(tester.widget<Container>(dayCard).foregroundDecoration, isNull,
          reason: 'the lit edge belongs to a perfect day only');
    });

    testWidgets('$mode: the ring is the grid colour on an empty square\'s grey',
        (tester) async {
      await pumpGrid(tester, dark: dark);
      final indicator = tester.widget<CircularProgressIndicator>(ring);
      expect(indicator.backgroundColor, SquareState.none.fill(dark),
          reason: 'the ring and the board say "not yet" in one colour');
      expect((indicator.valueColor! as AlwaysStoppedAnimation<Color?>).value,
          edgeOf(tester));
    });
  }

  group('everything on the card reads on it, in every theme', () {
    // Every preset, plus two custom pairs seen on real phones on 2026-09-28:
    // the simulator's red + mint and Aziz's own yellow + blue.
    final cases = <String, (Color, Color)?>{
      for (final p in ThemePresets.selectable) p.id: null,
      'custom red + mint': (const Color(0xFFFF4646), const Color(0xFF92FFA8)),
      'custom yellow + blue': (
        const Color(0xFFFFD600),
        const Color(0xFF3894EF)
      ),
    };
    for (final MapEntry(key: name, value: custom) in cases.entries) {
      testWidgets(name, (tester) async {
        final accentBefore = ThemePresets.customAccent;
        final gridBefore = ThemePresets.customGrid;
        addTearDown(() {
          ThemePresets.customAccent = accentBefore;
          ThemePresets.customGrid = gridBefore;
        });
        final ThemePreset preset;
        if (custom == null) {
          preset = ThemePresets.byId(name);
        } else {
          ThemePresets.customAccent = custom.$1;
          ThemePresets.customGrid = custom.$2;
          preset = ThemePresets.byId(ThemePresets.customId);
        }
        for (final dark in const [true, false]) {
          GameColors.applyPreset(preset);
          await pumpGrid(tester, dark: dark);
          final mode = dark ? 'dark' : 'light';
          final card = decorationOf(tester, dayCard).color!;

          void reads(Color fg, double bar, String what) {
            final r = contrastRatio(fg, card);
            expect(r, greaterThanOrEqualTo(bar - kSlack),
                reason: '$name $mode: $what is '
                    '${r.toStringAsFixed(2)}:1 on the card, needs $bar');
          }

          reads(tester.widget<Text>(cardText(34)).style!.color!, kText,
              'the big number');
          reads(tester.widget<Text>(cardText(12.5)).style!.color!, kText,
              'the "of N habits today" label');
          reads(tester.widget<Text>(cardText(12)).style!.color!, kText,
              'the week line');
          reads(tester.widget<Text>(cardText(24)).style!.color!, kText,
              'the percentage');
          final arc = (tester.widget<CircularProgressIndicator>(ring)
                  .valueColor! as AlwaysStoppedAnimation<Color?>)
              .value!;
          reads(arc, kLine, 'the ring');
          expect(arc, edgeOf(tester));
        }
      });
    }
  });

  group('a perfect day', () {
    /// Puts [quota] into a rest day for TODAY, whatever the real weekday is
    /// (see summary_card_today_wiring_test.dart), so [daily] alone decides
    /// whether today is finished.
    Future<void> restQuotaToday(WidgetTester tester) async {
      final grid = h.container.read(weeklyGridProvider.notifier);
      final days = h.container.read(weeklyGridProvider).days;
      final today = DateTime.now().effectiveDay;
      final todayIndex = days.indexWhere((d) => d.isSameDayAs(today));
      if (todayIndex >= 4) {
        for (var i = 0; i < 3; i++) {
          grid.setSquareStateOnly(quota, days[i], SquareState.complete);
        }
      }
      await h.settle(tester);
    }

    for (final dark in const [true, false]) {
      final mode = dark ? 'dark' : 'light';

      testWidgets(
          '$mode: lights the edge and the glow in the grid colour, and '
          'nothing moves', (tester) async {
        await pumpGrid(tester, dark: dark);
        await restQuotaToday(tester);
        final grid = h.container.read(weeklyGridProvider.notifier);
        final today = DateTime.now().effectiveDay;
        grid.setSquareStateOnly(daily, today, SquareState.none);
        await h.settle(tester);

        final cardBefore = tester.getRect(dayCard);
        final boardBefore = tester.getRect(boardBox);
        final ledgeBefore = tester.getRect(find.byType(SproutLedge));

        grid.setSquareStateOnly(daily, today, SquareState.complete);
        await h.settle(tester);
        // The ring's pop and glint (~1.7s) run to the end, so no timer is
        // left for the teardown check.
        await tester.pump(const Duration(seconds: 2));

        final gridEdge = edgeOf(tester);
        final edge = tester.widget<Container>(dayCard).foregroundDecoration;
        expect(edge, isA<BoxDecoration>(),
            reason: 'a perfect day lights the card\'s edge');
        expect(((edge! as BoxDecoration).border! as Border).top.color,
            gridEdge.withOpacity(0.55));

        final glows = tester
            .widgetList<Container>(
                find.descendant(of: dayCard, matching: find.byType(Container)))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .where((d) =>
                d.shape == BoxShape.circle && (d.boxShadow?.isNotEmpty ?? false))
            .toList();
        expect(glows, hasLength(1), reason: 'the ring glows on a perfect day');
        final glow = glows.single.boxShadow!.single.color;
        expect(glow, gridEdge.withOpacity(0.30),
            reason: 'the glow is the grid colour');
        expect(glow.withOpacity(1), isNot(GameColors.gold.withOpacity(1)),
            reason: 'never the accent: on a red theme a perfect day glowed '
                'red');

        expect(tester.getRect(dayCard), cardBefore,
            reason: 'the lit edge must not grow the card');
        expect(tester.getRect(boardBox), boardBefore,
            reason: 'nor push the board down');
        expect(tester.getRect(find.byType(SproutLedge)), ledgeBefore,
            reason: 'nor move the sprout\'s line');
      });
    }
  });
}
