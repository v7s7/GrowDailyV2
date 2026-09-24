// The account's copy of the notification settings: what the SERVER reads
// before it may send anyone a push (the room pushes in
// functions/push_policy.js, and the admin's message to everyone from
// scripts/admin_lookup's Messages page).
//
// What has to hold: settings this device saved before signing in (as a
// guest, or while signed out) reach the account, so someone who switched
// notifications off is not sent one; and a launch that changes nothing is
// not a write.
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:grow_daily_v2/features/settings/notifiers/notification_settings_notifier.dart';
import 'package:hive/hive.dart';

const _settingsKey = 'notification_settings_v1';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('notification_settings_mirror');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    dir.deleteSync(recursive: true);
  });

  test('settings saved before signing in reach the account, once', () async {
    await LocalStoreService.putSettingsMap(
      _settingsKey,
      const NotificationSettings(masterEnabled: false).toMap(),
    );
    final db = FakeFirebaseFirestore();

    await NotificationSettingsNotifier(firestore: db).pullFromAccount('u1');
    final stored = (await db.doc('users/u1').get()).data();
    expect(
      (stored?['notificationSettings'] as Map?)?['masterEnabled'],
      isFalse,
      reason: 'the server can now see that this person wants nothing sent',
    );

    // Nothing has changed since, so the next sign-in is not another write.
    await db.doc('users/u1').delete();
    await NotificationSettingsNotifier(firestore: db).pullFromAccount('u1');
    expect((await db.doc('users/u1').get()).exists, isFalse);
  });

  test('a change after that goes up again', () async {
    await LocalStoreService.putSettingsMap(
      _settingsKey,
      const NotificationSettings().toMap(),
    );
    final db = FakeFirebaseFirestore();
    await NotificationSettingsNotifier(firestore: db).pullFromAccount('u1');
    await db.doc('users/u1').delete();

    await LocalStoreService.putSettingsMap(
      _settingsKey,
      const NotificationSettings(
        quietHoursStart: TimeOfDay(hour: 23, minute: 30),
      ).toMap(),
    );
    await NotificationSettingsNotifier(firestore: db).pullFromAccount('u1');
    final stored = (await db.doc('users/u1').get()).data();
    expect(
      (stored?['notificationSettings'] as Map?)?['quietHoursStart'],
      '23:30',
    );
  });

  test('a device with none of its own still takes the account\'s', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/u2').set({
      'notificationSettings':
          const NotificationSettings(masterEnabled: false).toMap(),
    });
    final notifier = NotificationSettingsNotifier(firestore: db);

    await notifier.pullFromAccount('u2');
    expect(
      await LocalStoreService.getSettingsMap(_settingsKey),
      containsPair('masterEnabled', false),
      reason: 'pulled down and kept, exactly as before',
    );
  });
}
