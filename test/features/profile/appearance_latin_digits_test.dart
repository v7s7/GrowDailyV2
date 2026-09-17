import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';

/// Latin digits on the appearance surfaces and the paywall, in Arabic too
/// (Aziz, 2026-09-01). Four places broke it: the Settings custom theme card
/// converted its swatch count through arabicDigits, the theme preview and
/// the custom theme sheet's sample habit had Arabic-Indic digits typed in,
/// and so did the monthly plan's fine print.
void main() {
  // Arabic-Indic digits (U+0660 to U+0669), escaped so this file does not
  // contain the characters it bans.
  final arabicIndic = RegExp('[\u0660-\u0669]');
  const ar = S(Locale('ar'));

  test('theme and paywall copy prints Latin digits in Arabic', () {
    final lines = <String>[
      ar.themeCustomPreviewHabit,
      ar.premiumFinePrintMonthly,
      ar.premiumFinePrintMonthlyPlay,
      ar.premiumFinePrintLifetime,
      for (var n = 1; n <= 12; n++) ar.premiumTrialLine(n),
      for (var n = 1; n <= 12; n++) ar.premiumLifetimeBreakEven(n),
    ];
    for (final line in lines) {
      expect(arabicIndic.hasMatch(line), isFalse, reason: line);
    }
    expect(ar.themeCustomPreviewHabit, 'قراءة 10 صفحات');
    expect(ar.premiumFinePrintMonthly, contains('قبل 24 ساعة'));
  });

  test('the appearance and paywall screens never convert to Arabic-Indic',
      () {
    // A source scan, because the custom theme card and the preview sample
    // are private to files a test cannot pump on their own. Comment lines
    // are skipped so a note may still name the rule.
    const files = [
      'lib/features/profile/screens/profile_screen.dart',
      'lib/features/profile/screens/profile_screen_sheets.dart',
      'lib/features/profile/screens/theme_preview_screen.dart',
      'lib/features/premium/screens/premium_screen.dart',
    ];
    final offenders = <String>[];
    for (final path in files) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].trimLeft();
        if (code.startsWith('//')) continue;
        if (code.contains('arabicDigits') || arabicIndic.hasMatch(code)) {
          offenders.add('$path:${i + 1}: $code');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}