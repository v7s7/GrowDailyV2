// The start page: Habits or Tasks, the page the app opens on.
//
// Only a non-default pick is ever stored (same rule as the badges switch),
// and anything a newer build might write that this one cannot open on
// reads as Habits rather than as a crash or a blank shell.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/providers/nav_layout_provider.dart';
import 'package:grow_daily_v2/core/providers/start_page_provider.dart';

void main() {
  late Directory tmp;
  late Box<dynamic> box;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('start_page_test');
    Hive.init(tmp.path);
    box = await Hive.openBox<dynamic>('box_settings');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('Habits by default, with nothing stored', () async {
    expect(StartPageNotifier().state, NavTab.grid);
    expect(await loadPersistedStartPage(), NavTab.grid);
    expect(box.containsKey('start_page_v1'), isFalse);
  });

  test('Tasks is stored and is there at the next boot', () async {
    final n = StartPageNotifier();
    await n.set(NavTab.matrix);
    expect(n.state, NavTab.matrix);
    expect(await loadPersistedStartPage(), NavTab.matrix);
  });

  test('picking Habits again removes the field instead of writing it',
      () async {
    final n = StartPageNotifier();
    await n.set(NavTab.matrix);
    await n.set(NavTab.grid);
    expect(n.state, NavTab.grid);
    expect(box.containsKey('start_page_v1'), isFalse);
  });

  test('only Habits and Tasks can be a start page', () async {
    final n = StartPageNotifier();
    await n.set(NavTab.rooms);
    expect(n.state, NavTab.grid);
    expect(StartPageNotifier(NavTab.profile).state, NavTab.grid);

    // What a newer build, or a hand edit, might have left on disk.
    await box.put('start_page_v1', 'a_future_tab');
    expect(await loadPersistedStartPage(), NavTab.grid);
    await box.put('start_page_v1', 'rooms');
    expect(await loadPersistedStartPage(), NavTab.grid);
    await box.put('start_page_v1', 42);
    expect(await loadPersistedStartPage(), NavTab.grid);
  });

  test('sign-out goes back to Habits on this device', () async {
    final n = StartPageNotifier();
    await n.set(NavTab.matrix);
    await n.detachAccount();
    expect(n.state, NavTab.grid);
    expect(await loadPersistedStartPage(), NavTab.grid);
  });
}
