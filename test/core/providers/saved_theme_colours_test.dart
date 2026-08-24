// The shortlist behind the custom theme sheet's "+" button.
//
// Small surface, but three of its four behaviours are the kind that only
// show up on somebody else's device: a colour that was saved before the
// readability guard existed, a list that has grown past its cap, and a
// shortlist surviving a sign-out onto a shared phone. Each one is cheap to
// assert here and expensive to discover in the wild.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/providers/theme_provider.dart';
import 'package:grow_daily_v2/core/theme/theme_preset.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('saved_colours_test');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('a saved colour is fitted before it is stored', () async {
    // The swatch drawn in the row and the colour it applies have to be the
    // same colour. Storing raw and fitting on recall would make the row lie
    // about what tapping it does.
    final n = SavedThemeColoursNotifier();
    const navy = Color(0xFF14213D);
    await n.add(navy, asAccent: true);

    expect(n.state.single, isNot(navy));
    expect(accentColourFits(n.state.single), isTrue);
  });

  test('saving the same colour twice does not duplicate or reorder', () async {
    // The + button stays enabled while the active colour is already saved
    // (a button that vanishes under a moving finger is worse), so this is
    // the press that has to do nothing gracefully.
    final n = SavedThemeColoursNotifier();
    await n.add(const Color(0xFFE4B45F), asAccent: true);
    await n.add(const Color(0xFF2ECF8F), asAccent: true);
    await n.add(const Color(0xFFE4B45F), asAccent: true);

    expect(n.state.length, 2);
    expect(n.state.first.value, 0xFF2ECF8F, reason: 'order changed');
  });

  test('the newest colour wins when the list is full', () async {
    final n = SavedThemeColoursNotifier();
    // 12 distinct hues, into a list that holds 10.
    for (var i = 0; i < 12; i++) {
      await n.add(HSLColor.fromAHSL(1, i * 30.0, 0.6, 0.5).toColor(),
          asAccent: true);
    }
    expect(n.state.length, kMaxSavedColours);

    final newest = HSLColor.fromAHSL(1, 330, 0.6, 0.5).toColor();
    expect(n.state.first.value, fitAccentColour(newest).value,
        reason: 'the colour just saved is the one they care about');
    final oldest = HSLColor.fromAHSL(1, 0, 0.6, 0.5).toColor();
    expect(n.state.any((c) => c.value == fitAccentColour(oldest).value),
        isFalse, reason: 'the oldest should have dropped off');
  });

  test('removing takes out exactly the colour asked for', () async {
    final n = SavedThemeColoursNotifier();
    await n.add(const Color(0xFFE4B45F), asAccent: true);
    await n.add(const Color(0xFF2ECF8F), asAccent: true);
    await n.remove(const Color(0xFFE4B45F));

    expect(n.state.length, 1);
    expect(n.state.single.value, 0xFF2ECF8F);
  });

  test('signing out clears the shortlist off the device', () async {
    // Same reasoning as ThemePresetNotifier.detachAccount: the custom theme
    // is premium, so a shortlist built with it is both a paid artifact and,
    // more to the point, somebody else's colours sitting in front of whoever
    // signs in next on a shared phone.
    final n = SavedThemeColoursNotifier();
    await n.add(const Color(0xFFE4B45F), asAccent: true);
    await n.detachAccount();

    expect(n.state, isEmpty);
    expect(await loadPersistedSavedColours(), isEmpty,
        reason: 'cleared in memory but left on disk');
  });

  test('a colour stored by a build older than the guard is fitted on read',
      () async {
    // The reason loadPersistedSavedColours fits rather than trusting Hive.
    // 000000 is what an unguarded build could have written.
    final box = Hive.box<dynamic>('box_settings');
    await box.put('theme_saved_colours_v1', <int>[0xFF000000, 0xFFFFFFFF]);

    final restored = await loadPersistedSavedColours();
    expect(restored.length, 2);
    for (final c in restored) {
      expect(accentColourFits(c), isTrue, reason: '$c came back out of band');
    }
  });

  test('a shortlist written by a newer build cannot overflow this one',
      () async {
    final box = Hive.box<dynamic>('box_settings');
    await box.put('theme_saved_colours_v1',
        <int>[for (var i = 0; i < 40; i++) 0xFF000000 | (i * 0x0A0A0A)]);

    expect((await loadPersistedSavedColours()).length, kMaxSavedColours);
  });

  test('a garbage value on disk reads back as an empty list', () async {
    // Hive is schemaless, so this is a real shape to survive rather than a
    // hypothetical one.
    final box = Hive.box<dynamic>('box_settings');
    await box.put('theme_saved_colours_v1', 'not a list');
    expect(await loadPersistedSavedColours(), isEmpty);
  });
}
