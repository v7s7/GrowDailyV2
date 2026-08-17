import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:grow_daily_v2/core/utils/western_digits.dart';

/// The digit normaliser three call sites had each hand-rolled, plus the
/// date-formatting rule it exists to enforce.
void main() {
  final arabicIndic = RegExp(r'[٠-٩]');
  final arabicLetters = RegExp(r'[؀-ۿ]');

  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  group('toWesternDigits', () {
    test('maps every Arabic-Indic digit to its ASCII counterpart', () {
      expect(toWesternDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
    });

    test('leaves ASCII input untouched', () {
      expect(toWesternDigits('2026-08-16'), '2026-08-16');
      expect(toWesternDigits(''), '');
    });

    test('passes non-digit characters through, including Arabic letters', () {
      // The parsing call sites depend on this: a time typed as "٧:٣٠ ص" has
      // to keep its separator and its ص so the AM/PM pattern still matches.
      expect(toWesternDigits('٧:٣٠ ص'), '7:30 ص');
      expect(toWesternDigits('الأحد، ١٦ أغسطس'), 'الأحد، 16 أغسطس');
    });

    test('handles mixed input in one pass', () {
      expect(toWesternDigits('٤5٦'), '456');
    });
  });

  group('westernDate', () {
    final d = DateTime(2026, 8, 16);

    test('keeps the Arabic month name but normalises the digits', () {
      final out = westernDate(d, 'd MMMM', 'ar');
      expect(out, contains('16'));
      expect(arabicIndic.hasMatch(out), isFalse);
      expect(arabicLetters.hasMatch(out), isTrue,
          reason: 'the month name must stay Arabic, not fall back to English');
    });

    test('is a no-op for English', () {
      expect(westernDate(d, 'MMM d', 'en'), 'Aug 16');
    });

    test('documents what intl actually returns for the locales this app '
        'ships', () {
      // Pinned deliberately, because the obvious assumption is wrong and
      // cost a wrong diagnosis once already: plain 'ar' carries no
      // Arabic-Indic symbol data, so DateFormat returns ASCII and
      // westernDate is a no-op on it. Only the country-qualified locales do.
      // If this ever flips, westernDate starts doing real work and the
      // call sites that skipped it need revisiting.
      expect(DateFormat('d', 'ar').format(d), '16');
      expect(arabicIndic.hasMatch(DateFormat('d', 'ar_EG').format(d)), isTrue);
    });
  });
}
