// What the full-row pop-up says, and that no celebration names a colour.
//
// Aziz, 2026-09-27: the pop-up said «أسبوع X كله أخضر» on every full row,
// but a theme can paint done squares purple, blue or pink, and a habit on
// two days a week fills its row with two squares, not a green week. His
// pick: "say it's done", one short line for every row (S.gridFullRow).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';

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

  test('the full-day line does not claim every habit', () {
    // It fires at 80% of the day's habits (kStreakDayCompletionThreshold),
    // so with five habits it lands with one still open.
    expect(ar.perfectDayMsg, isNot(contains('كل عاداتك')));
    expect(en.perfectDayMsg, isNot(contains('Every habit')));
  });
}
