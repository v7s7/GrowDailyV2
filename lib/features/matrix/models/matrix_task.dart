import 'package:uuid/uuid.dart';

enum MatrixQuadrant {
  doFirst,
  schedule,
  delegate,
  eliminate;

  String get label => switch (this) {
        MatrixQuadrant.doFirst => 'DO FIRST',
        MatrixQuadrant.schedule => 'SCHEDULE',
        MatrixQuadrant.delegate => 'DELEGATE',
        MatrixQuadrant.eliminate => 'ELIMINATE',
      };

  String get subtitle => switch (this) {
        MatrixQuadrant.doFirst => 'Urgent · Important',
        MatrixQuadrant.schedule => 'Important, not urgent',
        MatrixQuadrant.delegate => 'Urgent, not important',
        MatrixQuadrant.eliminate => 'Neither',
      };
}

class MatrixTask {
  final String id;
  final String title;
  final MatrixQuadrant quadrant;
  final bool isDone;
  final DateTime createdAt;

  const MatrixTask({
    required this.id,
    required this.title,
    required this.quadrant,
    required this.isDone,
    required this.createdAt,
  });

  factory MatrixTask.create(String title, MatrixQuadrant quadrant) =>
      MatrixTask(
        id: const Uuid().v4(),
        title: title.trim(),
        quadrant: quadrant,
        isDone: false,
        createdAt: DateTime.now(),
      );

  MatrixTask copyWith({
    String? title,
    MatrixQuadrant? quadrant,
    bool? isDone,
  }) =>
      MatrixTask(
        id: id,
        title: title ?? this.title,
        quadrant: quadrant ?? this.quadrant,
        isDone: isDone ?? this.isDone,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MatrixTask && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
