// The ranking rows' view switch: seven days by default, the whole room on
// request, and only the non-default is worth a key on disk.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/providers/room_rows_view_provider.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('room_rows_view_test');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('seven days by default, with nothing stored', () async {
    expect(await loadPersistedRoomRowsCompact(), isTrue);
    expect(Hive.box<dynamic>('box_settings').get('room_rows_compact_v1'),
        isNull);
  });

  test('the whole-room view survives to the next boot', () async {
    await persistRoomRowsCompact(false);
    expect(await loadPersistedRoomRowsCompact(), isFalse);
  });

  test('going back to seven days leaves no key behind', () async {
    await persistRoomRowsCompact(false);
    await persistRoomRowsCompact(true);
    expect(await loadPersistedRoomRowsCompact(), isTrue);
    expect(Hive.box<dynamic>('box_settings').get('room_rows_compact_v1'),
        isNull, reason: 'the default is not a preference worth a key');
  });
}
