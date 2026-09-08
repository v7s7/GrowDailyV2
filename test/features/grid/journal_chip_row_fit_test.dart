// The five filter chips are ONE row, on every phone and at every font size.
//
// They used to be a Wrap, which solved a real problem (a scrolling filter row
// hides the chips that do not fit, with no scrollbar and nothing to suggest
// there are more, so a filter can exist and never be found) by dropping the
// fifth chip to a second line. Aziz asked for one row.
//
// The chips need roughly 435pt at their natural size against the 370 a 402pt
// phone actually has, so "make them smaller" is not a fix on its own: it fits
// this phone in Arabic and overflows the next one, or the same phone in
// English. The row scales as a whole instead, which is invisible at normal
// sizes and never hides a chip.
//
// Measured as GEOMETRY, not by intercepting Flutter's overflow error, for the
// two reasons header_action_row_fit_test records: the stripe is a debug-only
// diagnostic while a clipped control is what a user actually loses, and
// installing a FlutterError.onError collector around the harness swallows its
// own pumpAndSettle diagnostics and turns a failure into a ten-minute hang.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/grid/screens/grid_journal_screen.dart';

import '../../helpers/landing_harness.dart';

void main() {
  late LandingHarness h;

  setUp(() async {
    h = LandingHarness();
    await h.prepare(activeCatalogIds: const ['inbox_zero']);
  });
  tearDown(() => h.dispose());

  /// Every chip label, in the order the row lays them out.
  List<String> labelsFor(S s) => [
        s.gridJournalFilterAll,
        s.gridJournalFilterHasNote,
        s.isAr ? 'تخطّي' : 'Skipped',
        s.isAr ? 'فشل' : 'Failed',
        s.isAr ? 'إنجاز إضافي' : 'Bonus',
      ];

  Future<void> pumpJournal(
    WidgetTester tester, {
    required Size size,
    required double textScale,
    required Locale locale,
  }) async {
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        // The LOCALE, not just the direction: S reads Localizations.localeOf,
        // so a Directionality wrapper alone gives RTL layout with English
        // words and measures the wrong strings entirely.
        child: h.app(home: const GridJournalScreen(), locale: locale),
      ),
    );
    await h.settle(tester);
  }

  for (final locale in const [Locale('ar'), Locale('en')]) {
    for (final width in const [320.0, 360.0, 402.0]) {
      for (final scale in const [1.0, 1.4]) {
        testWidgets(
          'all five chips share one row at ${width.toInt()}pt, '
          '${scale}x, ${locale.languageCode}',
          (tester) async {
            await pumpJournal(
              tester,
              size: Size(width, 900),
              textScale: scale,
              locale: locale,
            );

            final s = S(locale);
            final rects = <String, Rect>{};
            for (final label in labelsFor(s)) {
              final finder = find.text(label);
              expect(finder, findsOneWidget,
                  reason: 'chip "$label" is not on screen at all');
              rects[label] = tester.getRect(finder);
            }

            // ONE ROW: every chip's vertical centre is the same. A wrapped
            // fifth chip is the exact failure this replaces, and it shows up
            // here as a second centre a whole line lower.
            //
            // Compared within a point rather than exactly: the FittedBox
            // scale is a fraction, so two chips on the same line can land
            // 5e-14 apart. A second ROW is tens of points away, so this
            // separates the two cases without pretending doubles are exact.
            final centres = rects.values.map((r) => r.center.dy).toList();
            final spread = centres.reduce((a, b) => a > b ? a : b) -
                centres.reduce((a, b) => a < b ? a : b);
            expect(spread, lessThan(1.0),
                reason: 'the chips are on more than one row, ${spread}pt '
                    'apart: ${rects.map((k, v) => MapEntry(k, v.center.dy))}');

            // NOTHING CLIPPED: a chip scaled off the edge would be worse than
            // the wrap it replaced, because it looks like it fits.
            for (final entry in rects.entries) {
              expect(entry.value.left, greaterThanOrEqualTo(-0.5),
                  reason: '"${entry.key}" runs off the start edge');
              expect(entry.value.right, lessThanOrEqualTo(width + 0.5),
                  reason: '"${entry.key}" runs off the end edge');
              expect(entry.value.width, greaterThan(0),
                  reason: '"${entry.key}" collapsed to nothing');
            }

            // STILL LEGIBLE: the row may scale, but not into decoration. The
            // smallest label keeps a real height rather than being squeezed
            // to a hairline.
            final shortest =
                rects.values.map((r) => r.height).reduce((a, b) => a < b ? a : b);
            expect(shortest, greaterThan(7.0),
                reason: 'the row scaled down to ${shortest}pt tall, which is '
                    'no longer something a person can read or aim at');
          },
        );
      }
    }
  }

  testWidgets('no chip is scaled at all on a normal phone', (tester) async {
    // The point of tightening the chip metrics: the FittedBox is a safety net
    // for narrow screens and large fonts, not the everyday layout. If this
    // fails, the chips got bigger again and every phone is now reading a
    // shrunken row.
    await pumpJournal(
      tester,
      size: const Size(402, 900),
      textScale: 1.0,
      locale: const Locale('ar'),
    );
    const s = S(Locale('ar'));
    final height = tester.getRect(find.text(s.gridJournalFilterAll)).height;
    // 12.5pt text lays out around 15pt tall; anything materially under that
    // means the row is being scaled on a phone that has room for it.
    expect(height, greaterThan(13.0),
        reason: 'the chips no longer fit a 402pt phone unscaled (measured '
            '${height}pt), so every device is now seeing a shrunken row');
  });
}
