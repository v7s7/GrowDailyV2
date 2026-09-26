// The widgets wear the app's colour theme (Aziz, 2026-09-25). This pins the
// one string the app hands them, because parseWidgetTheme in
// ios/GrowDailyWidget/WidgetFaceRules.swift reads exactly this shape:
// "presetId|#RRGGBB|#RRGGBB", accent then done, and the default theme's id
// is how the faces know to keep their own parchment colours.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/home_widget_service.dart';
import 'package:grow_daily_v2/core/theme/theme_preset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('home_widget');
  final calls = <MethodCall>[];

  /// What the app group already holds, as getWidgetData answers.
  String? stored;

  setUp(() {
    calls.clear();
    stored = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'getWidgetData' ? stored : true;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Iterable<String> saved() => calls
      .where((c) => c.method == 'saveWidgetData')
      .map((c) => (c.arguments as Map)['data'] as String);

  Iterable<String?> reloaded() => calls
      .where((c) => c.method == 'updateWidget')
      .map((c) => (c.arguments as Map)['ios'] as String?);

  test('the string the widget parses, and the three faces reloaded', () async {
    final pink = ThemePresets.byId('baby_pink');
    await HomeWidgetService.instance.pushTheme(
      presetId: pink.id,
      accent: pink.gold,
      done: pink.emerald,
    );

    final value = saved().single;
    expect(value, matches(RegExp(r'^baby_pink\|#[0-9A-F]{6}\|#[0-9A-F]{6}$')));
    final hex = pink.gold.toARGB32() & 0xFFFFFF;
    expect(value.split('|')[1],
        '#${hex.toRadixString(16).padLeft(6, '0').toUpperCase()}');
    expect(reloaded(), [
      'GrowDailyWidget',
      'GrowDailyMatrixWidget',
      'GrowDailyRoomRaceWidget',
    ], reason: 'the Home Screen faces only: Lock Screen ones are tinted by '
        'the system, and the prayer face keeps its skies');
  });

  test('the default theme is sent by its id, which the faces ignore', () async {
    final base = ThemePresets.byId(ThemePresets.defaultId);
    await HomeWidgetService.instance.pushTheme(
      presetId: base.id,
      accent: base.gold,
      done: base.emerald,
    );
    expect(saved().single, startsWith('emerald_gold|'),
        reason: 'WidgetFaceRules.swift keeps the parchment colours for '
            'exactly this id');
  });

  test('the same theme twice costs nothing the second time', () async {
    final teal = ThemePresets.byId('teal');
    for (var i = 0; i < 2; i++) {
      await HomeWidgetService.instance.pushTheme(
        presetId: teal.id,
        accent: teal.gold,
        done: teal.emerald,
      );
    }
    expect(saved(), hasLength(1));
    expect(reloaded(), hasLength(3));
  });

  test('a cold start on the theme the faces already wear reloads nothing',
      () async {
    // A fresh run of the app: this file's tests share the one service, so
    // the "already stored" answer below is what decides, as on a phone.
    final sage = ThemePresets.byId('sage');
    String hexOf(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    stored = 'sage|${hexOf(sage.gold)}|${hexOf(sage.emerald)}';
    await HomeWidgetService.instance.debugForgetTheme();
    await HomeWidgetService.instance.pushTheme(
      presetId: sage.id,
      accent: sage.gold,
      done: sage.emerald,
    );
    expect(saved(), isEmpty);
    expect(reloaded(), isEmpty);
  });

  test('nothing is written off iOS', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final navy = ThemePresets.byId('navy');
    await HomeWidgetService.instance.pushTheme(
      presetId: navy.id,
      accent: navy.gold,
      done: navy.emerald,
    );
    expect(calls, isEmpty);
  });
}
