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

    test('a missing pinned tab is put back where it belongs', () {
      // Grid first, Profile right after it: their default positions.
      expect(sanitizeNavTabs(const ['rooms', 'matrix']),
          [NavTab.grid, NavTab.profile, NavTab.rooms, NavTab.matrix]);
      expect(sanitizeNavTabs(const ['profile', 'rooms']),
          [NavTab.grid, NavTab.profile, NavTab.rooms]);
      // Profile goes after wherever Grid already is, not to index 1.
      expect(sanitizeNavTabs(const ['rooms', 'grid']),
          [NavTab.rooms, NavTab.grid, NavTab.profile]);
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
          reason: 'the tabs placed first survive, and both pinned ones do');
    });

    test('every tab survives the trip through its storage id', () {
      for (final t in NavTab.values) {
        expect(NavTab.byId(t.id), t);
      }
      expect(NavTab.byId(null), isNull);
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

      // Pinned: refused too.
      await n.remove(NavTab.grid);
      expect(n.state, contains(NavTab.grid));

      await n.remove(NavTab.matrix);
      expect(n.state, [NavTab.grid, NavTab.profile, NavTab.rooms, NavTab.progress]);

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
      expect(n.state, [NavTab.grid, NavTab.profile, NavTab.rooms, NavTab.matrix]);
    });
  });
}
