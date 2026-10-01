// The launch splash's settings (launch_settings.dart): the built-in values
// and the admin's edits laid over them. The cases in
// scripts/admin_lookup/test/fixtures/splash_cases.json are also run by the
// admin page's own rules (test/splash.test.js there), so the page shows
// before Save what phones do after it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/splash_edits.dart';
import 'package:grow_daily_v2/features/launch/launch_scene.dart';
import 'package:grow_daily_v2/features/launch/launch_settings.dart';

void main() {
  group('the cases the admin page also runs', () {
    final fixture = jsonDecode(
      File('scripts/admin_lookup/test/fixtures/splash_cases.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final c in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final shown = LaunchSettings.from(SplashEdits.fromData(c['edits']))
            .describe();
        (c['expect'] as Map<String, dynamic>).forEach((key, value) {
          expect(shown[key], value, reason: key);
        });
      });
    }
  });

  test('every scene of the order is a real scene, and none is the ordinary pair',
      () {
    final names = LaunchScene.values.map((s) => s.name).toSet();
    expect(kSplashSceneOrder.every(names.contains), isTrue);
    expect(kSplashSceneOrder, isNot(contains('dayRing')));
    expect(kSplashSceneOrder, isNot(contains('turnaround')));
    expect(kSplashSceneOrder.toSet().length, kSplashSceneOrder.length);
    expect(kSplashSceneOrder.length, LaunchScene.values.length - 2);
    expect(kSplashPoolWeights.keys.every(names.contains), isTrue);
    expect(
      kSplashPoolWeights.values.every((w) => w >= 0 && w <= kSplashPoolWeightMax),
      isTrue,
    );
  });

  test('the once-a-day and daily chance maps name real scenes', () {
    final names = LaunchScene.values.map((s) => s.name).toSet();
    expect(kSplashOnceADay.keys.every(names.contains), isTrue);
    expect(kSplashOnceADay.values.every((v) => v == 0 || v == 1), isTrue);
    expect(kSplashDailyChance.keys.every(kSplashSceneOrder.contains), isTrue);
    expect(kSplashDailyChance.values.every((v) => v >= 0 && v <= 100), isTrue);
  });

  test('the day roll is the one the admin page computes', () {
    // The same values test/splash.test.js pins for splash_rules.js.
    List<int> rolls(LaunchScene s) =>
        [for (var d = 1; d <= 3; d++) launchDayRoll(s, DateTime(2026, 10, d))];
    expect(rolls(LaunchScene.morningCoffee), [87, 26, 65]);
    expect(rolls(LaunchScene.eveningChecklist), [20, 59, 45]);
    expect(rolls(LaunchScene.winterWait), [15, 1, 40]);
  });

  test('every built-in line fits the length the admin page allows', () {
    for (final scene in LaunchScene.values) {
      expect(launchLine(scene).length, lessThanOrEqualTo(kSplashLineMaxLength),
          reason: scene.name);
    }
    expect(kLaunchSlowLine.length, lessThanOrEqualTo(kSplashLineMaxLength));
  });
}
