// The two collapsible cards at the top of a room: open by default, folded
// is the only state worth a key, and each card remembers on its own.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/providers/room_cards_collapse_provider.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('room_cards_collapse_test');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('both cards open by default, nothing stored', () async {
    expect(await loadPersistedRoomTodayCollapsed(), isFalse);
    expect(await loadPersistedRoomPlanCollapsed(), isFalse);
    final box = Hive.box<dynamic>('box_settings');
    expect(box.get(roomTodayCollapsedKey), isNull);
    expect(box.get(roomPlanCollapsedKey), isNull);
  });

  test('folding one card does not fold the other', () async {
    await persistRoomCardCollapsed(roomTodayCollapsedKey, true);
    expect(await loadPersistedRoomTodayCollapsed(), isTrue);
    expect(await loadPersistedRoomPlanCollapsed(), isFalse);
  });

  test('opening again leaves no key behind', () async {
    await persistRoomCardCollapsed(roomPlanCollapsedKey, true);
    await persistRoomCardCollapsed(roomPlanCollapsedKey, false);
    expect(await loadPersistedRoomPlanCollapsed(), isFalse);
    expect(Hive.box<dynamic>('box_settings').get(roomPlanCollapsedKey), isNull);
  });
}
