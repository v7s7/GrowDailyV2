import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/notifiers/auth_notifier.dart';
import '../models/matrix_task.dart';

class MatrixNotifier extends StateNotifier<List<MatrixTask>> {
  final String? _uid;

  MatrixNotifier(this._uid) : super([]) {
    if (_uid != null) _load();
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('matrix_tasks');

  Future<void> _load() async {
    if (_uid == null) return;
    try {
      final snap = await _col.get();
      if (mounted) {
        final tasks = snap.docs
            .map((d) => MatrixTask.fromFirestore(d))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        state = tasks;
      }
    } catch (_) {}
  }

  void add(String title, MatrixQuadrant quadrant) {
    if (title.trim().isEmpty) return;
    final task = MatrixTask.create(title, quadrant);
    state = [...state, task];
    _upsert(task);
  }

  void toggle(String id) {
    final tasks = state.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final updated = tasks[idx].copyWith(isDone: !tasks[idx].isDone);
    tasks[idx] = updated;
    state = tasks;
    _upsert(updated);
  }

  void delete(String id) {
    state = state.where((t) => t.id != id).toList();
    if (_uid != null) _col.doc(id).delete().ignore();
  }

  void move(String id, MatrixQuadrant newQuadrant) {
    final tasks = state.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final updated = tasks[idx].copyWith(quadrant: newQuadrant);
    tasks[idx] = updated;
    state = tasks;
    _upsert(updated);
  }

  void _upsert(MatrixTask task) {
    if (_uid == null) return;
    _col
        .doc(task.id)
        .set(task.toFirestore(), SetOptions(merge: true))
        .ignore();
  }
}

final matrixProvider =
    StateNotifierProvider<MatrixNotifier, List<MatrixTask>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return MatrixNotifier(uid);
});
