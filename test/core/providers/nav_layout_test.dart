// The bottom bar's layout rules, and the notifier that keeps them.
//
// Storage is the part that matters here. The bar is rebuilt from a list of
// ids that may have been written by an older build (Hive), a newer build
// (Firestore, from the user's other phone), or a hand edit, and the shell
// has to draw SOMETHING sane from every one of those without a crash: a
// missing pinned tab, an id this build has never heard of, a duplicate, a
// list past the cap. Each rule is a unit test because each one is cheap
// here and a blank home screen in the wild.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/providers/nav_layout_provider.dart';

void main() {
  group('sanitizeNavTabs', () {
    test('nothing usable means the default bar', () {
      expect(sanitizeNavTabs(const []), kDefaultNavTabs);
      expect(sanitizeNavTabs(const ['nonsense', 42, null]), kDefaultNavTabs);
    });

    test('unknown ids are dropped and a duplicate keeps its first slot', () {
      expect(
        sanitizeNavTabs(
            const ['grid', 'rooms', 'profile', 'rooms', 'a_future_tab']),
        [NavTab.grid, NavTab.rooms, NavTab.profile],
      );
    });

    test('neither Habits nor Tasks puts Habits back, first', () {
      expect(sanitizeNavTabs(const ['profile', 'rooms']),
          [NavTab.grid, NavTab.profile, NavTab.rooms]);
      // And Profile right after it when Profile is missing too: their
      // default positions.
      expect(sanitizeNavTabs(const ['rooms', 'tasbih']),
          [NavTab.grid, NavTab.profile, NavTab.rooms, NavTab.tasbih]);
    });

    test('a bar without Habits is a choice, and is kept', () {
      // Since 2026-09-30 Habits can leave the bar like Tasks can. Putting
      // it back here would undo what a tasks-only person arranged on every
      // boot and every sign-in.
      expect(sanitizeNavTabs(const ['matrix', 'profile', 'rooms']),
          [NavTab.matrix, NavTab.profile, NavTab.rooms]);
      expect(sanitizeNavTabs(const ['grid', 'profile']),
          [NavTab.grid, NavTab.profile]);
    });

    test('a missing Profile goes right after Habits, else after Tasks', () {
      // After wherever Habits already is, not to index 1.
      expect(sanitizeNavTabs(const ['rooms', 'grid']),
          [NavTab.rooms, NavTab.grid, NavTab.profile]);
      expect(sanitizeNavTabs(const ['matrix', 'rooms', 'grid']),
          [NavTab.matrix, NavTab.rooms, NavTab.grid, NavTab.profile]);
      expect(sanitizeNavTabs(const ['rooms', 'matrix']),
          [NavTab.rooms, NavTab.matrix, NavTab.profile]);
    });

    test('over the cap, unpinned tabs go from the end; pinned never do', () {
      final tabs = sanitizeNavTabs(const [
        'rooms',
        'progress',
        'tasbih',
        'rewards',
        'closet',
        'grid',
        'profile',
      ]);
      expect(tabs.length, kNavTabsMax);
      expect(tabs,
          [NavTab.rooms, NavTab.progress, NavTab.tasbih, NavTab.grid, NavTab.profile],
          reason: 'the tabs placed first survive, and so do Profile and '
              'the only home page');
    });

    test('over the cap, the last of Habits and Tasks is never the one cut',
        () {
      // Tasks sits late in the list and is the only home page: dropping
      // from the end would have taken it and left a bar with neither.
      final tabs = sanitizeNavTabs(const [
        'rooms',
        'progress',
        'tasbih',
        'rewards',
        'closet',
        'matrix',
      ]);
      expect(tabs, [
        NavTab.rooms,
        NavTab.progress,
        NavTab.tasbih,
        NavTab.matrix,
        NavTab.profile,
      ]);
    });

    test('every tab survives the trip through its storage id', () {
      for (final t in NavTab.values) {
        expect(NavTab.byId(t.id), t);
      }
      expect(NavTab.byId(null), isNull);
    });

    test('canRemoveNavTab: never Profile, never the last home page', () {
      const both = [NavTab.grid, NavTab.profile, NavTab.matrix];
      expect(canRemoveNavTab(both, NavTab.grid), isTrue);
      expect(canRemoveNavTab(both, NavTab.matrix), isTrue);
      expect(canRemoveNavTab(both, NavTab.profile), isFalse);

      const tasksOnly = [NavTab.matrix, NavTab.profile, NavTab.rooms];
      expect(canRemoveNavTab(tasksOnly, NavTab.matrix), isFalse);
      expect(canRemoveNavTab(tasksOnly, NavTab.rooms), isTrue);
      // Not in the bar: nothing to remove.
      expect(canRemoveNavTab(tasksOnly, NavTab.grid), isFalse);
    });

    test('resolveStartTab: the pick when the bar holds it, else the other',
        () {
      const both = [NavTab.grid, NavTab.profile, NavTab.matrix];
      expect(resolveStartTab(both, NavTab.grid), NavTab.grid);
      expect(resolveStartTab(both, NavTab.matrix), NavTab.matrix);
      // Tasks picked, then removed from the bar.
      expect(resolveStartTab(const [NavTab.grid, NavTab.profile], NavTab.matrix),
          NavTab.grid);
      // Habits removed: the app opens on Tasks whatever was picked.
      expect(
          resolveStartTab(
              const [NavTab.profile, NavTab.rooms, NavTab.matrix], NavTab.grid),
          NavTab.matrix);
    });

    test('isDefaultNavTabs is about order as well as membership', () {
      expect(isDefaultNavTabs([NavTab.grid, NavTab.profile, NavTab.matrix]),
          isTrue);
      expect(isDefaultNavTabs([NavTab.grid, NavTab.matrix, NavTab.profile]),
          isFalse);
      expect(isDefaultNavTabs([NavTab.grid, NavTab.profile]), isFalse);
    });
  });

  group('NavLayoutNotifier', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('nav_layout_test');
      Hive.init(tmp.path);
      await Hive.openBox<dynamic>('box_settings');
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('add, remove, move and reset', () async {
      final n = NavLayoutNotifier();
      await n.add(NavTab.rooms);
      await n.add(NavTab.progress);
      expect(n.state, [
        NavTab.grid,
        NavTab.profile,
        NavTab.matrix,
        NavTab.rooms,
        NavTab.progress,
      ]);

      // Full: a sixth is refused, not squeezed in.
      await n.add(NavTab.tasbih);
      expect(n.state.length, kNavTabsMax);
      expect(n.state, isNot(contains(NavTab.tasbih)));

      // Profile: refused.
      await n.remove(NavTab.profile);
      expect(n.state, contains(NavTab.profile));

      await n.remove(NavTab.matrix);
      expect(n.state, [NavTab.grid, NavTab.profile, NavTab.rooms, NavTab.progress]);

      // Habits is now the last of the two home pages: refused.
      await n.remove(NavTab.grid);
      expect(n.state, contains(NavTab.grid));

      // ReorderableListView semantics: newIndex counts the moved row as
      // still in place, so "to the end" of four rows is index 4.
      await n.move(0, 4);
      expect(n.state, [NavTab.profile, NavTab.rooms, NavTab.progress, NavTab.grid]);

      await n.reset();
      expect(n.state, kDefaultNavTabs);
    });

    test('what was arranged is there at the next boot', () async {
      final n = NavLayoutNotifier();
      await n.add(NavTab.rooms);
      expect(await loadPersistedNavTabs(),
          [NavTab.grid, NavTab.profile, NavTab.matrix, NavTab.rooms]);
    });

    test('reset leaves nothing stored, which is different from the default',
        () async {
      final n = NavLayoutNotifier();
      await n.add(NavTab.rooms);
      await n.reset();
      expect(await loadPersistedNavTabs(), isNull,
          reason: 'a stored default would freeze people who never customised '
              'onto today\'s default forever');
    });

    test('sign-out drops a custom bar on this device', () async {
      final n = NavLayoutNotifier();
      await n.add(NavTab.rooms);
      await n.detachAccount();
      expect(n.state, kDefaultNavTabs);
      expect(await loadPersistedNavTabs(), isNull);
    });

    test('set sanitises whatever it is handed', () async {
      final n = NavLayoutNotifier();
      await n.set([NavTab.rooms, NavTab.rooms, NavTab.matrix]);
      expect(n.state, [NavTab.rooms, NavTab.matrix, NavTab.profile]);
      await n.set([NavTab.rooms, NavTab.tasbih]);
      expect(n.state,
          [NavTab.grid, NavTab.profile, NavTab.rooms, NavTab.tasbih]);
    });

    test('Habits removed: a tasks-only bar, and it survives the next boot',
        () async {
      final n = NavLayoutNotifier();
      await n.remove(NavTab.grid);
      expect(n.state, [NavTab.profile, NavTab.matrix]);
      // Tasks is now the last home page and stays.
      await n.remove(NavTab.matrix);
      expect(n.state, [NavTab.profile, NavTab.matrix]);
      expect(await loadPersistedNavTabs(), [NavTab.profile, NavTab.matrix]);
    });
  });
}
