import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../models/matrix_task.dart';

class MatrixNotifier extends StateNotifier<List<MatrixTask>> {
  final String? _uid;

  // A guest can mutate (e.g. tap a one-tap suggestion) before the disk
  // read in _loadGuest resolves — both fire in the same tick right after
  // construction. Without this guard the disk read wins the race and
  // silently wipes out the just-added task.
  bool _mutatedBeforeLoad = false;

  MatrixNotifier(this._uid) : super([]) {
    if (_uid != null) {
      _load();
    } else {
      _loadGuest();
    }
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
      if (mounted && !_mutatedBeforeLoad) {
        final tasks = snap.docs
            .map((d) => MatrixTask.fromFirestore(d))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        state = tasks;
      }
    } catch (_) {}
  }

  Future<void> _loadGuest() async {
    try {
      final box = await LocalStoreService.settingsBox();
      final raw = LocalStoreService.asMapList(
        box.get(LocalStoreService.guestMatrixTasksKey),
      );
      if (!mounted || _mutatedBeforeLoad) return;
      state = raw.map(MatrixTask.fromMap).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } catch (_) {}
  }

  Future<void> _saveGuest() async {
    final box = await LocalStoreService.settingsBox();
    await box.put(
      LocalStoreService.guestMatrixTasksKey,
      state.map((t) => t.toMap()).toList(),
    );
  }

  void add(String title, MatrixQuadrant quadrant) {
    if (title.trim().isEmpty) return;
    _mutatedBeforeLoad = true;
    final task = MatrixTask.create(title, quadrant);
    state = [...state, task];
    _persist(task);
  }

  void toggle(String id) {
    _mutatedBeforeLoad = true;
    final tasks = state.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final updated = tasks[idx].copyWith(isDone: !tasks[idx].isDone);
    tasks[idx] = updated;
    state = tasks;
    _persist(updated);
  }

  void delete(String id) {
    _mutatedBeforeLoad = true;
    state = state.where((t) => t.id != id).toList();
    if (_uid != null) {
      _col.doc(id).delete().ignore();
    } else {
      _saveGuest().ignore();
    }
  }

  void move(String id, MatrixQuadrant newQuadrant) {
    _mutatedBeforeLoad = true;
    final tasks = state.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final updated = tasks[idx].copyWith(quadrant: newQuadrant);
    tasks[idx] = updated;
    state = tasks;
    _persist(updated);
  }

  void _persist(MatrixTask task) {
    if (_uid != null) {
      _col
          .doc(task.id)
          .set(task.toFirestore(), SetOptions(merge: true))
          .ignore();
    } else {
      _saveGuest().ignore();
    }
  }
}

final matrixProvider =
    StateNotifierProvider<MatrixNotifier, List<MatrixTask>>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return MatrixNotifier(uid);
});
