import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';

/// The paywall's benefit list is a claim about what the purchase delivers
/// (guidelines 2.3.1(a), 3.1.2(c), 5.6), so its words are pinned here.
///
/// Two lines went wrong before: the colours row sold "48 colours", which no
/// build ever had (27 swatches plus a free picker and hex), and the last row
/// sold "no ads, no data selling", which every free user already gets and
/// which made the free plan sound like it had ads.
void main() {
  const en = S(Locale('en'));
  const ar = S(Locale('ar'));

  List<String> benefitLines(S s) => [
        s.premiumBenefitHabitsTitle,
        s.premiumBenefitHabitsDesc,
        s.premiumBenefitHistoryTitle,
        s.premiumBenefitHistoryDesc,
        s.premiumBenefitInsightsTitle,
        s.premiumBenefitInsightsDesc,
        s.premiumBenefitAppearanceTitle,
        s.premiumBenefitAppearanceDesc,
        s.premiumBenefitTaskRemindersTitle,
        s.premiumBenefitTaskRemindersDesc,
        s.premiumBenefitVoiceTitle,
        s.premiumBenefitVoiceDesc,
        s.premiumBenefitNavBarTitle,
        s.premiumBenefitNavBarDesc,
        s.premiumBenefitFutureTitle,
        s.premiumBenefitFutureDesc,
      ];

  test('no line uses the em dash or Arabic-Indic digits', () {
    for (final s in [en, ar]) {
      for (final line in benefitLines(s)) {
        // The em dash (U+2014) and Arabic-Indic digits (U+0660 to U+0669),
        // escaped so this file does not contain the characters it bans.
        expect(line.contains('\u2014'), isFalse, reason: line);
        expect(
          RegExp('[\u0660-\u0669]').hasMatch(line),
          isFalse,
          reason: 'Latin digits everywhere: $line',
        );
      }
    }
  });

  test('the theme row sells a theme, not 48 colours', () {
    expect(en.premiumBenefitAppearanceTitle, contains('theme'));
    expect(ar.premiumBenefitAppearanceTitle, contains('مظهر'));
    for (final s in [en, ar]) {
      expect(s.premiumBenefitAppearanceDesc, isNot(contains('48')));
      // "9" is the Premium ready-made themes, named as themes so it cannot
      // read as nine colours.
      expect(s.premiumBenefitAppearanceDesc, contains('9'));
    }
    expect(en.premiumBenefitAppearanceDesc, contains('themes'));
    expect(ar.premiumBenefitAppearanceDesc, contains('مظاهر'));
  });

  test('nothing free users already have is sold as a benefit', () {
    final banned = [
      'ads',
      'donat',
      'tip',
      'coffee',
      'إعلان',
      'تبرع',
      'تبرّع',
      'قهوة',
      'ادعم',
    ];
    for (final s in [en, ar]) {
      for (final line in benefitLines(s)) {
        for (final word in banned) {
          expect(
            line.toLowerCase().contains(word),
            isFalse,
            reason: '"$word" in "$line"',
          );
        }
      }
    }
  });
}
