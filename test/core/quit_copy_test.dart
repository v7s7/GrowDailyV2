// What a quit habit is called, everywhere it is marked.
//
// Aziz, 2026-09-08, testing the quit side end to end. The palette called a
// slip «فشل» while the evening check-in's button called it «زلة», the board
// said «الإقلاع والتقليل» while the switch said «ترك أو تقليل», and a quit
// habit with a clock cue was told "It's time. Don't let today slip by." with
// Mark Done under it. One vocabulary now, and it is the check-in's.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/l10n/reminder_copy.dart';
import 'package:grow_daily_v2/features/grid/models/square_state.dart';

void main() {
  const ar = S(Locale('ar'));
  const en = S(Locale('en'));

  test('the palette names a quit day the way the check-in buttons do', () {
    expect(ar.quitSquareLabel(SquareState.complete), onTrackAction(true));
    expect(ar.quitSquareLabel(SquareState.failed), slippedAction(true));
    expect(en.quitSquareLabel(SquareState.complete), 'Kept');
    expect(en.quitSquareLabel(SquareState.failed), 'Slipped');
    expect(ar.quitSquareLabel(SquareState.none), 'بدون تسجيل');
  });

  test('«فشل» is never a quit word', () {
    for (final st in SquareState.values) {
      expect(ar.quitSquareLabel(st), isNot(contains('فشل')));
      expect(ar.quitSquareStateEffect(st), isNot(contains('فشل')));
    }
  });

  test('the board and the switch use the same words', () {
    expect(ar.gridSectionQuit, ar.goalTypeQuitOption);
    expect(en.gridSectionQuit, en.goalTypeQuitOption);
  });

  test('an unrecorded quit day explains the overnight rule, not a penalty', () {
    expect(ar.quitSquareStateEffect(SquareState.none), contains('تلقائيًا'));
    expect(ar.quitSquareStateEffect(SquareState.none),
        isNot(contains('تُحسب عليك')));
    expect(ar.quitSquareStateEffect(SquareState.failed), contains('زلة'));
  });

  test('a quit reminder asks the check-in question and names both answers',
      () {
    expect(quitReminderBody(isLimit: false, isAr: true),
        'كيف اليوم إلى الآن؟ التزام أو زلة.');
    expect(quitReminderBody(isLimit: true, isAr: true),
        'ضمن الحد إلى الآن؟ التزام أو زلة.');
    expect(quitReminderBody(isLimit: false, isAr: false),
        'How is today so far? Kept or slipped.');
    for (final isLimit in [true, false]) {
      final body = quitReminderBody(isLimit: isLimit, isAr: true);
      expect(body, isNot(contains('لسا')));
      expect(body, contains(onTrackAction(true)));
      expect(body, contains(slippedAction(true)));
    }
  });

  test('the limit rule reads as a rule, with the unit the person chose', () {
    expect(ar.quitLimitRule(30, ar.limitUnitLabel('minutes')),
        'الحد: 30 دقائق في اليوم');
    expect(ar.quitLimitRule(5, 'سجائر'), 'الحد: 5 سجائر في اليوم');
    expect(en.quitLimitRule(2, en.limitUnitLabel('cups')), 'Limit: 2 cups a day');
  });
}
