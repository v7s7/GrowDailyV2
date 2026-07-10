import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/game_constants.dart';
import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../models/matrix_task.dart';

class MatrixState {
  final List<MatrixTask> tasks;
  final bool isLoading;

  const MatrixState({this.tasks = const [], this.isLoading = true});
}

class MatrixNotifier extends StateNotifier<MatrixState> {
  final Ref _ref;
  final String? _uid;

  // A guest can mutate (e.g. tap a one-tap suggestion) before the disk
  // read in _loadGuest resolves — both fire in the same tick right after
  // construction. Without this guard the disk read wins the race and
  // silently wipes out the just-added task.
  bool _mutatedBeforeLoad = false;

  MatrixNotifier(this._ref, this._uid) : super(const MatrixState()) {
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
    final current = tasks[idx];
    final nowDone = !current.isDone;
    // Pay XP/gold the first time this task is ever finished. rewarded stays
    // true forever after, so un-completing and re-completing the same task
    // (or just un-completing it) never pays out again or claws it back —
    // see the field doc on MatrixTask.rewarded for why.
    final firstTimeDone = nowDone && !current.rewarded;
    final updated = current.copyWith(
      isDone: nowDone,
      completedAt: nowDone ? DateTime.now() : null,
      clearCompletedAt: !nowDone,
      rewarded: firstTimeDone ? true : null,
    );
    tasks[idx] = updated;
    state = MatrixState(tasks: tasks, isLoading: false);
    _persist(updated);
    if (firstTimeDone) {
      _ref.read(dashboardProvider.notifier).awardBonus(
            xp: GameConstants.matrixTaskXpReward,
            gold: GameConstants.matrixTaskGoldReward,
          );
    }
  }

  /// Flags/unflags a task as one of today's — independent of isDone and of
  /// quadrant. Powers the Today/All filter; no reward is attached to this,
  /// only to actually finishing the task.
  void toggleToday(String id) {
    _mutatedBeforeLoad = true;
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final updated = tasks[idx].copyWith(isToday: !tasks[idx].isToday);
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

  /// Drag-and-drop reorder: drops [id] into [quadrant], immediately before
  /// [beforeId] — or at the end of that quadrant if [beforeId] is null
  /// (dropped on empty space rather than on a specific row). Changes
  /// quadrant too, if it's moving from a different one, so this one method
  /// covers both "reorder within the same group" and "move to a specific
  /// spot in another group."
  ///
  /// Only [id]'s own `order` value changes — the new value is just the
  /// midpoint between its new neighbors, so a single drag never has to
  /// rewrite every other task in the quadrant to keep them all sorted.
  void reorder(String id, MatrixQuadrant quadrant, {String? beforeId}) {
    if (id == beforeId) return;
    _mutatedBeforeLoad = true;
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;

    final siblings = tasks
        .where((t) => t.quadrant == quadrant && t.id != id)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    double newOrder;
    if (siblings.isEmpty) {
      newOrder = 0;
    } else {
      final beforeIdx =
          beforeId == null ? -1 : siblings.indexWhere((t) => t.id == beforeId);
      if (beforeIdx == -1) {
        // No target row (dropped on empty space / the "add another" row) —
        // append after the last sibling.
        newOrder = siblings.last.order + 1000;
      } else {
        final before = siblings[beforeIdx];
        final prev = beforeIdx > 0 ? siblings[beforeIdx - 1] : null;
        newOrder =
            prev == null ? before.order - 1000 : (prev.order + before.order) / 2;
      }
    }

    final updated = tasks[idx].copyWith(quadrant: quadrant, order: newOrder);
    tasks[idx] = updated;
    state = MatrixState(tasks: tasks, isLoading: false);
    _persist(updated);
  }

  /// Undoes a single delete — re-inserts the exact task that was removed.
  /// Guards against double-restore (e.g. a stale SnackBar action firing
  /// twice) by skipping if a task with that id is already present.
  void restore(MatrixTask task) {
    if (state.tasks.any((t) => t.id == task.id)) return;
    _mutatedBeforeLoad = true;
    state = MatrixState(tasks: [...state.tasks, task], isLoading: false);
    _persist(task);
  }

  /// Undoes a bulk delete (multi-select). Same double-restore guard as
  /// [restore], applied per task.
  void restoreMany(Iterable<MatrixTask> tasks) {
    final existingIds = state.tasks.map((t) => t.id).toSet();
    final toRestore =
        tasks.where((t) => !existingIds.contains(t.id)).toList();
    if (toRestore.isEmpty) return;
    _mutatedBeforeLoad = true;
    state = MatrixState(
      tasks: [...state.tasks, ...toRestore],
      isLoading: false,
    );
    for (final task in toRestore) {
      _persist(task);
    }
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
  return MatrixNotifier(ref, uid);
});
