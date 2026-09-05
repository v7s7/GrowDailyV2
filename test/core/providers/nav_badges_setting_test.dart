// The badges switch: on by default, off is the only thing worth storing,
// and sign-out puts it back for the next person on the device.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/providers/nav_badges_setting_provider.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nav_badges_setting_test');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('on by default, and nothing is stored for the default', () async {
    expect(NavBadgesSettingNotifier().state, isTrue);
    expect(await loadPersistedNavBadgesEnabled(), isTrue);
  });

  test('off survives to the next boot, on leaves nothing behind', () async {
    final n = NavBadgesSettingNotifier();
    await n.set(false);
    expect(n.state, isFalse);
    expect(await loadPersistedNavBadgesEnabled(), isFalse);

    await n.set(true);
    expect(await loadPersistedNavBadgesEnabled(), isTrue);
    expect(Hive.box<dynamic>('box_settings').get('nav_badges_enabled_v1'),
        isNull,
        reason: 'the default is not a preference worth a key');
  });

  test('sign-out drops the switch back to on for the next person', () async {
    final n = NavBadgesSettingNotifier();
    await n.set(false);
    await n.detachAccount();
    expect(n.state, isTrue);
    expect(await loadPersistedNavBadgesEnabled(), isTrue);
  });
}
