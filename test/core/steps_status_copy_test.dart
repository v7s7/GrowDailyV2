// The copy a person reads when a linked walking habit is not completing.
//
// The whole point of these lines is that they are honest about a thing the
// app cannot always know. On iOS a refused read and a quiet morning are the
// same empty answer by Apple's design (HealthKit hides read grants), so the
// app must not assert a cause; on Android Health Connect fails the query
// outright, so it may. The two platforms also need the person sent to two
// different places, and sending someone to the wrong one is worse than
// saying nothing.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';

void main() {
  const ar = S(Locale('ar'));
  const en = S(Locale('en'));

  group('the not-arriving hint names the right store', () {
    test('Apple Health on the iOS side, and never Health Connect', () {
      for (final s in [ar, en]) {
        final hint = s.stepsNotArrivingHint(isHealthConnect: false);
        expect(hint, isNot(contains('Health Connect')));
        expect(hint, isNot(contains('Fitbit')));
      }
      expect(ar.stepsNotArrivingHint(isHealthConnect: false), contains('صحتي'));
      expect(
        en.stepsNotArrivingHint(isHealthConnect: false),
        contains('Apple Health'),
      );
    });

    test('Health Connect on the Android side, and never Apple Health', () {
      for (final s in [ar, en]) {
        final hint = s.stepsNotArrivingHint(isHealthConnect: true);
        expect(hint, contains('Health Connect'));
        expect(hint, isNot(contains('Apple')));
      }
    });

    test('the Android hint explains the thing that is actually wrong', () {
      // Health Connect is a store, not a pedometer. On a phone where nothing
      // writes into it the count is zero forever, and "check your permission"
      // would send the person to a setting that is already correct.
      expect(
        en.stepsNotArrivingHint(isHealthConnect: true),
        contains('write'),
      );
      expect(
        ar.stepsNotArrivingHint(isHealthConnect: true),
        contains('يكتبها'),
      );
    });
  });

  group('a stalled link', () {
    test('says what is missing and how to get it back', () {
      expect(ar.stepsLinkBlocked, contains('Health Connect'));
      expect(en.stepsLinkBlocked, contains('Health Connect'));
      expect(ar.stepsLinkBlocked, contains('إذن'));
      expect(en.stepsLinkBlocked, contains('permission'));
    });

    test('a device with no provider says the habit is still yours to mark', () {
      expect(ar.stepsLinkNoProvider, contains('تعلّمها بنفسك'));
      expect(en.stepsLinkNoProvider, contains('mark it yourself'));
    });

    test('every line is answered in both languages', () {
      for (final pair in [
        (ar.stepsLinkBlocked, en.stepsLinkBlocked),
        (ar.stepsLinkNoProvider, en.stepsLinkNoProvider),
        (
          ar.stepsNotArrivingHint(isHealthConnect: true),
          en.stepsNotArrivingHint(isHealthConnect: true)
        ),
      ]) {
        expect(pair.$1, isNotEmpty);
        expect(pair.$2, isNotEmpty);
        expect(pair.$1, isNot(pair.$2));
      }
    });
  });

  group('the custom goal control', () {
    test('the fourth choice is named, not a number', () {
      // It sits beside 3000 / 6000 / 10000, so it has to read as "type your
      // own" rather than as another suggestion from the app.
      expect(ar.stepGoalCustom, 'مخصص');
      expect(en.stepGoalCustom, 'Custom');
    });

    test('the field says what it is counting', () {
      // Beside the box, not inside it as a hint: a hint vanishes the moment
      // somebody types, which is exactly when "steps or minutes?" is asked.
      expect(ar.stepGoalFieldLabel, contains('خطوة'));
      expect(en.stepGoalFieldLabel, contains('steps'));
    });

    test('an unusable number names the range instead of just refusing', () {
      expect(ar.stepGoalOutOfRange(100, 100000), contains('100'));
      expect(ar.stepGoalOutOfRange(100, 100000), contains('100000'));
      expect(en.stepGoalOutOfRange(100, 100000),
          'Enter a number between 100 and 100000 steps.');
    });
  });

  group('the progress line', () {
    test('a null count shows the goal alone, never a made-up number', () {
      // What a stalled link renders: the last successful count is stale, and
      // showing it as today's would be the same false claim the silent zero
      // used to make.
      expect(ar.stepsProgressLine(null, 6000), contains('6000'));
      expect(ar.stepsProgressLine(null, 6000), isNot(contains('/')));
      expect(en.stepsProgressLine(null, 6000), 'Goal: 6000 steps');
    });

    test('a real count keeps current before goal', () {
      final line = en.stepsProgressLine(5320, 8000).replaceAll(
            RegExp('[⁦⁩]'),
            '',
          );
      expect(line, '5320 / 8000 steps today');
    });
  });
}
