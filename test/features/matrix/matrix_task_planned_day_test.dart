import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';

/// MatrixTask.plannedDay end to end: a 'yyyy-MM-dd' String on both the guest
/// Hive map and the signed-in Firestore document, cleared with a delete
/// sentinel on the merge-set path, and read defensively whatever shape it
/// comes back in.
void main() {
  MatrixTask task({String? plannedDay}) => MatrixTask(
        id: 't1',
        title: 'Pay the rent',
        quadrant: MatrixQuadrant.schedule,
        isDone: false,
        createdAt: DateTime(2026, 9, 27, 9, 30),
        plannedDay: plannedDay,
        order: 3,
      );

  group('guest map', () {
    test('round trips the key', () {
      final back = MatrixTask.fromMap(task(plannedDay: '2026-10-02').toMap());
      expect(back.plannedDay, '2026-10-02');
    });

    test('omits it when unset and reads it back as null', () {
      final map = task().toMap();
      expect(map.containsKey('plannedDay'), isFalse);
      expect(MatrixTask.fromMap(map).plannedDay, isNull);
    });

    test('a full ISO string comes back as its day, garbage as null', () {
      final map = task().toMap()
        ..['plannedDay'] = DateTime(2026, 10, 2, 15, 45).toIso8601String();
      expect(MatrixTask.fromMap(map).plannedDay, '2026-10-02');
      map['plannedDay'] = 42;
      expect(MatrixTask.fromMap(map).plannedDay, isNull);
      map['plannedDay'] = 'tomorrow';
      expect(MatrixTask.fromMap(map).plannedDay, isNull);
    });
  });

  group('Firestore', () {
    late FakeFirebaseFirestore db;
    setUp(() => db = FakeFirebaseFirestore());

    DocumentReference<Map<String, dynamic>> doc() =>
        db.collection('matrix_tasks').doc('t1');

    Future<MatrixTask> readBack() async => MatrixTask.fromFirestore(
          await doc().get(),
        );

    test('writes the key as a String, not a Timestamp, and reads it back',
        () async {
      final t = task(plannedDay: '2026-10-02');
      expect(t.toFirestore()['plannedDay'], '2026-10-02');
      await doc().set(t.toFirestore(), SetOptions(merge: true));
      expect((await doc().get()).data()!['plannedDay'], '2026-10-02');
      expect((await readBack()).plannedDay, '2026-10-02');
    });

    test('clearing it deletes the field on a merge-set', () async {
      final t = task(plannedDay: '2026-10-02');
      await doc().set(t.toFirestore(), SetOptions(merge: true));
      final cleared = t.copyWith(clearPlannedDay: true);
      expect(cleared.toFirestore()['plannedDay'], isA<FieldValue>());
      await doc().set(cleared.toFirestore(), SetOptions(merge: true));
      expect((await doc().get()).data()!.containsKey('plannedDay'), isFalse);
      expect((await readBack()).plannedDay, isNull);
    });

    test('a Timestamp someone else stored reads as its day, no cast throws',
        () async {
      await doc().set(
        {
          ...task().toFirestore(),
          'plannedDay': Timestamp.fromDate(DateTime(2026, 10, 2, 8)),
        },
        SetOptions(merge: true),
      );
      expect((await readBack()).plannedDay, '2026-10-02');
    });
  });

  group('copyWith and create', () {
    test('copyWith keeps it unless told otherwise', () {
      final t = task(plannedDay: '2026-10-02');
      expect(t.copyWith(title: 'x').plannedDay, '2026-10-02');
      expect(t.copyWith(plannedDay: '2026-10-05').plannedDay, '2026-10-05');
      expect(t.copyWith(clearPlannedDay: true).plannedDay, isNull);
      expect(
        t.copyWith(plannedDay: '2026-10-05', clearPlannedDay: true).plannedDay,
        isNull,
        reason: 'the clear flag wins, as clearReminderAnchorAt does',
      );
    });

    test('create carries it', () {
      final t = MatrixTask.create(
        'Buy bread',
        MatrixQuadrant.doFirst,
        plannedDay: '2026-10-02',
      );
      expect(t.plannedDay, '2026-10-02');
      expect(MatrixTask.create('Buy milk', MatrixQuadrant.doFirst).plannedDay,
          isNull);
    });
  });
}
