// Light or dark: the phone's own setting until the person picks one.
//
// The app used to open in light mode whatever the phone said. Aziz,
// 2026-10-02: it should take the person's own default. A fresh install now
// follows the phone (ThemeMode.system), and the toggle flips what is actually
// on screen, which while following the phone has to be read off the phone:
// comparing the mode with dark would turn a phone already in dark mode "dark"
// again, and the first tap would do nothing.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/providers/theme_provider.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('theme_mode_');
    Hive.init(tmp.path);
  });

  /// The toggle starts its Hive write without awaiting it, as in the app;
  /// it has to land before tearDown deletes the store under it.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

  tearDown(() async {
    await settle();
    await LocalStoreService.settleDailyWrites();
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  test('a fresh install follows the phone', () async {
    expect(ThemeModeNotifier().state, ThemeMode.system);
    expect(await loadPersistedThemeMode(), isNull,
        reason: 'nothing chosen yet, so nothing stored to override it');
  });

  test('on a phone in dark mode the first tap turns the app light', () async {
    final n = ThemeModeNotifier()
      ..toggle(platformBrightness: Brightness.dark);
    expect(n.state, ThemeMode.light);
  });

  test('on a phone in light mode the first tap turns the app dark', () async {
    final n = ThemeModeNotifier()
      ..toggle(platformBrightness: Brightness.light);
    expect(n.state, ThemeMode.dark);
  });

  test('once chosen, the choice is kept and the phone no longer decides',
      () async {
    final n = ThemeModeNotifier()
      ..toggle(platformBrightness: Brightness.light);
    await settle();
    expect(await loadPersistedThemeMode(), ThemeMode.dark);

    // The phone's setting is irrelevant from here: dark flips to light.
    n.toggle(platformBrightness: Brightness.dark);
    expect(n.state, ThemeMode.light);
    n.toggle(platformBrightness: Brightness.light);
    expect(n.state, ThemeMode.dark);
  });
}
