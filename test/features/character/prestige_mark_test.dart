// The rank ladder's ordering contract.
//
// The whole design rests on one claim: you can tell which of two prestige
// ranks is higher WITHOUT reading a colour. These tests are what stop that
// claim from quietly becoming false — every one of them fails if a future
// tweak flattens, inverts, or colour-couples the ladder.
//
// Background on why this is a test and not a comment: the shipped ladder had
// exactly this bug. Perceptual lightness fell three times across its eight
// tiers, lvl 5 was the brightest rung of all eight, and on the DEFAULT preset
// lvl 20 and lvl 100 were the identical hex — colour difference 0.0 — because
// two tiers read GameColors.emerald/gold, which the preset system swaps at
// runtime. game_theme.dart:105-117 records the same class of bug being caught
// and fixed for the achievement medal ladder; the prestige ladder was missed
// because nothing asserted it.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/character/models/prestige_tier.dart';
import 'package:grow_daily_v2/features/character/widgets/prestige_mark.dart';

/// CIE L*, the one dimension of colour the visual system reads as ordered.
double _lStar(Color c) {
  double lin(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final y = 0.2126 * lin(c.red / 255) +
      0.7152 * lin(c.green / 255) +
      0.0722 * lin(c.blue / 255);
  return y > 0.008856 ? 116 * math.pow(y, 1 / 3).toDouble() - 16 : 903.3 * y;
}

/// CIE Lab, for deltaE and lightness checks.
List<double> _lab(Color c) {
  double lin(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final r = lin(c.red / 255), g = lin(c.green / 255), b = lin(c.blue / 255);
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  final fx = f(x), fy = f(y), fz = f(z);
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}

double _deltaE(Color a, Color b) {
  final la = _lab(a), lb = _lab(b);
  var sum = 0.0;
  for (var i = 0; i < 3; i++) {
    sum += math.pow(la[i] - lb[i], 2).toDouble();
  }
  return math.sqrt(sum);
}

double _contrast(Color a, Color b) {
  double rl(Color c) {
    double lin(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * lin(c.red / 255) +
        0.7152 * lin(c.green / 255) +
        0.0722 * lin(c.blue / 255);
  }

  final x = rl(a), y = rl(b);
  final hi = x > y ? x : y, lo = x > y ? y : x;
  return (hi + 0.05) / (lo + 0.05);
}

List<PrestigeMarkSpec> _ladder() {
  final specs = PrestigeCatalog.tiers.map(prestigeMarkFor).toList();
  expect(
    specs.every((s) => s != null),
    isTrue,
    reason: 'every tier in PrestigeCatalog needs an entry in kPrestigeMarks; '
        'a missing one silently falls back to the old titled chip',
  );
  final out = specs.cast<PrestigeMarkSpec>().toList();
  out.sort((a, b) => a.rank.compareTo(b.rank));
  return out;
}

void main() {
  group('ink mass is the ordering channel', () {
    // The primary claim. Ink is pre-attentive: it survives peripheral vision,
    // small size and greyscale before shape or hue resolve. If this ever
    // stops increasing, two ranks become the same picture.
    test('opaque coverage increases at every single rung', () {
      final l = _ladder();
      for (var i = 0; i < l.length - 1; i++) {
        final a = prestigeMarkInkCoverage(l[i]);
        final b = prestigeMarkInkCoverage(l[i + 1]);
        expect(
          b,
          greaterThan(a),
          reason: 'rank ${l[i].rank} covers ${(a * 100).toStringAsFixed(1)}% '
              'and rank ${l[i + 1].rank} covers ${(b * 100).toStringAsFixed(1)}%'
              ' — the ladder is flat or inverted there',
        );
      }
    });

    test('the summit is the heaviest mark, by a wide margin', () {
      final l = _ladder();
      final cover = l.map(prestigeMarkInkCoverage).toList();
      expect(cover.last, equals(cover.reduce(math.max)));
      expect(
        cover.last / cover.first,
        greaterThanOrEqualTo(2.0),
        reason: 'a ladder whose ends differ by less than 2x reads as one '
            'undifferentiated set — Apex Legends is the counter-example, flat '
            'at 57-73% coverage, where Bronze and Gold are the same picture '
            'in greyscale',
      );
    });

    test('only the apex is solid', () {
      final l = _ladder();
      expect(l.where((s) => s.solid).length, 1);
      expect(l.last.solid, isTrue);
    });

    test('the apex is the simplest mark, not the busiest', () {
      // Detail added at the top backfires at exactly the size where the top
      // rank most needs to read. Every element count below the summit's is
      // allowed to be higher; the summit itself draws one shape.
      final l = _ladder();
      int elements(PrestigeMarkSpec s) =>
          s.solid ? 1 : (s.innerSweep > 0 ? 2 : 1);
      expect(elements(l.last), lessThanOrEqualTo(elements(l[l.length - 2])));
    });
  });

  group('geometry, not colour, carries the rank', () {
    test('the sweeps only ever open further', () {
      final l = _ladder();
      for (var i = 0; i < l.length - 1; i++) {
        expect(l[i + 1].outerSweep, greaterThanOrEqualTo(l[i].outerSweep));
        expect(l[i + 1].innerSweep, greaterThanOrEqualTo(l[i].innerSweep));
      }
      // The inner ring must not start before the outer one has closed, or the
      // two counts overlap and the "how far round has it got" read breaks.
      for (final s in l) {
        if (s.innerSweep > 0) expect(s.outerSweep, 360);
      }
    });

    test('strokes thicken monotonically', () {
      final l = _ladder();
      for (var i = 0; i < l.length - 1; i++) {
        expect(l[i + 1].outerStroke, greaterThan(l[i].outerStroke));
      }
    });

    test('the ladder still orders with every colour stripped', () {
      // The test the whole design exists to pass. Paint all eight in one flat
      // tone and the order must be unchanged — which is true iff nothing but
      // geometry is doing the ordering work.
      final l = _ladder();
      final byInk = [...l]..sort((a, b) =>
          prestigeMarkInkCoverage(a).compareTo(prestigeMarkInkCoverage(b)));
      expect(byInk.map((s) => s.rank).toList(),
          List<int>.generate(l.length, (i) => i + 1));
    });
  });

  group('colour is recognition, not rank', () {
    // The contract changed deliberately here, so the old assertion is gone on
    // purpose rather than by accident.
    //
    // This ladder used to be a single stone hue whose lightness climbed in
    // even steps, and a test asserted exactly that. It is now the metal ladder
    // every ranked-game player already knows: bronze, silver, gold, platinum,
    // diamond, master, grandmaster, champion. That convention CANNOT be
    // lightness-monotonic — bronze is darker than silver and always will be —
    // so requiring it would destroy the recognition it exists to provide.
    //
    // Nothing is lost, because colour was never carrying rank order. Geometry
    // is, via ink mass, and the group above asserts that independently. What
    // colour still owes is: be distinct, be visible, and never wear a meaning
    // this app has already spent.

    test('no tier reads a runtime theme token, on either theme', () {
      // GameColors.emerald and .gold are `static Color` fields the preset
      // system reassigns, so a tier using one has eleven different colours.
      // Const values cannot do that. Identical colours anywhere would mean two
      // ranks that look alike on some preset.
      final l = _ladder();
      expect(l.map((s) => s.onDark.value).toSet().length, l.length,
          reason: 'two tiers share a dark colour');
      expect(l.map((s) => s.onLight.value).toSet().length, l.length,
          reason: 'two tiers share a light colour');
    });

    test('every tier is visible on both grounds', () {
      final l = _ladder();
      for (final s in l) {
        expect(_contrast(s.onDark, const Color(0xFF07100D)),
            greaterThanOrEqualTo(3.0),
            reason: '${s.metal} is too dim on the dark card');
        expect(_contrast(s.onLight, const Color(0xFFFFFFFF)),
            greaterThanOrEqualTo(4.5),
            reason: '${s.metal} is too pale on the light card');
      }
    });

    test('no two metals are confusable on the dark card', () {
      final l = _ladder();
      for (var i = 0; i < l.length; i++) {
        for (var j = i + 1; j < l.length; j++) {
          expect(
            _deltaE(l[i].onDark, l[j].onDark),
            greaterThanOrEqualTo(20.0),
            reason: '${l[i].metal} and ${l[j].metal} are too close to name apart',
          );
        }
      }
    });

    test('no metal wears a colour this app has already spent', () {
      // The two that actually bit: grandmaster started as an orange-red, which
      // is the FAILURE colour that draws red crosses in the very same room
      // strip; and diamond started as a mid blue, which is the XP icon. Both
      // were moved. This is what stops them drifting back.
      const reserved = <String, Color>{
        'failure': Color(0xFFFF5A52),
        'streak': Color(0xFFFF8A4C),
        'xp': Color(0xFF5DADEC),
        'success': Color(0xFF2ECF8F),
      };
      for (final s in _ladder()) {
        reserved.forEach((name, c) {
          expect(
            _deltaE(s.onDark, c),
            greaterThanOrEqualTo(18.0),
            reason: '${s.metal} is too close to the $name colour',
          );
        });
      }
    });

    test('the gradient stops are ordered light to dark within every tier', () {
      // Light from above. A highlight darker than its base, or a shadow
      // lighter than it, reads as a hole rather than an object.
      for (final s in _ladder()) {
        expect(_lStar(s.highlightDark), greaterThan(_lStar(s.onDark)),
            reason: '${s.metal} dark highlight is not lighter than its base');
        expect(_lStar(s.shadowDark), lessThan(_lStar(s.onDark)),
            reason: '${s.metal} dark shadow is not darker than its base');
        expect(_lStar(s.highlightLight), greaterThan(_lStar(s.onLight)),
            reason: '${s.metal} light highlight is not lighter than its base');
        expect(_lStar(s.shadowLight), lessThan(_lStar(s.onLight)),
            reason: '${s.metal} light shadow is not darker than its base');
      }
    });
  });

  group('it renders, and it mirrors', () {
    testWidgets('paints at every size the app actually asks for', (t) async {
      for (final size in [11.0, 12.0, 16.0, 24.0, 44.0, 200.0]) {
        for (final spec in _ladder()) {
          await t.pumpWidget(MaterialApp(
            home: Center(child: PrestigeMark(spec: spec, size: size)),
          ));
          expect(_markOfSize(size), findsOneWidget);
        }
      }
    });

    testWidgets('is byte-identical under RTL', (t) async {
      // A CustomPainter does not mirror itself while the Row around it does,
      // so anything placed left-of or right-of something else would land on
      // the wrong side in Arabic. Every arc here is centred on 12 o'clock, so
      // there is no side to get wrong — this asserts that stays true, by
      // rasterising the same mark under both directions and diffing the bytes.
      const key = ValueKey('mark-boundary');
      final spec = _ladder()[2];

      Future<Uint8List> shot(TextDirection dir) async {
        await t.pumpWidget(
          Directionality(
            textDirection: dir,
            child: MediaQuery(
              data: const MediaQueryData(),
              child: Align(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: key,
                  child: PrestigeMark(
                    spec: spec,
                    size: 100,
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pump();
        final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
        late Uint8List out;
        // toImage only completes once the engine has actually rasterised, so
        // it needs real async — awaiting it on the fake test clock hangs.
        await t.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          out = data!.buffer.asUint8List();
          image.dispose();
        });
        return out;
      }

      expect(await shot(TextDirection.ltr), equals(await shot(TextDirection.rtl)));
    });
  });

  group('the summit engraving', () {
    /// Rasterises one mark and hands back raw RGBA.
    Future<Uint8List> shot(
      WidgetTester t, {
      required double size,
      required bool animate,
      TextDirection dir = TextDirection.ltr,
    }) async {
      const key = ValueKey('apex-boundary');
      await t.pumpWidget(
        Directionality(
          textDirection: dir,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: PrestigeMark(
                  spec: _ladder().last,
                  size: size,
                  animate: animate,
                ),
              ),
            ),
          ),
        ),
      );
      await t.pump();
      final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
      late Uint8List out;
      await t.runAsync(() async {
        final image = await boundary.toImage();
        final data =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        out = data!.buffer.asUint8List();
        image.dispose();
      });
      return out;
    }

    test('is mirror-symmetric about the vertical axis', () {
      // The one property that makes the figure safe in Arabic: a
      // CustomPainter is never mirrored while the row around it is, so a
      // summit mark with a left or a right would sit the wrong way round in
      // half the app.
      //
      // Asserted on the COORDINATES, not on pixels, and that is deliberate.
      // The engraving is low-contrast on purpose — it is struck into the
      // metal, not printed on it — so a whole square moved sideways changes
      // the render by about 15 levels, which is inside the antialiasing noise
      // of a mirrored circle. A pixel test would have passed a broken figure.
      final cells = prestigeApexEngravingCells();
      final mirrored = cells
          .map((c) => Offset(100 - c.dx - kApexEngravingSquare, c.dy))
          .toList();
      int byPosition(Offset a, Offset b) =>
          a.dy != b.dy ? a.dy.compareTo(b.dy) : a.dx.compareTo(b.dx);
      final left = [...cells]..sort(byPosition);
      final right = [...mirrored]..sort(byPosition);
      for (var i = 0; i < left.length; i++) {
        expect(left[i].dx, closeTo(right[i].dx, 0.001),
            reason: 'cell $i has a side');
        expect(left[i].dy, closeTo(right[i].dy, 0.001));
      }
    });

    test('is thirteen squares that stay inside the disc face', () {
      final cells = prestigeApexEngravingCells();
      expect(cells.length, 13);
      for (final c in cells) {
        // Every corner within the rim, which sits at radius 42.
        for (final corner in [
          c,
          Offset(c.dx + kApexEngravingSquare, c.dy),
          Offset(c.dx, c.dy + kApexEngravingSquare),
          Offset(c.dx + kApexEngravingSquare, c.dy + kApexEngravingSquare),
        ]) {
          final d = (corner - const Offset(50, 50)).distance;
          expect(d, lessThan(42),
              reason: 'a square pokes through the rim at $corner');
        }
      }
    });

    testWidgets('does not engrave below the size threshold', (t) async {
      // Below 48 the summit stays the plain disc: this is the size the
      // leaderboard and the profile header actually render at, where an
      // engraved figure is mud and the ladder still has to be readable.
      //
      // Detected by horizontal uniformity rather than by colour, because the
      // palette here depends on the ambient theme and the test has none. A
      // plain disc is a vertical gradient, so every row inside it is one
      // flat colour; an engraved one is not.
      int wobbliestRow(Uint8List px, int w) {
        var worst = 0;
        for (var y = 0; y < w; y++) {
          var lo = 255, hi = 0, seen = 0;
          for (var x = 0; x < w; x++) {
            final i = (y * w + x) * 4;
            if (px[i + 3] < 250) continue; // skip the antialiased rim
            seen++;
            final r = px[i];
            if (r < lo) lo = r;
            if (r > hi) hi = r;
          }
          if (seen > 4 && hi - lo > worst) worst = hi - lo;
        }
        return worst;
      }

      expect(wobbliestRow(await shot(t, size: 24, animate: false), 24),
          lessThanOrEqualTo(8),
          reason: 'the 24pt summit is carrying engraving');
      expect(wobbliestRow(await shot(t, size: 96, animate: false), 96),
          greaterThanOrEqualTo(12),
          reason: 'the 96pt summit lost its engraving');
    });

    testWidgets('animating settles, so it can never hang a pumpAndSettle',
        (t) async {
      // The reason the sheen runs a fixed three passes instead of repeat().
      // A controller on repeat() never settles, and the first version of this
      // hung both summit tests in rank_up_celebration_test until it timed
      // out.
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: PrestigeMark(
              spec: _ladder().last,
              size: 96,
              animate: true,
            ),
          ),
        ),
      );
      await t.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(PrestigeMark), findsOneWidget);
    });
  });
}

/// Kept at the bottom so the tests above read as prose.
Finder _markOfSize(double size) => find.byWidgetPredicate(
      (w) => w is PrestigeMark && w.size == size,
    );
