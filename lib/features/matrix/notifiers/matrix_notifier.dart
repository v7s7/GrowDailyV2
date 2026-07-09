import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../models/matrix_task.dart';

class MatrixState {
  final List<MatrixTask> tasks;
  final bool isLoading;

  const MatrixState({this.tasks = const [], this.isLoading = true});
}

class MatrixNotifier extends StateNotifier<MatrixState> {
  final String? _uid;

  // A guest can mutate (e.g. tap a one-tap suggestion) before the disk
  // read in _loadGuest resolves — both fire in the same tick right after
  // construction. Without this guard the disk read wins the race and
  // silently wipes out the just-added task.
  bool _mutatedBeforeLoad = false;

  MatrixNotifier(this._uid) : super(const MatrixState()) {
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
        state = MatrixState(tasks: tasks, isLoading: false);
      }
    } catch (_) {
      if (mounted && !_mutatedBeforeLoad) {
        state = MatrixState(tasks: state.tasks, isLoading: false);
      }
    }
  }

  Future<void> _loadGuest() async {
    try {
      final box = await LocalStoreService.settingsBox();
      final raw = LocalStoreService.asMapList(
        box.get(LocalStoreService.guestMatrixTasksKey),
      );
      if (!mounted || _mutatedBeforeLoad) return;
      final tasks = raw.map(MatrixTask.fromMap).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      state = MatrixState(tasks: tasks, isLoading: false);
    } catch (_) {
      if (mounted && !_mutatedBeforeLoad) {
        state = MatrixState(tasks: state.tasks, isLoading: false);
      }
    }
  }

  Future<void> _saveGuest() async {
    final box = await LocalStoreService.settingsBox();
    await box.put(
      LocalStoreService.guestMatrixTasksKey,
      state.tasks.map((t) => t.toMap()).toList(),
    );
  }

  void add(String title, MatrixQuadrant quadrant) {
    if (title.trim().isEmpty) return;
    _mutatedBeforeLoad = true;
    final task = MatrixTask.create(title, quadrant);
    state = MatrixState(tasks: [...state.tasks, task], isLoading: false);
    _persist(task);
  }

  void toggle(String id) {
    _mutatedBeforeLoad = true;
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final nowDone = !tasks[idx].isDone;
    final updated = tasks[idx].copyWith(
      isDone: nowDone,
      completedAt: nowDone ? DateTime.now() : null,
      clearCompletedAt: !nowDone,
    );
    tasks[idx] = updated;
    state = MatrixState(tasks: tasks, isLoading: false);
    _persist(updated);
  }

  void delete(String id) {
    _mutatedBeforeLoad = true;
    state = MatrixState(
      tasks: state.tasks.where((t) => t.id != id).toList(),
      isLoading: false,
    );
    if (_uid != null) {
      _col.doc(id).delete().ignore();
    } else {
      _saveGuest().ignore();
    }
  }

  void deleteMany(Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    _mutatedBeforeLoad = true;
    state = MatrixState(
      tasks: state.tasks.where((t) => !idSet.contains(t.id)).toList(),
      isLoading: false,
    );
    if (_uid != null) {
      for (final id in idSet) {
        _col.doc(id).delete().ignore();
      }
    } else {
      _saveGuest().ignore();
    }
  }

  void move(String id, MatrixQuadrant newQuadrant) {
    _mutatedBeforeLoad = true;
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final updated = tasks[idx].copyWith(quadrant: newQuadrant);
    tasks[idx] = updated;
    state = MatrixState(tasks: tasks, isLoading: false);
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
    StateNotifierProvider<MatrixNotifier, MatrixState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return MatrixNotifier(uid);
});
