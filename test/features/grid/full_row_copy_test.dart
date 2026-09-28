// What the full-row pop-up says, and that no celebration names a colour.
//
// Aziz, 2026-09-27: the pop-up said «أسبوع X كله أخضر» on every full row,
// but a theme can paint done squares purple, blue or pink, and a habit on
// two days a week fills its row with two squares, not a green week. His
// pick: "say it's done", one short line for every row (S.gridFullRow).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/mascot/sprout_praise.dart';

void main() {
  const ar = S(Locale('ar'));
  const en = S(Locale('en'));

  test('a full row says it is done, whatever days the habit asked for', () {
    expect(ar.gridFullRow('المشي'), 'صف كامل! «المشي»: تم هذا الأسبوع.');
    expect(en.gridFullRow('Walk'), 'Full row! "Walk": done this week.');
  });

  test('a quit row keeps the quit word', () {
    // «التدخين: تم» would read as the habit itself done.
    expect(
      ar.gridFullRowQuit('التدخين'),
      'صف كامل! «التدخين»: التزمت هذا الأسبوع.',
    );
    expect(
      en.gridFullRowQuit('Smoking'),
      'Full row! "Smoking": clean this week.',
    );
  });

  test('no full-row or full-day line names a colour', () {
    // The done colour is the theme's (see gridGreenSquares).
    for (final s in [ar, en]) {
      final lines = [
        s.gridFullRow('x'),
        s.gridFullRowQuit('x'),
        s.perfectDayMsg,
      ];
      for (final l in lines) {
        for (final colour in ['أخضر', 'خضرا', 'خضراء', 'green', 'Green']) {
          expect(l, isNot(contains(colour)), reason: l);
        }
        expect(l, isNot(contains('—')), reason: l);
      }
    }
  });

  test('the streak-point lines claim neither every habit nor a full day', () {
    // They fire at 80% of the day's habits (kStreakDayCompletionThreshold),
    // so with five habits they land with one still open. 80% is a streak
    // pass; a full day is every habit the day asked for (Aziz, 2026-09-28).
    // The sprout's praise plays at 80% too (every group, both forms).
    List<String> praise(S s) => [
          for (final group in PraiseGroup.values)
            for (final form in PraiseForm.values)
              ...praiseLines(s, group, form: form),
        ];
    for (final line in [ar.perfectDayMsg, ar.sproutStreakPoint, ...praise(ar)]) {
      expect(line, isNot(contains('كل عاداتك')), reason: line);
      expect(line, isNot(contains('كامل')), reason: line);
      expect(line, isNot(contains('مثالي')), reason: line);
    }
    for (final line in [en.perfectDayMsg, en.sproutStreakPoint, ...praise(en)]) {
      expect(line.toLowerCase(), isNot(contains('every habit')), reason: line);
      expect(line.toLowerCase(), isNot(contains('full day')), reason: line);
      expect(line.toLowerCase(), isNot(contains('perfect')), reason: line);
    }
  });

  test('every habit done is told it is a perfect day', () {
    // Aziz, 2026-09-28: "if user did them all he must get that he did a
    // perfect day". The card and the sprout say it on that tap, and the
    // streak's own explainer says where 80% ends and a perfect day begins.
    expect(ar.gridPerfectDay, contains('يوم مثالي'));
    expect(ar.sproutPerfectDay, contains('يوم مثالي'));
    expect(ar.statInfoStreakDesc, contains('80%'));
    expect(ar.statInfoStreakDesc, contains('مثالي'));
    expect(en.statInfoStreakDesc, contains('80%'));
    expect(en.statInfoStreakDesc, contains('perfect day'));
  });
}
