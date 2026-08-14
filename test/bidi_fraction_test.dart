import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/utils/bidi_fraction.dart';

// Regression tests for the "100 / 0" bug: Profile's level row rendered
// `'${currentLevelXp} / ${xpToNext}'` — "0 / 100" — but Arabic is an RTL
// paragraph, and digits (bidi class EN) plus '/' (class CS) are all weak
// characters, so the three runs were reordered right-to-left and the row
// read "100 / 0" on a real device. Five call sites shared the pattern.
void main() {
  const lri = '⁦';
  const pdi = '⁩';

  group('progressFraction', () {
    test('keeps the numbers in written order, current first', () {
      expect(progressFraction(0, 100), contains('0 / 100'));
      expect(progressFraction(0, 100).indexOf('0'),
          lessThan(progressFraction(0, 100).indexOf('100')));
    });

    test('wraps the fraction in a left-to-right isolate', () {
      final out = progressFraction(3, 10);
      expect(out.startsWith(lri), isTrue,
          reason: 'must open with U+2066 LEFT-TO-RIGHT ISOLATE');
      expect(out.endsWith(pdi), isTrue,
          reason: 'must close with U+2069 POP DIRECTIONAL ISOLATE');
    });

    test('the isolate characters are the only additions', () {
      // Nothing else may creep in: the visible text must be byte-identical
      // to the old interpolation, so English rendering is untouched.
      expect(progressFraction(3, 10).replaceAll(lri, '').replaceAll(pdi, ''),
          '3 / 10');
    });

    test('honours a tight separator for the cards that use one', () {
      expect(
        progressFraction(7, 20, separator: '/')
            .replaceAll(lri, '')
            .replaceAll(pdi, ''),
        '7/20',
      );
    });

    test('accepts any stringable operands, not just ints', () {
      expect(
        progressFraction('١', '١٠').replaceAll(lri, '').replaceAll(pdi, ''),
        '١ / ١٠',
      );
    });

    test('is stable when both sides are equal or the total is zero', () {
      // A freshly-created account has 0 achievements out of 0 in some
      // catalogs mid-load; the helper must not throw or reorder.
      expect(progressFraction(0, 0).replaceAll(lri, '').replaceAll(pdi, ''),
          '0 / 0');
      expect(progressFraction(10, 10).replaceAll(lri, '').replaceAll(pdi, ''),
          '10 / 10');
    });
  });

  group('bidiIsolate', () {
    test('wraps arbitrary text without altering it', () {
      expect(bidiIsolate('3 of 10'), '$lri３ of 10$pdi'.replaceAll('３', '3'));
    });

    test('is idempotent in content, not in wrapping', () {
      // Double-wrapping is harmless but should be visible in the output, so
      // callers can assert they are not stacking isolates by accident.
      expect(bidiIsolate(bidiIsolate('x')), '$lri$lri' 'x' '$pdi$pdi');
    });
  });
}
