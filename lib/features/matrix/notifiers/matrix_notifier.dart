import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/matrix_task.dart';

class MatrixNotifier extends StateNotifier<List<MatrixTask>> {
  MatrixNotifier() : super([]);

  void add(String title, MatrixQuadrant quadrant) {
    if (title.trim().isEmpty) return;
    state = [...state, MatrixTask.create(title, quadrant)];
  }

  void toggle(String id) {
    state = [
      for (final t in state)
        if (t.id == id) t.copyWith(isDone: !t.isDone) else t,
    ];
  }

  void delete(String id) {
    state = state.where((t) => t.id != id).toList();
  }

  void move(String id, MatrixQuadrant newQuadrant) {
    state = [
      for (final t in state)
        if (t.id == id) t.copyWith(quadrant: newQuadrant) else t,
    ];
  }
}

final matrixProvider =
    StateNotifierProvider<MatrixNotifier, List<MatrixTask>>(
  (ref) => MatrixNotifier(),
);
