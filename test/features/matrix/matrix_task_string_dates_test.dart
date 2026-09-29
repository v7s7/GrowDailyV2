import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';

/// Signed-in tasks whose dates are ISO strings rather than Timestamps.
///
/// Until 2026-09-28 GuestMigrationService copied a guest's Hive maps
/// (MatrixTask.toMap, ISO strings) into `matrix_tasks` unchanged. The
/// migration converts them now, but the accounts that already said yes
/// still hold the strings, and fromFirestore threw on the first one:
/// MatrixNotifier._load parsed every doc inside one try, so its catch-all
/// left the whole Tasks page empty on every open. These pin the read side,
/// which is what brings those accounts back.
void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  final task = MatrixTask(
    id: 't1',
    title: 'Ship it',
    quadrant: MatrixQuadrant.schedule,
    isDone: true,
    createdAt: DateTime(2026, 9, 20, 8, 15),
    completedAt: DateTime(2026, 9, 21, 17, 40),
    reminderAts: [DateTime(2026, 9, 21, 15), DateTime(2026, 9, 21, 16, 30)],
    reminderAnchorAt: DateTime(2026, 9, 21, 16, 30),
    order: 5,
  );

  /// Exactly what the old migration wrote: the guest map minus its id.
  Future<void> writeAsOldMigration(String id, Map<String, dynamic> map) =>
      db.collection('matrix_tasks').doc(id).set(
            Map<String, dynamic>.from(map)..remove('id'),
          );

  test('a task the old migration wrote reads back with its dates', () async {
    await writeAsOldMigration('t1', task.toMap());

    final back = MatrixTask.fromFirestore(
      await db.collection('matrix_tasks').doc('t1').get(),
    );
    expect(back.title, 'Ship it');
    expect(back.createdAt, task.createdAt);
    expect(back.completedAt, task.completedAt);
    expect(back.reminderAts, task.reminderAts);
    expect(back.reminderAnchorAt, task.reminderAnchorAt);
  });

  test('the legacy single reminder is read as a string too', () async {
    // A guest map from a build older than reminderAts carries only the
    // single key, and _remindersFrom falls back to it.
    final map = task.toMap()..remove('reminderAts');
    await writeAsOldMigration('t1', map);

    final back = MatrixTask.fromFirestore(
      await db.collection('matrix_tasks').doc('t1').get(),
    );
    expect(back.reminderAts, [task.reminderAt]);
  });

  test('one unreadable task costs only itself', () async {
    // What MatrixNotifier._load reads through. A doc no reader can use (no
    // title) sits beside a clean one, written the way MatrixNotifier._persist
    // writes, and an old-migration one.
    final clean = MatrixTask(
      id: 'clean',
      title: 'Call the bank',
      quadrant: MatrixQuadrant.doFirst,
      isDone: false,
      createdAt: DateTime(2026, 9, 2),
      order: 1,
    );
    await db
        .collection('matrix_tasks')
        .doc('clean')
        .set(clean.toFirestore(), SetOptions(merge: true));
    await writeAsOldMigration('t1', task.toMap());
    await db.collection('matrix_tasks').doc('broken').set({'quadrant': 1});

    final snap = await db.collection('matrix_tasks').get();
    final tasks = MatrixTask.listFromFirestore(snap.docs);
    expect(tasks.map((t) => t.id), unorderedEquals(['clean', 't1']));
  });
}
