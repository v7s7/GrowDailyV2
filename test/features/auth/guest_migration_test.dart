import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/auth/services/guest_migration_service.dart';

/// Moving a guest's local data onto the account they just created.
///
/// The interesting failures here are all shape-level rather than logic
/// level, which is why these run against a real (fake) Firestore instead
/// of asserting on an intermediate map: a String landing in a field every
/// reader expects to hold a Timestamp reads back as a crash, not as a
/// wrong number, and no amount of unit-testing the payload builder would
/// have caught it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const uid = 'user-1';
  late Directory tmp;
  late FakeFirebaseFirestore db;

  late Box<dynamic> settings;
  late Box<dynamic> habits;
  late Box<dynamic> daily;

  Future<Map<String, dynamic>> userDoc() async =>
      (await db.collection('users').doc(uid).get()).data() ?? {};

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('guest_migration_');
    Hive.init(tmp.path);
    settings = await Hive.openBox<dynamic>('box_settings');
    habits = await Hive.openBox<dynamic>('box_habits');
    daily = await Hive.openBox<dynamic>('box_daily_logs');
    db = FakeFirebaseFirestore();
    GuestMigrationService.firestoreOverride = db;
    // The account exists before the migration runs — it is created by
    // registration, and the migration merges onto it.
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Warrior',
      'level': 1,
      'activeCatalogIds': <String>[],
    });
  });

  tearDown(() async {
    GuestMigrationService.firestoreOverride = null;
    await LocalStoreService.settleDailyWrites();
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('summarize', () {
    test('counts what the sheet names back to the person', () async {
      await settings.put(
          LocalStoreService.activeCatalogIdsKey, ['morning_athkar', 'witr']);
      await habits.put(LocalStoreService.guestCustomHabitsKey, [
        {'id': 'a', 'name': 'Read'}
      ]);
      await settings.put(LocalStoreService.guestMatrixTasksKey, [
        {'id': 't1'},
        {'id': 't2'}
      ]);
      await settings
          .put(LocalStoreService.guestDashboardKey, {'level': 4, 'gold': 90});
      await daily.put('2026-08-30', {
        'habitCompletions': {'witr': 1}
      });

      final snapshot = await GuestMigrationService.summarize();
      expect(snapshot.habitCount, 3);
      expect(snapshot.dayCount, 1);
      expect(snapshot.level, 4);
      expect(snapshot.taskCount, 2);
      expect(snapshot.isEmpty, isFalse);
    });

    test('an empty stored day is not counted as history', () async {
      // Days get written for reasons other than progress. Counting them
      // would inflate the number the person is asked to recognise, which
      // is the one thing making the shared-device check work.
      await daily.put('2026-08-30', <String, dynamic>{});
      final snapshot = await GuestMigrationService.summarize();
      expect(snapshot.dayCount, 0);
      expect(snapshot.isEmpty, isTrue);
    });
  });

  group('migrate', () {
    test('carries the economy onto the profile document', () async {
      await settings.put(LocalStoreService.guestDashboardKey, {
        'level': 7,
        'cumulativeXp': 4200,
        'gold': 310,
        'currentStreak': 9,
        'longestStreak': 14,
        'unlockedAchievements': ['first_step'],
        'habitTotalCompletions': {'witr': 22},
      });

      final result = await GuestMigrationService.migrate(uid);
      expect(result.failed, isFalse);

      final doc = await userDoc();
      expect(doc['level'], 7);
      expect(doc['cumulativeXp'], 4200);
      expect(doc['gold'], 310);
      expect(doc['currentStreak'], 9);
      expect(doc['longestStreak'], 14);
      expect(doc['unlockedAchievements'], ['first_step']);
      expect(doc['habitTotalCompletions'], {'witr': 22});
    });

    test('carries the catalog WITH its activation dates', () async {
      // The whole point. Ids without dates is the state that made every
      // past day grade as a miss — see
      // test/features/habits/guest_signup_catalog_carryover_test.dart.
      await settings
          .put(LocalStoreService.activeCatalogIdsKey, ['morning_athkar']);
      await settings.put(LocalStoreService.activeCatalogActivatedAtKey,
          {'morning_athkar': '2026-08-01T00:00:00.000'});

      await GuestMigrationService.migrate(uid);

      final doc = await userDoc();
      expect(doc['activeCatalogIds'], ['morning_athkar']);
      expect(doc['activeCatalogActivatedAt'],
          {'morning_athkar': '2026-08-01T00:00:00.000'});
    });

    test('rewrites lastActiveDate as a Timestamp and adds lastActiveDay',
        () async {
      // A guest stores an ISO string here; every signed-in reader expects
      // a Timestamp, and firestore.rules validates a separate date-key
      // field that the guest side does not keep at all.
      await settings.put(LocalStoreService.guestDashboardKey,
          {'lastActiveDate': '2026-08-28T09:30:00.000'});

      await GuestMigrationService.migrate(uid);

      final doc = await userDoc();
      expect(doc['lastActiveDate'], isA<Timestamp>());
      expect((doc['lastActiveDate'] as Timestamp).toDate().day, 28);
      expect(doc['lastActiveDay'], '2026-08-28');
    });

    test('does not overwrite the account display name', () async {
      // The one field that reaches a Rooms leaderboard, and the guest's
      // copy never passed setDisplayName's moderation.
      await settings.put(LocalStoreService.guestDashboardKey,
          {'displayName': 'unscreened-name', 'level': 3});

      await GuestMigrationService.migrate(uid);

      final doc = await userDoc();
      expect(doc['displayName'], 'Warrior');
      expect(doc['level'], 3, reason: 'the rest of the map still moves');
    });

    test('moves every stored day into the daily collection', () async {
      await daily.put('2026-08-29', {
        'habitCompletions': {'witr': 1},
        'squareStates': {'witr': 'green'},
      });
      await daily.put('2026-08-30', {
        'habitCompletions': {'witr': 2}
      });

      final result = await GuestMigrationService.migrate(uid);
      expect(result.movedDays, 2);

      final col =
          await db.collection('users').doc(uid).collection('daily').get();
      expect(col.docs.map((d) => d.id), containsAll(['2026-08-29', '2026-08-30']));
      final first = col.docs.firstWhere((d) => d.id == '2026-08-29').data();
      expect(first['habitCompletions'], {'witr': 1});
      expect(first['squareStates'], {'witr': 'green'});
      // Stamped as a Timestamp, matching what the signed-in writer stores.
      expect(first['date'], isA<Timestamp>());
    });

    test('skips a day dated after today instead of failing the batch',
        () async {
      // firestore.rules refuses a future daily doc (notAhead), and one
      // rejected write fails its whole batch — so a device whose clock was
      // wound forward during the guest session would otherwise cost every
      // good day batched alongside it.
      final future = DateTime.now().effectiveDay.add(const Duration(days: 3));
      await daily.put(future.toDateKey(), {
        'habitCompletions': {'witr': 1}
      });
      await daily.put('2026-08-29', {
        'habitCompletions': {'witr': 1}
      });

      final result = await GuestMigrationService.migrate(uid);
      expect(result.failed, isFalse);
      expect(result.movedDays, 1);

      final col =
          await db.collection('users').doc(uid).collection('daily').get();
      expect(col.docs.map((d) => d.id), ['2026-08-29']);
    });

    test('moves custom habits and archived ones into one collection',
        () async {
      await habits.put(LocalStoreService.guestCustomHabitsKey, [
        {'id': 'h1', 'name': 'Read'}
      ]);
      await habits.put(LocalStoreService.guestArchivedCustomHabitsKey, [
        {'id': 'h2', 'name': 'Old', 'archivedAt': '2026-07-01T00:00:00.000'}
      ]);

      await GuestMigrationService.migrate(uid);

      final col = await db
          .collection('users')
          .doc(uid)
          .collection('custom_habits')
          .get();
      expect(col.docs.map((d) => d.id), containsAll(['h1', 'h2']));
      // Archived is the same document carrying archivedAt, not a separate
      // place — CustomHabitsNotifier._load splits one read on that field.
      final archived = col.docs.firstWhere((d) => d.id == 'h2').data();
      expect(archived['archivedAt'], isNotNull);
      // The id is the document name, not duplicated inside it.
      expect(archived.containsKey('id'), isFalse);
    });

    test('moves matrix tasks and custom rewards', () async {
      await settings.put(LocalStoreService.guestMatrixTasksKey, [
        {'id': 't1', 'title': 'Ship it'}
      ]);
      await settings.put(LocalStoreService.guestCustomRewardsKey, [
        {'id': 'r1', 'label': 'Coffee'}
      ]);

      await GuestMigrationService.migrate(uid);

      final tasks = await db
          .collection('users')
          .doc(uid)
          .collection('matrix_tasks')
          .get();
      final rewards = await db
          .collection('users')
          .doc(uid)
          .collection('custom_rewards')
          .get();
      expect(tasks.docs.single.id, 't1');
      expect(tasks.docs.single.data()['title'], 'Ship it');
      expect(rewards.docs.single.id, 'r1');
    });

    test('a record with no id is skipped rather than given a new one',
        () async {
      // A generated id would be a different id on every run, which is what
      // would turn the retry below into duplicated habits.
      await habits.put(LocalStoreService.guestCustomHabitsKey, [
        {'name': 'No id here'},
        {'id': 'h1', 'name': 'Read'},
      ]);

      await GuestMigrationService.migrate(uid);

      final col = await db
          .collection('users')
          .doc(uid)
          .collection('custom_habits')
          .get();
      expect(col.docs.map((d) => d.id), ['h1']);
    });

    test('running twice is not running it twice', () async {
      // The local copy deliberately survives a successful migration so a
      // partial failure can be retried from the Profile banner. That only
      // works if the retry is safe.
      await habits.put(LocalStoreService.guestCustomHabitsKey, [
        {'id': 'h1', 'name': 'Read'}
      ]);
      await settings.put(LocalStoreService.guestMatrixTasksKey, [
        {'id': 't1', 'title': 'Ship it'}
      ]);
      await daily.put('2026-08-29', {
        'habitCompletions': {'witr': 1}
      });
      await settings.put(LocalStoreService.guestDashboardKey, {'gold': 50});

      await GuestMigrationService.migrate(uid);
      await GuestMigrationService.migrate(uid);

      final userRef = db.collection('users').doc(uid);
      expect((await userRef.collection('custom_habits').get()).docs.length, 1);
      expect((await userRef.collection('matrix_tasks').get()).docs.length, 1);
      expect((await userRef.collection('daily').get()).docs.length, 1);
      expect((await userDoc())['gold'], 50);
    });

    test('an empty device writes nothing and still reports success',
        () async {
      final result = await GuestMigrationService.migrate(uid);
      expect(result.failed, isFalse);
      expect(result.movedDays, 0);
      // The profile document is left exactly as registration made it.
      expect((await userDoc())['level'], 1);
    });
  });
}
