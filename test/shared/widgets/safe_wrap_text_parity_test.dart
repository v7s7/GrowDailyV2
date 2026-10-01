// Parity goldens for SafeWrapText and its two measuring helpers, frozen
// from the code as it stood on 2026-09-30: before the widget reused its
// last measurement across rebuilds, and before the helpers disposed their
// TextPainters. Every value below was produced by that code. Never
// regenerate one: a moved value is a change a user can see, a name drawn
// on one line with "…" instead of two, or a name that gains or loses its
// tap-to-reveal bubble.
//
// Four layers, from the inside out:
//  * the helpers on their own ([wordExceedsWidth], [textOverflowsAt]);
//  * the widget mounted fresh for every case, which is what a first
//    build does and what the web still does on every build;
//  * one label kept mounted while its inputs change one at a time, the
//    path a reused measurement could get wrong. Each step must match the
//    frozen value and, live, a twin mounted fresh beside it;
//  * a font registered while a name is on screen, the one moment a kept
//    answer goes stale without any input changing.
//
// The app's own Arabic face (IBM Plex Sans Arabic, bundled under
// google_fonts/) is registered under a private family name, so the Arabic
// cases shape and measure like real habit names rather than as the test
// font's boxes. The default test font covers the rest.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/shared/widgets/safe_wrap_text.dart';

/// Registered in setUpAll, before any widget is built.
const _plex = 'SafeWrapParityPlex';

/// Registered in the middle of one test, while a label names it.
const _late = 'SafeWrapParityLate';

const _base = TextStyle(fontSize: 14, color: Color(0xFF000000));

// The three label styles the matrix runs through: none (the label takes
// the ambient DefaultTextStyle as it is), the Grid's habit name in the
// app's Arabic face, and the history screen's struck-through task title.
const _styles = <TextStyle?>[
  null,
  TextStyle(
    fontFamily: _plex,
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    height: 1.15,
  ),
  TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.lineThrough,
  ),
];

const _longText =
    'This is a genuinely long habit name that will not fit on two lines';
const _giantWord = 'Supercalifragilisticexpialidocious';
const _quranDaily = 'قراءة صفحة من القرآن الكريم يوميًا';

const _texts = <(String, TextDirection)>[
  ('Fajr', TextDirection.ltr),
  ('Morning walk', TextDirection.ltr),
  ('Read one page of Quran', TextDirection.ltr),
  (_longText, TextDirection.ltr),
  (_giantWord, TextDirection.ltr),
  ('قيام الليل', TextDirection.rtl),
  ('أذكار الصباح والمساء', TextDirection.rtl),
  (_quranDaily, TextDirection.rtl),
  ('الاستغفار', TextDirection.rtl),
  ('', TextDirection.ltr),
  ('  spaced   out\tname\n', TextDirection.ltr),
];

const _widths = <double>[44, 90, 300];

// (maxLines, tapToRevealWhenTruncated). maxLines 1 without the reveal is
// left out: it measures nothing and always renders one plain line.
const _caps = <(int, bool)>[(1, true), (2, false), (2, true), (3, true)];

/// Splits a frozen block into its codes, one per case, in case order.
List<String> _codes(String block) =>
    block.split(RegExp(r'\s+')).where((c) => c.isNotEmpty).toList();

/// What a user sees of the label under [key], as two characters: the line
/// cap its Text was given, then 'T' when it sits inside the tap-to-reveal
/// Tooltip and '.' when it does not.
String _seen(WidgetTester tester, Key key) {
  final label = find.byKey(key);
  final text = tester.widget<Text>(
    find.descendant(of: label, matching: find.byType(Text)),
  );
  final tip = find
      .descendant(of: label, matching: find.byType(Tooltip))
      .evaluate()
      .isNotEmpty;
  return '${text.maxLines}${tip ? 'T' : '.'}';
}

/// The ambient inputs SafeWrapText reads from its context, around [child].
/// The Overlay sits outside it all, so the Tooltip branch has one to open
/// into without a MaterialApp in the tree.
Widget _ambient({
  required TextScaler scaler,
  required TextDirection direction,
  required TextStyle base,
  required Widget child,
}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: scaler),
    child: Directionality(
      textDirection: direction,
      child: DefaultTextStyle(
        style: base,
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

Widget _overlay(WidgetBuilder builder) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Overlay(initialEntries: [OverlayEntry(builder: builder)]),
  );
}

void main() {
  late Uint8List plexBytes;

  setUpAll(() async {
    plexBytes = File(
      'google_fonts/IBMPlexSansArabic-SemiBold.ttf',
    ).readAsBytesSync();
    await ui.loadFontFromList(plexBytes, fontFamily: _plex);
  });

  testWidgets('the two helpers answer as they did', (tester) async {
    final exceeds = <String>[];
    final overflows = <String>[];
    for (final (text, direction) in _texts) {
      for (final width in const <double>[44, 60, 90]) {
        for (final style in _styles.skip(1)) {
          for (final scaler in const [
            TextScaler.noScaling,
            TextScaler.linear(1.3),
          ]) {
            final merged = _base.merge(style);
            exceeds.add(
              wordExceedsWidth(
                text,
                width,
                style: merged,
                textDirection: direction,
                textScaler: scaler,
              )
                  ? 'T'
                  : 'F',
            );
            overflows.add(
              textOverflowsAt(
                text,
                width,
                maxLines: 2,
                style: merged,
                textDirection: direction,
                textScaler: scaler,
              )
                  ? 'T'
                  : 'F',
            );
          }
        }
      }
    }
    expect(exceeds.join(), _codes(_exceedsGolden.join(' ')).join());
    expect(overflows.join(), _codes(_overflowsGolden.join(' ')).join());
  });

  testWidgets('every case mounted fresh renders as it did', (tester) async {
    const key = ValueKey('label');
    final seen = <String>[];
    var mount = 0;
    for (final (text, direction) in _texts) {
      for (final width in _widths) {
        for (final style in _styles) {
          for (final (maxLines, tap) in _caps) {
            // A new key at the root each time: a new Overlay, a new
            // SafeWrapText state, nothing carried over from the last case.
            await tester.pumpWidget(
              KeyedSubtree(
                key: ValueKey(mount++),
                child: _overlay(
                  (_) => _ambient(
                    scaler: TextScaler.noScaling,
                    direction: direction,
                    base: _base,
                    child: SizedBox(
                      width: width,
                      child: SafeWrapText(
                        text,
                        key: key,
                        style: style,
                        maxLines: maxLines,
                        tapToRevealWhenTruncated: tap,
                      ),
                    ),
                  ),
                ),
              ),
            );
            seen.add(_seen(tester, key));
          }
        }
      }
    }
    expect(seen, _codes(_freshGolden.join(' ')));
  });

  testWidgets(
      'one label kept mounted renders what a fresh mount does after '
      'every change', (tester) async {
    const kept = ValueKey('kept');
    const twin = ValueKey('twin');
    var twinMount = 0;

    var text = 'Morning walk';
    double width = 90;
    TextStyle? style = _styles[1];
    var maxLines = 2;
    var tap = true;
    var scaler = TextScaler.noScaling;
    var direction = TextDirection.ltr;
    var base = _base;

    late StateSetter rebuild;
    await tester.pumpWidget(
      _overlay(
        (_) => StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            SafeWrapText label(Key key) => SafeWrapText(
                  text,
                  key: key,
                  style: style,
                  maxLines: maxLines,
                  tapToRevealWhenTruncated: tap,
                );
            return _ambient(
              scaler: scaler,
              direction: direction,
              base: base,
              child: SizedBox(
                width: width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    label(kept),
                    // Keyed afresh on every rebuild, so it is always a
                    // brand-new state measuring for the first time.
                    KeyedSubtree(
                      key: ValueKey(twinMount++),
                      child: label(twin),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    final seen = <String>[_seen(tester, kept)];
    expect(seen.last, _seen(tester, twin));

    Future<void> step(void Function() change) async {
      rebuild(change);
      await tester.pump();
      seen.add(_seen(tester, kept));
      expect(
        seen.last,
        _seen(tester, twin),
        reason: 'step ${seen.length - 1}: the kept label must render what '
            'a fresh mount renders',
      );
    }

    await step(() {});
    await step(() => width = 44);
    await step(() {});
    await step(() => width = 60);
    await step(() => text = _giantWord);
    await step(() => text = _longText);
    await step(() => style = _styles[2]);
    // Layout-neutral: only the colour moves.
    await step(
      () => style = _styles[2]!.copyWith(color: const Color(0xFF00AA00)),
    );
    await step(() => style = _styles[2]!.copyWith(fontSize: 20));
    await step(() => scaler = const TextScaler.linear(1.3));
    await step(() => scaler = const TextScaler.linear(2));
    await step(() => scaler = TextScaler.noScaling);
    await step(() {
      text = _quranDaily;
      style = _styles[1];
      direction = TextDirection.rtl;
    });
    await step(() => direction = TextDirection.ltr);
    await step(() => maxLines = 3);
    await step(() => maxLines = 1);
    await step(() => tap = false);
    await step(() => maxLines = 2);
    await step(() => width = 90);
    // The label's own style gone: the merged style is the ambient one, so
    // a change to DefaultTextStyle alone has to reach the measurement.
    await step(() => style = null);
    await step(() => base = _base.copyWith(fontSize: 18));
    await step(() => base = _base.copyWith(fontSize: 26));
    // A Paint-carrying style compares by identity: the same inputs twice,
    // each time in a style that never compares equal to the last one.
    await step(
      () => style = TextStyle(
        fontSize: 11.5,
        foreground: Paint()..color = const Color(0xFF112233),
      ),
    );
    await step(
      () => style = TextStyle(
        fontSize: 11.5,
        foreground: Paint()..color = const Color(0xFF112233),
      ),
    );
    await step(() {
      text = 'Morning walk';
      width = 90;
      style = _styles[1];
      maxLines = 2;
      tap = true;
      scaler = TextScaler.noScaling;
      direction = TextDirection.ltr;
      base = _base;
    });
    await step(() => width = 300);
    await step(() {});
    // One input at a time, each moving the answer on its own: the scaler,
    // then the width, there and back.
    await step(() {
      text = 'Fajr';
      style = null;
      width = 90;
    });
    await step(() => scaler = const TextScaler.linear(2));
    await step(() => scaler = TextScaler.noScaling);
    await step(() => text = 'Morning walk');
    await step(() => width = 300);
    await step(() => width = 90);
    await step(() => width = 90.5);
    await step(() {});

    expect(seen, _codes(_keptGolden.join(' ')));
  });

  testWidgets(
      'a font registered while a name is on screen is measured on the '
      'next rebuild', (tester) async {
    const kept = ValueKey('kept');
    const twin = ValueKey('twin');
    var twinMount = 0;
    late StateSetter rebuild;

    // The family is named before it exists, so the first measurement runs
    // on the fallback face. The width sits between the two faces' widths
    // of "Walking": narrower than the fallback's, wider than Plex's, so
    // the same name lands on one line before the font and two after.
    await tester.pumpWidget(
      _overlay(
        (_) => StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            SafeWrapText label(Key key) => SafeWrapText(
                  'Walking daily',
                  key: key,
                  style: const TextStyle(fontFamily: _late, fontSize: 14),
                );
            return _ambient(
              scaler: TextScaler.noScaling,
              direction: TextDirection.ltr,
              base: _base,
              child: SizedBox(
                width: 70,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    label(kept),
                    KeyedSubtree(
                      key: ValueKey(twinMount++),
                      child: label(twin),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    final before = _seen(tester, kept);

    var notified = false;
    void heard() => notified = true;
    PaintingBinding.instance.systemFonts.addListener(heard);
    await tester.runAsync(
      () => ui.loadFontFromList(plexBytes, fontFamily: _late),
    );
    // The fontsChange message reaches PaintingBinding a few microtasks
    // after the registration itself.
    for (var i = 0; i < 50 && !notified; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    PaintingBinding.instance.systemFonts.removeListener(heard);
    expect(notified, isTrue);

    rebuild(() {});
    await tester.pump();
    final after = _seen(tester, kept);
    expect(after, _seen(tester, twin));

    expect(before, _lateBefore);
    expect(after, _lateAfter);
  });
}

// ── Frozen 2026-09-30 from the code before the change. Never regenerate. ──

// One row per text, in _texts order. Each row: widths 44, 60 and 90; in
// each width the Grid style then the history style; in each style no
// scaling then 1.3x.
const _exceedsGolden = <String>[
  'FFTT FFFT FFFF',
  'FTTT FFTT FFTT',
  'FFTT FFTT FFFF',
  'TTTT FTTT FFTT',
  'TTTT TTTT TTTT',
  'FFTT FFTT FFFF',
  'FTTT FFTT FFTT',
  'FFTT FFTT FFFT',
  'FTTT FFTT FFTT',
  'FFFF FFFF FFFF',
  'FTTT FFTT FFFT',
];

// Same order as _exceedsGolden, laid out at maxLines 2.
const _overflowsGolden = <String>[
  'FFFF FFFF FFFF',
  'FTTT FFTT FFFT',
  'TTTT TTTT FTTT',
  'TTTT TTTT TTTT',
  'TTTT TTTT TTTT',
  'FFTT FFTT FFFF',
  'TTTT FTTT FFTT',
  'TTTT TTTT FTTT',
  'FFTT FFTT FFFF',
  'FFFF FFFF FFFF',
  'TTTT FTTT FFTT',
];

// Three rows per text, in _texts order: widths 44, 90 and 300. Each row:
// no label style, the Grid style, the history style; in each style the
// caps (1, reveal), (2), (2, reveal), (3, reveal).
const _freshGolden = <String>[
  // Fajr
  '1T 1. 1T 1T  1. 2. 2. 3.  1T 1. 1T 1T',
  '1. 2. 2. 3.  1. 2. 2. 3.  1. 2. 2. 3.',
  '1. 2. 2. 3.  1. 2. 2. 3.  1. 2. 2. 3.',
  // Morning walk
  '1T 1. 1T 1T  1T 2. 2. 3.  1T 1. 1T 1T',
  '1T 1. 1T 1T  1. 2. 2. 3.  1T 1. 1T 1T',
  '1. 2. 2. 3.  1. 2. 2. 3.  1. 2. 2. 3.',
  // Read one page of Quran
  '1T 1. 1T 1T  1T 2. 2T 3T  1T 1. 1T 1T',
  '1T 2. 2T 3T  1T 2. 2. 3.  1T 2. 2T 3T',
  '1T 2. 2. 3.  1. 2. 2. 3.  1. 2. 2. 3.',
  // _longText
  '1T 1. 1T 1T  1T 1. 1T 1T  1T 1. 1T 1T',
  '1T 1. 1T 1T  1T 2. 2T 3T  1T 1. 1T 1T',
  '1T 2. 2T 3T  1T 2. 2. 3.  1T 2. 2T 3T',
  // _giantWord
  '1T 1. 1T 1T  1T 1. 1T 1T  1T 1. 1T 1T',
  '1T 1. 1T 1T  1T 1. 1T 1T  1T 1. 1T 1T',
  '1T 1. 1T 1T  1. 2. 2. 3.  1T 1. 1T 1T',
  // قيام الليل
  '1T 1. 1T 1T  1. 2. 2. 3.  1T 1. 1T 1T',
  '1T 2. 2. 3.  1. 2. 2. 3.  1T 2. 2. 3.',
  '1. 2. 2. 3.  1. 2. 2. 3.  1. 2. 2. 3.',
  // أذكار الصباح والمساء
  '1T 1. 1T 1T  1T 2. 2T 3.  1T 1. 1T 1T',
  '1T 1. 1T 1T  1T 2. 2. 3.  1T 1. 1T 1T',
  '1. 2. 2. 3.  1. 2. 2. 3.  1. 2. 2. 3.',
  // _quranDaily
  '1T 1. 1T 1T  1T 2. 2T 3T  1T 1. 1T 1T',
  '1T 2. 2T 3T  1T 2. 2. 3.  1T 2. 2T 3T',
  '1T 2. 2. 3.  1. 2. 2. 3.  1T 2. 2. 3.',
  // الاستغفار
  '1T 1. 1T 1T  1. 2. 2. 3.  1T 1. 1T 1T',
  '1T 1. 1T 1T  1. 2. 2. 3.  1T 1. 1T 1T',
  '1. 2. 2. 3.  1. 2. 2. 3.  1. 2. 2. 3.',
  // The empty name
  '1. 2. 2. 3.  1. 2. 2. 3.  1. 2. 2. 3.',
  '1. 2. 2. 3.  1. 2. 2. 3.  1. 2. 2. 3.',
  '1. 2. 2. 3.  1. 2. 2. 3.  1. 2. 2. 3.',
  // Stray spaces, a tab and a newline
  '1T 1. 1T 1T  1T 2. 2T 3.  1T 1. 1T 1T',
  '1T 2. 2T 3T  1T 2. 2. 3.  1T 2. 2T 3T',
  '1. 2. 2. 3.  1. 2. 2. 3.  1. 2. 2. 3.',
];

// One code per step of the kept-label test, the first build included.
const _keptGolden = <String>[
  // Mounted, same again, 44, same again, 60.
  '2. 2. 2. 2. 2.',
  // Giant word, long text, history style, colour only, size 20.
  '1T 2T 1T 1T 1T',
  // 1.3x, 2x, 1x, the Arabic name right to left, left to right.
  '1T 1T 1T 2T 2T',
  // maxLines 3, maxLines 1, reveal off, maxLines 2, width 90.
  '3. 1T 1. 2. 2.',
  // No label style, ambient 18, ambient 26, a Paint style, a new Paint.
  '2. 1. 1. 2. 2.',
  // Back to the start, 300, same again.
  '2. 2. 2.',
  // Fajr at 90, 2x, 1x, Morning walk, 300, 90, 90.5, same again.
  '2. 1T 2. 1T 2. 1T 1T 1T',
];

// Walking daily at 70 on a family that did not exist yet, then again on
// the first rebuild after it was registered.
const _lateBefore = '1.';
const _lateAfter = '2.';
