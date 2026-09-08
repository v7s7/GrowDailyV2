// The task reward float must read cleanly in both languages.
//
// It used to be one line. «+10 XP · +4 ذهب» behind a left-to-right mark
// forced the whole pill LTR on an RTL screen and read backwards; the
// all-Arabic «+10 خبرة و+4 ذهب» still put two Latin-digit runs inside one
// Arabic sentence, which bidi is free to reorder. This pins the fix: one
// reward per line, one number and one word each, no bidi control characters
// and no English left in the Arabic copy.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';

void main() {
  test('Arabic reward lines are one number and one word each', () {
    const ar = S(Locale('ar'));
    expect(ar.matrixRewardFloatXp(10), '+10 خبرة');
    expect(ar.matrixRewardFloatGold(4), '+4 ذهب');
    for (final line in [ar.matrixRewardFloatXp(10), ar.matrixRewardFloatGold(4)]) {
      expect(line.contains('‎'), isFalse);
      expect(line.contains('‏'), isFalse);
      expect(RegExp(r'[A-Za-z]').hasMatch(line), isFalse);
      // One digit run per line: nothing left for bidi to swap.
      expect(RegExp(r'\d+').allMatches(line).length, 1);
    }
  });

  test('English reward lines name both rewards', () {
    const en = S(Locale('en'));
    expect(en.matrixRewardFloatXp(10), '+10 XP');
    expect(en.matrixRewardFloatGold(4), '+4 gold');
  });
}
